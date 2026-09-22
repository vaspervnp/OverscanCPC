#!/usr/bin/env python3
"""Run an assembled CPC program on a small Z80 interpreter, then render what
the CRTC would fetch from screen RAM.

The point is to check a screen layout without an emulator: it executes the
real code, watches the CRTC and Gate Array writes it makes, and decodes video
RAM through the CPC's actual MA/RA address wiring. If the display start
address, the line table and the fills agree, the picture comes out right.

    make bin
    tools/z80check.py build/hello.bin --png /tmp/screen.png

What it does NOT do, and what it therefore cannot tell you:

  * No cycle timing. A virtual frame is a fixed number of INSTRUCTIONS
    (--frame-instr), not 19968 microseconds, and interrupts are spread six to
    the frame inside that, the first of them inside the VSYNC pulse where the
    Gate Array puts it. So the six-to-one relationship and which interrupt
    starts a frame are both real; nothing about raster position, or how long a
    routine takes in microseconds, is. In particular a profile that shows the
    frame half idle says nothing about whether it is idle on a real CPC.
  * No ROMs. The 128K banking is modelled only as far as the second game
    uses it: #C4-#C7 swap bank 4-7 into #4000-#7FFF and #C0 puts bank 1
    back. Anything else stops the run rather than being got wrong quietly.
  * One static frame at the end of the run, decoded from the CRTC registers
    left set then. Rupture (reprogramming R12/R13 mid-frame) is invisible.
  * Only the PPI ports the keyboard and VSYNC need are modelled; every other
    read returns #FF. The PSG is write-only here: the eight-port sequence is
    followed through the PPI and the value latched into a register file, so
    --watch psg7 says what the mixer holds and --watch psg8 what channel A's
    volume is, but nothing is synthesised and there is no sound.

It aborts on any opcode it does not implement rather than guessing, so a clean
run means the code really did execute.
"""

import argparse
import bisect
import os
import sys

PARITY = [bin(i).count("1") % 2 == 0 for i in range(256)]


#: Microseconds an instruction costs beyond its memory accesses.
#:
#: On the CPC the Gate Array stretches every Z80 machine cycle to a whole
#: microsecond, so an instruction costs one microsecond per memory access -
#: opcode fetch, operand fetch, data read, data write - plus whatever internal
#: cycles it has on top. Counting the accesses is free here, because every one
#: of them already goes through rb/wb; this table is the rest. Conditional
#: jumps are charged as if taken, which is right in a loop and one microsecond
#: pessimistic on the way out of one.
US_EXTRA = [0] * 256
for _op in (0x03, 0x13, 0x23, 0x33, 0x0B, 0x1B, 0x2B, 0x3B):
    US_EXTRA[_op] = 1                       # INC/DEC rr, 5-cycle M1
for _op in (0x09, 0x19, 0x29, 0x39):
    US_EXTRA[_op] = 2                       # ADD HL,rr
for _op in (0x18, 0x20, 0x28, 0x30, 0x38):
    US_EXTRA[_op] = 1                       # JR, taken
US_EXTRA[0x10] = 2                          # DJNZ, taken
for _op in (0xC5, 0xD5, 0xE5, 0xF5):
    US_EXTRA[_op] = 1                       # PUSH
for _op in range(0xC7, 0x100, 8):
    US_EXTRA[_op] = 1                       # RST
for _op in (0xC0, 0xC8, 0xD0, 0xD8, 0xE0, 0xE8, 0xF0, 0xF8):
    US_EXTRA[_op] = 1                       # RET cc
US_EXTRA[0xE3] = 1                          # EX (SP),HL
US_EXTRA[0xF9] = 1                          # LD SP,HL


#: An LDIR longer than this is reported. The game does one legitimate copy of
#: about twelve kilobytes at startup - the level data moving down into the RAM
#: under the lower ROM - so the threshold has to clear that while still
#: catching the failure this exists for: a length that reached zero, decremented
#: once more and became 65536.
LDIR_SUSPECT = 20000


class Unsupported(Exception):
    pass


# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------

class Z80:
    """Registers are indexed the way the opcodes encode them: B C D E H L (HL) A."""

    B, C, D, E, H, L, MHL, A = range(8)

    def __init__(self, mem, io):
        self.m = mem
        self.io = io
        self.r = [0] * 8
        self.r2 = [0] * 8                      # shadow set for EXX
        self.ix = self.iy = 0
        self.sp = 0
        self.pc = 0
        self.sf = self.zf = self.hf = self.pf = self.nf = self.cf = False
        self.af2 = 0
        self.iff = False
        self.imode = 0
        self.halted = False
        self.us = 0                            # CPC microseconds, see US_EXTRA

    # -- memory / fetch -----------------------------------------------------
    trap = None
    trap_value = None
    trap_frame = None
    trap_hit = None
    big_ldir = None

    def rb(self, a):
        self.us += 1
        return self.m[a & 0xFFFF]

    def wb(self, a, v):
        self.us += 1
        a &= 0xFFFF
        if (a == self.trap and self.trap_hit is None
                and (self.trap_value is None or (v & 0xFF) == self.trap_value)
                and (self.trap_frame is None or self.io.frame() >= self.trap_frame)):
            self.trap_hit = (self.pc, v, self.io.frame(),
                             self.hl, self.de, self.bc, self.sp,
                             self.rb(self.sp) | (self.rb(self.sp + 1) << 8))
        self.m[a] = v & 0xFF

    def rw(self, a):
        return self.rb(a) | (self.rb(a + 1) << 8)

    def ww(self, a, v):
        self.wb(a, v)
        self.wb(a + 1, v >> 8)

    def fetch(self):
        v = self.rb(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def fetchw(self):
        v = self.rw(self.pc)
        self.pc = (self.pc + 2) & 0xFFFF
        return v

    def fetchd(self):
        d = self.fetch()
        return d - 256 if d > 127 else d

    # -- register pairs -----------------------------------------------------
    def _pair(self, hi):
        return (self.r[hi] << 8) | self.r[hi + 1]

    def _setpair(self, hi, v):
        self.r[hi] = (v >> 8) & 0xFF
        self.r[hi + 1] = v & 0xFF

    bc = property(lambda s: s._pair(0), lambda s, v: s._setpair(0, v))
    de = property(lambda s: s._pair(2), lambda s, v: s._setpair(2, v))
    hl = property(lambda s: s._pair(4), lambda s, v: s._setpair(4, v))

    def rr(self, i):                           # BC DE HL SP
        return (self.bc, self.de, self.hl, self.sp)[i]

    def set_rr(self, i, v):
        if i == 0:
            self.bc = v
        elif i == 1:
            self.de = v
        elif i == 2:
            self.hl = v
        else:
            self.sp = v & 0xFFFF

    # -- 8-bit operand, where 6 means (HL) ----------------------------------
    def g8(self, i):
        return self.rb(self.hl) if i == 6 else self.r[i]

    def s8(self, i, v):
        if i == 6:
            self.wb(self.hl, v)
        else:
            self.r[i] = v & 0xFF

    # -- flags --------------------------------------------------------------
    def get_f(self):
        return ((0x80 if self.sf else 0) | (0x40 if self.zf else 0) |
                (0x10 if self.hf else 0) | (0x04 if self.pf else 0) |
                (0x02 if self.nf else 0) | (0x01 if self.cf else 0))

    def set_f(self, f):
        self.sf = bool(f & 0x80)
        self.zf = bool(f & 0x40)
        self.hf = bool(f & 0x10)
        self.pf = bool(f & 0x04)
        self.nf = bool(f & 0x02)
        self.cf = bool(f & 0x01)

    def _sz(self, v):
        self.zf = v == 0
        self.sf = bool(v & 0x80)

    # -- ALU ----------------------------------------------------------------
    def add8(self, v, carry=0):
        a = self.r[7]
        t = a + v + carry
        res = t & 0xFF
        self.hf = ((a & 0xF) + (v & 0xF) + carry) > 0xF
        self.cf = t > 0xFF
        self.pf = bool((~(a ^ v)) & (a ^ res) & 0x80)
        self.nf = False
        self._sz(res)
        self.r[7] = res

    def sub8(self, v, carry=0, store=True):
        a = self.r[7]
        t = a - v - carry
        res = t & 0xFF
        self.hf = ((a & 0xF) - (v & 0xF) - carry) < 0
        self.cf = t < 0
        self.pf = bool((a ^ v) & (a ^ res) & 0x80)
        self.nf = True
        self._sz(res)
        if store:
            self.r[7] = res

    def logic8(self, v, op):
        a = self.r[7]
        res = {0: a & v, 1: a ^ v, 2: a | v}[op]
        self.r[7] = res
        self.hf = op == 0
        self.cf = self.nf = False
        self.pf = PARITY[res]
        self._sz(res)

    def inc8(self, v):
        res = (v + 1) & 0xFF
        self.hf = (v & 0xF) == 0xF
        self.pf = v == 0x7F
        self.nf = False
        self._sz(res)
        return res

    def dec8(self, v):
        res = (v - 1) & 0xFF
        self.hf = (v & 0xF) == 0
        self.pf = v == 0x80
        self.nf = True
        self._sz(res)
        return res

    def add16(self, a, b):
        t = a + b
        self.hf = ((a & 0xFFF) + (b & 0xFFF)) > 0xFFF
        self.cf = t > 0xFFFF
        self.nf = False
        return t & 0xFFFF

    def adc16(self, a, b):
        c = 1 if self.cf else 0
        t = a + b + c
        res = t & 0xFFFF
        self.hf = ((a & 0xFFF) + (b & 0xFFF) + c) > 0xFFF
        self.cf = t > 0xFFFF
        self.pf = bool((~(a ^ b)) & (a ^ res) & 0x8000)
        self.nf = False
        self.zf = res == 0
        self.sf = bool(res & 0x8000)
        return res

    def sbc16(self, a, b):
        c = 1 if self.cf else 0
        t = a - b - c
        res = t & 0xFFFF
        self.hf = ((a & 0xFFF) - (b & 0xFFF) - c) < 0
        self.cf = t < 0
        self.pf = bool((a ^ b) & (a ^ res) & 0x8000)
        self.nf = True
        self.zf = res == 0
        self.sf = bool(res & 0x8000)
        return res

    # -- stack / flow -------------------------------------------------------
    sp_floor = None
    sp_hit = None

    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF
        if (self.sp_floor is not None and self.sp < self.sp_floor
                and self.sp_hit is None):
            self.sp_hit = (self.pc, self.sp, self.io.frame())
        self.ww(self.sp, v)

    def pop(self):
        v = self.rw(self.sp)
        self.sp = (self.sp + 2) & 0xFFFF
        return v

    def cond(self, i):
        return (not self.zf, self.zf, not self.cf, self.cf,
                not self.pf, self.pf, not self.sf, self.sf)[i]

    # -- rotates / shifts ---------------------------------------------------
    def rot(self, op, v):
        if op == 0:                                     # rlc
            self.cf = bool(v & 0x80)
            v = ((v << 1) | (1 if self.cf else 0)) & 0xFF
        elif op == 1:                                   # rrc
            self.cf = bool(v & 1)
            v = ((v >> 1) | (0x80 if self.cf else 0)) & 0xFF
        elif op == 2:                                   # rl
            c = self.cf
            self.cf = bool(v & 0x80)
            v = ((v << 1) | (1 if c else 0)) & 0xFF
        elif op == 3:                                   # rr
            c = self.cf
            self.cf = bool(v & 1)
            v = ((v >> 1) | (0x80 if c else 0)) & 0xFF
        elif op == 4:                                   # sla
            self.cf = bool(v & 0x80)
            v = (v << 1) & 0xFF
        elif op == 5:                                   # sra
            self.cf = bool(v & 1)
            v = ((v >> 1) | (v & 0x80)) & 0xFF
        elif op == 6:                                   # sll (undocumented)
            self.cf = bool(v & 0x80)
            v = ((v << 1) | 1) & 0xFF
        else:                                           # srl
            self.cf = bool(v & 1)
            v = (v >> 1) & 0xFF
        self.hf = self.nf = False
        self.pf = PARITY[v]
        self._sz(v)
        return v

    # -- one instruction ----------------------------------------------------
    def step(self):
        op = self.fetch()
        self.us += US_EXTRA[op]

        if op == 0xCB:
            return self.op_cb()
        if op == 0xED:
            return self.op_ed()
        if op in (0xDD, 0xFD):
            return self.op_index(op)

        hi, lo = op >> 6, op & 7
        mid = (op >> 3) & 7

        if op == 0x00:
            return
        if op == 0x76:
            self.halted = True
            return
        if hi == 1:                                     # ld r,r'
            return self.s8(mid, self.g8(lo))
        if hi == 2:                                     # alu a,r
            return self.alu(mid, self.g8(lo))
        if hi == 0:
            if lo == 0:
                if op == 0x08:
                    af = (self.r[7] << 8) | self.get_f()
                    self.r[7] = self.af2 >> 8
                    self.set_f(self.af2 & 0xFF)
                    self.af2 = af
                elif op == 0x10:                        # djnz
                    d = self.fetchd()
                    self.r[0] = (self.r[0] - 1) & 0xFF
                    if self.r[0]:
                        self.pc = (self.pc + d) & 0xFFFF
                elif op == 0x18:
                    d = self.fetchd()
                    self.pc = (self.pc + d) & 0xFFFF
                else:                                   # jr cc,e
                    d = self.fetchd()
                    if self.cond(mid - 4):
                        self.pc = (self.pc + d) & 0xFFFF
                return
            if lo == 1:
                if op & 8:
                    self.hl = self.add16(self.hl, self.rr(mid >> 1))
                else:
                    self.set_rr(mid >> 1, self.fetchw())
                return
            if lo == 2:
                if op == 0x02: self.wb(self.bc, self.r[7])
                elif op == 0x0A: self.r[7] = self.rb(self.bc)
                elif op == 0x12: self.wb(self.de, self.r[7])
                elif op == 0x1A: self.r[7] = self.rb(self.de)
                elif op == 0x22: self.ww(self.fetchw(), self.hl)
                elif op == 0x2A: self.hl = self.rw(self.fetchw())
                elif op == 0x32: self.wb(self.fetchw(), self.r[7])
                else: self.r[7] = self.rb(self.fetchw())
                return
            if lo == 3:
                i = mid >> 1
                self.set_rr(i, (self.rr(i) + (-1 if op & 8 else 1)) & 0xFFFF)
                return
            if lo == 4:
                return self.s8(mid, self.inc8(self.g8(mid)))
            if lo == 5:
                return self.s8(mid, self.dec8(self.g8(mid)))
            if lo == 6:
                return self.s8(mid, self.fetch())
            # lo == 7: the accumulator/flag oddities
            if op in (0x07, 0x0F, 0x17, 0x1F):
                self.r[7] = self.rot(op >> 3, self.r[7])
                self.zf = self.sf = False               # these four leave S/Z alone
                self.pf = False
                return
            if op == 0x27:
                return self.daa()
            if op == 0x2F:
                self.r[7] ^= 0xFF
                self.hf = self.nf = True
                return
            if op == 0x37:
                self.cf = True
                self.hf = self.nf = False
                return
            if op == 0x3F:
                self.hf = self.cf
                self.cf = not self.cf
                self.nf = False
                return

        # hi == 3
        if lo == 0:
            if self.cond(mid):
                self.pc = self.pop()
            return
        if lo == 1:
            if op & 8:
                if op == 0xC9: self.pc = self.pop()
                elif op == 0xD9:
                    # EXX is BC DE HL and nothing else - A has its own
                    # ex af,af' - so only the first six of r may move.
                    self.r[:6], self.r2[:6] = self.r2[:6], self.r[:6]
                elif op == 0xE9: self.pc = self.hl
                else: self.sp = self.hl
            else:
                v = self.pop()
                i = mid >> 1
                if i == 3:
                    self.r[7] = v >> 8
                    self.set_f(v & 0xFF)
                else:
                    self.set_rr(i, v)
            return
        if lo == 2:
            t = self.fetchw()
            if self.cond(mid):
                self.pc = t
            return
        if lo == 3:
            if op == 0xC3: self.pc = self.fetchw()
            elif op == 0xD3:
                self.us += 1
                self.io.out((self.r[7] << 8) | self.fetch(), self.r[7])
            elif op == 0xDB:
                self.us += 1
                self.r[7] = self.io.inp((self.r[7] << 8) | self.fetch())
            elif op == 0xE3:
                t = self.rw(self.sp)
                self.ww(self.sp, self.hl)
                self.hl = t
            elif op == 0xEB:
                t = self.de
                self.de = self.hl
                self.hl = t
            elif op == 0xF3: self.iff = False
            elif op == 0xFB: self.iff = True
            return
        if lo == 4:
            t = self.fetchw()
            if self.cond(mid):
                self.push(self.pc)
                self.pc = t
            return
        if lo == 5:
            if op & 8:
                if op == 0xCD:
                    t = self.fetchw()
                    self.push(self.pc)
                    self.pc = t
                    return
                raise Unsupported("opcode #%02X at #%04X" % (op, self.pc - 1))
            i = mid >> 1
            self.push((self.r[7] << 8) | self.get_f() if i == 3 else self.rr(i))
            return
        if lo == 6:
            return self.alu(mid, self.fetch())
        # lo == 7: rst
        self.push(self.pc)
        self.pc = mid * 8

    def alu(self, op, v):
        if op == 0: self.add8(v)
        elif op == 1: self.add8(v, 1 if self.cf else 0)
        elif op == 2: self.sub8(v)
        elif op == 3: self.sub8(v, 1 if self.cf else 0)
        elif op == 4: self.logic8(v, 0)
        elif op == 5: self.logic8(v, 1)
        elif op == 6: self.logic8(v, 2)
        else: self.sub8(v, 0, store=False)

    def daa(self):
        a = self.r[7]
        t = 0
        if self.hf or (a & 0xF) > 9:
            t |= 6
        if self.cf or a > 0x99:
            t |= 0x60
            self.cf = True
        if self.nf:
            self.hf = self.hf and (a & 0xF) < 6
            a = (a - t) & 0xFF
        else:
            self.hf = (a & 0xF) > 9
            a = (a + t) & 0xFF
        self.r[7] = a
        self.pf = PARITY[a]
        self._sz(a)

    # -- CB prefix ----------------------------------------------------------
    def op_cb(self):
        op = self.fetch()
        hi, reg, bit = op >> 6, op & 7, (op >> 3) & 7
        if hi == 0:
            return self.s8(reg, self.rot(bit, self.g8(reg)))
        v = self.g8(reg)
        if hi == 1:                                     # bit
            self.zf = not (v & (1 << bit))
            self.pf = self.zf
            self.sf = bit == 7 and not self.zf
            self.hf = True
            self.nf = False
            return
        if hi == 2:
            return self.s8(reg, v & ~(1 << bit))
        return self.s8(reg, v | (1 << bit))

    # -- ED prefix ----------------------------------------------------------
    def op_ed(self):
        op = self.fetch()
        if 0xB0 <= op <= 0xBB:
            self.us += 2                       # LDIR and friends, per iteration
        elif 0xA0 <= op <= 0xAB:
            self.us += 1                       # LDI and friends, five in all
        mid = (op >> 3) & 7
        if op & 0xC7 == 0x40:                           # in r,(c)
            self.us += 1
            v = self.io.inp(self.bc)
            if mid != 6:
                self.r[mid] = v
            self.hf = self.nf = False
            self.pf = PARITY[v]
            self._sz(v)
            return
        if op & 0xC7 == 0x41:                           # out (c),r
            self.us += 1
            return self.io.out(self.bc, 0 if mid == 6 else self.r[mid])
        if op & 0xCF == 0x42:                           # sbc hl,rr
            return setattr(self, "hl", self.sbc16(self.hl, self.rr(mid >> 1)))
        if op & 0xCF == 0x4A:                           # adc hl,rr
            return setattr(self, "hl", self.adc16(self.hl, self.rr(mid >> 1)))
        if op & 0xCF == 0x43:                           # ld (nn),rr
            return self.ww(self.fetchw(), self.rr(mid >> 1))
        if op & 0xCF == 0x4B:                           # ld rr,(nn)
            return self.set_rr(mid >> 1, self.rw(self.fetchw()))
        if op & 0xC7 == 0x44:                           # neg
            a = self.r[7]
            self.r[7] = 0
            self.sub8(a)
            return
        if op & 0xC7 == 0x45:                           # retn / reti
            self.pc = self.pop()
            return
        if op & 0xC7 == 0x46:                           # im n
            self.imode = (0, 0, 1, 2)[mid & 3]
            return
        if op in (0x47, 0x4F, 0x57, 0x5F):              # ld i/r,a and back
            return
        if op in (0xA0, 0xA8, 0xB0, 0xB8):              # ldi ldd ldir lddr
            step = 1 if op in (0xA0, 0xB0) else -1
            repeat = op >= 0xB0
            if repeat and self.bc > LDIR_SUSPECT and self.big_ldir is None:
                # Almost always a zero length that wrapped to 65535, which on
                # a CPC smears one byte over the whole of memory.
                self.big_ldir = (self.pc - 2, self.bc, self.hl, self.de,
                                 self.rb(self.sp) | (self.rb(self.sp + 1) << 8))
            while True:
                self.wb(self.de, self.rb(self.hl))
                self.hl = (self.hl + step) & 0xFFFF
                self.de = (self.de + step) & 0xFFFF
                self.bc = (self.bc - 1) & 0xFFFF
                if not repeat or self.bc == 0:
                    break
            self.hf = self.nf = False
            self.pf = self.bc != 0
            return
        if op in (0xA1, 0xA9, 0xB1, 0xB9):              # cpi cpd cpir cpdr
            step = 1 if op in (0xA1, 0xB1) else -1
            repeat = op >= 0xB0
            while True:
                v = self.rb(self.hl)
                self.sub8(v, 0, store=False)
                self.hl = (self.hl + step) & 0xFFFF
                self.bc = (self.bc - 1) & 0xFFFF
                if not repeat or self.bc == 0 or self.zf:
                    break
            self.pf = self.bc != 0
            return
        raise Unsupported("opcode #ED%02X at #%04X" % (op, self.pc - 2))

    # -- DD / FD prefix -----------------------------------------------------
    def op_index(self, prefix):
        name = "ix" if prefix == 0xDD else "iy"
        idx = getattr(self, name)
        op = self.fetch()
        self.us += 1                           # the index add, on top of the fetch

        if op == 0x21:
            return setattr(self, name, self.fetchw())
        if op == 0x22:
            return self.ww(self.fetchw(), idx)
        if op == 0x2A:
            return setattr(self, name, self.rw(self.fetchw()))
        if op == 0x23:
            return setattr(self, name, (idx + 1) & 0xFFFF)
        if op == 0x2B:
            return setattr(self, name, (idx - 1) & 0xFFFF)
        if op == 0xE5:
            return self.push(idx)
        if op == 0xE1:
            return setattr(self, name, self.pop())
        if op == 0xE9:
            self.pc = idx
            return
        if op == 0xF9:
            self.sp = idx
            return
        if op & 0xCF == 0x09:                           # add ix,rr
            rp = (op >> 4) & 3
            v = (self.bc, self.de, idx, self.sp)[rp]
            return setattr(self, name, self.add16(idx, v))
        if op == 0x36:                                  # ld (ix+d),n
            d = self.fetchd()
            return self.wb(idx + d, self.fetch())
        if op == 0x34:                                  # inc (ix+d)
            d = self.fetchd()
            return self.wb(idx + d, self.inc8(self.rb(idx + d)))
        if op == 0x35:                                  # dec (ix+d)
            d = self.fetchd()
            return self.wb(idx + d, self.dec8(self.rb(idx + d)))
        if op >> 6 == 1 and (op & 7) == 6 and op != 0x76:       # ld r,(ix+d)
            d = self.fetchd()
            return self.s8((op >> 3) & 7, self.rb(idx + d))
        if op >> 6 == 1 and ((op >> 3) & 7) == 6:               # ld (ix+d),r
            d = self.fetchd()
            return self.wb(idx + d, self.r[op & 7])
        if op >> 6 == 2 and (op & 7) == 6:                      # alu a,(ix+d)
            d = self.fetchd()
            return self.alu((op >> 3) & 7, self.rb(idx + d))
        if op == 0xCB:                                  # DD CB d op
            # The displacement comes before the opcode in this group, which is
            # the only place in the instruction set where that happens.
            d = self.fetchd()
            sub = self.fetch()
            addr = (idx + d) & 0xFFFF
            hi, reg, bit = sub >> 6, sub & 7, (sub >> 3) & 7
            v = self.rb(addr)
            if hi == 1:                                 # bit n,(ix+d)
                self.zf = not (v & (1 << bit))
                self.pf = self.zf
                self.sf = bit == 7 and not self.zf
                self.hf = True
                self.nf = False
                return
            if hi == 0:
                v = self.rot(bit, v)
            elif hi == 2:
                v &= ~(1 << bit)
            else:
                v |= 1 << bit
            self.wb(addr, v)
            if reg != 6:
                self.s8(reg, v)                         # the undocumented copy
            return
        # With a DD/FD prefix, a register code of 4 or 5 is not H or L but the
        # high or low half of the index register. Undocumented, but every Z80
        # ever made does it, and the Arkos player is one of the many things
        # that uses it.
        def half(i, v=None):
            cur = getattr(self, name)
            if i not in (4, 5):
                if v is None:
                    return self.r[i]
                self.r[i] = v & 0xFF
                return None
            if v is None:
                return (cur >> 8) if i == 4 else (cur & 0xFF)
            if i == 4:
                setattr(self, name, ((v & 0xFF) << 8) | (cur & 0xFF))
            else:
                setattr(self, name, (cur & 0xFF00) | (v & 0xFF))
            return None

        dst, src = (op >> 3) & 7, op & 7
        if op & 0xC7 == 0x06 and dst != 6:                      # ld ixh/ixl,n
            return half(dst, self.fetch())
        if op >> 6 == 1 and dst != 6 and src != 6:              # ld r,r'
            return half(dst, half(src))
        if op & 0xC7 == 0x04 and dst != 6:                      # inc ixh/ixl
            return half(dst, self.inc8(half(dst)))
        if op & 0xC7 == 0x05 and dst != 6:                      # dec ixh/ixl
            return half(dst, self.dec8(half(dst)))
        if op >> 6 == 2 and src != 6:                           # alu a,ixh/ixl
            return self.alu(dst, half(src))

        raise Unsupported("opcode #%02X%02X at #%04X" % (prefix, op, self.pc - 2))


# ---------------------------------------------------------------------------
# CPC I/O: just enough to capture what the display ends up doing
# ---------------------------------------------------------------------------

# CPC key matrix: name -> (line, bit). A pressed key reads as 0.
KEY_MATRIX = {
    "UP": (9, 0), "DOWN": (9, 1), "LEFT": (9, 2), "RIGHT": (9, 3),
    "FIRE": (9, 4), "FIRE2": (9, 5), "DEL": (9, 7),
    "SPACE": (5, 7), "ENTER": (0, 6), "ESC": (8, 2),
    "A": (8, 5), "L": (4, 4), "M": (4, 6), "O": (4, 2), "P": (3, 3),
    "Q": (8, 3), "S": (7, 4), "W": (7, 3), "Z": (8, 7),
    "0": (4, 0), "1": (8, 0), "2": (8, 1), "3": (7, 1), "4": (7, 0),
    "5": (6, 1), "6": (6, 0), "7": (5, 1), "8": (5, 0), "9": (4, 1),
}


class CPCIO:
    #: A CPC frame: 312 scanlines of 64 us. Nothing about it is negotiable.
    FRAME_US = 19968
    LINE_US = 64

    def __init__(self, keys=(), frame_instr=6000):
        self.crtc = [0] * 18
        self.crtc_sel = 0
        self.pen = 0
        self.ink = {}
        self.rmr = None
        self.ram_cfg = None

        # The other 64K. Only the four configurations the second game uses
        # are modelled: #C0 is the plain map, and #C4-#C7 put bank 4, 5, 6 or
        # 7 at #4000-#7FFF in place of bank 1. The screen is at #8000-#FFFF,
        # which none of them touch, and the code is in the window - which is
        # why the game's own paging routine runs from below #4000.
        #
        # It is done by swapping sixteen kilobytes in and out of the flat
        # array rather than by indirecting every memory access, because every
        # memory access is the interpreter's whole cost and a page-in happens
        # twice at boot and twice a room.
        self.mem = None                         # set by main, once
        self.banks = [bytearray(0x4000) for _ in range(4)]
        self.bank1 = None                       # what #4000 holds when out
        self.banked = None                      # which of them is in, if any

        # PPI / PSG state, enough for the keyboard and the VSYNC bit
        self.ppi_a = 0
        self.ppi_a_input = False
        self.ppi_c = 0
        self.psg_reg = 0
        self.psg = [0] * 16                     # the AY as it stands
        self.keys = keys            # (name, first frame, last frame)
        self.clock = 0
        self.frame_instr = frame_instr
        self.key_reads = 0

    def vsync_line(self):
        """Scanline VSYNC starts on, from R7 - 34 until the program sets it."""
        return (self.crtc[7] or 34) * ((self.crtc[9] or 7) + 1)

    def vsync(self):
        line = (self.clock % self.FRAME_US) // self.LINE_US
        start = self.vsync_line()
        return start <= line < start + 8

    def frame(self):
        return self.clock // self.FRAME_US

    def matrix_row(self, line):
        """The keyboard line as it stands this frame. A pressed key reads 0."""
        now = self.frame()
        row = 0xFF
        for name, first, last in self.keys:
            if first <= now <= last:
                kline, bit = KEY_MATRIX[name]
                if kline == line:
                    row &= ~(1 << bit) & 0xFF
        return row

    def out(self, port, val):
        hi = port >> 8
        if hi == 0xBC:
            self.crtc_sel = val & 0x1F
        elif hi == 0xBD:
            if self.crtc_sel < 18:
                self.crtc[self.crtc_sel] = val
        elif hi == 0xF4:                        # PPI port A - PSG data
            self.ppi_a = val
            if (self.ppi_c >> 6) == 3:          # already selecting: the
                self.psg_reg = val              # address latch follows port A
        elif hi == 0xF6:                        # PPI port C - PSG function
            self.ppi_c = val
            if (val >> 6) == 3:                 # 11 = select register
                self.psg_reg = self.ppi_a
            elif (val >> 6) == 2:               # 10 = write it
                if self.psg_reg < 16 and not self.ppi_a_input:
                    self.psg[self.psg_reg] = self.ppi_a
        elif hi == 0xF7:                        # PPI control
            if val & 0x80:
                self.ppi_a_input = bool(val & 0x10)
        elif not (hi & 0x80):                   # #7Fxx - Gate Array / PAL
            if val < 0x40:
                self.pen = val
            elif val < 0x80:
                self.ink[self.pen] = val & 0x1F
            elif val < 0xC0:
                self.rmr = val
            else:
                self.ram_cfg = val
                self.set_bank(val)

    def set_bank(self, val):
        """#C4-#C7 put bank 4-7 at #4000-#7FFF; anything else is bank 1."""
        if self.mem is None:
            return
        cfg = val & 7
        want = cfg - 4 if cfg >= 4 else None
        if cfg in (1, 2, 3):
            sys.exit("z80check: RAM configuration #%02X is not modelled - "
                     "only #C0 and #C4-#C7 are" % val)
        if want == self.banked:
            return
        if self.banked is not None:                 # put back what is there
            self.banks[self.banked][:] = self.mem[0x4000:0x8000]
            self.mem[0x4000:0x8000] = self.bank1
        if want is not None:                        # and take out what is not
            self.bank1 = bytes(self.mem[0x4000:0x8000])
            self.mem[0x4000:0x8000] = self.banks[want]
        self.banked = want

    def inp(self, port):
        hi = port >> 8
        if hi == 0xF4:
            if self.ppi_a_input and (self.ppi_c >> 6) == 1 and self.psg_reg == 14:
                line = self.ppi_c & 0x0F
                if line < 10:
                    self.key_reads += 1
                    return self.matrix_row(line)
            return 0xFF
        if hi == 0xF5:                          # PPI port B, bit 0 = VSYNC
            return 0x1E | (1 if self.vsync() else 0)
        return 0xFF


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

# Hardware colour numbers 0-31 as the Gate Array sees them (not firmware INKs).
HW_RGB = [
    (128, 128, 128), (128, 128, 128), (0, 255, 128), (255, 255, 128),
    (0, 0, 128),     (255, 0, 128),   (0, 128, 128), (255, 128, 128),
    (255, 0, 128),   (255, 255, 128), (255, 255, 0), (255, 255, 255),
    (255, 0, 0),     (255, 0, 255),   (255, 128, 0), (255, 128, 255),
    (0, 0, 128),     (0, 255, 128),   (0, 255, 0),   (0, 255, 255),
    (0, 0, 0),       (0, 0, 255),     (0, 128, 0),   (0, 128, 255),
    (128, 0, 128),   (128, 255, 128), (128, 255, 0), (128, 255, 255),
    (128, 0, 0),     (128, 0, 255),   (128, 128, 0), (128, 128, 255),
]


def decode_byte(byte, mode):
    """Unpack one screen byte into its pens, leftmost pixel first."""
    if mode == 0:
        return [
            ((byte >> 7) & 1) | (((byte >> 3) & 1) << 1) |
            (((byte >> 5) & 1) << 2) | (((byte >> 1) & 1) << 3),
            ((byte >> 6) & 1) | (((byte >> 2) & 1) << 1) |
            (((byte >> 4) & 1) << 2) | ((byte & 1) << 3),
        ]
    if mode == 2:
        return [(byte >> (7 - i)) & 1 for i in range(8)]
    return [((byte >> (7 - i)) & 1) | (((byte >> (3 - i)) & 1) << 1)
            for i in range(4)]


def screen_pens(mem, io):
    """Walk the CRTC's fetch and return a grid of pen numbers."""
    r1, r6, r9 = io.crtc[1], io.crtc[6], io.crtc[9]
    mode = (io.rmr & 3) if io.rmr is not None else 1
    base = ((io.crtc[12] & 0x3F) << 8) | io.crtc[13]
    per_byte = (2, 4, 8)[mode]
    rows = []
    for row in range(r6):
        for raster in range(r9 + 1):
            line = []
            for char in range(r1):
                ma = base + row * r1 + char
                # A15,A14 = MA13,MA12   A13..A11 = RA2..RA0   A10..A1 = MA9..MA0
                addr = ((ma & 0x3000) << 2) | ((raster & 7) << 11) | ((ma & 0x3FF) << 1)
                line += decode_byte(mem[addr & 0xFFFF], mode)
                line += decode_byte(mem[(addr + 1) & 0xFFFF], mode)
            rows.append(line)
    return rows, mode, per_byte


def pixel_aspect(per_byte):
    """How wide one pixel of this mode is, in mode 1 pixels.

    All three modes fill the same width of tube; they differ in how finely it
    is divided. A mode 0 pixel is two mode 1 pixels wide, so a picture decoded
    in mode 0 has to be stretched to come out the shape it is on the monitor.
    Mode 2 would want half, which integers cannot do - it is rendered 1:1 and
    so comes out twice as wide as it should. Nothing here uses mode 2.
    """
    return max(1, 4 // per_byte)


def write_png(rows, io, path, scale, aspect=1):
    try:
        from PIL import Image
    except ImportError:
        sys.exit("--png needs Pillow (pip install pillow); try --ascii instead")
    h, w = len(rows), len(rows[0])
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y, line in enumerate(rows):
        for x, pen in enumerate(line):
            px[x, y] = HW_RGB[io.ink.get(pen, 20)]
    if scale != 1 or aspect != 1:
        img = img.resize((w * scale * aspect, h * scale), Image.NEAREST)
    img.save(path)
    return img.size


def write_ascii(rows, io, cols, aspect=1):
    """Coarse terminal preview: one character per block, darkest pen wins."""
    ramp = " .:-=+*#%@"
    h, w = len(rows), len(rows[0])
    step_x = max(1, w // cols)
    step_y = step_x * 2 * aspect              # characters are about twice as tall
    out = []
    for y in range(0, h, step_y):
        line = []
        for x in range(0, w, step_x):
            r, g, b = HW_RGB[io.ink.get(rows[y][x], 20)]
            line.append(ramp[min(9, (r + g + b) * 10 // 766)])
        out.append("".join(line))
    return "\n".join(out)


# ---------------------------------------------------------------------------

def debris_rows(mem, d):
    """The play area, read the way the game addresses it - through the line
    table it built, so the 2048-byte stride and the page crossing stay the
    machine's business."""
    tab, bpl = d["line_tab"], d["bytes_per_line"]
    out = []
    for y in range(d["play_top"], d["display_lines"]):
        a = mem[tab + y * 2] | (mem[tab + y * 2 + 1] << 8)
        out.append(bytes(mem[a:a + bpl]))
    return out


def debris_rects(mem, d):
    """Where every sprite's picture is standing at this instant, which is what
    E_OX and cat_ox mean: not where it is going, where it already is."""
    out = []
    if mem[d["cat_drawn"]]:
        out.append((mem[d["cat_ox"]], mem[d["cat_oy"]],
                    mem[d["cat_ow"]], mem[d["cat_oh"]]))
    for i in range(d["enemy_count"]):
        b = d["enemies"] + i * d["e_size"]
        if mem[b + d["e_type"]] and mem[b + d["e_drawn"]]:
            out.append((mem[b + d["e_ox"]], mem[b + d["e_oy"]],
                        mem[b + d["e_ow"]], mem[b + d["e_oh"]]))
    return out


def debris_scan(mem, d, frame):
    """Ink standing on ground the room painted empty, where nothing is.

    The room is the reference: whatever it looked like once it was drawn. A
    sausage disappearing is a byte going back to the background, which is the
    game working; a byte going the other way, outside every sprite, is a piece
    of something that was lifted off in the wrong order and left there."""
    room = mem[d["cur_room"]]
    if room != d["room"]:                   # a new room takes a while to paint
        d.update(room=room, skip=16, ref=None)
        return
    if d["skip"]:
        d["skip"] -= 1
        return
    if d["ref"] is None:
        d["ref"] = debris_rows(mem, d)
        d["ref_rects"] = debris_rects(mem, d)
        return

    now = debris_rows(mem, d)
    rects = debris_rects(mem, d) + list(d["ref_rects"])
    stray = []
    for i, row in enumerate(now):
        was = d["ref"][i]
        if row == was:
            continue
        y = d["play_top"] + i
        for x in range(d["bytes_per_line"]):
            if was[x] or not row[x]:
                continue                    # the room's own ink, or ink going
            if any(rx <= x < rx + rw and ry <= y < ry + rh
                   for rx, ry, rw, rh in rects):
                continue
            stray.append((x, y))
    d["frames"] += 1
    if stray and os.environ.get("DEBRIS_VERBOSE"):
        tab = d["line_tab"]
        vals = []
        for x, y in stray[:12]:
            a = mem[tab + y * 2] | (mem[tab + y * 2 + 1] << 8)
            vals.append("%d,%d=%02X" % (x, y, mem[a + x]))
        print("  frame %3d  %d stray  %s  rects %s"
              % (frame, len(stray), " ".join(vals), debris_rects(mem, d)))
    if len(stray) > d["worst"]:
        xs = [x for x, _ in stray]
        ys = [y for _, y in stray]
        d.update(worst=len(stray), worst_frame=frame,
                 where=(min(xs), max(xs), min(ys), max(ys)))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary", help="raw assembled code (make bin)")
    ap.add_argument("--org", default="0x4000", help="load and entry address (default 0x4000)")
    ap.add_argument("--png", help="write the decoded screen here")
    ap.add_argument("--scale", type=int, default=2, help="PNG pixel scale (default 2)")
    ap.add_argument("--ascii", action="store_true", help="print a terminal preview")
    ap.add_argument("--dump", help="write the decoded screen here as raw mode 0 "
                    "bytes - one line after another, the same shape a picture "
                    "out of tools/mkscreen.py has, so the two can be compared")
    ap.add_argument("--keys", default="",
                    help="keys held down, comma separated. NAME is held the "
                         "whole run, NAME@12 from frame 12 on, NAME@12-14 for "
                         "those frames only - e.g. FIRE@12-13,RIGHT@15")
    ap.add_argument("--sym", help="rasm symbol file (rasm -s -sl -os ...)")
    ap.add_argument("--watch", default="",
                    help="comma separated symbols to print once per frame, "
                         "optionally with a byte offset (enemies+8); suffix "
                         ":w for a 16-bit value, :s for signed 16-bit. psg0 "
                         "to psg15 read the AY register file instead of RAM")
    ap.add_argument("--frames", type=int, default=0,
                    help="stop after this many virtual frames (0 = only on a "
                         "self-jump or HALT)")
    ap.add_argument("--profile", action="store_true",
                    help="count instructions executed in each named routine "
                         "(needs --sym); says where a frame is going")
    ap.add_argument("--profile-from", type=int, default=0, metavar="FRAME",
                    help="start counting at this frame, to skip the title "
                         "screen and the first room load")
    ap.add_argument("--frame-instr", type=int, default=12000,
                    help="instructions per virtual frame (default 12000, roughly "
                         "what a 19968 us CPC frame gets through)")
    ap.add_argument("--save-mem", action="append", default=[],
                    metavar="ADDR:LEN=FILE",
                    help="write a range of memory out when the run ends, so a "
                         "table the program built or unpacked can be compared "
                         "with what it was built from")
    ap.add_argument("--beam", action="store_true",
                    help="where the beam is when each sprite is drawn (needs "
                         "--sym). Every sprite has to be back on the screen "
                         "before the beam reaches it, and this says whether "
                         "it was")
    ap.add_argument("--beam-from", type=int, default=40,
                    help="first frame to report for --beam")
    ap.add_argument("--debris", action="store_true",
                    help="watch for ink left behind on ground the room "
                         "painted empty (needs --sym). A sprite whose saved "
                         "background is put back out of turn stamps a piece "
                         "of another one into the room, and nothing will ever "
                         "erase it")
    ap.add_argument("--debris-from", type=int, default=30,
                    help="first frame to watch for --debris")
    ap.add_argument("--trap", help="symbol or address; report the first write "
                                   "to it and where it came from")
    ap.add_argument("--trap-value", help="only trap a write of this byte value")
    ap.add_argument("--sp-floor", help="report the first push below this address")
    ap.add_argument("--trap-frame", type=int, help="ignore trap hits before this frame")
    ap.add_argument("--poke", action="append", default=[], metavar="SYM=N@FRAME",
                    help="write a byte into memory at the top of a frame, so a "
                         "branch can be reached without a route that walks all "
                         "the way to it: --poke cat_lives=7@200")
    ap.add_argument("--max-steps", type=int, default=50_000_000)
    args = ap.parse_args()

    keys = []
    for item in args.keys.split(","):
        item = item.strip().upper()
        if not item:
            continue
        name, _, when = item.partition("@")
        if name not in KEY_MATRIX:
            sys.exit("z80check: no such key %r (have %s)"
                     % (name, ", ".join(sorted(KEY_MATRIX))))
        first, last = 0, 1 << 30
        if when:
            lo, dash, hi = when.partition("-")
            try:
                first = int(lo)
                last = int(hi) if dash else 1 << 30
            except ValueError:
                sys.exit("z80check: bad frame range in %r" % item)
        keys.append((name, first, last))

    symbols = {}
    if args.sym:
        for line in open(args.sym):
            parts = line.split()
            if len(parts) >= 2 and parts[1].startswith("#"):
                symbols[parts[0].upper()] = int(parts[1][1:], 16)

    watch = []
    for item in args.watch.split(","):
        item = item.strip()
        if not item:
            continue
        name, _, kind = item.partition(":")
        if not args.sym and not name.lower().startswith("psg"):
            sys.exit("z80check: --watch needs --sym")
        if name.lower().startswith("psg") and name[3:].isdigit():
            n = int(name[3:])
            if n > 15:
                sys.exit("z80check: %r - the AY has sixteen registers" % name)
            watch.append((name, n, "psg"))
            continue
        base, offset = name, 0
        for sep in ("+", "-"):
            if sep in name:
                base, _, off = name.partition(sep)
                try:
                    offset = int(off, 0) * (1 if sep == "+" else -1)
                except ValueError:
                    sys.exit("z80check: bad offset in %r" % name)
                break
        if base.upper() not in symbols:
            sys.exit("z80check: %r is not in %s" % (base, args.sym))
        watch.append((name, symbols[base.upper()] + offset, kind or "b"))

    org = int(args.org, 0)
    code = open(args.binary, "rb").read()
    mem = bytearray(0x10000)
    mem[org:org + len(code)] = code

    io = CPCIO(keys, args.frame_instr)
    io.mem = mem
    cpu = Z80(mem, io)
    if args.trap:
        cpu.trap = (symbols.get(args.trap.upper()) if args.trap.upper() in symbols
                    else int(args.trap, 0))
        if args.trap_value:
            cpu.trap_value = int(args.trap_value, 0) & 0xFF
        if args.trap_frame:
            cpu.trap_frame = args.trap_frame
    if args.sp_floor:
        cpu.sp_floor = int(args.sp_floor, 0)
    cpu.pc = org
    cpu.sp = 0xC000

    # A frame is 19968 microseconds, not a number of instructions, because
    # the only question worth asking about this program is where the beam is
    # when it writes to the screen. Instructions are charged at the CPC's own
    # rate - a microsecond per machine cycle - in Z80.us.
    #
    # Six interrupts to a frame, the first of them two scanlines into VSYNC
    # where the Gate Array resets its HSYNC counter and issues one. That is
    # the interrupt a program locks its frame to; spacing them evenly from
    # zero instead hides every phase bug there is.
    irq_period = 52 * CPCIO.LINE_US
    irq_first = (io.vsync_line() + 2) * CPCIO.LINE_US
    us_budget = args.frames * CPCIO.FRAME_US if args.frames else None
    limit = args.max_steps
    next_irq = irq_first
    irqs = 0
    reason = "instruction budget"
    last_frame = -1
    trace = []

    prof = None
    if args.profile:
        if not symbols:
            sys.exit("--profile needs --sym")
        prof_addr = sorted(set(symbols.values()))
        prof_name = {v: k for k, v in sorted(symbols.items(), reverse=True)}
        prof = dict.fromkeys(prof_addr, 0)
        prof_start = args.profile_from * CPCIO.FRAME_US

    beam = None
    if args.beam:
        if not symbols:
            sys.exit("--beam needs --sym")
        want = ("SPR_RESTORE", "SPR_DRAW", "SPRITES_UPDATE_NEXT", "LINE_TAB",
                "SPR_H")
        for w in want:
            if w not in symbols:
                sys.exit("--beam needs the symbol %s" % w)
        beam = {"erase": symbols["SPR_RESTORE"], "draw": symbols["SPR_DRAW"],
                "done": symbols["SPRITES_UPDATE_NEXT"],
                "line_tab": symbols["LINE_TAB"], "spr_h": symbols["SPR_H"],
                "open": None, "y": 0, "h": 0, "units": []}

    #: frame -> [(address, byte)], applied as that frame starts.
    pokes = {}
    for item in args.poke:
        where, _, when = item.partition("@")
        name, _, value = where.partition("=")
        addr = symbols.get(name.upper(), None)
        if addr is None:
            addr = int(name, 0)
        pokes.setdefault(int(when), []).append((addr, int(value, 0) & 0xFF))

    failed = False
    debris = None
    if args.debris:
        if not symbols:
            sys.exit("--debris needs --sym")
        want = ("LINE_TAB", "CAT_DRAWN", "CAT_OX", "CAT_OY", "CAT_OW", "CAT_OH",
                "ENEMIES", "ENEMY_COUNT", "E_SIZE", "E_TYPE", "E_DRAWN",
                "E_OX", "E_OY", "E_OW", "E_OH", "CUR_ROOM", "PLAY_TOP",
                "DISPLAY_LINES", "BYTES_PER_LINE")
        for w in want:
            if w not in symbols:
                sys.exit("--debris needs the symbol %s" % w)
        debris = {w.lower(): symbols[w] for w in want}
        debris.update(room=None, skip=0, ref=None, ref_rects=(), worst=0,
                      worst_frame=0, where=None, frames=0)

    steps = 0
    while steps < limit:
        io.clock = cpu.us
        if us_budget is not None and cpu.us >= us_budget:
            reason = "frame budget"
            break
        if beam is not None:
            if cpu.pc == beam["erase"]:
                beam["open"] = cpu.us
            elif cpu.pc == beam["draw"] and beam["open"] is not None:
                beam["y"] = (cpu.ix - beam["line_tab"]) // 2
                beam["h"] = mem[beam["spr_h"]]
            elif cpu.pc == beam["done"] and beam["open"] is not None:
                beam["units"].append((beam["y"], beam["h"],
                                      beam["open"], cpu.us))
                beam["open"] = None
        if pokes:
            f = cpu.us // CPCIO.FRAME_US
            for addr, value in pokes.pop(f, ()):
                mem[addr] = value
                print("  frame %3d  poked #%04X = %d" % (f, addr, value))
        if debris is not None:
            f = cpu.us // CPCIO.FRAME_US
            if f != debris.get("last"):
                debris["last"] = f
                if f >= args.debris_from:
                    debris_scan(mem, debris, f)
        prof_in = None
        if prof is not None and cpu.us >= prof_start:
            i = bisect.bisect_right(prof_addr, cpu.pc) - 1
            if i >= 0:
                prof_in = prof_addr[i]
        us_before = cpu.us
        if watch:
            f = cpu.us // CPCIO.FRAME_US
            if f != last_frame:
                last_frame = f
                cells = []
                for name, addr, kind in watch:
                    if kind == "psg":
                        cells.append("%s=%d" % (name, cpu.io.psg[addr]))
                    elif kind == "b":
                        cells.append("%s=%d" % (name, mem[addr]))
                    else:
                        v = mem[addr] | (mem[addr + 1] << 8)
                        if kind == "s" and v > 32767:
                            v -= 65536
                        cells.append("%s=%d" % (name, v))
                trace.append("  frame %3d  %s" % (f, "  ".join(cells)))
        if cpu.us >= next_irq:
            # 6 x 52 scanlines is 312, so the cadence divides the frame
            # exactly and the phase never has to be nudged back
            next_irq += irq_period
            if cpu.iff and cpu.imode == 1:
                # IM 1: the CPU stacks PC, jumps to #0038 and masks interrupts
                # until the handler re-enables them.
                cpu.halted = False
                cpu.iff = False
                cpu.push(cpu.pc)
                cpu.pc = 0x38
                irqs += 1
        if cpu.halted and not cpu.iff:
            reason = "HALT with interrupts off"
            break
        op = mem[cpu.pc]
        if op == 0x18 and mem[(cpu.pc + 1) & 0xFFFF] == 0xFE:
            reason = "self-jump"
            break
        if op == 0xC3 and (mem[(cpu.pc + 1) & 0xFFFF] |
                           mem[(cpu.pc + 2) & 0xFFFF] << 8) == cpu.pc:
            reason = "self-jump"
            break
        try:
            cpu.step()
        except Unsupported as e:
            sys.exit("z80check: %s - not implemented" % e)
        if prof_in is not None:
            prof[prof_in] += cpu.us - us_before
        steps += 1
    else:
        if not args.frames:
            sys.exit("z80check: still running after %d instructions" % limit)
        reason = "instruction ceiling"

    for spec in args.save_mem:
        where, _, path = spec.partition("=")
        addr, _, length = where.partition(":")
        addr = int(addr, 0)
        length = int(length, 0)
        open(path, "wb").write(bytes(mem[addr:addr + length]))
        print("wrote %s (%d bytes from #%04X)" % (path, length, addr))

    if cpu.sp_hit:
        print("STACK SP reached #%04X on frame %d, at PC #%04X"
              % (cpu.sp_hit[1], cpu.sp_hit[2], cpu.sp_hit[0]))
    if cpu.big_ldir:
        pc, n, src, dst, ret = cpu.big_ldir
        print("LDIR  %d bytes at PC #%04X, HL=#%04X DE=#%04X - a length that "
              "wrapped? Return address on the stack #%04X"
              % (n, pc, src, dst, ret))
    if cpu.trap is not None:
        if cpu.trap_hit:
            pc, v, fr, hl, de, bc, sp, ret = cpu.trap_hit
            print("TRAP  #%04X written with #%02X on frame %d, PC after the "
                  "store #%04X" % (cpu.trap, v, fr, pc))
            print("      HL=#%04X DE=#%04X BC=#%04X SP=#%04X, return address "
                  "on the stack #%04X" % (hl, de, bc, sp, ret))
        else:
            print("TRAP  #%04X never written" % cpu.trap)
    if trace:
        print("WATCH")
        print("\n".join(trace))
    print("stopped at #%04X after %d instructions (%s)" % (cpu.pc, steps, reason))
    held = []
    for name, first, last in keys:
        if first == 0 and last > 1 << 20:
            held.append(name)
        elif last > 1 << 20:
            held.append("%s@%d-" % (name, first))
        else:
            held.append("%s@%d-%d" % (name, first, last))
    print("SIM   %d virtual frames, %d interrupts delivered, %d key matrix reads%s"
          % (cpu.us // CPCIO.FRAME_US, irqs, io.key_reads,
             ", holding " + " ".join(held) if held else ""))
    if io.rmr is None:
        sys.exit("z80check: the code never set a screen mode - nothing to render")
    print("CRTC  " + " ".join("R%d=%d" % (i, io.crtc[i]) for i in range(14)))
    print("GA    RMR=#%02X (mode %d, ROMs %s)  RAM=%s" % (
        io.rmr, io.rmr & 3,
        "off" if (io.rmr & 0x0C) == 0x0C else "#%X" % ((io.rmr >> 2) & 3),
        "#%02X" % io.ram_cfg if io.ram_cfg is not None else "default"))
    print("INK   " + " ".join("%s=%d" % ("border" if k == 0x10 else "pen%d" % k, v)
                              for k, v in sorted(io.ink.items())))

    rows, mode, per_byte = screen_pens(mem, io)
    aspect = pixel_aspect(per_byte)
    print("SCREEN %dx%d pixels%s, %d bytes per line, start address #%04X" % (
        len(rows[0]), len(rows),
        " (%d wide on the tube)" % (len(rows[0]) * aspect) if aspect != 1 else "",
        io.crtc[1] * 2, ((io.crtc[12] & 0x3F) << 8) | io.crtc[13]))

    if debris is not None:
        print()
        print("DEBRIS  every sprite's background is saved before it is drawn "
              "and put back")
        print("        before it moves. Two of them standing in each other "
              "save pieces of")
        print("        each other, and whichever hands its piece back last "
              "leaves it in the")
        print("        room for good. This is that, counted: ink on ground "
              "the room")
        print("        painted empty, where no sprite is.")
        if debris["worst"]:
            x0, x1, y0, y1 = debris["where"]
            print("    %d bytes left behind, worst at frame %d, x %d-%d y %d-%d"
                  % (debris["worst"], debris["worst_frame"], x0, x1, y0, y1))
            failed = True
        else:
            print("    %d frames watched, and the room came through every one "
                  "of them clean" % debris["frames"])

    if beam is not None:
        lines = (io.crtc[4] + 1) * (io.crtc[9] + 1) + io.crtc[5]
        print()
        print("BEAM  a sprite is off the screen from the moment its erase "
              "starts to the moment")
        print("      its redraw finishes. The beam sweeps scanline y at "
              "64y us into every")
        print("      %d us frame. If it crosses the sprite's own rows inside "
              "that window," % (lines * 64))
        print("      it draws a hole, and that is what flicker is.")
        bad = 0
        shown = 0
        for y, h, t0, t1 in beam["units"][args.beam_from:]:
            hit = None
            k = (t0 // (lines * 64)) * (lines * 64)
            while k <= t1 + lines * 64:
                for row in range(y, y + h):
                    when = k + 64 * row
                    if t0 <= when < t1:
                        hit = row
                        break
                if hit is not None:
                    break
                k += lines * 64
            if hit is not None:
                bad += 1
            if os.environ.get("BEAM_HITS") and hit is None:
                pass
            elif shown < 12:
                shown += 1
                print("      rows %3d-%-3d rebuilt over %6d us, beam at %3d "
                      "when it started - %s"
                      % (y, y + h - 1, t1 - t0,
                         (t0 % (lines * 64)) // 64,
                         "caught at row %d" % hit if hit is not None
                         else "clear"))
        total_units = len(beam["units"][args.beam_from:])
        print("    %d of %d sprite rebuilds were caught by the beam" %
              (bad, total_units))

    if prof is not None:
        total = sum(prof.values())
        frames = max(1, cpu.us // CPCIO.FRAME_US - args.profile_from)
        print()
        print("PROFILE  %d us of work over %d frames from frame %d on, which "
              "is %d us" % (total, frames, args.profile_from, total // frames))
        print("         a frame against the 19968 a CPC frame actually has. "
              "One scanline is 64 us.")
        for addr, n in sorted(prof.items(), key=lambda kv: -kv[1])[:20]:
            if not n:
                break
            print("    %8d us  %6d/frame  %5.1f lines  %5.1f%%  %s"
                  % (n, n // frames, n / frames / 64.0, 100.0 * n / total,
                     prof_name.get(addr, "#%04X" % addr)))

    if args.ascii:
        print()
        print(write_ascii(rows, io, 96, aspect))
    if args.png:
        size = write_png(rows, io, args.png, args.scale, aspect)
        print("wrote %s (%dx%d)" % (args.png, size[0], size[1]))
    if args.dump:
        if per_byte != 2:
            sys.exit("z80check: --dump is mode 0 only")
        bits = ((7, 3, 5, 1), (6, 2, 4, 0))
        out = bytearray()
        for row in rows:
            for i in range(0, len(row), 2):
                byte = 0
                for j, pen in enumerate(row[i:i + 2]):
                    for k, b in enumerate(bits[j]):
                        if pen & (1 << k):
                            byte |= 1 << b
                out.append(byte)
        open(args.dump, "wb").write(bytes(out))
        print("wrote %s (%d bytes of screen)" % (args.dump, len(out)))

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

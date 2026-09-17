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
    the frame inside that. So the six-to-one relationship the code depends on
    is real, but nothing about raster position or how long a routine takes is.
  * No ROMs, no 128K banking - a flat 64K of RAM.
  * One static frame at the end of the run, decoded from the CRTC registers
    left set then. Rupture (reprogramming R12/R13 mid-frame) is invisible.
  * Only the PPI ports the keyboard and VSYNC need are modelled; every other
    read returns #FF.

It aborts on any opcode it does not implement rather than guessing, so a clean
run means the code really did execute.
"""

import argparse
import sys

PARITY = [bin(i).count("1") % 2 == 0 for i in range(256)]


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

    # -- memory / fetch -----------------------------------------------------
    def rb(self, a):
        return self.m[a & 0xFFFF]

    def wb(self, a, v):
        self.m[a & 0xFFFF] = v & 0xFF

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
    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF
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
                elif op == 0xD9: self.r, self.r2 = self.r2, self.r
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
            elif op == 0xD3: self.io.out((self.r[7] << 8) | self.fetch(), self.r[7])
            elif op == 0xDB: self.r[7] = self.io.inp((self.r[7] << 8) | self.fetch())
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
        mid = (op >> 3) & 7
        if op & 0xC7 == 0x40:                           # in r,(c)
            v = self.io.inp(self.bc)
            if mid != 6:
                self.r[mid] = v
            self.hf = self.nf = False
            self.pf = PARITY[v]
            self._sz(v)
            return
        if op & 0xC7 == 0x41:                           # out (c),r
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
    def __init__(self, keys=(), frame_instr=6000):
        self.crtc = [0] * 18
        self.crtc_sel = 0
        self.pen = 0
        self.ink = {}
        self.rmr = None
        self.ram_cfg = None

        # PPI / PSG state, enough for the keyboard and the VSYNC bit
        self.ppi_a = 0
        self.ppi_a_input = False
        self.ppi_c = 0
        self.psg_reg = 0
        self.keys = keys            # (name, first frame, last frame)
        self.clock = 0
        self.frame_instr = frame_instr
        self.key_reads = 0

    def vsync(self):
        return (self.clock % self.frame_instr) < self.frame_instr // 8

    def frame(self):
        return self.clock // self.frame_instr

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
        elif hi == 0xF6:                        # PPI port C - PSG function
            self.ppi_c = val
            if (val >> 6) == 3:                 # 11 = select register
                self.psg_reg = self.ppi_a
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


def write_png(rows, io, path, scale):
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
    if scale != 1:
        img = img.resize((w * scale, h * scale), Image.NEAREST)
    img.save(path)
    return img.size


def write_ascii(rows, io, cols):
    """Coarse terminal preview: one character per block, darkest pen wins."""
    ramp = " .:-=+*#%@"
    h, w = len(rows), len(rows[0])
    step_x = max(1, w // cols)
    step_y = step_x * 2                       # characters are about twice as tall
    out = []
    for y in range(0, h, step_y):
        line = []
        for x in range(0, w, step_x):
            r, g, b = HW_RGB[io.ink.get(rows[y][x], 20)]
            line.append(ramp[min(9, (r + g + b) * 10 // 766)])
        out.append("".join(line))
    return "\n".join(out)


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary", help="raw assembled code (make bin)")
    ap.add_argument("--org", default="0x4000", help="load and entry address (default 0x4000)")
    ap.add_argument("--png", help="write the decoded screen here")
    ap.add_argument("--scale", type=int, default=2, help="PNG pixel scale (default 2)")
    ap.add_argument("--ascii", action="store_true", help="print a terminal preview")
    ap.add_argument("--keys", default="",
                    help="keys held down, comma separated. NAME is held the "
                         "whole run, NAME@12 from frame 12 on, NAME@12-14 for "
                         "those frames only - e.g. FIRE@12-13,RIGHT@15")
    ap.add_argument("--sym", help="rasm symbol file (rasm -s -sl -os ...)")
    ap.add_argument("--watch", default="",
                    help="comma separated symbols to print once per frame, "
                         "optionally with a byte offset (enemies+8); suffix "
                         ":w for a 16-bit value, :s for signed 16-bit")
    ap.add_argument("--frames", type=int, default=0,
                    help="stop after this many virtual frames (0 = only on a "
                         "self-jump or HALT)")
    ap.add_argument("--frame-instr", type=int, default=12000,
                    help="instructions per virtual frame (default 12000, roughly "
                         "what a 19968 us CPC frame gets through)")
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
        if not args.sym:
            sys.exit("z80check: --watch needs --sym")
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
    cpu = Z80(mem, io)
    cpu.pc = org
    cpu.sp = 0xC000

    irq_period = max(1, args.frame_instr // 6)
    budget = args.frames * args.frame_instr if args.frames else args.max_steps
    limit = min(budget, args.max_steps)
    next_irq = irq_period
    irqs = 0
    reason = "instruction budget"
    last_frame = -1
    trace = []

    steps = 0
    while steps < limit:
        io.clock = steps
        if watch:
            f = steps // args.frame_instr
            if f != last_frame:
                last_frame = f
                cells = []
                for name, addr, kind in watch:
                    if kind == "b":
                        cells.append("%s=%d" % (name, mem[addr]))
                    else:
                        v = mem[addr] | (mem[addr + 1] << 8)
                        if kind == "s" and v > 32767:
                            v -= 65536
                        cells.append("%s=%d" % (name, v))
                trace.append("  frame %3d  %s" % (f, "  ".join(cells)))
        if steps >= next_irq:
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
        steps += 1
    else:
        if not args.frames:
            sys.exit("z80check: still running after %d instructions" % limit)
        reason = "frame budget"

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
          % (steps // args.frame_instr, irqs, io.key_reads,
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

    rows, mode, _ = screen_pens(mem, io)
    print("SCREEN %dx%d pixels, %d bytes per line, start address #%04X" % (
        len(rows[0]), len(rows), io.crtc[1] * 2,
        ((io.crtc[12] & 0x3F) << 8) | io.crtc[13]))

    if args.ascii:
        print()
        print(write_ascii(rows, io, 96))
    if args.png:
        size = write_png(rows, io, args.png, args.scale)
        print("wrote %s (%dx%d)" % (args.png, size[0], size[1]))


if __name__ == "__main__":
    main()

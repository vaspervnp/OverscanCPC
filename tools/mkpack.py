#!/usr/bin/env python3
"""Pack the game's tables so the file has room for anything else.

The low block - font, strings, sprites, artwork, enemy kinds and every room -
is twelve and a half kilobytes of the twenty-six the file is allowed to be,
and every byte of it is carried verbatim. It does not have to be. It is read
only, it is moved into place before anything else happens, and it compresses
to about two thirds.

    tools/mkpack.py build/tables.bin src/tablepack.asm 0x0100
    tools/mkpack.py build/mitsosart.bin src/mitsosartpack.asm 0x0100 art

A fourth argument renames what comes out - ART_PACKED_LEN and art_packed
rather than TABLE_ - because the second game's low block is pictures and
calling them tables in its source would be a lie.

The format is LZSS, and it is shaped around the fact that the tables always
unpack to the same address:

    flag byte, most significant bit first, eight items to a byte
      1  a literal, one byte
      0  a match: length, then the ADDRESS it is copied from, low byte first

A match carrying its source address rather than a distance means the whole of
what has been unpacked so far is the window - there is no 4096-byte limit and
no arithmetic in the decoder, which is an LDIR and nothing else. It costs a
byte a match against a 12-bit offset, and wins it back on the longer reach.

A length of zero ends the stream.

The parse is optimal, not greedy: the cost of every position is worked out
from the end backwards, in eighths of a byte so the flag bits count, and each
position takes whichever of literal-or-match leads to the cheaper finish. The
result is decoded again here and compared with the input, so a packed table
that would not come back is a build error, not a crash on the machine.
"""

import os
import sys

MINLEN = 3          # a match costs 25 eighths, three literals 27, so even
                    # a three-byte match is worth having
MAXLEN = 255        # the length is one byte, and 0 ends the stream
LIT_COST = 8 * 1 + 1
MATCH_COST = 8 * 3 + 1


def longest_matches(src):
    """For each position, the longest earlier match and where it starts."""
    index = {}
    best = [(0, 0)] * len(src)
    for i in range(len(src)):
        key = src[i:i + MINLEN]
        if len(key) == MINLEN:
            blen, bpos = 0, 0
            for j in index.get(key, ()):
                n = 0
                limit = min(MAXLEN, len(src) - i)
                while n < limit and src[j + n] == src[i + n]:
                    n += 1
                if n > blen:
                    blen, bpos = n, j
            best[i] = (blen, bpos)
            runs = index.setdefault(key, [])
            runs.append(i)
            if len(runs) > 128:         # enough candidates; keep it quick
                del runs[0]
    return best


def pack(src, base):
    best = longest_matches(src)
    n = len(src)

    #: cost[i] is the cheapest way to finish from i, in eighths of a byte.
    cost = [0] * (n + 1)
    take = [0] * (n + 1)                # 0 = literal, else the match length
    for i in range(n - 1, -1, -1):
        c = LIT_COST + cost[i + 1]
        t = 0
        blen, _bpos = best[i]
        for ln in range(MINLEN, blen + 1):
            c2 = MATCH_COST + cost[i + ln]
            if c2 < c:
                c, t = c2, ln
        cost[i] = c
        take[i] = t

    out = bytearray()
    flags = 0
    nflag = 0
    buf = bytearray()
    i = 0
    lits = matches = 0
    while i < n:
        ln = take[i]
        if ln:
            src_addr = base + best[i][1]
            buf += bytes([ln, src_addr & 0xFF, src_addr >> 8])
            i += ln
            matches += 1
        else:
            buf.append(src[i])
            flags |= 1 << (7 - nflag)
            i += 1
            lits += 1
        nflag += 1
        if nflag == 8:
            out.append(flags)
            out += buf
            flags, nflag, buf = 0, 0, bytearray()
    # the end marker is a match, so its flag bit stays 0
    buf.append(0)
    out.append(flags)
    out += buf
    return bytes(out), lits, matches


def unpack(packed, base, length):
    """The decoder, in Python, so the build can prove the Z80 one is possible."""
    out = bytearray()
    i = 0
    while True:
        flags = packed[i]
        i += 1
        for bit in range(8):
            if flags & (0x80 >> bit):
                out.append(packed[i])
                i += 1
            else:
                ln = packed[i]
                if ln == 0:
                    if len(out) != length:
                        sys.exit("mkpack: stream ends at %d, wanted %d"
                                 % (len(out), length))
                    return bytes(out)
                at = packed[i + 1] | (packed[i + 2] << 8)
                i += 3
                at -= base
                for k in range(ln):
                    out.append(out[at + k])


def main():
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__.strip().splitlines()[0])
    raw = open(sys.argv[1], "rb").read()
    out_asm = sys.argv[2]
    base = int(sys.argv[3], 0)
    what = sys.argv[4] if len(sys.argv) > 4 else "table"

    packed, lits, matches = pack(raw, base)
    back = unpack(packed, base, len(raw))
    if back != raw:
        sys.exit("mkpack: the packed tables do not come back")

    name = os.path.basename(sys.argv[1])
    with open(out_asm, "w", encoding="utf-8") as fh:
        fh.write(";; Generated by tools/mkpack.py from %s - do not edit.\n;;\n"
                 % name)
        fh.write(";; The game's low block, LZSS packed. See the tool for the\n")
        fh.write(";; format; src/unpack.asm has the decoder, forty bytes of it.\n")
        fh.write(";; %d bytes in %d, %d literals and %d matches.\n\n"
                 % (len(raw), len(packed), lits, matches))
        fh.write("%-16s EQU %d\n" % (what.upper() + "_RAW_LEN", len(raw)))
        fh.write("%-16s EQU %d\n\n" % (what.upper() + "_PACKED_LEN",
                                         len(packed)))
        fh.write("%s_packed\n" % what)
        for i in range(0, len(packed), 16):
            fh.write("    defb %s\n"
                     % ",".join("#%02X" % b for b in packed[i:i + 16]))
    print("mkpack: %d bytes of tables packed to %d, %d%% - %d bytes back"
          % (len(raw), len(packed), 100 * len(packed) // len(raw),
             len(raw) - len(packed)))


if __name__ == "__main__":
    main()

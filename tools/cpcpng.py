#!/usr/bin/env python3
"""A PNG reader, so the build needs nothing that is not in the standard library.

Aseprite writes 8-bit RGBA, uninterlaced; the other colour types are here
because a one-line check beats a confusing failure. Both art converters read
their pictures through this - tools/mkart.py for the mode 0 game and
tools/mkmitsos.py for the mode 1 one - so there is one place that knows what
a PNG is.
"""

import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("%s: not a PNG" % path)
    idat = b""
    plte = trns = None
    pos = 8
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, colour, _comp, _filt, interlace = struct.unpack(
                ">IIBBBBB", body)
            if depth != 8 or interlace:
                sys.exit("%s: %d-bit%s PNG - save it as 8 bits, uninterlaced"
                         % (path, depth, " interlaced" if interlace else ""))
            if colour not in (2, 3, 6):
                sys.exit("%s: colour type %d is not supported" % (path, colour))
        elif kind == b"PLTE":
            plte = body
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length

    per = {2: 3, 3: 1, 6: 4}[colour]
    raw = zlib.decompress(idat)
    stride = w * per
    out = []
    prev = bytearray(stride)
    pos = 0
    for _y in range(h):
        filt = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - per] if i >= per else 0
            b = prev[i]
            c = prev[i - per] if i >= per else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
            elif filt:
                sys.exit("%s: filter %d" % (path, filt))
        prev = line
        out.append(bytes(line))
    return w, h, colour, plte, trns, out

#!/usr/bin/env python3
"""Convert the testbench's ASCII PPM frame to PNG (stdlib only)."""
import struct
import sys
import zlib

src, dst = sys.argv[1], sys.argv[2]
tok = open(src).read().split()
w, h = int(tok[1]), int(tok[2])
px = list(map(int, tok[4:4 + w * h * 3]))
raw = b"".join(b"\x00" + bytes(px[y * w * 3:(y + 1) * w * 3]) for y in range(h))
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(dst, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                      + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

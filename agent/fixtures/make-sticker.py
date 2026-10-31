#!/usr/bin/env python3
"""make-sticker.py: draw the workshop's fox sticker as a 128x128 PNG (sticker.png), deterministically.

A PNG, not SVG: the sticker crosses machines from a stranger's agent, and SVG can carry script.
"""
import struct, zlib

W = H = 128
BLUE, YELLOW, BLACK, CLEAR = (75, 123, 236, 255), (247, 183, 49, 255), (0, 0, 0, 255), (0, 0, 0, 0)
EARS = [(24, 96), (40, 30), (64, 56), (88, 30), (104, 96)]

def inside_rounded(x, y, r=24):
    cx = min(max(x, r), W - r); cy = min(max(y, r), H - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r

def inside_poly(x, y, pts):
    c = False
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c

def pixel(x, y):
    px, py = x + 0.5, y + 0.5
    if not inside_rounded(px, py):
        return CLEAR
    for cx, cy in ((52, 72), (76, 72)):
        if (px - cx) ** 2 + (py - cy) ** 2 <= 25:
            return BLACK
    return YELLOW if inside_poly(px, py, EARS) else BLUE

raw = b"".join(b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(W)) for y in range(H))
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open("sticker.png", "wb").write(png)

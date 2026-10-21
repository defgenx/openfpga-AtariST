#!/usr/bin/env python3
"""Generate the platform image dist/Platforms/_images/atarist.bin (an Atari 520STFM).

  tools/gen_platform_image.py [preview.png]

The Pocket format is 521x165, stored rotated 90 degrees counter-clockwise, one
little-endian 16-bit word per pixel with the brightness in the low byte (0 = black).
The optional PNG is a preview as the Pocket shows it.
"""
import struct
import sys
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "dist/Platforms/_images/atarist.bin"
W, H = 521, 165

# Case in millimetres: X right, Y towards the back, Z up; the top slopes from front to back.
CASE_W, CASE_D, FRONT_H, BACK_H = 470, 220, 24, 56
SCALE, SHEAR_X, SHEAR_Y = 0.56, 0.30, 0.62
ORIGIN = (108, 147)
U = 18.5  # key pitch

BODY_TOP, BODY_FRONT, BODY_SIDE, EDGE = 150, 105, 70, 200
KEY_TOP, KEY_FACE, KEY_DARK, SLOT = 225, 120, 175, 20

img = [[0] * W for _ in range(H)]


def height(y):
    return FRONT_H + (BACK_H - FRONT_H) * y / CASE_D


def proj(x, y, z):
    sx = ORIGIN[0] + SCALE * (x + SHEAR_X * y)
    sy = ORIGIN[1] - SCALE * (z + SHEAR_Y * y)
    return sx, sy


def top(x, y, lift=0.0):
    return proj(x, y, height(y) + lift)


def fill(poly, value):
    ys = [p[1] for p in poly]
    for py in range(max(0, int(min(ys))), min(H, int(max(ys)) + 2)):
        cy = py + 0.5
        xs = []
        for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
            if (y0 <= cy < y1) or (y1 <= cy < y0):
                xs.append(x0 + (cy - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            for px in range(max(0, round(a)), min(W, round(b))):
                img[py][px] = value


def line(p0, p1, value):
    (x0, y0), (x1, y1) = p0, p1
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n + 1):
        px, py = round(x0 + (x1 - x0) * i / n - 0.5), round(y0 + (y1 - y0) * i / n - 0.5)
        if 0 <= px < W and 0 <= py < H:
            img[py][px] = value


def outline(poly, value):
    for a, b in zip(poly, poly[1:] + poly[:1]):
        line(a, b, value)


def key(x, y, w, d, shear=0.0, top_value=KEY_TOP):
    """A key of w x d mm at (x, y) on the deck; shear slants it (function keys)."""
    g, lift = 1.6, 3.0
    x0, x1, y0, y1 = x + g, x + w - g, y + g, y + d - g
    face = [top(x0, y0, lift), top(x1, y0, lift), top(x1, y0), top(x0, y0)]
    cap = [top(x0, y0, lift), top(x1, y0, lift), top(x1 + shear, y1, lift), top(x0 + shear, y1, lift)]
    fill(face, KEY_FACE)
    fill(cap, top_value)


def draw_case():
    front = [proj(0, 0, 0), proj(CASE_W, 0, 0), proj(CASE_W, 0, FRONT_H), proj(0, 0, FRONT_H)]
    side = [proj(CASE_W, 0, 0), proj(CASE_W, CASE_D, 0), proj(CASE_W, CASE_D, BACK_H), proj(CASE_W, 0, FRONT_H)]
    deck = [top(0, 0), top(CASE_W, 0), top(CASE_W, CASE_D), top(0, CASE_D)]
    fill(front, BODY_FRONT)
    fill(side, BODY_SIDE)
    fill(deck, BODY_TOP)
    for poly in (front, side, deck):
        outline(poly, EDGE)

    # Floppy drive on the right side: slot and eject button.
    slot = [proj(CASE_W, 70, 14), proj(CASE_W, 160, 14), proj(CASE_W, 160, 19), proj(CASE_W, 70, 19)]
    fill(slot, SLOT)
    fill([proj(CASE_W, 168, 12), proj(CASE_W, 182, 12), proj(CASE_W, 182, 20), proj(CASE_W, 168, 20)], KEY_DARK)

    # Vent slots along the back of the deck.
    for i in range(14):
        x = 28 + i * 11
        line(top(x, 196), top(x, 212), BODY_FRONT)


def draw_keyboard():
    x0, y0 = 18, 16
    # Main block, back row first so front rows overlap correctly.
    rows = [
        [1.5, 1.5, 9.0, 1.5, 1.5],                               # space row: Alt, Caps, Space...
        [2.25] + [1] * 10 + [2.75],                              # Shift ... Shift
        [1.75] + [1] * 11 + [2.25],                              # Control ... Return
        [1.5] + [1] * 12 + [1.5],                                # Tab ... Delete
        [1] * 13 + [2],                                          # Esc ... Backspace
    ]
    for r in reversed(range(len(rows))):
        x = x0
        for w in rows[r]:
            key(x, y0 + r * U, w * U, U, top_value=KEY_DARK if w >= 1.5 else KEY_TOP)
            x += w * U
    main_w = sum(rows[0]) * U

    fy = y0 + 5 * U + 6
    for i in range(10):
        key(x0 + 0.4 * U + i * 1.45 * U, fy, 1.45 * U, 0.8 * U, shear=6)

    # Cursor block: Help/Undo, Insert/Up/Clr, Left/Down/Right.
    cx = x0 + main_w + 0.5 * U
    key(cx, y0 + 4 * U, 1.5 * U, U, top_value=KEY_DARK)
    key(cx + 1.5 * U, y0 + 4 * U, 1.5 * U, U, top_value=KEY_DARK)
    for i in range(3):
        key(cx + i * U, y0 + 3 * U, U, U)
        key(cx + i * U, y0 + 2 * U, U, U)

    # Keypad: 4 x 5 with a tall Enter and a wide 0.
    kx = cx + 3.5 * U
    for r in reversed(range(1, 5)):
        for c in range(4):
            if c == 3 and r == 1:
                key(kx + c * U, y0, U, 2 * U, top_value=KEY_DARK)
            elif not (c == 3 and r == 0):
                key(kx + c * U, y0 + r * U, U, U)
    key(kx, y0, 2 * U, U)
    key(kx + 2 * U, y0, U, U)
    return kx


def draw_badge(kx):
    """Fuji logo and a 520 ST plate on the deck behind the keypad."""
    fuji = ["1.1.1",
            "1.1.1",
            "1.1.1",
            "1.1.1",
            "11.11",
            "1...1"]
    bx, by = top(kx + 6, 190)
    bx, by = round(bx), round(by)
    for j, row in enumerate(fuji):
        for i, c in enumerate(row):
            if c == "1":
                img[by + j][bx + i] = 255
    plate = [top(kx + 22, 178), top(kx + 70, 178), top(kx + 70, 200), top(kx + 22, 200)]
    fill(plate, BODY_SIDE)
    outline(plate, EDGE)


def write_png(path):
    rows = b"".join(b"\0" + bytes(r) for r in img)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


def main():
    draw_case()
    draw_badge(draw_keyboard())
    # Rotate 90 degrees counter-clockwise: stored row i is image column W-1-i.
    words = [img[y][x] for x in reversed(range(W)) for y in range(H)]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(struct.pack(f"<{len(words)}H", *words))
    if len(sys.argv) > 1:
        write_png(sys.argv[1])


if __name__ == "__main__":
    main()

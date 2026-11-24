"""Convert a picture to a C64 multicolour bitmap (Koala format).

    python tools/img2c64.py picture.png [-o art/title] [--bg N] [--dither bayer|fs|none] [--only 0,11,12,15,1]
                                        [--strength 40] [--crop center|top|bottom]

Any size: cropped to the C64 frame (320x200 shape), scaled to 160x200 fat
pixels, mapped to the 16 colours and dithered.
Exactly 160x200: taken as finished pixel art, each pixel snaps to the
nearest C64 colour, no scaling or dithering.

Either way every 4x8 cell may hold only 3 colours plus the one background
colour; cells that had more are fixed by picking the 3 that fit best.

Writes, next to the -o name:
    .kla        Koala picture the game loads (10003 bytes)
    _edit.png   the result at 160x200: edit it and convert it again
    _preview.png  how it looks on the C64 (wide pixels, 2x)
    _clash.png  the preview with fixed cells marked red
    c64.act / c64.gpl  the palette for Photoshop / GIMP / Aseprite (in tools/)
"""
import argparse
import itertools
import os

import numpy as np
from PIL import Image

# colodore palette (close to a real PAL C64)
PALETTE = np.array([
    (0x00, 0x00, 0x00), (0xff, 0xff, 0xff), (0x81, 0x33, 0x38), (0x75, 0xce, 0xc8),
    (0x8e, 0x3c, 0x97), (0x56, 0xac, 0x4d), (0x2e, 0x2c, 0x9b), (0xed, 0xf1, 0x71),
    (0x8e, 0x50, 0x29), (0x55, 0x38, 0x00), (0xc4, 0x6c, 0x71), (0x4a, 0x4a, 0x4a),
    (0x7b, 0x7b, 0x7b), (0xa9, 0xff, 0x9f), (0x70, 0x6d, 0xeb), (0xb2, 0xb2, 0xb2),
], dtype=np.float64)
NAMES = ["black", "white", "red", "cyan", "purple", "green", "blue", "yellow",
         "orange", "brown", "light red", "dark grey", "grey", "light green",
         "light blue", "light grey"]

W, H = 160, 200
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.47


def dist2(pixels, colours):
    """Weighted squared distance, pixels (..., 3) against colours (k, 3) -> (..., k)."""
    d = pixels[..., None, :] - colours
    rmean = (pixels[..., None, 0] + colours[:, 0]) / 2
    return ((2 + rmean / 256) * d[..., 0] ** 2 + 4 * d[..., 1] ** 2
            + (2 + (255 - rmean) / 256) * d[..., 2] ** 2)


def nearest(pixels, allowed):
    """Index into `allowed` (list of palette numbers) for each pixel."""
    return np.argmin(dist2(pixels, PALETTE[allowed]), axis=-1)


def load(path, crop):
    img = Image.open(path).convert("RGB")
    if img.size == (W, H):
        return np.asarray(img, dtype=np.float64), True
    # crop to the 320x200 shape (1.6 : 1), then squash to 160 fat pixels
    w, h = img.size
    if w / h > 1.6:
        nw = round(h * 1.6)
        x0 = (w - nw) // 2
        img = img.crop((x0, 0, x0 + nw, h))
    else:
        nh = round(w / 1.6)
        y0 = {"top": 0, "bottom": h - nh}.get(crop, (h - nh) // 2)
        img = img.crop((0, y0, w, y0 + nh))
    img = img.resize((W, H), Image.LANCZOS)
    return np.asarray(img, dtype=np.float64), False


def convert(rgb, pixel_art, bg, dither, strength, only):
    if pixel_art or dither == "none":
        target = rgb
    elif dither == "bayer":
        ys, xs = np.mgrid[0:H, 0:W]
        target = rgb + (BAYER4[ys % 4, xs % 4] * strength)[..., None]
    else:
        target = rgb  # Floyd-Steinberg is done per cell below

    free = np.array(only)[nearest(target, only)]
    if bg is None:  # the most used colour is the background
        bg = int(np.bincount(free.ravel(), minlength=16).argmax())

    out = np.zeros((H, W), dtype=np.int64)
    clashed = np.zeros((25, 40), dtype=bool)
    for cy in range(25):
        for cx in range(40):
            ys, xs = slice(cy * 8, cy * 8 + 8), slice(cx * 4, cx * 4 + 4)
            cell_t = target[ys, xs]
            used = [c for c in np.unique(free[ys, xs]) if c != bg]
            if len(used) > 3:
                clashed[cy, cx] = True
                # try every 3 of the 6 most used, keep the closest fit
                counts = np.bincount(free[ys, xs].ravel(), minlength=16)
                cands = sorted(used, key=lambda c: -counts[c])[:6]
                best, best_err = None, None
                for trio in itertools.combinations(cands, 3):
                    allowed = [bg, *trio]
                    err = dist2(cell_t, PALETTE[allowed]).min(axis=-1).sum()
                    if best_err is None or err < best_err:
                        best, best_err = allowed, err
                allowed = best
            else:
                allowed = [bg, *used]
            if dither == "fs" and not pixel_art:
                out[ys, xs] = fs_cell(rgb[ys, xs].copy(), allowed)
            else:
                out[ys, xs] = np.array(allowed)[nearest(cell_t, allowed)]
    return out, bg, clashed


def fs_cell(cell, allowed):
    res = np.zeros(cell.shape[:2], dtype=np.int64)
    pal = PALETTE[allowed]
    for y in range(cell.shape[0]):
        for x in range(cell.shape[1]):
            i = int(nearest(cell[y, x], allowed))
            res[y, x] = allowed[i]
            err = cell[y, x] - pal[i]
            for dx, dy, f in ((1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)):
                if 0 <= x + dx < cell.shape[1] and y + dy < cell.shape[0]:
                    cell[y + dy, x + dx] += err * f / 16
    return res


def koala(idx, bg):
    """Koala: load address $6000, bitmap 8000, screen 1000, colour 1000, bg 1."""
    bitmap = bytearray(8000)
    screen = bytearray(1000)
    colour = bytearray(1000)
    for cy in range(25):
        for cx in range(40):
            cell = idx[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4]
            others = [c for c in np.unique(cell) if c != bg]
            others += [0] * (3 - len(others))
            c1, c2, c3 = others[:3]
            code = {bg: 0, c1: 1, c2: 2, c3: 3}
            n = cy * 40 + cx
            screen[n] = (c1 << 4) | c2      # bits 01: high nibble, 10: low nibble
            colour[n] = c3                  # bits 11: colour RAM
            for row in range(8):
                b = 0
                for px in range(4):
                    b = (b << 2) | code[int(cell[row, px])]
                bitmap[n * 8 + row] = b
    return bytes([0x00, 0x60]) + bitmap + screen + colour + bytes([bg])


def save_palettes(folder):
    act = bytearray(768)
    for i, (r, g, b) in enumerate(PALETTE.astype(int)):
        act[i * 3:i * 3 + 3] = bytes((r, g, b))
    act += bytes((0, 16, 0xff, 0xff))       # 16 colours, no transparent one
    with open(os.path.join(folder, "c64.act"), "wb") as f:
        f.write(act)
    with open(os.path.join(folder, "c64.gpl"), "w") as f:
        f.write("GIMP Palette\nName: C64 (colodore)\nColumns: 4\n#\n")
        for (r, g, b), name in zip(PALETTE.astype(int), NAMES):
            f.write(f"{r:3d} {g:3d} {b:3d}\t{name}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("-o", "--out", help="output name without extension (default: next to the image)")
    ap.add_argument("--bg", type=int, help="background colour 0-15 (default: the most used)")
    ap.add_argument("--dither", choices=["bayer", "fs", "none"], default="bayer")
    ap.add_argument("--strength", type=float, default=40, help="bayer dither strength (default 40)")
    ap.add_argument("--only", help="use only these colours, e.g. 0,11,12,15,1 for greys")
    ap.add_argument("--crop", choices=["center", "top", "bottom"], default="center")
    a = ap.parse_args()

    out = a.out or os.path.splitext(a.image)[0]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    rgb, pixel_art = load(a.image, a.crop)
    only = [int(c) for c in a.only.split(",")] if a.only else list(range(16))
    idx, bg, clashed = convert(rgb, pixel_art, a.bg, a.dither, a.strength, only)

    with open(out + ".kla", "wb") as f:
        f.write(koala(idx, bg))
    pic = Image.fromarray(PALETTE[idx].astype(np.uint8))
    pic.save(out + "_edit.png")
    pic.resize((640, 400), Image.NEAREST).save(out + "_preview.png")
    marked = PALETTE[idx].copy()
    for cy, cx in zip(*np.nonzero(clashed)):
        marked[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4] = marked[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4] * 0.5 + (128, 0, 0)
    Image.fromarray(marked.astype(np.uint8)).resize((640, 400), Image.NEAREST).save(out + "_clash.png")
    save_palettes(os.path.dirname(os.path.abspath(__file__)))

    kind = "pixel art (160x200)" if pixel_art else "picture, scaled and dithered"
    print(f"{a.image}: {kind}, background {bg} ({NAMES[bg]}), "
          f"{int(clashed.sum())} of 1000 cells fixed -> {out}.kla")


if __name__ == "__main__":
    main()

"""The view's art for Derelict (bitmap version).

  python tools/art.py paint     paint art/view.png from code (OVERWRITES your edits!)
  python tools/art.py convert   art/view.png -> src/gen/view_art.asm (build.bat runs this)

art/view.png is a sheet of 18 frames (6 x 3), each the whole 20 x 20 cell view
(160 x 160 pixels; one C64 multicolour pixel = 2 screen pixels wide). Frame 0 is the
background (floor, ceiling, lamps), the others are the pieces the engine stacks far to
near: walls ahead, side walls, side openings, doors. Each frame only uses the cells of
its piece; magenta cells aren't part of it. Paint with the 16 C64 colours. In every
8 x 8 cell: black plus at most 3 other colours (the converter squeezes extra colours to
the nearest of the 3, and says how many cells it had to squeeze).
"""
import os, sys, random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PNG = os.path.join(ROOT, 'art', 'view.png')
OUT = os.path.join(ROOT, 'src', 'gen', 'view_art.asm')

VW = VH = 20
INSET = [0, 4, 7, 9]
FW, FH = VW * 4, VH * 8          # a frame in multicolour pixels: 80 x 160
COLS = 6                         # frames per sheet row
MAGENTA = (255, 0, 255)

# the C64 palette (Pepto)
PAL = [(0, 0, 0), (255, 255, 255), (104, 55, 43), (112, 164, 178), (111, 61, 134), (88, 141, 67),
       (53, 40, 121), (184, 199, 111), (111, 79, 37), (67, 57, 0), (154, 103, 89), (68, 68, 68),
       (108, 108, 108), (154, 210, 132), (108, 94, 181), (149, 149, 149)]
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW, ORANGE, BROWN, LRED, DGREY, GREY, LGREEN, LBLUE, LGREY = range(16)

# ---------------------------------------------------------------- the pieces (cells)
def front_cells(k):
    a = INSET[k]
    return [(c, r) for r in range(a, VH - a) for c in range(a, VW - a)]

def lside_cells(f):
    out = []
    for c in range(INSET[f], INSET[f + 1]):
        out += [(c, r) for r in range(c, VH - c)]
    return out

def lopen_cells(f):
    a = INSET[f + 1]
    return [(c, r) for c in range(INSET[f], INSET[f + 1]) for r in range(a, VH - a)]

def mirror(cells):
    return [(VW - 1 - c, r) for c, r in cells]

DOOR1 = [(c, r) for r in range(7, 16) for c in range(7, 13)]
DOOR2 = [(c, r) for r in range(9, 13) for c in range(9, 11)]

# (name, cells, depth, preferred ink colour)  - the order is the engine's piece numbers
PIECES = ([('front%d' % k, front_cells(k), k, None) for k in (1, 2, 3)] +
          [('lside%d' % f, lside_cells(f), f, None) for f in (0, 1, 2)] +
          [('lopen%d' % f, lopen_cells(f), f + 1, None) for f in (0, 1, 2)] +
          [('rside%d' % f, mirror(lside_cells(f)), f, None) for f in (0, 1, 2)] +
          [('ropen%d' % f, mirror(lopen_cells(f)), f + 1, None) for f in (0, 1, 2)] +
          [('door1', DOOR1, 1, CYAN), ('door2', DOOR2, 2, CYAN)])
FRAMES = [('background', [(c, r) for r in range(VH) for c in range(VW)], None, None)] + PIECES

def row_depth(r):
    d = min(r, VH - 1 - r)
    return 0 if d < INSET[1] else 1 if d < INSET[2] else 2 if d < INSET[3] else 3

# ---------------------------------------------------------------- painting
B4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

def bayer(x, y):
    return (B4[y % 4][x % 4] + 0.5) / 16

def mix(lo, hi, t, x, y):
    """t of hi, the rest lo, as an ordered dither"""
    return hi if t > bayer(x, y) else lo

def ramp(cols, light, x, y):
    light = max(0.0, min(len(cols) - 1.0, light))
    i = int(light)
    if i >= len(cols) - 1:
        return cols[-1]
    return mix(cols[i], cols[i + 1], light - i, x, y)

rnd = random.Random(64)
GRIME = {}
def grime(x, y, amount):
    if (x, y) not in GRIME:
        GRIME[(x, y)] = rnd.random()
    return GRIME[(x, y)] < amount

def background(x, y):
    """the ceiling (dark blue, yellow lamps) and the floor (brown plates), into the dark"""
    if y < FH // 2:                                  # ceiling
        far = y / (FH / 2)                           # 0 overhead .. 1 the horizon
        for k in (1, 2, 3):
            if y == INSET[k] * 8 - 1:
                return BLACK
        if 28 <= x <= 51 and 11 <= y <= 15:          # the lamp overhead
            if 13 <= y <= 14 and 30 <= x <= 49:
                return WHITE
            return YELLOW
        if 25 <= x <= 54 and 9 <= y <= 17:           # its glow
            return mix(BLUE, YELLOW, 0.35, x, y)
        if 35 <= x <= 44 and 42 <= y <= 44:          # the next one
            return YELLOW if y == 43 else mix(BLUE, YELLOW, 0.5, x, y)
        light = max(0.0, 1.05 - far * 1.25)
        return mix(BLACK, BLUE, light, x, y)
    far = (FH - 1 - y) / (FH / 2)                    # floor: 0 at your feet .. 1 the horizon
    for k in (1, 2, 3):
        if y == FH - INSET[k] * 8:
            return BLACK
        if y == FH - INSET[k] * 8 + 1 and far < 0.6:
            return ORANGE                            # the lit edge of each plate
    light = max(0.0, 1.05 - far * 1.3)
    if far < 0.35 and (x % 4 == 1) and (y % 4 == 2):  # tread dots near you
        return ORANGE
    return mix(BLACK, BROWN, light, x, y)

# the wall facing you at plane k: bulkhead panels, bevels, bolts, a vent along the bottom
WALL = {1: (GREY, LGREY, DGREY), 2: (DGREY, GREY, DGREY), 3: (BLACK, DGREY, DGREY)}

def front(k, x, y):
    x0, y0 = INSET[k] * 4, INSET[k] * 8
    w, h = FW - 2 * x0, FH - 2 * y0
    px, py = x - x0, y - y0
    half_w, half_h = w // 2, h // 2
    body, hi, sh = WALL[k]
    if k == 3:
        return mix(BLACK, DGREY, 0.55, x, y)
    pu = px % half_w                                 # inside a panel
    pv = py if py < half_h else py - half_h
    if py >= h - max(2, h // 8):                     # the vent
        return BLACK if py % 2 == 0 else sh
    if pu == 0 or pv == 0:
        return BLACK                                 # seams
    if pu == 1 or pv == 1:
        return hi                                    # bevel, lit
    if pu == half_w - 1 or pv == half_h - 1:
        return sh                                    # bevel, shade
    if k == 1 and pu in (3, half_w - 3) and pv in (3, half_h - 3):
        return BLACK                                 # bolts
    if k == 2:
        return mix(DGREY, GREY, 0.5, x, y)
    if grime(x, y, 0.06):
        return sh
    return body

# the left wall of the cell f ahead: the same panels in perspective, darker further on
def lside(f, x, y):
    top, bot = 2 * x, FH - 1 - 2 * x
    h = max(1, bot - top)
    v = (y - top) / h
    mid = (top + bot) / 2
    seams = (INSET[1] * 4, INSET[2] * 4, INSET[1] * 4 // 2)    # where cells meet, + a plate seam
    if x in seams:
        return BLACK
    if x in (s + 1 for s in seams) and f < 2:
        return LGREY if f == 0 else GREY             # the lit edge after a seam
    if abs(y - mid) < 0.5 * (1 + f) * 0.6:
        return BLACK                                 # the middle seam (on the horizon)
    if f < 2 and 0.12 <= v < 0.16:
        return LGREY if f == 0 else GREY             # a pipe along the wall
    if f < 2 and 0.16 <= v < 0.19:
        return DGREY                                 # ... and its shadow
    if v >= 0.88:
        return BLACK if y % 2 == 0 else DGREY        # the vent
    if f == 0:
        if 0 < y - mid < 2.5:
            return LGREY                             # the bevel under the seam
        return DGREY if grime(x, y, 0.07) else GREY
    if f == 1:
        return mix(DGREY, GREY, 0.45, x, y)
    return mix(BLACK, DGREY, 0.7, x, y)

def door(k, x, y):
    cells = DOOR1 if k == 1 else DOOR2
    cs = [c for c, r in cells]
    rs = [r for c, r in cells]
    x0, x1 = min(cs) * 4, max(cs) * 4 + 3
    y0, y1 = min(rs) * 8, max(rs) * 8 + 7
    mid = (x0 + x1) // 2
    if x in (x0, x1) or y == y0:
        return DGREY                                 # the frame
    if x == mid:
        return BLACK                                 # where the halves meet
    if k == 1:
        v = (y - y0) / (y1 - y0)
        if 0.44 <= v <= 0.56:                        # hazard band
            return BLACK if (x + y // 2) % 4 < 2 else CYAN
        if x == mid + 1 or y == y0 + 1:
            return LGREY                             # a lit edge
        if 0.1 <= v <= 0.2 and (x0 + 2 <= x <= mid - 2 or mid + 3 <= x <= x1 - 2):
            return DGREY                             # windows
    return CYAN

def paint_frame(i):
    name, cells, depth, ink = FRAMES[i]
    cellset = set(cells)
    img = {}
    for y in range(FH):
        for x in range(FW):
            if (x // 4, y // 8) not in cellset:
                img[(x, y)] = None
                continue
            col = background(x, y)
            if name.startswith('front'):
                col = front(int(name[-1]), x, y)
            elif name.startswith('lside') or name.startswith('rside'):
                xx = x if name[0] == 'l' else FW - 1 - x
                f = int(name[-1])
                top, bot = 2 * xx, FH - 1 - 2 * xx
                if top <= y <= bot:
                    col = lside(f, xx, y)
            elif name.startswith('lopen') or name.startswith('ropen'):
                f = int(name[-1])
                col = front(f + 1, x, y)
            elif name.startswith('door'):
                col = door(int(name[-1]), x, y)
            img[(x, y)] = col
    return img

def paint():
    rows = (len(FRAMES) + COLS - 1) // COLS
    sheet = Image.new('RGB', (COLS * FW * 2, rows * FH), MAGENTA)
    px = sheet.load()
    for i in range(len(FRAMES)):
        img = paint_frame(i)
        ox, oy = (i % COLS) * FW * 2, (i // COLS) * FH
        for (x, y), col in img.items():
            if col is not None:
                px[ox + 2 * x, oy + y] = PAL[col]
                px[ox + 2 * x + 1, oy + y] = PAL[col]
    os.makedirs(os.path.dirname(PNG), exist_ok=True)
    sheet.save(PNG)
    print('painted', PNG)

# ---------------------------------------------------------------- converting
def nearest(rgb):
    return min(range(16), key=lambda i: sum((a - b) ** 2 for a, b in zip(rgb, PAL[i])))

def convert():
    sheet = Image.open(PNG).convert('RGB')
    px = sheet.load()
    cache = {}
    def colour(sx, sy):
        rgb = px[sx, sy]
        if rgb not in cache:
            cache[rgb] = nearest(rgb)
        return cache[rgb]
    patterns, pat_index = [], {}
    squeezed = 0
    out_frames = []
    for i, (name, cells, depth, ink_pref) in enumerate(FRAMES):
        ox, oy = (i % COLS) * FW * 2, (i // COLS) * FH
        recs = []
        for c, r in cells:
            pix = [[colour(ox + 2 * (c * 4 + fx), oy + r * 8 + fy) for fx in range(4)] for fy in range(8)]
            counts = {}
            for row in pix:
                for col in row:
                    if col != BLACK:
                        counts[col] = counts.get(col, 0) + 1
            order = sorted(counts, key=lambda k: -counts[k])
            if len(order) > 3:
                squeezed += 1
                keep = order[:3]
                remap = {k: min(keep, key=lambda q: sum((a - b) ** 2 for a, b in zip(PAL[k], PAL[q]))) for k in order[3:]}
                pix = [[remap.get(col, col) for col in row] for row in pix]
                order = keep
            if ink_pref in order:
                ink = ink_pref
            else:
                ink = order[0] if order else BLACK
            others = [k for k in order if k != ink]
            hi = others[0] if len(others) > 0 else BLACK
            lo = others[1] if len(others) > 1 else BLACK
            bits = {BLACK: 0, hi: 1, lo: 2, ink: 3}
            if hi == BLACK: bits[BLACK] = 0
            pat = []
            for row in pix:
                b = 0
                for fx, col in enumerate(row):
                    v = 0 if col == BLACK else bits[col]
                    b |= v << (6 - 2 * fx)
                pat.append(b)
            pat = tuple(pat)
            if pat not in pat_index:
                pat_index[pat] = len(patterns)
                patterns.append(pat)
            recs.append((r * VW + c, pat_index[pat], (hi << 4) | lo, ink))
        out_frames.append(recs)

    L = []
    w = L.append
    w('// GENERATED by tools/art.py convert from art/view.png - edit the PNG (or the painter), not this')
    w('.const NPIECES = %d' % len(PIECES))
    w('art_patterns:')
    for p in patterns:
        w('        .byte ' + ', '.join('$%02x' % b for b in p))
    def bytes_(label, vals):
        w(label + ':')
        for j in range(0, len(vals), 20):
            w('        .byte ' + ', '.join(str(v) for v in vals[j:j + 20]))
    def patlist(var, recs):
        w('.var %s = List()' % var)
        for j in range(0, len(recs), 40):
            w('.eval %s.add(%s)' % (var, ', '.join(str(rec[1]) for rec in recs[j:j + 40])))
    # the background: all 400 cells, in order
    bg = sorted(out_frames[0])
    patlist('PAT_BG', bg)
    w('bg_l: .fill %d, <(art_patterns + 8*PAT_BG.get(i))' % len(bg))
    w('bg_h: .fill %d, >(art_patterns + 8*PAT_BG.get(i))' % len(bg))
    bytes_('bg_s', [rec[2] for rec in bg])
    bytes_('bg_k', [rec[3] for rec in bg])
    bytes_('bg_depth', [row_depth(rec[0] // VW) for rec in bg])
    for n, recs in enumerate(out_frames[1:]):
        patlist('PAT_%d' % n, recs)
        bytes_('pofs_lo_%d' % n, [rec[0] & 255 for rec in recs])
        bytes_('pofs_hi_%d' % n, [rec[0] >> 8 for rec in recs])
        w('ppl_%d: .fill %d, <(art_patterns + 8*PAT_%d.get(i))' % (n, len(recs), n))
        w('pph_%d: .fill %d, >(art_patterns + 8*PAT_%d.get(i))' % (n, len(recs), n))
        bytes_('pscr_%d' % n, [rec[2] for rec in recs])
        bytes_('pink_%d' % n, [rec[3] for rec in recs])
    N = len(PIECES)
    def table(label, fmt):
        w(label + ': .byte ' + ', '.join(fmt % n for n in range(N)))
    w('p_count: .byte ' + ', '.join(str(len(r)) for r in out_frames[1:]))
    for lab, arr in (('pa', 'pofs_lo_'), ('pb', 'pofs_hi_'), ('pc', 'ppl_'), ('pe', 'pph_'), ('pf', 'pscr_'), ('pd', 'pink_')):
        table(lab + '_lo', '<' + arr + '%d')
        table(lab + '_hi', '>' + arr + '%d')
    w('piece_depth: .byte ' + ', '.join(str(p[2]) for p in PIECES))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as f:
        f.write('\n'.join(L) + '\n')
    cells = sum(len(r) for r in out_frames)
    print('art: %d cells, %d different patterns (%d bytes), %d cells squeezed to 3 colours'
          % (cells, len(patterns), len(patterns) * 8, squeezed))

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'paint':
        paint()
    elif cmd == 'convert':
        convert()
    else:
        print(__doc__)

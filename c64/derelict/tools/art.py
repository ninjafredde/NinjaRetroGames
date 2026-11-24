"""The view's art for Derelict (bitmap version).

  python tools/art.py convert       art/*.png -> src/gen/*.asm (build.bat runs this)
  python tools/art.py paint view    paint art/view.png from code (OVERWRITES your edits!)
  python tools/art.py paint frame   paint art/frame.png from code (OVERWRITES your edits!)
  python tools/art.py paint title   paint art/title.png from code (OVERWRITES your edits!)

art/view.png is a sheet of 18 frames (6 x 3), each the whole 20 x 20 cell view
(160 x 160 pixels; one C64 multicolour pixel = 2 screen pixels wide). Frame 0 is the
background (floor, ceiling, lamps), the others are the pieces the engine stacks far to
near: walls ahead, side walls, side openings, doors. Each frame only uses the cells of
its piece; magenta cells aren't part of it. Paint with the 16 C64 colours. In every
8 x 8 cell: black plus at most 3 other colours (the converter squeezes extra colours to
the nearest of the 3, and says how many cells it had to squeeze).

art/frame.png is the frame around everything: the top 20 rows of the screen (320 x 160,
2 screen pixels per C64 pixel, the same colour rules). Magenta: the holes the program
draws itself (the view, the minimap, the title).

art/title.png is the title screen: the whole screen (320 x 200), the same colour rules.
The program writes PRESS FIRE on row 22 (columns 15-24) itself, so keep that black.
"""
import os, sys, random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PNG = os.path.join(ROOT, 'art', 'view.png')
OUT = os.path.join(ROOT, 'src', 'gen', 'view_art.asm')
FRAME_PNG = os.path.join(ROOT, 'art', 'frame.png')
FRAME_OUT = os.path.join(ROOT, 'src', 'gen', 'frame_art.asm')
TITLE_PNG = os.path.join(ROOT, 'art', 'title.png')
TITLE_OUT = os.path.join(ROOT, 'src', 'gen', 'title_art.asm')

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

def paint_view():
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

# ---------------------------------------------------------------- the frame around it all
# The bitmap part of the screen is 40 x 20 cells. Holes: what the program draws itself
# (the view, the minimap, the title). Everything else is the frame, drawn once at start.
SW, SH = 40, 20
UW, UH = SW * 4, SH * 8                 # 160 x 160 multicolour pixels
VIEW_R0, VIEW_R1 = 1, 18                # the view rows on screen (the view's own rows 1-18)

def ui_hole(cx, cy):
    if 1 <= cx <= 20 and VIEW_R0 <= cy <= VIEW_R1:
        return True                     # the view
    if 23 <= cx <= 38 and 3 <= cy <= 18:
        return True                     # the minimap
    if 23 <= cx <= 38 and 0 <= cy <= 1:
        return True                     # the title
    return False

def ui_pixel(x, y):
    def off(px, py):
        return px < 0 or py < 0 or px >= UW or py >= UH
    def hole(px, py):
        return not off(px, py) and ui_hole(px // 4, py // 8)
    if hole(x, y):
        return None
    if any(hole(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
        return BLACK                    # a dark gap around every window
    # bolts
    for bx, by in BOLTS:
        if bx <= x <= bx + 1 and by <= y <= by + 1:
            return LGREY if (x, y) == (bx, by) else DGREY
    # vent slots on the bar between the view and the map
    if 86 <= x <= 89 and 60 <= y < 100:
        if y % 4 == 0:
            return BLACK
        if y % 4 == 1:
            return DGREY
    # hazard stripes on the bar under the view
    if 28 <= x <= 59 and 154 <= y <= 158:
        return YELLOW if ((2 * x + y) // 4) % 2 == 0 else BLACK
    # bevels: faces that look up or left catch the light, down or right are in shade
    if off(x, y + 1) or off(x + 1, y) or hole(x, y + 2) or hole(x + 2, y):
        return DGREY
    if off(x, y - 1) or off(x - 1, y) or hole(x, y - 2) or hole(x - 2, y):
        return LGREY
    return GREY

BOLTS = ([(x, 2) for x in (9, 25, 41, 57, 73)] +              # the bar over the view
         [(x, 155) for x in (9, 21, 66, 78, 100, 116, 132, 148)] +   # the bar under it all
         [(1, y) for y in (30, 70, 110, 140)] +                # left
         [(87, y) for y in (20, 40, 115, 140)] +               # the middle bar
         [(157, y) for y in (30, 70, 110, 140)] +              # right
         [(x, 19) for x in (96, 148)])                         # over the map

def paint_ui():
    sheet = Image.new('RGB', (UW * 2, UH), MAGENTA)
    px = sheet.load()
    for y in range(UH):
        for x in range(UW):
            col = ui_pixel(x, y)
            if col is not None:
                px[2 * x, y] = PAL[col]
                px[2 * x + 1, y] = PAL[col]
    sheet.save(FRAME_PNG)
    print('painted', FRAME_PNG)

# ---------------------------------------------------------------- converting
def nearest(rgb):
    return min(range(16), key=lambda i: sum((a - b) ** 2 for a, b in zip(rgb, PAL[i])))

class Cells:
    """8 x 8 cells -> 4-colour patterns: black, two in the screen byte, one ink"""
    def __init__(self, path):
        self.img = Image.open(path).convert('RGB')
        self.px = self.img.load()
        self.cache = {}
        self.squeezed = 0
        self.patterns, self.index = [], {}

    def colour(self, sx, sy):
        rgb = self.px[sx, sy]
        if rgb not in self.cache:
            self.cache[rgb] = nearest(rgb)
        return self.cache[rgb]

    def cell(self, ox, oy, ink_pref=None):
        """the cell at sheet pixel (ox, oy) -> (pattern number, screen byte, ink)"""
        pix = [[self.colour(ox + 2 * fx, oy + fy) for fx in range(4)] for fy in range(8)]
        counts = {}
        for row in pix:
            for col in row:
                if col != BLACK:
                    counts[col] = counts.get(col, 0) + 1
        order = sorted(counts, key=lambda k: -counts[k])
        if len(order) > 3:
            self.squeezed += 1
            keep = order[:3]
            remap = {k: min(keep, key=lambda q: sum((a - b) ** 2 for a, b in zip(PAL[k], PAL[q]))) for k in order[3:]}
            pix = [[remap.get(col, col) for col in row] for row in pix]
            order = keep
        ink = ink_pref if ink_pref in order else (order[0] if order else BLACK)
        others = [k for k in order if k != ink]
        hi = others[0] if len(others) > 0 else BLACK
        lo = others[1] if len(others) > 1 else BLACK
        bits = {hi: 1, lo: 2, ink: 3}
        pat = []
        for row in pix:
            b = 0
            for fx, col in enumerate(row):
                v = 0 if col == BLACK else bits[col]
                b |= v << (6 - 2 * fx)
            pat.append(b)
        pat = tuple(pat)
        if pat not in self.index:
            self.index[pat] = len(self.patterns)
            self.patterns.append(pat)
        return self.index[pat], (hi << 4) | lo, ink

def write_bytes(w, label, vals):
    w(label + ':')
    if not vals:
        w('        .byte 0')
    for j in range(0, len(vals), 20):
        w('        .byte ' + ', '.join(str(v) for v in vals[j:j + 20]))

def convert_view():
    cv = Cells(PNG)
    combos, combo_index = [], {}
    def combo(scr, depth):
        key = (scr, depth)
        if key not in combo_index:
            combo_index[key] = len(combos)
            combos.append(key)
        return combo_index[key]
    out_frames = []
    for i, (name, cells, depth, ink_pref) in enumerate(FRAMES):
        ox, oy = (i % COLS) * FW * 2, (i // COLS) * FH
        recs = []
        for c, r in cells:
            pat, scr, ink = cv.cell(ox + 2 * c * 4, oy + r * 8, ink_pref)
            d = row_depth(r) if depth is None else depth
            recs.append((r * VW + c, pat, combo(scr, d), ink | (d << 4)))
        out_frames.append(sorted(recs))
    n = len(cv.patterns)
    if n > 512:
        sys.exit('art: %d different patterns, the engine takes 512 at most' % n)
    if len(combos) > 256:
        sys.exit('art: %d colour combinations, the engine takes 256 at most' % len(combos))
    n1 = max(1, n - 256)
    L = []
    w = L.append
    w('// GENERATED by tools/art.py convert from art/view.png - edit the PNG (or the painter), not this')
    w('.const NPIECES = %d' % len(PIECES))
    w('.const NCOMBO = %d' % len(combos))
    w('.const PAT1_N = %d          // the plane length of patterns 256 on' % n1)
    w('// the patterns as 8 planes: byte b of pattern p is at patN + b*len + (p & 255)')
    w('.align $100')
    w('pat0:')
    for b in range(8):
        vals = [cv.patterns[p][b] for p in range(min(n, 256))]
        vals += [0] * (256 - len(vals))
        write_bytes(w, 'pat0_%d' % b, vals)
    w('pat1:')
    for b in range(8):
        vals = [cv.patterns[p][b] for p in range(256, n)] or [0]
        write_bytes(w, 'pat1_%d' % b, vals)
    write_bytes(w, 'combo_s', [s for s, d in combos])
    write_bytes(w, 'combo_d', [d for s, d in combos])
    bg = out_frames[0]
    write_bytes(w, 'bg_l', [rec[1] & 255 for rec in bg])
    write_bytes(w, 'bg_h', [rec[1] >> 8 for rec in bg])
    write_bytes(w, 'bg_s', [rec[2] for rec in bg])
    write_bytes(w, 'bg_k', [rec[3] for rec in bg])
    for k, recs in enumerate(out_frames[1:]):
        write_bytes(w, 'pofs_%d' % k, [rec[0] & 255 for rec in recs])
        write_bytes(w, 'ppl_%d' % k, [rec[1] & 255 for rec in recs])
        write_bytes(w, 'pph_%d' % k, [rec[1] >> 8 for rec in recs])
        write_bytes(w, 'pscr_%d' % k, [rec[2] for rec in recs])
        write_bytes(w, 'pink_%d' % k, [rec[3] for rec in recs])
    N = len(PIECES)
    def table(label, fmt):
        w(label + ': .byte ' + ', '.join(fmt % k for k in range(N)))
    w('p_count: .byte ' + ', '.join(str(len(r)) for r in out_frames[1:]))
    w('p_nlo: .byte ' + ', '.join(str(sum(1 for rec in r if rec[0] < 256)) for r in out_frames[1:]))
    for lab, arr in (('pa', 'pofs_'), ('pc', 'ppl_'), ('pe', 'pph_'), ('pf', 'pscr_'), ('pd', 'pink_')):
        table(lab + '_lo', '<' + arr + '%d')
        table(lab + '_hi', '>' + arr + '%d')
    w('piece_depth: .byte ' + ', '.join(str(p[2]) for p in PIECES))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as f:
        f.write('\n'.join(L) + '\n')
    cells = sum(len(r) for r in out_frames)
    print('view art: %d cells, %d different patterns, %d colour combinations, %d cells squeezed to 3 colours'
          % (cells, n, len(combos), cv.squeezed))

def convert_ui():
    cv = Cells(FRAME_PNG)
    recs = []
    for cy in range(SH):
        for cx in range(SW):
            if ui_hole(cx, cy):
                continue
            pat, scr, ink = cv.cell(cx * 8, cy * 8)
            recs.append((cy, cx, pat, scr, ink))
    L = []
    w = L.append
    w('// GENERATED by tools/art.py convert from art/frame.png - edit the PNG (or the painter), not this')
    w('.const NFRAME = %d' % len(recs))
    w('frame_patterns:')
    for p in cv.patterns:
        w('        .byte ' + ', '.join('$%02x' % b for b in p))
    write_bytes(w, 'fr_row', [r[0] for r in recs])
    write_bytes(w, 'fr_col', [r[1] for r in recs])
    w('fr_pl: .byte ' + ', '.join('<(frame_patterns + %d)' % (8 * r[2]) for r in recs))
    w('fr_ph: .byte ' + ', '.join('>(frame_patterns + %d)' % (8 * r[2]) for r in recs))
    write_bytes(w, 'fr_scr', [r[3] for r in recs])
    write_bytes(w, 'fr_ink', [r[4] for r in recs])
    with open(FRAME_OUT, 'w') as f:
        f.write('\n'.join(L) + '\n')
    print('frame art: %d cells, %d different patterns, %d cells squeezed to 3 colours'
          % (len(recs), len(cv.patterns), cv.squeezed))


# ---------------------------------------------------------------- the title screen
# art/title.png: the whole screen (320 x 200), shown until fire. The program writes
# PRESS FIRE on row 22 itself (it blinks), so keep cells 15-24 of that row black.
TW, TH = 160, 200
CHARGEN = os.path.join(ROOT, '..', 'tools', 'GTK3VICE-3.10-win64', 'C64', 'chargen-901225-01.bin')

def text_pixels(s, x0, y0, sx, sy, gap=0):
    """the ROM letters of s, each font pixel sx x sy C64 pixels -> {(x, y): row in the letter}"""
    rom = open(CHARGEN, 'rb').read()
    out = {}
    for n, ch in enumerate(s):
        code = ord(ch) - 64 if 'A' <= ch <= 'Z' else ord(ch)
        for fy in range(8):
            bits = rom[code * 8 + fy]
            for fx in range(8):
                if bits & (0x80 >> fx):
                    for dy in range(sy):
                        for dx in range(sx):
                            out[(x0 + n * (8 * sx + gap) + fx * sx + dx, y0 + fy * sy + dy)] = fy * sy + dy
    return out

HULL = [(8, 136), (36, 120), (92, 114), (98, 102), (110, 97), (124, 101), (128, 114),
        (146, 118), (150, 124), (150, 148), (144, 154), (40, 154)]

def inside(poly, x, y):
    c = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[i - 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c

def paint_title():
    logo = text_pixels('DERELICT', 9, 34, 2, 4, gap=2)
    small = text_pixels('WASTE OF SPACE', 24, 14, 1, 1)
    crew = text_pixels('JOHN  SHIN  JIMMIE', 8, 190, 1, 1)
    srnd = random.Random(7)
    stars = {}
    for _ in range(140):
        x, y = srnd.randrange(TW), srnd.randrange(TH)
        if 26 <= y <= 74 or y >= 172:
            continue                                 # not by the logo, the prompt, the names
        stars[(x, y)] = srnd.choice((DGREY, DGREY, GREY, LGREY))
    spans = {}
    for x in range(TW):
        ys = [y for y in range(90, 160) if inside(HULL, x + 0.5, y + 0.5)]
        spans[x] = (min(ys), max(ys)) if ys else None
    hole = {}
    sheet = Image.new('RGB', (TW * 2, TH), PAL[BLACK])
    px = sheet.load()
    for y in range(TH):
        for x in range(TW):
            col = stars.get((x, y), BLACK)
            if (x, y) in small:
                col = LBLUE
            if (x - 1, y - 2) in logo:
                col = DGREY                          # the logo's shadow
            if (x, y) in logo:
                t = logo[(x, y)] / 31
                col = mix(YELLOW, ORANGE, (t - 0.25) * 1.6, x, y)
            if (x, y) in crew:
                col = GREY
            sp = spans[x]
            if sp and inside(HULL, x + 0.5, y + 0.5):
                top, bot = sp
                t = (y - top) / max(1, bot - top)
                col = ramp([LGREY, GREY, DGREY, BLACK], 0.4 + t * 2.4 + (x / TW) * 0.5, x, y)
                if y == top:
                    col = LGREY                      # the lit top edge
                elif x % 14 == 0 and y > top + 1:
                    col = DGREY                      # plate seams
                elif y == 131:
                    col = DGREY
                if y in (124, 125) and x % 6 == 0 and 26 <= x <= 140:
                    col = YELLOW if x in (54, 90) else BLACK    # windows, nearly all dark
                if y in (104, 105) and x % 4 == 0 and 104 <= x <= 120:
                    col = BLACK
                d = (x - 72) ** 2 + ((y - 142) * 1.8) ** 2
                if d < 60 + srnd.random() * 30:
                    col = BLACK                      # the hole in her side
            if 151 <= x <= 156 and (121 <= y <= 132 or 137 <= y <= 148):
                col = DGREY if x in (151, 156) or y in (121, 132, 137, 148) else BLACK   # dead engines
            px[2 * x, y] = PAL[col]
            px[2 * x + 1, y] = PAL[col]
    sheet.save(TITLE_PNG)
    print('painted', TITLE_PNG)

def rle(data, esc):
    out, i = [], 0
    while i < len(data):
        v = data[i]
        n = 1
        while i + n < len(data) and data[i + n] == v and n < 255:
            n += 1
        if n >= 4 or v == esc:
            out += [esc, n, v]
        else:
            out += [v] * n
        i += n
    return out + [esc, 0]

def convert_title():
    cv = Cells(TITLE_PNG)
    cells = [[cv.cell(cx * 8, cy * 8) for cx in range(40)] for cy in range(25)]
    # the bitmap a row of cells at a time: byte 0 of all 40 cells, then byte 1, ...
    # (so dither that repeats along the screen packs into runs)
    bm = []
    for cy in range(25):
        for b in range(8):
            for cx in range(40):
                bm.append(cv.patterns[cells[cy][cx][0]][b])
    scr = [cells[cy][cx][1] for cy in range(25) for cx in range(40)]
    col = [cells[cy][cx][2] for cy in range(25) for cx in range(40)]
    allb = bm + scr + col
    esc = min(range(256), key=lambda v: allb.count(v))
    packs = [rle(bm, esc), rle(scr, esc), rle(col, esc)]
    L = []
    w = L.append
    w('// GENERATED by tools/art.py convert from art/title.png - edit the PNG (or the painter), not this')
    w('.const TITLE_ESC = %d' % esc)
    for name, data in zip(('title_bm', 'title_scr', 'title_col'), packs):
        write_bytes(w, name, data)
    with open(TITLE_OUT, 'w') as f:
        f.write('\n'.join(L) + '\n')
    print('title art: packed into %d bytes (of 10000), %d cells squeezed to 3 colours'
          % (sum(len(p) for p in packs), cv.squeezed))

USAGE = """usage:
  python tools/art.py convert       both PNGs -> src/gen (build.bat runs this)
  python tools/art.py paint view    paint art/view.png from code (OVERWRITES your edits!)
  python tools/art.py paint frame   paint art/frame.png from code (OVERWRITES your edits!)
  python tools/art.py paint title   paint art/title.png from code (OVERWRITES your edits!)"""

if __name__ == '__main__':
    cmd = sys.argv[1:]
    if cmd == ['paint', 'view']:
        paint_view()
    elif cmd == ['paint', 'frame']:
        paint_ui()
    elif cmd == ['paint', 'title']:
        paint_title()
    elif cmd == ['convert']:
        convert_view()
        convert_ui()
        convert_title()
    else:
        print(__doc__)
        print(USAGE)

#!/usr/bin/env python3
"""Text art -> Game Boy data.

Reads art/tiles.txt, art/font.txt, art/sprites.txt and art/rooms.txt and writes
src/gen/gfx.asm (tiles, constants, charmaps) and src/gen/rooms.asm (room table).
build.bat runs this before the assembler. Errors name the file and line.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
GEN = ROOT / "src" / "gen"
PIX = {".": 0, "1": 1, "2": 2, "3": 3}
ROOM_W, ROOM_H = 20, 16
BAD_CHARS = set('"\\{}')  # would break an RGBDS string


class ArtError(Exception):
    pass


def blocks(path):
    out, cur = [], None
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        s = line.rstrip()
        if not s.strip() or s.lstrip().startswith(";"):
            continue
        if s.startswith("@"):
            cur = {"head": s[1:].split(), "rows": [], "line": n, "where": f"{path.name}:{n}"}
            out.append(cur)
        elif cur is None:
            raise ArtError(f"{path.name}:{n}: art before any @ header")
        else:
            cur["rows"].append(s.strip())
    return out


def check_art(blk, w, h, pad=False):
    rows = blk["rows"]
    if pad:
        rows = [r.ljust(w, ".") for r in rows] + ["." * w] * (h - len(rows))
    if len(rows) != h:
        raise ArtError(f"{blk['where']}: {len(rows)} rows, expected {h}")
    for i, r in enumerate(rows):
        if len(r) != w:
            raise ArtError(f"{blk['where']}: row {i + 1} is {len(r)} wide, expected {w}: {r}")
        bad = set(r) - set(PIX)
        if bad:
            raise ArtError(f"{blk['where']}: row {i + 1} has {''.join(sorted(bad))} (use . 1 2 3)")
    return rows


def tile_bytes(rows, x0, y0):
    out = []
    for y in range(8):
        lo = hi = 0
        for x in range(8):
            c = PIX[rows[y0 + y][x0 + x]]
            lo = (lo << 1) | (c & 1)
            hi = (hi << 1) | (c >> 1)
        out += [lo, hi]
    return out


def main():
    tiles = []      # list of 16-byte lists, in VRAM order
    consts = {}     # DEF name EQU value
    room_map = {}   # letter -> tile index

    # --- background tiles: walkable first, then solid
    bg = blocks(ART / "tiles.txt")
    for b in bg:
        if len(b["head"]) < 3 or b["head"][0] != "tile" or b["head"][2] not in ("walk", "solid"):
            raise ArtError(f"{b['where']}: header must be @tile <chars> <walk|solid> <name>")
    for kind in ("walk", "solid"):
        if kind == "solid":
            consts["FIRST_SOLID"] = len(tiles)
        for b in bg:
            letters, flag = b["head"][1], b["head"][2]
            if flag != kind:
                continue
            h = len(b["rows"])
            w = len(b["rows"][0]) if b["rows"] else 0
            if w % 8 or h % 8 or (w // 8) * (h // 8) != len(letters):
                raise ArtError(f"{b['where']}: {w}x{h} art does not fit {len(letters)} letter(s) '{letters}'")
            rows = check_art(b, w, h)
            i = 0
            for ty in range(h // 8):
                for tx in range(w // 8):
                    ch = letters[i]
                    i += 1
                    if ch in room_map or ch in BAD_CHARS:
                        raise ArtError(f"{b['where']}: letter '{ch}' already used or not allowed")
                    room_map[ch] = len(tiles)
                    tiles.append(tile_bytes(rows, tx * 8, ty * 8))
    consts["BG_TILES"] = len(tiles)

    # --- font
    text_map = {}
    consts["FONT_BASE"] = len(tiles)
    for b in blocks(ART / "font.txt"):
        if len(b["head"]) != 2 or b["head"][0] != "glyph":
            raise ArtError(f"{b['where']}: header must be @glyph <char>")
        ch = " " if b["head"][1] == "space" else b["head"][1]
        if len(ch) != 1 or ch in BAD_CHARS or ch in text_map:
            raise ArtError(f"{b['where']}: bad or repeated glyph '{ch}'")
        text_map[ch] = len(tiles)
        tiles.append(tile_bytes(check_art(b, 8, 8, pad=True), 0, 0))
    for ch in list(text_map):
        if ch.isalpha() and ch.isupper():
            text_map.setdefault(ch.lower(), text_map[ch])
    consts["TILE_SPACE"] = text_map[" "]
    consts["TILE_HUDLINE"] = text_map["~"]

    # --- sprites (8x16 mode: start on an even tile; each 16x16 = TL, BL, TR, BR)
    if len(tiles) % 2:
        tiles.append([0] * 16)
    for b in blocks(ART / "sprites.txt"):
        if len(b["head"]) != 2 or b["head"][0] != "sprite":
            raise ArtError(f"{b['where']}: header must be @sprite <name>")
        rows = check_art(b, 16, 16)
        consts["SPR_" + b["head"][1].upper()] = len(tiles)
        for x0, y0 in ((0, 0), (0, 8), (8, 0), (8, 8)):
            tiles.append(tile_bytes(rows, x0, y0))
    consts["TILE_COUNT"] = len(tiles)
    if len(tiles) > 256:
        raise ArtError(f"{len(tiles)} tiles, the $8000 block holds 256")

    # --- rooms
    rooms = blocks(ART / "rooms.txt")
    names = []
    for b in rooms:
        if len(b["head"]) < 2 or b["head"][0] != "room":
            raise ArtError(f"{b['where']}: header must be @room NAME n=.. s=.. w=.. e=..")
        names.append(b["head"][1])
    walkable = lambda ch: room_map[ch] < consts["FIRST_SOLID"]
    parsed = []
    for b in rooms:
        name = b["head"][1]
        links = {}
        for kv in b["head"][2:]:
            k, _, v = kv.partition("=")
            if k not in "nswe" or len(k) != 1 or v not in names:
                raise ArtError(f"{b['where']}: bad link '{kv}' (rooms: {', '.join(names)})")
            links[k] = v
        rows = b["rows"]
        if len(rows) != ROOM_H:
            raise ArtError(f"{b['where']}: {len(rows)} rows, expected {ROOM_H}")
        for i, r in enumerate(rows):
            if len(r) != ROOM_W:
                raise ArtError(f"{b['where']}: row {i + 1} is {len(r)} wide, expected {ROOM_W}: {r}")
            bad = set(r) - set(room_map)
            if bad:
                raise ArtError(f"{b['where']}: row {i + 1} has unknown letters {''.join(sorted(bad))}")
        for ch in name.replace("_", " "):
            if ch not in text_map:
                raise ArtError(f"{b['where']}: no glyph for '{ch}' in the room name")
        parsed.append((b, name, links, rows))

    by_name = {p[1]: p for p in parsed}
    opposite = {"n": "s", "s": "n", "w": "e", "e": "w"}

    def edge(rows, side):
        if side == "n":
            return [x for x in range(ROOM_W) if walkable(rows[0][x])]
        if side == "s":
            return [x for x in range(ROOM_W) if walkable(rows[-1][x])]
        col = 0 if side == "w" else ROOM_W - 1
        return [y for y in range(ROOM_H) if walkable(rows[y][col])]

    for b, name, links, rows in parsed:
        for side in "nswe":
            open_cells = edge(rows, side)
            if side not in links:
                if open_cells:
                    raise ArtError(f"{b['where']}: {name} is open on side {side} but has no {side}= link")
                continue
            other = by_name[links[side]]
            back = other[2].get(opposite[side])
            if back != name:
                raise ArtError(f"{b['where']}: {name} {side}= {links[side]}, but {links[side]} "
                               f"{opposite[side]}= {back or 'nothing'}")
            if not open_cells:
                raise ArtError(f"{b['where']}: {name} links {side} but its edge has no doorway")
            if open_cells != edge(other[3], opposite[side]):
                raise ArtError(f"{b['where']}: doorway on side {side} of {name} does not line up with {links[side]}")

    # --- write gfx.asm
    GEN.mkdir(parents=True, exist_ok=True)
    out = ["; Generated by tools/gfx.py from art/*.txt - edit the art, not this file", ""]
    for k, v in consts.items():
        out.append(f"DEF {k} EQU {v}")
    out += ["", "; rooms.txt letters", "NEWCHARMAP room"]
    for ch, i in room_map.items():
        out.append(f'CHARMAP "{ch}", {i}')
    out += ["", "; text: dialogue strings use SETCHARMAP text", "NEWCHARMAP text"]
    for ch, i in text_map.items():
        out.append(f'CHARMAP "{ch}", {i}')
    out += ["SETCHARMAP main", "", 'SECTION "Tiles", ROM0', "AllTiles::"]
    for i, t in enumerate(tiles):
        out.append("    db " + ",".join(f"${x:02X}" for x in t) + f"  ; {i}")
    out += ["AllTilesEnd::", ""]
    (GEN / "gfx.asm").write_text("\n".join(out), encoding="utf-8", newline="\n")

    # --- write rooms.asm
    out = ["; Generated by tools/gfx.py from art/rooms.txt - edit the art, not this file", ""]
    for i, name in enumerate(names):
        out.append(f"DEF ROOM_{name.upper()} EQU {i}")
    out += [f"DEF ROOM_COUNT EQU {len(names)}", "", 'SECTION "Rooms", ROM0', "RoomTable::"]
    out += [f"    dw Room{i}" for i in range(len(names))]
    for i, (b, name, links, rows) in enumerate(parsed):
        link_ids = [names.index(links[s]) if s in links else 0xFF for s in "nswe"]
        label = name.replace("_", " ")
        out += ["", f"Room{i}:  ; {label}",
                "    db " + ",".join(f"${x:02X}" for x in link_ids) + "  ; links n,s,w,e",
                f"    db {len(label)}, " + ",".join(str(text_map[c]) for c in label) + f'  ; "{label}"']
        for r in rows:
            out.append("    db " + ",".join(str(room_map[c]) for c in r) + f"  ; {r}")
    out.append("")
    (GEN / "rooms.asm").write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"gfx: {len(tiles)} tiles ({consts['BG_TILES']} background, solid from {consts['FIRST_SOLID']}), "
          f"{len(names)} rooms")


if __name__ == "__main__":
    try:
        main()
    except ArtError as e:
        print("art error:", e, file=sys.stderr)
        sys.exit(1)

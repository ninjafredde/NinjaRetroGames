#!/usr/bin/env python3
"""Text art -> Game Boy data.

Reads art/tiles.txt, font.txt, items.txt, sprites.txt, rooms.txt and things.txt
and writes src/gen/gfx.asm (tiles, constants, charmaps), src/gen/rooms.asm (room table)
and src/gen/things.asm (people/objects per room + their text boxes).
build.bat runs this before the assembler. Errors name the file and line.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
GEN = ROOT / "src" / "gen"
PIX = {".": 0, "1": 1, "2": 2, "3": 3}
ROOM_W, ROOM_H = 20, 16
BOX_W = 18          # letters per text box line (2 lines a box)
THING_SIZE = 7      # tx, ty, w, h, sprite tile, talk pointer
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
    consts["TILE_ARROW"] = text_map["^"]

    # --- items: 8x8 HUD icons
    item_names = []
    consts["ITEM_ICON_BASE"] = len(tiles)
    for b in blocks(ART / "items.txt"):
        if len(b["head"]) != 2 or b["head"][0] != "item":
            raise ArtError(f"{b['where']}: header must be @item NAME")
        name = b["head"][1].lower()
        if name in item_names or not name.replace("_", "").isalnum():
            raise ArtError(f"{b['where']}: bad or repeated item name")
        item_names.append(name)
        tiles.append(tile_bytes(check_art(b, 8, 8), 0, 0))
    consts["ITEM_COUNT"] = len(item_names)

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

    # --- things: people and objects John can talk to, each with a little script
    var_names = list(item_names)          # items are the first variables
    set_somewhere = set(item_names)
    used_in_if = {}

    def var(name, where):
        n = name.lower()
        if not n or not n.replace("_", "").isalnum() or n in ("if", "do", "give", "take"):
            raise ArtError(f"{where}: '{name}' is not a usable name")
        if n not in var_names:
            var_names.append(n)
        return var_names.index(n)

    def number(v, where):
        if not v.isdigit() or int(v) > 255:
            raise ArtError(f"{where}: '{v}' should be a number 0-255")
        return int(v)

    def wrap(line, where):
        lines, cur = [], ""
        for wd in line.split():
            if len(wd) > BOX_W:
                raise ArtError(f"{where}: '{wd}' is longer than a box line ({BOX_W})")
            for ch in wd:
                if ch not in text_map:
                    raise ArtError(f"{where}: no glyph for '{ch}' (add it to font.txt)")
            if not cur:
                cur = wd
            elif len(cur) + 1 + len(wd) <= BOX_W:
                cur += " " + wd
            else:
                lines.append(cur)
                cur = wd
        if cur:
            lines.append(cur)
        return [(lines[i].ljust(BOX_W), (lines[i + 1] if i + 1 < len(lines) else "").ljust(BOX_W))
                for i in range(0, len(lines), 2)]

    room_things = {n: [] for n in names}
    talks = []
    for b in blocks(ART / "things.txt"):
        head = b["head"]
        if len(head) < 2 or head[0] != "thing":
            raise ArtError(f"{b['where']}: header must be @thing NAME room=ROOM at=X,Y [sprite=NAME] [size=WxH]")
        tname = head[1]
        opts = {}
        for kv in head[2:]:
            k, _, v = kv.partition("=")
            opts[k] = v
        room = opts.get("room")
        if room not in by_name:
            raise ArtError(f"{b['where']}: room= must be one of {', '.join(names)}")
        try:
            tx, ty = (int(v) for v in opts["at"].split(","))
        except (KeyError, ValueError):
            raise ArtError(f"{b['where']}: needs at=X,Y (tiles)")
        spr = opts.get("sprite")
        if spr:
            key = "SPR_" + spr.upper()
            if key not in consts:
                raise ArtError(f"{b['where']}: no @sprite {spr} in sprites.txt")
            spr_tile, w, h = consts[key], 2, 2
        else:
            spr_tile, w, h = 0xFF, 1, 1
        if "size" in opts:
            try:
                w, h = (int(v) for v in opts["size"].lower().split("x"))
            except ValueError:
                raise ArtError(f"{b['where']}: size= is WxH, like 2x2")
        if not (1 <= tx and tx + w <= ROOM_W - 1 and 1 <= ty and ty + h <= ROOM_H - 1):
            raise ArtError(f"{b['where']}: {tname} at {tx},{ty} size {w}x{h} is outside the room's floor")
        rows = by_name[room][3]
        if spr:
            for yy in range(ty, ty + h):
                for xx in range(tx, tx + w):
                    if not walkable(rows[yy][xx]):
                        raise ArtError(f"{b['where']}: {tname} stands on a solid tile at {xx},{yy}")

        # sections: [conditions or None for the fallback, ops]
        sections = [[None, []]]
        for line in b["rows"]:
            where = f"{b['where']} ({tname})"
            word = line.split()[0].lower()
            if word == "if":
                conds = []
                for tok in line.split()[1:]:
                    if "!=" in tok:
                        n, v = tok.split("!=", 1)
                        conds.append((var(n, where), 1, number(v, where)))
                    elif "=" in tok:
                        n, v = tok.split("=", 1)
                        conds.append((var(n, where), 0, number(v, where)))
                    elif tok.startswith("!"):
                        n = tok[1:]
                        conds.append((var(n, where), 0, 0))
                    else:
                        n = tok
                        conds.append((var(n, where), 1, 0))
                    used_in_if.setdefault(n.lower(), where)
                if not conds:
                    raise ArtError(f"{where}: 'if' needs at least one condition")
                sections.append([conds, []])
            elif word == "do":
                toks = line.split()[1:]
                ops = sections[-1][1]
                i = 0
                while i < len(toks):
                    t = toks[i].lower()
                    i += 1
                    if t in ("give", "take"):
                        if i >= len(toks) or toks[i].lower() not in item_names:
                            raise ArtError(f"{where}: '{t}' needs an item from items.txt ({', '.join(item_names)})")
                        ops.append(("set", var_names.index(toks[i].lower()), 1 if t == "give" else 0, f"{t} {toks[i]}"))
                        i += 1
                    elif t == "shake":
                        ops.append(("shake", 20, 1))
                    elif t == "rattle":
                        ops.append(("shake", 60, 2))
                    elif t == "boom":
                        ops.append(("boom",))
                    elif t == "end":
                        ops.append(("end",))
                    elif "=" in t:
                        n, v = t.split("=", 1)
                        ops.append(("set", var(n, where), number(v, where), t))
                        set_somewhere.add(n)
                    else:
                        raise ArtError(f"{where}: don't know 'do {t}' (name=N, give X, take X, shake, rattle, boom, end)")
            else:
                sections[-1][1] += [("page", pg) for pg in wrap(line, where)]
        cases = [sec for sec in sections[1:]]
        if sections[0][1]:
            cases.append([[], sections[0][1]])
        for conds, ops in cases:
            if not any(op[0] == "page" for op in ops):
                raise ArtError(f"{b['where']}: every case of {tname} needs at least one line of text")
        label = f"Talk{len(talks)}"
        talks.append((label, tname, cases))
        room_things[room].append((tx, ty, w, h, spr_tile, label, tname))
    for room, lst in room_things.items():
        if sum(1 for t in lst if t[4] != 0xFF) > 8:
            raise ArtError(f"things.txt: more than 8 people in {room}")
    for n, where in used_in_if.items():
        if n.lower() not in set_somewhere:
            raise ArtError(f"{where}: '{n}' is checked but no 'do' line ever sets it (typo?)")
    if len(var_names) > 32:
        raise ArtError(f"things.txt: {len(var_names)} names, the game keeps 32")

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
    # --- write things.asm
    out = ["; Generated by tools/gfx.py from art/things.txt - edit the art, not this file", "",
           f"DEF THING_SIZE EQU {THING_SIZE}", f"DEF BOX_W EQU {BOX_W}", f"DEF PAGE_LEN EQU {BOX_W * 2}",
           f"DEF VAR_COUNT EQU {len(var_names)}",
           "DEF OP_STOP EQU 0", "DEF OP_PAGE EQU 1", "DEF OP_SET EQU 2", "DEF OP_SHAKE EQU 3",
           "DEF OP_BOOM EQU 4", "DEF OP_END EQU 5", "",
           "; variables: " + ", ".join(f"{i} {n}" for i, n in enumerate(var_names)), "",
           'SECTION "Things", ROM0', "RoomThings::"]
    out += [f"    dw Things{i}" for i in range(len(names))]
    for i, name in enumerate(names):
        lst = room_things[name]
        out += ["", f"Things{i}:  ; {name}", f"    db {len(lst)}"]
        for tx, ty, w, h, spr_tile, label, tname in lst:
            out.append(f"    db {tx},{ty},{w},{h},${spr_tile:02X}")
            out.append(f"    dw {label}  ; {tname}")
    for label, tname, cases in talks:
        out += ["", f"{label}:  ; {tname}", f"    db {len(cases)}  ; cases"]
        for k, (conds, ops) in enumerate(cases):
            desc = " ".join(f"{var_names[v]}{'!=' if op else '='}{val}" for v, op, val in conds) or "otherwise"
            out.append(f"    db {len(conds)}" + "".join(f", {v},{op},{val}" for v, op, val in conds) + f"  ; {desc}")
            out.append(f"    dw {label}_{k}")
        for k, (conds, ops) in enumerate(cases):
            out.append(f"{label}_{k}:")
            for op in ops:
                if op[0] == "page":
                    out.append("    db OP_PAGE")
                    for ln in op[1]:
                        out.append("    db " + ",".join(str(text_map[c]) for c in ln) + f"  ; {ln.rstrip()}")
                elif op[0] == "set":
                    out.append(f"    db OP_SET, {op[1]}, {op[2]}  ; {op[3]}")
                elif op[0] == "shake":
                    out.append(f"    db OP_SHAKE, {op[1]}, {op[2]}")
                elif op[0] == "boom":
                    out.append("    db OP_BOOM")
                elif op[0] == "end":
                    out.append("    db OP_END")
            out.append("    db OP_STOP")
    out.append("")
    (GEN / "things.asm").write_text("\n".join(out), encoding="utf-8", newline="\n")

    print(f"gfx: {len(tiles)} tiles ({consts['BG_TILES']} background, solid from {consts['FIRST_SOLID']}), "
          f"{len(names)} rooms, {len(talks)} things, {len(var_names)} names")


if __name__ == "__main__":
    try:
        main()
    except ArtError as e:
        print("art error:", e, file=sys.stderr)
        sys.exit(1)

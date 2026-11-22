# Derelict
A Waste of Space first-person dungeon crawl for the C64. 6502 assembly (KickAssembler),
joystick in port 2 or the keyboard.

## Now: walk the deck, map + log
- Up / W: step forward. Down / S: step back. Left / A, right / D: turn.
- Walking into a wall: a thud, a red border flash, "BONK".
- Minimap (right): fills in with the cells you have seen; yellow arrow = you, yellow dot = a note.
- Log (bottom, 3 lines, older ones fade). Stepping on a note cell prints its line.
- The crew (right): JOHNSON, SHIN, JIMMIE with HP (green, yellow under half, red under a quarter).
  Everyone up gets 1 HP back every 6 steps.
- Fights: now and then something blocks the way (a monster in the view, made of 4 sprites).
  Each crew member picks F)ight, D)efend (half damage) or R)un (half the time the crew gets away).
  Fire / space = fight; hold fire or space to speed up the fight text.
  The downed get back up with 1 HP after a fight; everyone down = start again.
- Doors: cyan ones open when you bump them. Red ones are locked: bump with a keycard.
- Items (stars on the minimap): keycards, medkits, plasma spanners (+2 hit), the vending machine.
  MED / KEY counts top right. M = use a medkit (on whoever is hurt worst, the downed too),
  also in a fight. Monsters sometimes drop one.
- H on deck 1 = the hatch down to deck 2. E on deck 2 = the bridge: the end.

## How the view works
- Text mode with **extended background colour** (ECM): every character cell picks one of
  4 backgrounds. Black = text and far darkness, `$d022` = floor (brown), `$d023` = ceiling.
  That is how one cell can show wall + floor, or wall + ceiling, across a diagonal.
- 7 custom shapes on screen codes text never uses: solid, 4 triangles, 2 "seam" blocks.
  The rest of the 64 characters are the ROM letters (ECM only has 64 shapes).
- `src/view.asm` works out the view as 15 **pieces** when assembling (wall ahead at 1/2/3
  cells, left/right side walls, left/right openings). Each piece is a list of cells.
- `render` paints far to near (painter's order), checking the map cells around you,
  into a buffer at `$c000`, then copies it to the screen while the raster is under the view.

## Editing
- `src/map.asm`: the decks as text (legend at the top: walls, doors, notes, items, hatch, end),
  each deck's start direction, colours and fight chance, the notes and item lines.
  Keep the edges all walls.
- `src/view.asm`: `INSET` (perspective), `SIDE_COL` / `FRONT_COL` (wall colours by distance),
  `wallGlyph` (the bulkhead panels), `DOOR_ART` (doors as text-art), the lamps.
  17 wall/fog shapes on screen codes text doesn't use (see the `G_` list): game text can't use
  `# $ % & ( + - ; < = > ? @ [ ] ^` or the letters Q and Z (the build stops and says so).
- Fog: `DECK_FOG` in `src/map.asm` (per deck: how foggy at 0-3 cells ahead, 0 clear, 1-3 dithered,
  4 black). The fog pass dithers walls/floor/ceiling into black and dims edges, far items and monsters.
- `src/monsters.asm`: also the item pictures seen in the corridor (`ITEM_PICS`, one sprite each).
- `src/monsters.asm`: monster names, verbs, HP, hit, how many, colour, and the pictures
  as text (left half only, mirrored).
- `src/items.asm`: deck loading, doors, items, medkits (`MED_HEAL`), door colours.
- `src/combat.asm`: the crew (names, HP, hit), how often fights happen, the fight words.
- `src/main.asm`: `COL_FLOOR`, `COL_CEIL`, frame and text colours at the top.

## Build
`build.bat` (build + run in VICE), `build.bat norun`. Uses the tools in `..\c64\tools`.
Test builds: `-define DEMO` walks a scripted route by itself; `-define FIGHTTEST` = a fight every step;
`-define NOFIGHTS`; `-define DECK2` starts on deck 2.

## Next steps
2. ~~Text panel + minimap~~ done.
3. ~~Encounters and turn-based combat~~ done.
4. ~~Items, doors, the way down to the next deck~~ done.

Graphics pass 1 (22 Nov): bulkhead panels, door art, floor/ceiling seams, lamps (dead on deck 2),
items as sprites in the corridor, new Cleanbot.
Fog (22 Nov): dithered distance fog per deck (light on deck 1, heavy on deck 2).

## Bitmap branch (work in progress)
`git checkout bitmap`. The screen is split by a raster interrupt (`src/screen.asm`):
multicolour bitmap on top (view, title, pixel minimap), text below (crew, status, log).
VIC bank 3: screen $c000, sprites $c400/$cc00, letters $c800, bitmap $e000; work memory $8000.
- M1 (done): the split screen; the view's cell codes turned into 4x8 fat-pixel patterns
  (`FAT` in `src/view.asm`), so it looks like the text version, in bitmap.
- M2: painted pieces made by a Python script + a converter (PNG -> cell data).
- M3: polish (per-deck art, faster drawing).

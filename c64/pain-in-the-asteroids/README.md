# A Pain in the Asteroids
6502 assembly (KickAssembler). Joystick in port 2: move, fire.
Each level: launch from the mothership, shoot the rocks, dock in its back.
Big rocks (10 points) split into two small ones (20 points) that fly diagonally
and vanish off the sides. At most 3 big rocks at once, so 6 small ones fit the
6 rock sprites. ROCKS in the top bar counts the big ones left.

- `build.bat` builds `build/asteroids.prg` + `build/wos.d64` and runs it in VICE
- `build.bat norun` builds only
- `src/main.asm` the game, `src/sprites.asm` the sprite art

## Editing sprites
Sprites are text pictures in `src/sprites.asm`; edit and run `build.bat`.
Multicolour rows are up to 12 characters (fat pixels), up to 21 rows:
`.` clear, `1` dark grey, `2` the sprite's own colour, `3` white.
`mirror("abc")` draws a symmetric sprite from its left half.
The mothership is one 36 x 42 picture cut into 6 sprites; keep its middle third
solid in rows 12-32 (the docked ship hides behind it).

## Title picture
`art/title.kla` is built into the game. Make one from any picture:

    python ..\tools\img2c64.py art\src\keyart.png -o art\title [--only 0,11,12,15,1] [--dither fs]

It writes `art/title.kla`, `title_preview.png` (how it looks on a C64),
`title_clash.png` (cells it had to fix, in red) and `title_edit.png` (160x200).
Edit `title_edit.png` by hand (Photoshop: View -> Pixel Aspect Ratio 2.0;
Image -> Mode -> Indexed -> Custom -> Load `../tools/c64.act`) and convert that
file again: a 160x200 picture is taken as finished pixel art, no scaling or dither.
Rule: each 4x8 cell holds 3 colours plus the background colour.

## Title tune
`src/music.asm`: three voices written as note text, played by a small player
from a raster interrupt while the title picture shows.
`a4:4` = note a, octave 4, 4 rows; `c#5`; `r:8` rest; `@2` instrument 2; `|` bar line.
Instruments (waveform, envelope, pulse width sweep, chord arpeggio) are at the top.
Also two one-shot jingles (the word `end` stops a voice): get ready (each level's launch)
and game over. Recordings from VICE: `build/title_tune.wav`, `get_ready.wav`, `game_over.wav`.

## Test builds
`java -jar ..\tools\KickAssembler\KickAss.jar src\main.asm -define SKIPTITLE -define DEMO -define QUICK`
(skip the title, fire held, 2 rocks a level).

Tools (in `../tools/`, not in git; see the main README): KickAssembler 5.25 (needs Java), VICE 3.10 GTK3.

## Real hardware
- TheC64: copy `asteroids.prg` (or `wos.d64`) to a FAT32 USB stick, plug it in, Media Access -> pick it.
- Breadbox C64: needs a loader such as SD2IEC, Kung Fu Flash or 1541 Ultimate; put the `.prg`/`.d64` on its SD card.

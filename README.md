# NinjaRetroGames

Small games for real retro machines, written in **assembly language** and built
to run on the original hardware (and in emulators). These are not modern games
with a retro look: each one is a native `.prg` / `.d64` / `.gb` file for the
actual machine.

Made for learning, mine and anyone else's. The code is meant to be read: art,
maps and music are kept as plain text or PNGs and converted at build time, so
you can change things and rebuild.

Most of the games take place in the same small universe, *Waste of Space*: the
mothership *Dilettante* and its crew.

## Games

| Game | Machine | Language | What it is |
|---|---|---|---|
| [A Pain in the Asteroids](c64/pain-in-the-asteroids/) | Commodore 64 | 6502, KickAssembler | Top-down scrolling shooter: launch from the mothership, clear the rocks, dock again |
| [Derelict](c64/derelict/) | Commodore 64 | 6502, KickAssembler | First-person dungeon crawl |
| [Mushroom for Improvement](c64/mushroom/) | Commodore 64 | 6502, KickAssembler | Flick-screen platformer: clear the fungus room by room |
| [Out of Coffee](gameboy/out-of-coffee/) | Game Boy (DMG) | SM83, RGBDS | Adventure game |

Tested on: the C64 games run in VICE and on TheC64 Mini. They have not yet been
tested on an original breadbox C64. Out of Coffee runs in SameBoy.

Ready-to-play disk images and ROMs are on the
[Releases](../../releases) page.

## Layout

```
c64/
  tools/        shared C64 tools: img2c64.py, C64 palettes, toolchain (not in git)
  <game>/       src/, art/, build.bat, README.md
gameboy/
  tools/        toolchain (not in git)
  <game>/
```

Each game is self-contained apart from the toolchain in its machine's `tools/`
folder. Some code, such as the C64 music player, is copied between games on
purpose so that each game can be read on its own.

## Building (Windows)

The toolchains are not in the repo. Download them and unpack them here:

**C64**: needs Java (8 or newer) and Python 3 with `pillow` and `numpy`
- [KickAssembler](http://theweb.dk/KickAssembler/) 5.25 to `c64/tools/KickAssembler/` (so `KickAss.jar` is in that folder)
- [VICE](https://vice-emu.sourceforge.io/) 3.10 GTK3 win64 to `c64/tools/GTK3VICE-3.10-win64/`

**Game Boy**: needs Python 3 (and `pyboy` for the headless test scripts)
- [RGBDS](https://rgbds.gbdev.io/) 1.0.4 to `gameboy/tools/rgbds/` (`rgbasm.exe` etc.)
- [SameBoy](https://sameboy.github.io/) 1.0.5 to `gameboy/tools/sameboy/`

Then run `build.bat` in a game's folder. C64 games build and start in VICE
(`build.bat norun` only builds). Out of Coffee: `run.bat` builds and plays it,
`build.bat` only builds.

Each game's README covers its own details: controls, how to edit sprites, maps
and music, test builds, and how to run it on real hardware.

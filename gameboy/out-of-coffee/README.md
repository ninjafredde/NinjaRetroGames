# Out of Coffee

A Waste of Space adventure for the original Game Boy (4 shades), in SM83 assembly.

- `build.bat` builds `build\coffee.gb`; `build.bat run` builds and opens it in SameBoy.
- Tools in `tools\` (not in git): RGBDS 1.0.4 (`tools\rgbds`), SameBoy 1.0.5 (`tools\sameboy`).
- Art is text: `art\tiles.txt`, `art\sprites.txt`, `art\font.txt`, `art\rooms.txt`.
  `tools\gfx.py` turns it into `src\gen\*.asm` on every build (and checks doors line up).
- `python tools\shot.py build\coffee.gb out 200 left:60 shot:name` plays it headless (PyBoy) and saves screenshots.

SameBoy keys: arrows, X = A, Z = B, Enter = Start, Backspace = Select.

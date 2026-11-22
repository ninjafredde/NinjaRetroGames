// The first-person view (bitmap version).
//
// The view is 20 x 20 cells. Its pictures come from tools/art.py: art/view.png is
// converted on every build into src/gen/view_art.asm: the background (400 cells) and
// 17 pieces, each a list of cells (where, which 8-byte pattern, screen byte, ink):
//    0- 2  FRONT  the wall straight ahead at plane 1, 2, 3
//    3- 5  LSIDE  the left-hand wall of the cell f ahead (f = 0, 1, 2)
//    6- 8  LOPEN  the left side is open at f: the face of the wall beyond it
//    9-11  RSIDE
//   12-14  ROPEN
//   15-16  a door on FRONT 1, 2 (its ink is the door's colour)
// render stacks them far to near into the buffers; present puts the result in the
// bitmap, through this deck's colour tables (deck colours + fog by depth).

.const VW = 20
.const VH = 20

// shapes for the minimap and the frame (cell_out); the top 2 bits of a code pick the
// background: 0 black, 64 the floor colour, 128 the ceiling colour
.const G_SOLID = 0
.const ON_FLOOR = 64
.const ON_CEIL  = 128
.const C_FLOOR  = 32 + ON_FLOOR
.const C_DARK   = 32

// ---------------------------------------------------------------- the cell patterns
// The minimap's and the frame's shapes. Every shape is 4 fat pixels x 8 rows: x = the ink (colour RAM), . = the background
// the code picks with its top 2 bits (0: black, 64: floor, 128: ceiling).
// mc_patterns holds all 256 codes x 8 bytes; a code with no shape is all background.
.var FAT = Hashtable()
.function fill8(s) { .return List().add(s, s, s, s, s, s, s, s) }
.eval FAT.put(G_SOLID, fill8("xxxx"))
// the minimap: you (N E S W), a note, an item, the hatch, the end
.eval FAT.put(59, List().add(".xx.", "xxxx", "xxxx", ".xx.", ".xx.", ".xx.", ".xx.", "...."))
.eval FAT.put(61, List().add("....", "..x.", "..xx", "xxxx", "xxxx", "..xx", "..x.", "...."))
.eval FAT.put(62, List().add("....", ".xx.", ".xx.", ".xx.", ".xx.", "xxxx", "xxxx", ".xx."))
.eval FAT.put(63, List().add("....", ".x..", "xx..", "xxxx", "xxxx", "xx..", ".x..", "...."))
.eval FAT.put(46, List().add("....", "....", "....", ".xx.", ".xx.", "....", "....", "...."))
.eval FAT.put(42, List().add("....", ".xx.", "xxxx", "xxxx", ".xx.", "....", "....", "...."))
.eval FAT.put(8,  List().add("x..x", "x..x", "x..x", "xxxx", "x..x", "x..x", "x..x", "...."))
.eval FAT.put(5,  List().add("xxxx", "x...", "x...", "xxx.", "x...", "x...", "xxxx", "...."))
.eval FAT.lock()
.function bgBits(sel) {
    .if (sel == 1) .return 1
    .if (sel == 2) .return 2
    .return 0
}
.function fatByte(c, y) {
    .var g = c & 63
    .var bg = bgBits(c >> 6)
    .var b = 0
    .for (var k=0; k<4; k++) {
        .var on = false
        .if (FAT.containsKey(g)) .eval on = FAT.get(g).get(y).substring(k, k+1) == "x"
        .eval b = b | ((on ? 3 : bg) << (6 - 2*k))
    }
    .return b
}
mc_patterns:
.for (var c=0; c<256; c++)
    .for (var y=0; y<8; y++) .byte fatByte(c, y)

// each colour one step darker (the fog)
ramp:       .byte 0, 15, 9, 14, 6, 11, 0, 8, 9, 0, 2, 0, 11, 5, 6, 12

#import "gen/view_art.asm"

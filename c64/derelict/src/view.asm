// The first-person view: a 20 x 20 grid of characters (extended background colour
// mode), built from pieces worked out here when assembling.
//
// Looking down the corridor there are 4 planes: the screen edge (0) and the walls
// 1, 2 and 3 cells ahead. INSET says how far each plane sits in from the edge (the
// side walls run at 45 degrees, so it is the same across and down).
//
// Pieces (the number is what render passes to blit):
//    0- 2  FRONT  the wall straight ahead at plane 1, 2, 3
//    3- 5  LSIDE  the left-hand wall of the cell f ahead (f = 0, 1, 2)
//    6- 8  LOPEN  the left side is open at f: the face of the wall beyond it
//    9-11  RSIDE
//   12-14  ROPEN
//   15-16  a door on FRONT 1, 2 (always drawn in the door's colour)
//   17     the seams across floor and ceiling at each plane (drawn in the deck's line colour)
//   18     the ceiling lamps

.const VW = 20
.const VH = 20
.var INSET     = List().add(0, 4, 7, 9)
.var SIDE_COL  = List().add(1, 15, 12)          // side walls by cell f
.var FRONT_COL = List().add(0, 15, 12, 12)      // front faces by plane
.var LAMP_COL  = List().add(1, 15)              // near lamp, far lamp

// glyphs (screen codes no text uses)
.const G_SOLID = 0              // @
.const G_TLL   = 27             // triangle, lower-left filled
.const G_TUL   = 28             // upper-left
.const G_TLR   = 29             // lower-right
.const G_TUR   = 30             // upper-right
.const G_SEAMR = 31             // solid, a dark line down the right edge
.const G_SEAML = 60             // solid, a dark line down the left edge
.const G_ARROW = 59             // minimap: you, facing north (59, 61, 62, 63 = N E S W)
.const G_LINEB = 34             // "  a line along the bottom (ceiling seams)
.const G_LINET = 35             // #  a line along the top (floor seams)
.const G_LAMP  = 36             // $  a bar: ceiling lamp
.const G_PANH  = 37             // %  solid, a seam along the top
.const G_PANX  = 38             // &  solid, seams along the top and the left
.const G_GRILL = 40             // (  vent: stripes
.const G_RIVET = 43             // +  solid with a bolt
.const G_D75   = 45             // -  fog: 3 in 4 pixels lit
.const G_D50   = 17             // Q  fog: checkerboard
.const G_D25   = 26             // Z  fog: 1 in 4 lit
// game text can't use these (checkText in main.asm says so when assembling)
.var RESERVED_CHARS = "#$%&(+-;<=>?@[]^QZ"
// + the background the glyph's empty pixels show (ECM: the top 2 bits of the code)
.const ON_FLOOR = 64            // $d022
.const ON_CEIL  = 128           // $d023
.const C_CEIL   = 32 + ON_CEIL  // a blank cell of ceiling
.const C_FLOOR  = 32 + ON_FLOOR
.const C_DARK   = 32            // far away: black

.function modp(a, b) { .return a - b*floor(a/b) }

// the bulkhead texture of a wall facing you at plane k, at view cell c, r:
// panels with seams, a bolt in each panel's corner, a vent along the bottom
.function wallGlyph(k, c, r) {
    .if (k == 3) .return G_SOLID
    .var a = INSET.get(k)
    .var h = VH - 2*a                   // the face's height: 12 or 6
    .var lr = r - a
    .var pc = modp(c - a, h/2)          // column inside a panel
    .var hseam = lr == 0 || (k == 1 && lr == 6)
    .if (k == 1 && lr == h-1) .return G_GRILL
    .if (hseam && pc == 0) .return G_PANX
    .if (hseam) .return G_PANH
    .if (pc == 0) .return G_SEAML
    .if (k == 1 && (lr == 1 || lr == 7) && pc == 1) .return G_RIVET
    .return G_SOLID
}

.var PIECES = List()

// FRONT
.for (var k=1; k<=3; k++) {
    .var p = List()
    .var a = INSET.get(k)
    .for (var r=a; r<VH-a; r++)
        .for (var c=a; c<VW-a; c++)
            .eval p.add(List().add(r*VW + c, wallGlyph(k, c, r), FRONT_COL.get(k)))
    .eval PIECES.add(p)
}
// LSIDE
.for (var f=0; f<3; f++) {
    .var p = List()
    .var last = INSET.get(f+1) - 1
    .for (var c=INSET.get(f); c<=last; c++) {
        .var col = SIDE_COL.get(f)
        .eval p.add(List().add(c*VW + c, G_TLL + ON_CEIL, col))
        .for (var r=c+1; r<VH-1-c; r++)
            .eval p.add(List().add(r*VW + c, c == last ? G_SEAMR : G_SOLID, col))
        .eval p.add(List().add((VH-1-c)*VW + c, G_TUL + ON_FLOOR, col))
    }
    .eval PIECES.add(p)
}
// LOPEN
.for (var f=0; f<3; f++) {
    .var p = List()
    .var last = INSET.get(f+1) - 1
    .var a = INSET.get(f+1)
    .for (var c=INSET.get(f); c<=last; c++)
        .for (var r=a; r<VH-a; r++)
            .eval p.add(List().add(r*VW + c, c == last ? G_SEAMR : wallGlyph(f+1, c, r), FRONT_COL.get(f+1)))
    .eval PIECES.add(p)
}
// RSIDE (LSIDE mirrored)
.for (var f=0; f<3; f++) {
    .var p = List()
    .var last = INSET.get(f+1) - 1
    .for (var c=INSET.get(f); c<=last; c++) {
        .var col = SIDE_COL.get(f)
        .var x = VW-1-c
        .eval p.add(List().add(c*VW + x, G_TLR + ON_CEIL, col))
        .for (var r=c+1; r<VH-1-c; r++)
            .eval p.add(List().add(r*VW + x, c == last ? G_SEAML : G_SOLID, col))
        .eval p.add(List().add((VH-1-c)*VW + x, G_TUR + ON_FLOOR, col))
    }
    .eval PIECES.add(p)
}
// ROPEN
.for (var f=0; f<3; f++) {
    .var p = List()
    .var last = INSET.get(f+1) - 1
    .var a = INSET.get(f+1)
    .for (var c=INSET.get(f); c<=last; c++)
        .for (var r=a; r<VH-a; r++)
            .eval p.add(List().add(r*VW + VW-1-c, c == last ? G_SEAML : wallGlyph(f+1, VW-1-c, r), FRONT_COL.get(f+1)))
    .eval PIECES.add(p)
}

// DOORS on the wall 1 and 2 ahead, as text-art:
//   #  solid   -  seam on top   +  seams top + left   |  seam on the left   !  seam on the right
//   =  vent    o  bolt
.var DOOR_ART = List().add(
    List().add(7, 7, List().add(        // left column, top row, rows
        "+--+--",
        "|o#!o#",
        "|##!##",
        "|##!##",
        "|==!==",
        "|##!##",
        "|##!##",
        "|o#!o#",
        "|##!##")),
    List().add(9, 9, List().add(
        "--",
        "#|",
        "=|",
        "#|")))
.function artGlyph(ch) {
    .if (ch == "#") .return G_SOLID
    .if (ch == "-") .return G_PANH
    .if (ch == "+") .return G_PANX
    .if (ch == "|") .return G_SEAML
    .if (ch == "!") .return G_SEAMR
    .if (ch == "=") .return G_GRILL
    .if (ch == "o") .return G_RIVET
    .error "unknown door art character: '" + ch + "'"
}
.for (var k=0; k<2; k++) {
    .var p = List()
    .var d = DOOR_ART.get(k)
    .var rows = d.get(2)
    .for (var r=0; r<rows.size(); r++)
        .for (var c=0; c<rows.get(r).size(); c++)
            .eval p.add(List().add((d.get(1)+r)*VW + d.get(0)+c, artGlyph(rows.get(r).substring(c, c+1)), 0))
    .eval PIECES.add(p)
}

// FLOOR AND CEILING SEAMS where each plane meets them
{
    .var p = List()
    .for (var k=1; k<=3; k++) {
        .var a = INSET.get(k)
        .for (var c=a; c<VW-a; c++) {
            .eval p.add(List().add((a-1)*VW + c, G_LINEB + ON_CEIL, 0))
            .eval p.add(List().add((VH-a)*VW + c, G_LINET + ON_FLOOR, 0))
        }
    }
    .eval PIECES.add(p)
}
// CEILING LAMPS: a wide one overhead, a narrow one a cell further on
{
    .var p = List()
    .for (var c=8; c<=11; c++) .eval p.add(List().add(2*VW + c, G_LAMP + ON_CEIL, LAMP_COL.get(0)))
    .for (var c=9; c<=10; c++) .eval p.add(List().add(5*VW + c, G_LAMP + ON_CEIL, LAMP_COL.get(1)))
    .eval PIECES.add(p)
}
.const P_SEAMS = 17
.const P_LAMPS = 18

.for (var n=0; n<PIECES.size(); n++)
    .errorif PIECES.get(n).size() > 255, "piece " + n + " is too big for blit"

// ---------------------------------------------------------------- the piece data
// each piece: offset lo[n], offset hi[n], code[n], colour[n]
.var PIECE_AT = List()
piece_data:
.for (var n=0; n<PIECES.size(); n++) {
    .var p = PIECES.get(n)
    .eval PIECE_AT.add(*)
    .fill p.size(), <p.get(i).get(0)
    .fill p.size(), >p.get(i).get(0)
    .fill p.size(), p.get(i).get(1)
    .fill p.size(), p.get(i).get(2)
}
.const NPIECES = PIECES.size()
p_count: .fill NPIECES, PIECES.get(i).size()
pa_lo:   .fill NPIECES, <(PIECE_AT.get(i))
pa_hi:   .fill NPIECES, >(PIECE_AT.get(i))
pb_lo:   .fill NPIECES, <(PIECE_AT.get(i) + PIECES.get(i).size())
pb_hi:   .fill NPIECES, >(PIECE_AT.get(i) + PIECES.get(i).size())
pc_lo:   .fill NPIECES, <(PIECE_AT.get(i) + PIECES.get(i).size()*2)
pc_hi:   .fill NPIECES, >(PIECE_AT.get(i) + PIECES.get(i).size()*2)
pd_lo:   .fill NPIECES, <(PIECE_AT.get(i) + PIECES.get(i).size()*3)
pd_hi:   .fill NPIECES, >(PIECE_AT.get(i) + PIECES.get(i).size()*3)

// ---------------------------------------------------------------- the cell patterns
// Every shape is 4 fat pixels x 8 rows: x = the ink (colour RAM), . = the background
// the code picks with its top 2 bits (0: black, 64: floor, 128: ceiling).
// mc_patterns holds all 256 codes x 8 bytes; a code with no shape is all background.
.var FAT = Hashtable()
.function fill8(s) { .return List().add(s, s, s, s, s, s, s, s) }
.eval FAT.put(G_SOLID, fill8("xxxx"))
.eval FAT.put(G_TLL,   List().add("x...", "x...", "xx..", "xx..", "xxx.", "xxx.", "xxxx", "xxxx"))
.eval FAT.put(G_TUL,   List().add("xxxx", "xxxx", "xxx.", "xxx.", "xx..", "xx..", "x...", "x..."))
.eval FAT.put(G_TLR,   List().add("...x", "...x", "..xx", "..xx", ".xxx", ".xxx", "xxxx", "xxxx"))
.eval FAT.put(G_TUR,   List().add("xxxx", "xxxx", ".xxx", ".xxx", "..xx", "..xx", "...x", "...x"))
.eval FAT.put(G_SEAMR, fill8("xxx."))
.eval FAT.put(G_SEAML, fill8(".xxx"))
.eval FAT.put(G_LINEB, List().add("....", "....", "....", "....", "....", "....", "....", "xxxx"))
.eval FAT.put(G_LINET, List().add("xxxx", "....", "....", "....", "....", "....", "....", "...."))
.eval FAT.put(G_LAMP,  List().add("....", "....", "....", ".xx.", "xxxx", ".xx.", "....", "...."))
.eval FAT.put(G_PANH,  List().add("....", "xxxx", "xxxx", "xxxx", "xxxx", "xxxx", "xxxx", "xxxx"))
.eval FAT.put(G_PANX,  List().add("....", ".xxx", ".xxx", ".xxx", ".xxx", ".xxx", ".xxx", ".xxx"))
.eval FAT.put(G_GRILL, List().add("xxxx", "....", "xxxx", "....", "xxxx", "....", "xxxx", "...."))
.eval FAT.put(G_RIVET, List().add("xxxx", "xxxx", "x.xx", "x.xx", "xxxx", "xxxx", "xxxx", "xxxx"))
.eval FAT.put(G_D75,   List().add("xxx.", "x.xx", "xxx.", "x.xx", "xxx.", "x.xx", "xxx.", "x.xx"))
.eval FAT.put(G_D50,   List().add("x.x.", ".x.x", "x.x.", ".x.x", "x.x.", ".x.x", "x.x.", ".x.x"))
.eval FAT.put(G_D25,   List().add("x...", "..x.", "x...", "..x.", "x...", "..x.", "x...", "..x."))
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

// ---------------------------------------------------------------- fog
// Every cell of the view gets a depth (0 near - 3 far): the piece's own, or for floor
// and ceiling, from how far the row is from the horizon. The deck's fog profile says
// how foggy each depth is (0 clear, 1-3 dithered, 4 black); the fog pass then swaps
// solid-ish cells for a dither of their colour on black, and dims diagonal edges.
piece_depth:
        .byte 1, 2, 3                   // FRONT
        .byte 0, 1, 2                   // LSIDE
        .byte 1, 2, 3                   // LOPEN
        .byte 0, 1, 2                   // RSIDE
        .byte 1, 2, 3                   // ROPEN
        .byte 1, 2                      // doors
        .byte $ff, $ff                  // seams, lamps: keep the floor's / ceiling's
.errorif piece_depth + NPIECES != *, "piece_depth needs one entry per piece"
.function rowDepth(r) {
    .var d = min(r, VH-1-r)
    .if (d < INSET.get(1)) .return 0
    .if (d < INSET.get(2)) .return 1
    .if (d < INSET.get(3)) .return 2
    .return 3
}
bg_depth:   .fill VW*VH, rowDepth(floor(i/VW))
// what fog does to each glyph: 0 nothing, 1 dither it, 2 dim its colour
.var FOG_DITHER = List().add(G_SOLID, G_SEAMR, G_SEAML, G_LINEB, G_LINET, G_PANH, G_PANX, G_GRILL, G_RIVET, 32)
.var FOG_DIM    = List().add(G_TLL, G_TUL, G_TLR, G_TUR)
.function fogKind(g) {
    .for (var n=0; n<FOG_DITHER.size(); n++) .if (FOG_DITHER.get(n) == g) .return 1
    .for (var n=0; n<FOG_DIM.size(); n++) .if (FOG_DIM.get(n) == g) .return 2
    .return 0
}
glyph_fog:  .fill 64, fogKind(i)
dither_code: .byte 0, G_D75, G_D50, G_D25, 32     // by fog level 1-4
// each colour one step darker
ramp:       .byte 0, 15, 9, 14, 6, 11, 0, 8, 9, 0, 2, 0, 11, 5, 6, 12

// Sprite art for A Pain in the Asteroids.
//
// Multicolour sprites: up to 12 characters a row (each is one fat pixel,
// 2 screen pixels wide), up to 21 rows:
//   .  clear
//   1  shared colour 1   ($d025, dark grey)
//   2  the sprite's own colour ($d027 + sprite number)
//   3  shared colour 2   ($d026, white)
// Hi-res sprites: up to 24 characters a row, # set, . clear.
// mirror("abc") gives "abccba": draw the left half of a symmetric sprite.

.function mirror(h) {
    .var r = h
    .for (var i=h.size()-1; i>=0; i--) .eval r = r + h.substring(i, i+1)
    .return r
}

.macro SpriteMC(rows) {
    .errorif rows.size() > 21, "sprite taller than 21 rows"
    .for (var r=0; r<21; r++) {
        .var s = ""
        .if (r < rows.size()) .eval s = rows.get(r)
        .errorif s.size() > 12, "multicolour sprite row longer than 12: " + s
        .for (var b=0; b<3; b++) {
            .var v = 0
            .for (var i=0; i<4; i++) {
                .eval v = v*4
                .var p = b*4 + i
                .if (p < s.size()) {
                    .var c = s.substring(p, p+1)
                    .if (c == "1") .eval v = v + 1
                    .if (c == "2") .eval v = v + 2
                    .if (c == "3") .eval v = v + 3
                }
            }
            .byte v
        }
    }
    .byte 0
}

.macro SpriteHi(rows) {
    .for (var r=0; r<21; r++) {
        .var s = ""
        .if (r < rows.size()) .eval s = rows.get(r)
        .errorif s.size() > 24, "sprite row longer than 24: " + s
        .for (var b=0; b<3; b++) {
            .var v = 0
            .for (var i=0; i<8; i++) {
                .eval v = v*2
                .var p = b*8 + i
                .if (p < s.size()) {
                    .if (s.substring(p, p+1) == "#") .eval v = v + 1
                }
            }
            .byte v
        }
    }
    .byte 0
}

// A big picture, 12*cols wide and 21*tall rows, cut into sprites
// left to right, top to bottom.
.macro BigSprite(rows, cols, tall) {
    .errorif rows.size() != 21*tall, "big sprite needs " + 21*tall + " rows"
    .for (var by=0; by<tall; by++) {
        .for (var bx=0; bx<cols; bx++) {
            .var part = List()
            .for (var r=0; r<21; r++) {
                .var s = rows.get(by*21 + r)
                .errorif s.size() != 12*cols, "big sprite row must be " + 12*cols + " wide: " + s
                .eval part.add(s.substring(bx*12, bx*12 + 12))
            }
            SpriteMC(part)
        }
    }
}

* = $2000 "Sprites"

// ---- the ship (own colour light blue)
SpriteMC(List().add(
    mirror(".....3"),
    mirror(".....3"),
    mirror("....22"),
    mirror("....23"),
    mirror("....23"),
    mirror("...223"),
    mirror("...222"),
    mirror("..1222"),
    mirror("..1222"),
    mirror("1.1222"),
    mirror("1.2222"),
    mirror("3.2221"),
    mirror("212221"),
    mirror("222211"),
    mirror("222221"),
    mirror("122222"),
    mirror("1.1122"),
    mirror("...1.1")))

// ---- the bullet (hi-res, yellow)
SpriteHi(List().add(
    mirror("...........#"),
    mirror("...........#"),
    mirror("...........#"),
    mirror("...........#"),
    mirror("...........#"),
    mirror("...........#")))

// ---- rock A
SpriteMC(List().add(
    "....2222....",
    "...222322...",
    "..22233222..",
    ".2223322222.",
    ".2232222112.",
    ".2322221112.",
    "232222211122",
    "222122222122",
    "221112222222",
    "221112222221",
    "222122222221",
    "222222222211",
    "222222211221",
    ".2222221112.",
    ".2222222121.",
    ".2222222211.",
    "..22222211..",
    "...221111...",
    "....1111...."))

// ---- rock B
SpriteMC(List().add(
    "......222...",
    "....222322..",
    "...22233222.",
    "..222332222.",
    ".22322222222",
    ".22322211222",
    ".23222111122",
    "222222211122",
    "222222222222",
    "221122222221",
    "211112222221",
    "211112222211",
    ".2111222222.",
    ".2212222211.",
    "..222222111.",
    "..22222211..",
    "...2222111..",
    ".....2211..."))
// ---- explosion, frame 1 (fire)
SpriteMC(List().add(
    "",
    "...2....2...",
    ".2..2..2..2.",
    "..2.2222.2..",
    "....23332...",
    ".2.2333332.2",
    "..223333322.",
    "2.233333332.",
    "..233333322.",
    ".22233332.2.",
    "..2.2332.2..",
    ".2..2222..2.",
    "..2..2..2...",
    "....2...2..."))

// ---- explosion, frame 2 (smoke)
SpriteMC(List().add(
    "",
    ".1...1...1..",
    "...1...2...1",
    ".2..1.1..2..",
    "1..2.121.2..",
    "..1.22322.1.",
    ".1.2233321..",
    "..12332221.1",
    "1..122212...",
    "..1.1211..1.",
    ".1...1..1...",
    "...1....1...",
    ".1....1....1"))

// ---- the mothership, 36 x 42, nose up: the ship launches out of the nose
// and docks in the back. The middle third must stay solid in rows 12-32:
// the docked ship hides behind it.
BigSprite(List().add(
    mirror("...............222"),
    mirror("..............2222"),
    mirror(".............22211"),
    mirror("............222111"),
    mirror("...........2222111"),
    mirror("..........22232111"),
    mirror(".........222322111"),
    mirror("........2222322111"),
    mirror(".......22222322222"),
    mirror("......222223222222"),
    mirror(".....2222232221222"),
    mirror("....12222232212222"),
    mirror("...112222232222222"),
    mirror("..1112222232222122"),
    mirror(".11122222322221222"),
    mirror("111222222322221222"),
    mirror("122222222322221222"),
    mirror("122333222322222222"),
    mirror("122222222322222112"),
    mirror("122111222322222112"),
    mirror("122222222322222222"),
    mirror("122222222322221222"),
    mirror(".12222222322221222"),
    mirror(".12233222322222222"),
    mirror(".12222222322222222"),
    mirror(".11222222322222112"),
    mirror("..1222222322222112"),
    mirror("..1222222322222222"),
    mirror("..1222222322221222"),
    mirror("..1122222322221222"),
    mirror("...122222322222222"),
    mirror("...112222322222222"),
    mirror("....12222222222222"),
    mirror("....11222222221122"),
    mirror(".....1222111211112"),
    mirror("......11..111..111"),
    mirror("......33..333..333"),
    mirror("......33...3...333"),
    mirror(".......3...3....33"),
    mirror("...........3.....3"),
    mirror(".................3"),
    mirror("..................")), 3, 2)

// ---- small rock (what a big rock splits into)
SpriteMC(List().add(
    "", "", "", "", "",
    ".....222....",
    "....22322...",
    "...2233222..",
    "...2322212..",
    "...2222112..",
    "...2221122..",
    "....22212...",
    ".....211...."))

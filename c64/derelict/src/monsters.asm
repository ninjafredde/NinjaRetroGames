// The monsters: their numbers, words and pictures.
//
// PICTURES are 4 multicolour sprites (2 x 2), shown doubled in size in the view.
// Draw the LEFT HALF only (12 fat pixels wide); the right half is its mirror.
// Up to 42 rows; shorter pictures stand on the bottom (the floor).
//   .  clear
//   1  shared colour 1 ($d025, black: outlines, pupils)
//   2  the monster's own colour (MON_COLOUR)
//   3  shared colour 2 ($d026, white: eyes, teeth, spots)

.var MON_NAME   = List().add("SPORE BUG", "FUNGOID", "CLEANBOT")
.var MON_VERB   = List().add("BITES", "SPORES", "SCRUBS")
.var MON_HP     = List().add(6, 12, 22)
.var MON_ATK    = List().add(3, 5, 7)     // a hit does 1 to this
.var MON_MAX    = List().add(3, 2, 1)     // how many can turn up together
.var MON_COLOUR = List().add(5, 2, 15)

.var MON_PICS = List()

.eval MON_PICS.add(List().add(      // SPORE BUG
    "...1........",
    "....1.......",
    ".....1......",
    "......1.....",
    "......1.....",
    ".......11111",
    ".....1122222",
    "....12222222",
    "...122222222",
    "...123332222",
    "..1233113222",
    "..1233113222",
    "..1223332222",
    "..1222222222",
    "..1222222222",
    "...122211111",
    "...122221333",
    "....12222111",
    ".....1122222",
    "1.....122222",
    ".1...1222222",
    "..1.12222222",
    "...112222222",
    "....12222222",
    "..1112222222",
    ".1..12222222",
    "1...12222222",
    "....12222222",
    "...112222222",
    "..1.12222222",
    ".1...1222222",
    "1.....122222",
    ".......11111"))

.eval MON_PICS.add(List().add(      // FUNGOID
    ".......11111",
    ".....1122222",
    "....12222222",
    "...122332222",
    "..1223333222",
    "..1222332222",
    ".12222222223",
    ".12222222233",
    "122333222223",
    "123333222222",
    "122332222222",
    "122222222222",
    ".11111111111",
    "....13333333",
    "....13333333",
    "....13311333",
    "....13311333",
    "....13333333",
    "....13333333",
    "....13311111",
    "..1.13333333",
    ".1.133333333",
    "1..133333333",
    "...133333333",
    "...133333333",
    "....13333333",
    "....13333333",
    "...111333333",
    "..1333113333",
    "..1111..1111"))

.eval MON_PICS.add(List().add(      // CLEANBOT: one big eye, two mops
    "..........11",
    "...........1",
    "..........13",
    "........1111",
    "......113333",
    ".....1322222",
    "....13222222",
    "....12222222",
    "...122211111",
    "...122113333",
    "...122133311",
    "...122133311",
    "...122113333",
    "...122211111",
    "....12222222",
    ".....1111111",
    ".......12222",
    "...111111111",
    "..1222222222",
    ".12233222222",
    "1.1232222222",
    "121222222222",
    "121222211111",
    "121222213131",
    "121222211111",
    "121222222222",
    "131222222222",
    "131122222222",
    "131.12222222",
    "131.12222222",
    "131..1111111",
    "131.13113113",
    "131.11111111",
    "333.........",
    "3333........",
    "33333.......",
    "3.3.3......."))

.eval MON_PICS.lock()
.const NMON = MON_NAME.size()

// one sprite (64 bytes) from 21 rows of 12 fat pixels
.macro SpriteMC(rows) {
    .for (var y=0; y<21; y++) {
        .var s = rows.get(y)
        .for (var b=0; b<3; b++) {
            .var v = 0
            .for (var p=0; p<4; p++) {
                .var c = s.substring(b*4+p, b*4+p+1)
                .var bits = c == "1" ? 1 : c == "2" ? 2 : c == "3" ? 3 : 0
                .eval v = v | (bits << (6 - p*2))
            }
            .byte v
        }
    }
    .byte 0
}

// a monster: left halves -> 42 rows of 24 -> 4 sprites (top-left, top-right, bottom-left, bottom-right)
.macro MonsterSprites(half) {
    .errorif half.size() > 42, "a monster picture is at most 42 rows"
    .var rows = List()
    .for (var y=0; y<42-half.size(); y++) .eval rows.add("........................")
    .for (var y=0; y<half.size(); y++) {
        .var h = half.get(y)
        .errorif h.size() != 12, "monster rows are 12 wide (the left half): " + h
        .var m = ""
        .for (var x=11; x>=0; x--) .eval m = m + h.substring(x, x+1)
        .eval rows.add(h + m)
    }
    .var tl = List()
    .var tr = List()
    .var bl = List()
    .var br = List()
    .for (var y=0; y<21; y++) {
        .eval tl.add(rows.get(y).substring(0, 12))
        .eval tr.add(rows.get(y).substring(12, 24))
        .eval bl.add(rows.get(y+21).substring(0, 12))
        .eval br.add(rows.get(y+21).substring(12, 24))
    }
    SpriteMC(tl)
    SpriteMC(tr)
    SpriteMC(bl)
    SpriteMC(br)
}

// ---------------------------------------------------------------- items you can see in the corridor
// One multicolour sprite each (12 x 21, same colours as above), standing on the floor:
// doubled one cell ahead, normal size two cells ahead. Order: the special numbers
// 10-15 (keycard, medkit, spanners, vending machine, hatch, the captain's chair).
.var ITEM_COLOUR = List().add(7, 2, 8, 2, 12, 6)
.var ITEM_PICS = List()
.eval ITEM_PICS.add(List().add(     // keycard
    "..11111111..",
    ".1222222221.",
    ".1233333321.",
    ".1222222221.",
    ".1211222221.",
    ".1211222221.",
    ".1222222221.",
    "..11111111.."))
.eval ITEM_PICS.add(List().add(     // medkit
    "...111111...",
    "...1....1...",
    "111111111111",
    "133332233331",
    "133332233331",
    "132222222231",
    "132222222231",
    "133332233331",
    "133332233331",
    "111111111111"))
.eval ITEM_PICS.add(List().add(     // a crate of plasma spanners
    "111111111111",
    "132222222231",
    "123222222321",
    "122322223221",
    "122232232221",
    "122223322221",
    "122223322221",
    "122232232221",
    "122322223221",
    "123222222321",
    "132222222231",
    "111111111111"))
.eval ITEM_PICS.add(List().add(     // the vending machine
    "111111111111",
    "122222222221",
    "121111111121",
    "121333333121",
    "121313313121",
    "121333333121",
    "121313313121",
    "121333333121",
    "121111111121",
    "122222222221",
    "122221112221",
    "122222222221",
    "121111111121",
    "121333333121",
    "121111111121",
    "122222222221",
    "122222222221",
    "111111111111",
    ".11......11."))
.eval ITEM_PICS.add(List().add(     // the hatch, in the floor
    "...111111...",
    ".1133333311.",
    "132222222231",
    "132111111231",
    "132111111231",
    "132222222231",
    ".1133333311.",
    "...111111..."))
.eval ITEM_PICS.add(List().add(     // the captain's chair
    "...111111...",
    "..12222221..",
    "..12333221..",
    "..12222221..",
    "..12222221..",
    "..12222221..",
    "111222222111",
    "122111111221",
    "122222222221",
    "111111111111",
    ".....11.....",
    ".....11.....",
    "...111111...",
    "..1......1.."))
.eval ITEM_PICS.lock()
.const NITEM_PICS = ITEM_PICS.size()

// a single sprite, standing on its bottom row
.macro ItemSprite(rows) {
    .errorif rows.size() > 21, "an item picture is at most 21 rows"
    .var full = List()
    .for (var y=0; y<21-rows.size(); y++) .eval full.add("............")
    .for (var y=0; y<rows.size(); y++) {
        .errorif rows.get(y).size() != 12, "item rows are 12 wide: " + rows.get(y)
        .eval full.add(rows.get(y))
    }
    SpriteMC(full)
}

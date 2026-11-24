// Graphics for Mushroom for Improvement: the room characters and the sprites.
//
// CHARACTERS are multicolour, 4 fat pixels wide, 8 rows:
//   .  background (black)
//   1  shared colour 1 ($d022, dark grey)
//   2  shared colour 2 ($d023, light grey)
//   3  the character's own colour (colour_of in main.asm, 0-7)
//
// SPRITES are multicolour, up to 12 fat pixels wide, 21 rows:
//   .  clear
//   1  shared sprite colour 1 ($d025, brown: hair, boots, bug legs)
//   2  the sprite's own colour (John's uniform, the bug, the spray)
//   3  shared sprite colour 2 ($d026, pink: skin, bug eyes)
// Feet go on the last row (20): that row stands on the floor.
// flip(rows) mirrors a picture left-right (the facing-left frames).

.function pad12(s) {
    .var r = s
    .for (var i=s.size(); i<12; i++) .eval r = r + "."
    .return r
}

.function flip(rows) {
    .var out = List()
    .for (var r=0; r<rows.size(); r++) {
        .var s = pad12(rows.get(r))
        .var m = ""
        .for (var i=s.size()-1; i>=0; i--) .eval m = m + s.substring(i, i+1)
        .eval out.add(m)
    }
    .return out
}

.function mcValue(c) {
    .if (c == "1") .return 1
    .if (c == "2") .return 2
    .if (c == "3") .return 3
    .return 0
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
                .if (p < s.size()) .eval v = v + mcValue(s.substring(p, p+1))
            }
            .byte v
        }
    }
    .byte 0
}

.macro CharMC(rows) {
    .errorif rows.size() != 8, "a character has 8 rows"
    .for (var r=0; r<8; r++) {
        .var s = rows.get(r)
        .errorif s.size() != 4, "multicolour character row must be 4 wide: " + s
        .var v = 0
        .for (var i=0; i<4; i++) .eval v = v*4 + mcValue(s.substring(i, i+1))
        .byte v
    }
}

// ---------------------------------------------------------------- characters
// in screen code order from 64 (see the T_ constants in main.asm)
.var CH_WALL = List().add("1111","1222","1232","1222","1222","1222","1232","1222").lock()
.var CH_PLAT = List().add("2222","3333","1111","1.1.",".1.1","....","....","....").lock()
.var CH_LAD  = List().add("2..2","2332","2..2","2..2","2..2","2332","2..2","2..2").lock()
.var CH_LADP = List().add("2222","3333","1111","2..2","2332","2..2","2..2","2..2").lock()
.var CH_M1   = List().add("....","....","....","....",".33.","3333",".22.",".22.").lock()
.var CH_M2   = List().add("....","....",".33.","3333","3233","3333",".22.",".22.").lock()
.var CH_M3A  = List().add(".33.","3323","3333","3233","3333","3332",".22.",".22.").lock()
.var CH_M3B  = List().add("....",".33.","3323","3333","3233","3333",".22.","2222").lock()
.var CH_TANK = List().add(".22.","2332","2332","2112","2332","2332","2332","2222").lock()
.var CH_WIN  = List().add("1111","....",".2..","....","....","...2","....","1111").lock()
.var CH_CON  = List().add("2222","2132","2312","2222","1111","1..1","1..1","1..1").lock()
.var CH_PIPV = List().add("1221",".21.",".21.",".21.",".21.",".21.",".21.",".21.").lock()
.var CH_PIPH = List().add("....","1111","2222","2222","1111","....","....","....").lock()
.var CH_KTOP = List().add("2222","2332","2332","2222","2..2","2..2","2.12","2..2").lock()
.var CH_KBOT = List().add("2..2","2..2","2332","2..2","2222","2112","2222","1111").lock()
.var CH_LOO  = List().add("..33","..33","..33","3333","3333",".33.",".22.","2222").lock()
.var CH_BOX  = List().add("1111","1321","1231","1321","1231","1321","1231","1111").lock()
.var CH_SPARE= List().add("....","....","....","....","....","....","....","....").lock()

// ---------------------------------------------------------------- sprites
.var HEAD = List().add(
    "....1111....",
    "...111111...",
    "...113333...",
    "...113313...",
    "....33333...",
    ".....333....").lock()

.function john(body) {
    .var out = List()
    .for (var i=0; i<HEAD.size(); i++) .eval out.add(HEAD.get(i))
    .for (var i=0; i<body.size(); i++) .eval out.add(body.get(i))
    .return out
}

.var TORSO = List().add(
    "....2222....",
    "..22222222..",
    "..22222222..",
    "..2.2222.2..",
    "..2.2222.2..",
    "..3.1111.3..",
    "....2222....").lock()

.function plus(a, b) {
    .var out = List()
    .for (var i=0; i<a.size(); i++) .eval out.add(a.get(i))
    .for (var i=0; i<b.size(); i++) .eval out.add(b.get(i))
    .return out
}

.var LEGS_STAND = List().add(
    "....22.22...",
    "....22.22...",
    "....22.22...",
    "....22.22...",
    "....22.22...",
    "....22.22...",
    "....11.11...",
    "....111.111.").lock()
.var LEGS_WALK1 = List().add(
    "...22..22...",
    "...22..22...",
    "..22....22..",
    "..22....22..",
    ".22......22.",
    ".22......22.",
    ".11......11.",
    ".111.....111").lock()
.var LEGS_WALK2 = List().add(
    "....22.22...",
    "....22.22...",
    "....22.22...",
    "...22..22...",
    "...22...22..",
    "...22...22..",
    "...11...11..",
    "...111..111.").lock()
.var LEGS_JUMP = List().add(
    "...22..22...",
    "..22....22..",
    "..22....22..",
    "...22..22...",
    "...11..11...").lock()

.var SPR_STAND = john(plus(TORSO, LEGS_STAND)).lock()
.var SPR_WALK1 = john(plus(TORSO, LEGS_WALK1)).lock()
.var SPR_WALK2 = john(plus(TORSO, LEGS_WALK2)).lock()
.var SPR_JUMP  = john(plus(List().add(
    "....2222....",
    ".322222223..",
    ".2.222222.2.",
    "...222222...",
    "...222222...",
    "....1111....",
    "....2222...."), LEGS_JUMP)).lock()
.var SPR_SPRAY = john(plus(List().add(
    "....2222....",
    "..22222222..",
    "..222222222.",
    "..2.2222.331",
    "..2.2222..1.",
    "..3.1111....",
    "....2222...."), LEGS_STAND)).lock()

.var SPR_CLIMB = List().add(        // from behind; the second frame is this one flipped
    "....1111....",
    "...111111...",
    "...111111...",
    "...111111...",
    "....1111....",
    "..3..33.....",
    "..2.2222....",
    "..222222222.",
    "...222222.2.",
    "...222222.2.",
    "...222222.3.",
    "....1111....",
    "....2222....",
    "....22.22...",
    "...22..22...",
    "...22..22...",
    "...11..22...",
    ".......22...",
    ".......22...",
    ".......11...",
    ".......11...").lock()

.var SPR_DEAD = List().add(
    "","","","","","","","","","","","","","","","","",
    "............",
    "113222222211",
    "113222222211",
    ".3........3.").lock()

.var SPR_BUG1 = List().add(
    "","","","","","","","","","","","","",
    "...1....1...",
    "....1..1....",
    "...222222...",
    "..23222232..",
    ".2222222222.",
    ".2222222222.",
    "..22222222..",
    ".1.1.11.1.1.").lock()
.var SPR_BUG2 = List().add(
    "","","","","","","","","","","","","",
    "....1..1....",
    "....1..1....",
    "...222222...",
    "..23222232..",
    ".2222222222.",
    ".2222222222.",
    "..22222222..",
    "1.1..11..1.1").lock()
.var SPR_SQUISH = List().add(
    "","","","","","","","","","","","","","","","","","",
    "............",
    ".1.222222.1.",
    "122222222221").lock()

.var SPR_PUFF1 = List().add(
    "","","","","","","",
    "2...........",
    ".22.........",
    "222.2.......",
    ".2222.2.....",
    "2.22222.2...",
    ".222.222.2..",
    "..22.2222...",
    "...2.2.222.2",
    "....2.2.22..",
    ".....2..2.2.",
    "......2..2..",
    ".......2...2",
    "........2...").lock()
.var SPR_PUFF2 = List().add(
    "","","","","","","",
    ".2..........",
    "2.22........",
    ".222.2......",
    "22222.2.....",
    ".22222.2.2..",
    "2.222.222...",
    ".222.2.22.2.",
    "...22.2.222.",
    ".....2.2..2.",
    "....2..2.2..",
    ".......2..2.",
    "......2...2.",
    ".........2..").lock()

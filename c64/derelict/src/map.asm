// The decks: 16 x 16 cells each, one text row per map row.
//   #    wall
//   .    floor
//   S    start (floor), facing the deck's START_DIR
//   D    a door (bump it to open)
//   L    a locked door (bump it with a keycard)
//   1-9  floor with a note: NOTES line n shows in the log when you step on it
//   K    a keycard     M  a medkit     W  plasma spanners (+2 hit for the crew)
//   V    the vending machine (a medkit, with a line)
//   H    the hatch down to the next deck
//   E    the bridge: the end
// Keep the outside edge all walls (the view looks through the map with wrap-around).

.var DECK1 = List().add(
    "################",
    "#S1....#.......#",
    "#.####D#.#####.#",
    "#.#K.#..2#...#.#",
    "#.#..#####.#.#.#",
    "#.#........#.V.#",
    "#.####.#####.###",
    "#......#.......#",
    "###D##.#.#####.#",
    "#..4#..#.#.....#",
    "#.###.##.#.###.#",
    "#.....#..#.#...#",
    "#.#####.##.#.#.#",
    "#M#.....#.W#.#L#",
    "#...###...##3#H#",
    "################")

.var DECK2 = List().add(
    "################",
    "#S..#.....#..M.#",
    "#.#.#.###.#.##.#",
    "#.#...#...#..#.#",
    "#.#####.####.#.#",
    "#.....#.#5...#.#",
    "###.#.#.#.####.#",
    "#M..#...#....#.#",
    "#.#######.##.#.#",
    "#.#.....#..#...#",
    "#.#.###.##.###L#",
    "#...#K#..#...#.#",
    "###.#.##D###.#.#",
    "#..6#....#...#7#",
    "#.###.##...#.#E#",
    "################")

.var DECKS       = List().add(DECK1, DECK2)
.var DECK_DIR    = List().add(1, 2)        // facing at the start: 0 north, 1 east, 2 south, 3 west
.var DECK_FLOOR  = List().add(9, 8)        // brown, orange
.var DECK_CEIL   = List().add(11, 0)       // dark grey, black (the lights are out)
.var DECK_FIGHTS = List().add(24, 36)      // fight chance each step, out of 256
.var DECK_LINES  = List().add(12, 9)       // the seams across floor and ceiling
.var DECK_LAMPS  = List().add(0, 11)       // 0: lamps lit; a colour: dead lamps in it
// fog at depth 0 (your cell), 1, 2, 3 cells ahead: how many steps darker the colours
// get (the painted art already fades into the dark; this is extra, per deck)
.var DECK_FOG    = List().add(
    List().add(0, 0, 0, 1),
    List().add(0, 1, 1, 2))
// the painted view's colours on each deck: colour n is drawn as entry n
//  0 black 1 white 2 red 3 cyan 4 purple 5 green 6 blue 7 yellow
//  8 orange 9 brown 10 light red 11 dark grey 12 grey 13 light green 14 light blue 15 light grey
.var DECK_REMAP  = List().add(
    List().add(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    List().add(0, 1, 2, 3, 4, 5, 0, 11, 9, 8, 10, 11, 12, 13, 14, 15))   // lights out: ceiling black, dead lamps; rust

// at most 38 characters each
.var NOTES = List().add(
    "A SIGN: MIND THE GAP. THERE IS NO GAP.",
    "SCORCH MARKS. SOMEONE MICROWAVED FOIL.",
    "A HUM FROM BELOW. SOMETHING BIG.",
    "THE LIGHTS FLICKER. SPOOKY, OR CHEAP.",
    "A POSTER: HANG IN THERE. NOBODY DID.",
    "A MUG: WORLD'S OKAYEST CAPTAIN.",
    "THE BRIDGE IS CLOSE. IT SMELLS OF FEET")

// items: what they are (0 keycard, 1 medkit, 2 spanners) and the line when found
.var ITEM_CHARS = "KMWV"
.var ITEM_KIND  = List().add(0, 1, 2, 1)
.var ITEM_TEXT  = List().add(
    "A KEYCARD! IT SMELLS OF CHEESE.",
    "A MEDKIT. PRESS M TO USE ONE.",
    "PLASMA SPANNERS FOR ALL. HIT HARDER.",
    "VENDING MACHINE COUGHS UP A MEDKIT!")

// a cell is one byte: what it is (0 floor, 1 wall, 2 door, 3 locked) + 4 x special:
// special 1-9 a note, 10-13 an item, 14 the hatch, 15 the end
.const SP_ITEM  = 10
.const SP_HATCH = 14
.const SP_END   = 15
.function cellByte(ch) {
    .if (ch == "#") .return 1
    .if (ch == "D") .return 2
    .if (ch == "L") .return 3
    .if (ch == "H") .return SP_HATCH*4
    .if (ch == "E") .return SP_END*4
    .if (ch == "." || ch == "S") .return 0
    .var digits = "123456789"
    .for (var n=0; n<9; n++) .if (digits.substring(n, n+1) == ch) {
        .errorif n+1 > NOTES.size(), "map note " + (n+1) + " has no NOTES line"
        .return (n+1)*4
    }
    .for (var n=0; n<ITEM_CHARS.size(); n++) .if (ITEM_CHARS.substring(n, n+1) == ch) .return (SP_ITEM+n)*4
    .error "unknown map character: '" + ch + "'"
}
.function findStart(rows) {
    .for (var y=0; y<16; y++)
        .for (var x=0; x<16; x++)
            .if (rows.get(y).substring(x, x+1) == "S") .return y*16 + x
    .error "put an S on every deck"
}

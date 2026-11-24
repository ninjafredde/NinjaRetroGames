// The rooms of the Dilettante, as text. 22 rows of exactly 40 characters.
//   W  hull wall (solid)         =  platform (stand on it, jump up through it)
//   H  ladder                    h  ladder through a platform / floor
//   1 2 3  mushroom: small, big, ripe (ripe ones spread and hatch bugs)
//   R  spray refill tank         B  crate (solid)
//   O window  C console  P - pipes  K k coffee machine  T toilet (decoration)
//   b  a bug starts here (up to 4 a room)   S  John starts here (one, any room)
// Exits: a gap in the side wall at rows 18-20 = a door; a ladder at the top or
// bottom edge = a shaft to the room above/below (same column in both rooms).
// Which room is next to which: room_left/right/up/down in main.asm.

.var ROOM_NAMES = List()
.var ROOM_MAPS = List()

// 0: BRIDGE
.eval ROOM_NAMES.add("BRIDGE")
.eval ROOM_MAPS.add(List().add(
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
    "W     OOOOOOOOOOOOOOOOOOOOOOOOOOOO     W",
    "W     OOOOOOOOOOOOOOOOOOOOOOOOOOOO     W",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W      CCC    1     b   2     21       W",
    "W    ======================h=======    W",
    "W                          H           W",
    "W                          H           W",
    "W                          H           W",
    "W                          H           W",
    "W                          H           W",
    "W  CCC          12         H           W",
    "W=========h=======================     W",
    "W         H                            W",
    "W         H                            W",
    "W         H                            W",
    "W         H                             ",
    "W         H                             ",
    "W CC  S   H   1          2     R  1     ",
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWhWWW").lock())

// 1: CORRIDOR
.eval ROOM_NAMES.add("CORRIDOR")
.eval ROOM_MAPS.add(List().add(
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
    "W--------------------------------------W",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W    12                     213        W",
    "W  ============h=====    ========h==== W",
    "W              H                 H     W",
    "W              H                 H     W",
    "W              H                 H     W",
    "W              H                 H     W",
    "W              H                 H     W",
    "W           b  H    1   2        H     W",
    "W     ==h===========================   W",
    "W       H                              W",
    "W       H                              W",
    "W       H                              W",
    "        H                               ",
    "        H                               ",
    "   2    H   b     31     1         2    ",
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWhWWWWWWWWW").lock())

// 2: GALLEY
.eval ROOM_NAMES.add("GALLEY")
.eval ROOM_MAPS.add(List().add(
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W             12    b   3              W",
    "W       ==h===================h=       W",
    "W         H                   H        W",
    "W         H                   H        W",
    "W         H                   H        W",
    "W         H                   H        W",
    "W         H                   H        W",
    "W   1     H                   H  21    W",
    "W ==========h====       ====h========= W",
    "W           H               H          W",
    "W           H               H          W",
    "W           H               H          W",
    "            H               H           ",
    "     K      H               H           ",
    "  R  k      H  2        13  H  b 1      ",
    "WWWWWWWWWWWWWWWWWWWWhWWWWWWWWWWWWWWWWWWW").lock())

// 3: CREW QUARTERS
.eval ROOM_NAMES.add("CREW QUARTERS")
.eval ROOM_MAPS.add(List().add(
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W                                      W",
    "W                 123       b    2  R  W",
    "W         ====h======================= W",
    "W             H                        W",
    "W             H                        W",
    "W             H                        W",
    "W             H                        W",
    "W             H                        W",
    "W    1  b     H     21                 W",
    "W=========================h====        W",
    "W                         H            W",
    "W                         H            W",
    "W                         H            W",
    "                          H            W",
    "                          H            W",
    "          2               H   31       W",
    "WWWWhWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW").lock())

// 4: LAVATORY
.eval ROOM_NAMES.add("LAVATORY")
.eval ROOM_MAPS.add(List().add(
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWHWWW",
    "W                                   H  W",
    "W                                   H  W",
    "W                                   H  W",
    "W                                   H  W",
    "W                                   H  W",
    "W        21                         H  W",
    "W ===h===========                   H  W",
    "W    H                              H  W",
    "W    H                              H  W",
    "W    H                              H  W",
    "W    H                              H  W",
    "W    H                              H  W",
    "W    H                      3 b 1   H  W",
    "W ======h====       ====h===========h==W",
    "W       H               H              W",
    "W       H               H              W",
    "W       H               H              W",
    "W       H               H               ",
    "W       H               H               ",
    "W  T  T H  T   T  12  b H     2         ",
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW").lock())

// 5: CARGO BAY
.eval ROOM_NAMES.add("CARGO BAY")
.eval ROOM_MAPS.add(List().add(
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWHWWWWWWWWW",
    "W                             H        W",
    "W                             H        W",
    "W                             H        W",
    "W                             H        W",
    "W                             H        W",
    "W         BB  12      b       H        W",
    "W       ============h====     H        W",
    "W                   H         H        W",
    "W                   H         H        W",
    "W                   H         H        W",
    "W                   H         H        W",
    "W                   H         H        W",
    "W  2        b       H   31    H     R  W",
    "W=====h=======================h======= W",
    "W     H                                W",
    "W     H                                W",
    "W     H                                W",
    "      H                                 ",
    "      H       B                         ",
    "      H  1   BB       2   B   b   13    ",
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW").lock())

// 6: HYDROPONICS
.eval ROOM_NAMES.add("HYDROPONICS")
.eval ROOM_MAPS.add(List().add(
    "WWWWWWWWWWWWWWWWWWWWHWWWWWWWWWWWWWWWWWWW",
    "W                   H                  W",
    "W                   H                  W",
    "W                   H                  W",
    "W                   H                  W",
    "W                   H                  W",
    "W      1223     b   H   321            W",
    "W     ======h=======h=======h=====     W",
    "W           H       H       H          W",
    "W           H       H       H          W",
    "W           H       H       H          W",
    "W           H       H       H          W",
    "W           H       H       H          W",
    "W 12  3     H       H       H    213b  W",
    "W=========h=====    H    =====h========W",
    "W         H         H         H        W",
    "W         H         H         H        W",
    "W         H         H         H        W",
    "          H         H         H         ",
    "          H         H         H         ",
    "   2132   H    b    H   1231  H    2    ",
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW").lock())

// 7: ENGINE ROOM
.eval ROOM_NAMES.add("ENGINE ROOM")
.eval ROOM_MAPS.add(List().add(
    "WWWWHWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
    "W   H -------------------------------- W",
    "W   H                                  W",
    "W   H                                  W",
    "W   H                                  W",
    "W   H                                  W",
    "W   H               12    b   3        W",
    "W   H          ===h=================== W",
    "W   H             H                    W",
    "W   H             H                    W",
    "W   H             H                    W",
    "W   H             H                    W",
    "W   H             H                    W",
    "W R H   21  1     H                    W",
    "W===============h====                  W",
    "W               H       PP             W",
    "W               H       PP             W",
    "W               H       PP             W",
    "                H       PP             W",
    "                H       PP             W",
    "      2   b     H  13   PP    CC   2   W",
    "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW").lock())
.eval ROOM_NAMES.lock()
.eval ROOM_MAPS.lock()

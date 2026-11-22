; Game Boy hardware registers used by Out of Coffee (DMG)

DEF rP1    EQU $FF00   ; joypad
DEF rIF    EQU $FF0F   ; interrupt flags
DEF rNR52  EQU $FF26   ; sound on/off
DEF rLCDC  EQU $FF40   ; LCD control
DEF rSTAT  EQU $FF41
DEF rSCY   EQU $FF42
DEF rSCX   EQU $FF43
DEF rLY    EQU $FF44   ; current scanline
DEF rLYC   EQU $FF45   ; scanline compare (STAT interrupt)
DEF rDMA   EQU $FF46   ; OAM DMA start
DEF rBGP   EQU $FF47   ; background palette
DEF rOBP0  EQU $FF48   ; sprite palette 0
DEF rOBP1  EQU $FF49   ; sprite palette 1
DEF rWY    EQU $FF4A   ; window y
DEF rWX    EQU $FF4B   ; window x + 7
DEF rIE    EQU $FFFF   ; interrupt enable

; LCD on, window map $9C00, window on, tiles at $8000, BG map $9800,
; 8x16 sprites, sprites on, BG on
DEF LCDC_GAME EQU %11110111

; hKeys bits (1 = held)
DEF PADB_A      EQU 0
DEF PADB_B      EQU 1
DEF PADB_SELECT EQU 2
DEF PADB_START  EQU 3
DEF PADB_RIGHT  EQU 4
DEF PADB_LEFT   EQU 5
DEF PADB_UP     EQU 6
DEF PADB_DOWN   EQU 7

; OUT OF COFFEE - a Waste of Space adventure for the Game Boy
; Step 1: walk John around the ship, room by room.
; Step 2: the crew, and text boxes (face someone, press A).

INCLUDE "hw.inc"
INCLUDE "gen/gfx.asm"
INCLUDE "gen/rooms.asm"
INCLUDE "gen/things.asm"

DEF START_ROOM EQU ROOM_CORRIDOR

DEF DIR_DOWN  EQU 0
DEF DIR_UP    EQU 1
DEF DIR_LEFT  EQU 2
DEF DIR_RIGHT EQU 3

DEF LINK_N EQU 0
DEF LINK_S EQU 1
DEF LINK_W EQU 2
DEF LINK_E EQU 3

; John is 16x16; x 0..144, y 0..112 keeps him inside the 160x128 room.
DEF MAX_X EQU 144
DEF MAX_Y EQU 112
; His feet are the box that collides: x+3..x+12, y+9..y+15
DEF FEET_L EQU 3
DEF FEET_W EQU 9     ; right edge = left + 9
DEF FEET_T EQU 9
DEF FEET_H EQU 6     ; bottom edge = top + 6
; TryMove's blocked mask: corners shifted in TL, TR, BL, BR
DEF MASK_LEFT   EQU %1010
DEF MASK_RIGHT  EQU %0101
DEF MASK_TOP    EQU %1100
DEF MASK_BOTTOM EQU %0011

; Window: HUD at line 128; the text box slides up to line 104 (5 rows)
DEF HUD_WY  EQU 128
DEF BOX_WY  EQU 104
DEF HIDE_WY EQU 144
DEF BOX_ROW1 EQU $9C21      ; window row 1, column 1
DEF BOX_ROW2 EQU $9C61      ; window row 3, column 1
DEF BOX_MORE EQU $9C92      ; window row 4, column 18: blinking arrow
DEF PHASE_OPEN  EQU 0
DEF PHASE_TYPE  EQU 1
DEF PHASE_WAIT  EQU 2
DEF PHASE_CLOSE EQU 3


SECTION "VBlank IRQ", ROM0[$40]
    jp VBlankHandler

SECTION "STAT IRQ", ROM0[$48]
    jp StatHandler


SECTION "Header", ROM0[$100]
    nop
    jp Start
    ds $150 - @, 0          ; rgbfix fills in the header


SECTION "Main", ROM0

Start:
    di
    ld sp, $E000
.waitVB:                    ; the LCD may only be turned off in VBlank
    ldh a, [rLY]
    cp 144
    jr c, .waitVB
    xor a
    ldh [rLCDC], a
    ldh [rNR52], a          ; sound off until there is music

    ld hl, $C000            ; clear WRAM
    ld bc, $2000
.clrW:
    xor a
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .clrW

    ld hl, $FF80            ; clear HRAM
    ld c, $7F
.clrH:
    xor a
    ld [hli], a
    dec c
    jr nz, .clrH

    ld hl, DMARoutineROM    ; OAM DMA routine has to run from HRAM
    ld de, hOAMDMA
    ld bc, hOAMDMA.end - hOAMDMA
    call Memcpy

    ld hl, AllTiles
    ld de, $8000
    ld bc, AllTilesEnd - AllTiles
    call Memcpy

    ld hl, $FE00            ; clear OAM
    ld bc, 160
    xor a
    call Memset

    ld hl, $9C00            ; HUD: divider line on the window's top row
    ld bc, 20
    ld a, TILE_HUDLINE
    call Memset

    ld a, %11100100         ; BG: 0 white, 1 light, 2 dark, 3 black
    ldh [rBGP], a
    ld a, %11100000         ; sprites: 1 white, 2 dark, 3 black
    ldh [rOBP0], a
    ldh [rOBP1], a
    ld a, HUD_WY            ; HUD = window over the bottom 16 lines
    ldh [hWY], a
    ldh [rWY], a
    ld a, HUD_WY - 1        ; sprites off from the window down (StatHandler)
    ldh [rLYC], a
    ld a, %01000000         ; STAT interrupt on LY = LYC
    ldh [rSTAT], a
    ld a, 7
    ldh [rWX], a
    xor a
    ldh [rSCX], a
    ldh [rSCY], a

    ld a, 72
    ld [wX], a
    ld a, 64
    ld [wY], a
    ld a, DIR_DOWN
    ld [wDir], a
    ld a, START_ROOM
    call LoadRoom           ; also turns the LCD on

    ld a, %00000011         ; VBlank + STAT interrupts
    ldh [rIE], a
    xor a
    ldh [rIF], a
    ei

MainLoop:
    halt
    ldh a, [hVBlank]
    and a
    jr z, MainLoop
    xor a
    ldh [hVBlank], a

    call ReadPad
    ld a, [wTalking]
    and a
    jr nz, .talking
    call UpdateJohn
    call CheckTalk
    jr .draw
.talking:
    call UpdateTalk
.draw:
    call DrawJohn
    jr MainLoop


VBlankHandler:
    push af
    ld a, HIGH(wShadowOAM)
    call hOAMDMA
    ldh a, [hWY]            ; window position for the coming frame
    ldh [rWY], a
    dec a                   ; sprites switch off one line above it
    cp HIDE_WY - 1
    jr c, .lyc
    ld a, $FF               ; window hidden: never
.lyc:
    ldh [rLYC], a
    ldh a, [rLCDC]          ; sprites back on for the top of the screen
    or %00000010
    ldh [rLCDC], a
    ld a, 1
    ldh [hVBlank], a
    pop af
    reti


; Sprites off below the window line, so nobody walks over the HUD or text box
StatHandler:
    push af
    ldh a, [rLCDC]
    and %11111101
    ldh [rLCDC], a
    pop af
    reti


; ---------------------------------------------------------------- joypad
; hKeys = held, hNew = pressed this frame
; bits: 0 A, 1 B, 2 Select, 3 Start, 4 Right, 5 Left, 6 Up, 7 Down
ReadPad:
    ld a, $20               ; d-pad
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    ld b, a
    ld a, $10               ; buttons
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    or b
    ld b, a
    ldh a, [hKeys]
    cpl
    and b
    ldh [hNew], a
    ld a, b
    ldh [hKeys], a
    ld a, $30
    ldh [rP1], a
    ret


; ---------------------------------------------------------------- rooms
; LoadRoom: a = room id. Turns the LCD off in VBlank, draws the room and
; its name in the HUD, turns the LCD back on.
LoadRoom:
    ld [wRoomId], a
    add a, a
    ld e, a
    ld d, 0
    ld hl, RoomTable
    add hl, de
    ld a, [hli]
    ld h, [hl]
    ld l, a

    ld de, wLinks           ; n, s, w, e
    ld bc, 4
    call Memcpy
    ld a, [hli]             ; name: length, then tiles
    ld [wNameLen], a
    ld a, l
    ld [wNamePtr], a
    ld a, h
    ld [wNamePtr + 1], a
    ld a, [wNameLen]
    ld e, a
    ld d, 0
    add hl, de
    ld de, wRoom            ; map: 20x16 tiles
    ld bc, 20 * 16
    call Memcpy

    ldh a, [rLCDC]
    bit 7, a
    jr z, .lcdIsOff
.waitVB:
    ldh a, [rLY]
    cp 144
    jr c, .waitVB
    xor a
    ldh [rLCDC], a
.lcdIsOff:

    ld hl, wRoom            ; room -> BG map (32 tiles a row)
    ld de, $9800
    ld b, 16
.row:
    ld c, 20
.col:
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .col
    ld a, e
    add 32 - 20
    ld e, a
    jr nc, .noCarry
    inc d
.noCarry:
    dec b
    jr nz, .row

    call DrawHudName
    call SetupThings

    ld a, LCDC_GAME
    ldh [rLCDC], a
    ret


; SolidAt: d = x, e = y (pixels in the room). Carry set if the tile there
; is solid. Keeps bc, de.
SolidAt:
    push de
    srl d
    srl d
    srl d
    srl e
    srl e
    srl e
    call RoomCell
    ld a, [hl]
    pop de
    cp FIRST_SOLID
    ccf
    ret

; RoomCell: d = column, e = row -> hl = that cell in wRoom. Keeps bc, de.
RoomCell:
    push bc
    ld l, e
    ld h, 0
    add hl, hl
    add hl, hl
    ld b, h
    ld c, l
    add hl, hl
    add hl, hl
    add hl, bc              ; row * 20
    ld c, d
    ld b, 0
    add hl, bc
    ld bc, wRoom
    add hl, bc
    pop bc
    ret

; DrawHudName: HUD row 2 = the room's name, centred. Safe with the LCD on.
DrawHudName:
    ld hl, $9C20
    ld b, 20
    ld a, TILE_SPACE
    call VramFill
    ld a, [wNameLen]
    ld b, a
    ld a, 20
    sub b
    srl a
    add LOW($9C20)
    ld l, a
    ld h, HIGH($9C20)
    ld a, [wNamePtr]
    ld e, a
    ld a, [wNamePtr + 1]
    ld d, a
    ld a, [wNameLen]
    ld b, a
    jp VramCopy


; ---------------------------------------------------------------- things
; SetupThings: after a room loads - people become sprites (OAM 2+) and every
; thing's tiles become solid in wRoom.
SetupThings:
    ld hl, wShadowOAM + 8
    ld bc, 160 - 8
    xor a
    call Memset
    ld a, LOW(wShadowOAM + 8)
    ld [wOamPtr], a
    ld a, HIGH(wShadowOAM + 8)
    ld [wOamPtr + 1], a

    ld a, [wRoomId]
    add a, a
    ld e, a
    ld d, 0
    ld hl, RoomThings
    add hl, de
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld a, [hli]
    ld [wThingCount], a
    ld a, l
    ld [wThingPtr], a
    ld a, h
    ld [wThingPtr + 1], a
    ld a, [wThingCount]
    and a
    ret z
    ld b, a
.thing:
    push bc
    ld a, [hli]
    ld [wTX], a
    ld a, [hli]
    ld [wTY], a
    ld a, [hli]
    ld [wTW], a
    ld a, [hli]
    ld [wTH], a
    ld a, [hli]
    ld [wTSpr], a
    inc hl                  ; talk pointer
    inc hl
    push hl
    call MarkThing
    call SpriteThing
    pop hl
    pop bc
    dec b
    jr nz, .thing
    ret

MarkThing:
    ld a, [wTH]
    ld c, a
    ld a, [wTY]
    ld e, a
.row:
    ld a, [wTX]
    ld d, a
    call RoomCell
    ld a, [wTW]
    ld b, a
.col:
    ld [hl], FIRST_SOLID
    inc hl
    dec b
    jr nz, .col
    inc e
    dec c
    jr nz, .row
    ret

SpriteThing:
    ld a, [wTSpr]
    cp $FF
    ret z
    ld c, a
    ld a, [wOamPtr]
    ld l, a
    ld a, [wOamPtr + 1]
    ld h, a
    ld a, [wTY]
    add a, a
    add a, a
    add a, a
    add 16
    ld d, a
    ld a, [wTX]
    add a, a
    add a, a
    add a, a
    add 8
    ld e, a
    ld a, d
    ld [hli], a
    ld a, e
    ld [hli], a
    ld a, c
    ld [hli], a
    xor a
    ld [hli], a
    ld a, d
    ld [hli], a
    ld a, e
    add 8
    ld [hli], a
    ld a, c
    add 2
    ld [hli], a
    xor a
    ld [hli], a
    ld a, l
    ld [wOamPtr], a
    ld a, h
    ld [wOamPtr + 1], a
    ret

; CheckTalk: A pressed -> is there a thing just in front of John's feet?
CheckTalk:
    ldh a, [hNew]
    bit PADB_A, a
    ret z
    ld a, [wDir]
    cp DIR_UP
    jr z, .up
    cp DIR_LEFT
    jr z, .left
    cp DIR_RIGHT
    jr z, .right
    ld a, [wX]              ; down
    add 8
    ld d, a
    ld a, [wY]
    add FEET_T + FEET_H + 4
    ld e, a
    jr .probe
.up:
    ld a, [wX]
    add 8
    ld d, a
    ld a, [wY]
    add FEET_T - 4
    ld e, a
    jr .probe
.left:
    ld a, [wX]
    add FEET_L - 4
    ld d, a
    ld a, [wY]
    add 12
    ld e, a
    jr .probe
.right:
    ld a, [wX]
    add FEET_L + FEET_W + 4
    ld d, a
    ld a, [wY]
    add 12
    ld e, a
.probe:
    ld a, [wThingCount]
    and a
    ret z
    ld b, a
    ld a, [wThingPtr]
    ld l, a
    ld a, [wThingPtr + 1]
    ld h, a
.loop:
    push bc
    push hl
    ld a, [hli]             ; left = tx * 8
    add a, a
    add a, a
    add a, a
    ld c, a
    ld a, [hli]             ; top = ty * 8
    add a, a
    add a, a
    add a, a
    ld b, a
    ld a, d
    sub c
    jr c, .miss
    ld c, a                 ; c = d - left
    ld a, [hli]             ; width in pixels
    add a, a
    add a, a
    add a, a
    cp c
    jr c, .miss
    jr z, .miss
    ld a, e
    sub b
    jr c, .miss
    ld b, a                 ; b = e - top
    ld a, [hli]             ; height in pixels
    add a, a
    add a, a
    add a, a
    cp b
    jr c, .miss
    jr z, .miss
    inc hl                  ; sprite
    ld a, [hli]
    ld h, [hl]
    ld l, a
    pop bc                  ; (saved hl)
    pop bc
    jp StartTalk
.miss:
    pop hl
    ld bc, THING_SIZE
    add hl, bc
    pop bc
    dec b
    jr nz, .loop
    ret


; ---------------------------------------------------------------- text box
; StartTalk: hl = talk data (page count, then pages of 2 x BOX_W tiles)
StartTalk:
    ld a, [hli]
    ld [wPagesLeft], a
    ld a, l
    ld [wPagePtr], a
    ld a, h
    ld [wPagePtr + 1], a
    ld a, 1
    ld [wTalking], a
    xor a
    ld [wMoving], a
    ld a, PHASE_OPEN
    ld [wPhase], a
    ld a, HIDE_WY
    ldh [hWY], a
    jp ClearBox

; ClearBox: window rows 1-4 to spaces (row 0 is the line on top)
ClearBox:
    ld hl, $9C20
    ld c, 4
.row:
    ld b, 20
    ld a, TILE_SPACE
    call VramFill
    ld a, l
    add 32 - 20
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry:
    dec c
    jr nz, .row
    ret

UpdateTalk:
    ld a, [wPhase]
    cp PHASE_OPEN
    jr z, .open
    cp PHASE_TYPE
    jr z, .type
    cp PHASE_WAIT
    jr z, .wait
    ldh a, [hWY]            ; closing: slide down
    add 4
    ldh [hWY], a
    cp HIDE_WY
    ret c
    call DrawHudName
    ld a, HUD_WY
    ldh [hWY], a
    xor a
    ld [wTalking], a
    ret
.open:                      ; slide up
    ldh a, [hWY]
    sub 4
    ldh [hWY], a
    cp BOX_WY
    ret nz
    ld a, PHASE_TYPE
    ld [wPhase], a
    xor a
    ld [wTypePos], a
    ret
.type:                      ; one letter a frame; A shows the rest at once
    ldh a, [hNew]
    bit PADB_A, a
    jp z, TypeOne
.rest:
    call TypeOne
    ld a, [wPhase]
    cp PHASE_TYPE
    jr z, .rest
    ret
.wait:
    ld hl, wBlink
    inc [hl]
    ld a, [hl]
    and 15
    jr nz, .noBlink
    ld a, [hl]
    and 16
    ld a, TILE_ARROW
    jr z, .show
    ld a, TILE_SPACE
.show:
    ld hl, BOX_MORE
    ld b, 1
    call VramFill
.noBlink:
    ldh a, [hNew]
    bit PADB_A, a
    ret z
    ld hl, wPagesLeft
    dec [hl]
    jr z, .close
    ld a, [wPagePtr]        ; next page
    add PAGE_LEN
    ld [wPagePtr], a
    ld a, [wPagePtr + 1]
    adc 0
    ld [wPagePtr + 1], a
    call ClearBox
    ld a, PHASE_TYPE
    ld [wPhase], a
    xor a
    ld [wTypePos], a
    ret
.close:
    ld a, PHASE_CLOSE
    ld [wPhase], a
    ret

; TypeOne: put the next letter of the page in the box
TypeOne:
    ld a, [wTypePos]
    ld c, a
    ld a, [wPagePtr]
    add c
    ld e, a
    ld a, [wPagePtr + 1]
    adc 0
    ld d, a
    ld a, c
    cp BOX_W
    jr nc, .line2
    add LOW(BOX_ROW1)
    ld l, a
    ld h, HIGH(BOX_ROW1)
    jr .put
.line2:
    sub BOX_W
    add LOW(BOX_ROW2)
    ld l, a
    ld h, HIGH(BOX_ROW2)
.put:
    ld b, 1
    call VramCopy
    inc c
    ld a, c
    ld [wTypePos], a
    cp PAGE_LEN
    ret nz
    ld a, PHASE_WAIT
    ld [wPhase], a
    ld a, 15                ; arrow shows on the next frame
    ld [wBlink], a
    ret


; ---------------------------------------------------------------- John
UpdateJohn:
    xor a
    ld [wMoving], a
    ldh a, [hKeys]
    bit PADB_UP, a
    jr z, .notUp
    call GoUp
    jr .horiz
.notUp:
    ldh a, [hKeys]
    bit PADB_DOWN, a
    call nz, GoDown
.horiz:
    ldh a, [hKeys]
    bit PADB_LEFT, a
    jr z, .notLeft
    call GoLeft
    jr .anim
.notLeft:
    ldh a, [hKeys]
    bit PADB_RIGHT, a
    call nz, GoRight
.anim:
    ld a, [wMoving]
    and a
    ret z
    ld hl, wAnim
    inc [hl]
    ret

GoUp:
    ld a, DIR_UP
    call Walking
    ld a, [wY]
    and a
    jr nz, .walk
    ld a, [wLinks + LINK_N]
    cp $FF
    ret z
    ld b, a
    ld a, MAX_Y
    ld [wY], a
    ld a, b
    jp LoadRoom
.walk:
    ld bc, $00FF            ; dx 0, dy -1
    call TryMove
    jp AssistV

GoDown:
    ld a, DIR_DOWN
    call Walking
    ld a, [wY]
    cp MAX_Y
    jr c, .walk
    ld a, [wLinks + LINK_S]
    cp $FF
    ret z
    ld b, a
    xor a
    ld [wY], a
    ld a, b
    jp LoadRoom
.walk:
    ld bc, $0001            ; dx 0, dy +1
    call TryMove
    jp AssistV

GoLeft:
    ld a, DIR_LEFT
    call Walking
    ld a, [wX]
    and a
    jr nz, .walk
    ld a, [wLinks + LINK_W]
    cp $FF
    ret z
    ld b, a
    ld a, MAX_X
    ld [wX], a
    ld a, b
    jp LoadRoom
.walk:
    ld bc, $FF00            ; dx -1, dy 0
    call TryMove
    jp AssistH

GoRight:
    ld a, DIR_RIGHT
    call Walking
    ld a, [wX]
    cp MAX_X
    jr c, .walk
    ld a, [wLinks + LINK_E]
    cp $FF
    ret z
    ld b, a
    xor a
    ld [wX], a
    ld a, b
    jp LoadRoom
.walk:
    ld bc, $0100            ; dx +1, dy 0
    call TryMove
    jp AssistH

Walking:
    ld [wDir], a
    ld a, 1
    ld [wMoving], a
    ret

; TryMove: b = dx, c = dy (signed). Moves John if his feet fit.
; Out: a = blocked corners (0 = moved).
TryMove:
    ld a, [wX]
    add b
    ld [wNX], a
    cp MAX_X + 1
    jr nc, .outside
    ld a, [wY]
    add c
    ld [wNY], a
    cp MAX_Y + 1
    jr nc, .outside

    xor a
    ld [wMask], a
    ld a, [wNX]
    add FEET_L
    ld d, a
    ld a, [wNY]
    add FEET_T
    ld e, a
    call SolidAt            ; top left
    call .addBit
    ld a, d
    add FEET_W
    ld d, a
    call SolidAt            ; top right
    call .addBit
    ld a, d
    sub FEET_W
    ld d, a
    ld a, e
    add FEET_H
    ld e, a
    call SolidAt            ; bottom left
    call .addBit
    ld a, d
    add FEET_W
    ld d, a
    call SolidAt            ; bottom right
    call .addBit

    ld a, [wMask]
    and a
    ret nz
    ld a, [wNX]
    ld [wX], a
    ld a, [wNY]
    ld [wY], a
    xor a
    ret
.outside:
    ld a, $0F
    and a
    ret
.addBit:                    ; shift carry into the mask
    ld a, [wMask]
    rla
    ld [wMask], a
    ret

; Corner help: walking up/down with only one side of the feet caught,
; slide sideways round the corner (so doorways are easy to hit).
AssistV:
    and a
    ret z
    ld b, a
    and MASK_LEFT
    jr z, .slideLeft
    ld a, b
    and MASK_RIGHT
    ret nz
    ld bc, $0100
    jp TryMove
.slideLeft:
    ld bc, $FF00
    jp TryMove

AssistH:
    and a
    ret z
    ld b, a
    and MASK_TOP
    jr z, .slideUp
    ld a, b
    and MASK_BOTTOM
    ret nz
    ld bc, $0001
    jp TryMove
.slideUp:
    ld bc, $00FF
    jp TryMove

; DrawJohn: two 8x16 sprites into shadow OAM 0-1
DrawJohn:
    ld a, [wDir]
    ld b, a
    cp DIR_LEFT
    jr c, .upDown
    ld a, 2                 ; side frames
.upDown:
    add a, a                ; frame = pose * 2 (+1 every 8 frames walking)
    ld c, a
    ld a, [wMoving]
    and a
    jr z, .still
    ld a, [wAnim]
    srl a
    srl a
    srl a
    and 1
    add c
    ld c, a
.still:
    ld a, c
    add a, a
    add a, a
    add SPR_JOHN_DOWN0
    ld c, a                 ; c = left half tile, c+2 = right half

    ld hl, wShadowOAM
    ld a, [wY]
    add 16
    ld d, a
    ld a, [wX]
    add 8
    ld e, a
    ld a, b
    cp DIR_LEFT
    jr z, .flipped

    ld a, d
    ld [hli], a
    ld a, e
    ld [hli], a
    ld a, c
    ld [hli], a
    xor a
    ld [hli], a
    ld a, d
    ld [hli], a
    ld a, e
    add 8
    ld [hli], a
    ld a, c
    add 2
    ld [hli], a
    xor a
    ld [hli], a
    ret
.flipped:                   ; mirror: halves swap sides
    ld a, d
    ld [hli], a
    ld a, e
    ld [hli], a
    ld a, c
    add 2
    ld [hli], a
    ld a, $20
    ld [hli], a
    ld a, d
    ld [hli], a
    ld a, e
    add 8
    ld [hli], a
    ld a, c
    ld [hli], a
    ld a, $20
    ld [hli], a
    ret


; ---------------------------------------------------------------- helpers
; VramFill: hl = dest, b = count, a = value. Waits for VRAM each byte (LCD on is fine).
VramFill:
    ld d, a
.loop:
    ldh a, [rSTAT]
    and %10
    jr nz, .loop
    ld [hl], d
    inc hl
    dec b
    jr nz, .loop
    ret

; VramCopy: de = source, hl = dest, b = count. Waits for VRAM each byte. Keeps c.
VramCopy:
    ldh a, [rSTAT]
    and %10
    jr nz, VramCopy
    ld a, [de]
    ld [hli], a
    inc de
    dec b
    jr nz, VramCopy
    ret

; Memcpy: hl = source, de = dest, bc = count (> 0)
Memcpy:
    ld a, [hli]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, Memcpy
    ret

; Memset: hl = dest, bc = count (> 0), a = value
Memset:
    ld d, a
.loop:
    ld a, d
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .loop
    ret


SECTION "OAM DMA routine", ROM0
DMARoutineROM:
LOAD "OAM DMA", HRAM
hOAMDMA:                    ; a = high byte of the source
    ldh [rDMA], a
    ld a, 40
.wait:
    dec a
    jr nz, .wait
    ret
.end:
ENDL


SECTION "Shadow OAM", WRAM0, ALIGN[8]
wShadowOAM: ds 160

SECTION "Game vars", WRAM0
wRoom:    ds 20 * 16        ; current room's tiles (collision)
wLinks:   ds 4
wRoomId:  ds 1
wNameLen: ds 1
wNamePtr: ds 2
wX:       ds 1
wY:       ds 1
wNX:      ds 1
wNY:      ds 1
wMask:    ds 1
wDir:     ds 1
wMoving:  ds 1
wAnim:    ds 1
wThingCount: ds 1
wThingPtr:   ds 2
wOamPtr:     ds 2
wTX:      ds 1
wTY:      ds 1
wTW:      ds 1
wTH:      ds 1
wTSpr:    ds 1
wTalking: ds 1
wPhase:   ds 1
wPagesLeft: ds 1
wPagePtr: ds 2
wTypePos: ds 1
wBlink:   ds 1

SECTION "HRAM vars", HRAM
hKeys:   ds 1
hNew:    ds 1
hVBlank: ds 1
hWY:     ds 1

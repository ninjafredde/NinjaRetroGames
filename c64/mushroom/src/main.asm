// Mushroom for Improvement - a Waste of Space game for the C64
// KickAssembler. Joystick in port 2.
//
// Something is growing aboard the mothership Dilettante. Lt John Johnson
// clears it room by room with a can of weedkiller spray. Mushrooms grow
// green -> purple -> red; red (ripe) ones spread to the next spot on the
// floor and now and then pop and hatch a bug. Clear every room to win.
//
// Test builds:  -define SKIPTITLE  start without waiting for fire
//               -define JOYTEST    a scripted joystick (with SKIPTITLE)

.encoding "screencode_upper"

#import "rooms.asm"
#import "gfx.asm"

.const SCREEN   = $0400
.const COLRAM   = $d800
.const SPRPTR   = SCREEN + $3f8
.const SPRITES  = $2000
.const CHARSET  = $3800
.const ROOMRAM  = $a000         // working copies of the rooms (RAM under BASIC)
.const ROOM_W   = 40
.const ROOM_H   = 22
.const ROOM_SIZE = ROOM_W*ROOM_H
.const NROOMS   = 8
.const TOP      = 3             // screen row of room row 0 (rows 0-2: status)
.const FY_MAX   = ROOM_H*8
.const MAXBUGS  = 4
.const CAN_MAX  = 100
.const SPR_Y    = 53            // sprite y = feet y + this

// How fast the infestation grows. Each frame GROW_LOOKS random cells of
// John's room are looked at (each cell about every 5 seconds) and one cell
// of a random room (rooms you're not in creep along slowly).
// When a cell is looked at, "1 in mask+1" chances:
//   GROW_MASK 3: a mushroom grows a stage   (~20 s a stage, green to red ~40 s)
//   SEED_MASK 3: an empty spot next to a red one gets a new one (~20 s)
//   POP_MASK  7: a red one hatches a bug and goes back to green (~40 s)
.const GROW_LOOKS = 8
.const GROW_MASK = 3
.const POP_MASK  = 7
.const SEED_MASK = 3

// screen codes of the room characters (64 on; 0-63 are the ROM letters)
.const T_EMPTY = 32
.const T_WALL  = 64
.const T_PLAT  = 65
.const T_LAD   = 66
.const T_LADP  = 67
.const T_M1    = 68
.const T_M2    = 69
.const T_M3    = 70
.const T_TANK  = 71
.const T_WIN   = 72
.const T_CON   = 73
.const T_PIPV  = 74
.const T_PIPH  = 75
.const T_KTOP  = 76
.const T_KBOT  = 77
.const T_LOO   = 78
.const T_BOX   = 79
.const CH_MAP  = 81             // status bar: hi-res blocks
.const CH_FULL = 82
.const CH_EMPTY = 83
.const CH_HALF = 84

// what a tile is
.const P_TOP    = 1             // stand on it
.const P_WALL   = 2             // blocks walking and heads
.const P_LAD    = 4
.const P_MUSH   = 8
.const P_TANK   = 16

// colours
.const COL_MC1   = 11           // characters "1": dark grey
.const COL_MC2   = 15           // characters "2": light grey
.const COL_SPR1  = 9            // sprites "1": brown
.const COL_SPR3  = 10           // sprites "3": pink
.const COL_JOHN  = 14
.const COL_PUFF  = 13
.const COL_BUG   = 8

// sprite frames
.const PTR0     = SPRITES/64
.const F_STAND  = 0
.const F_WALK1  = 1
.const F_WALK2  = 2
.const F_JUMP   = 3
.const F_SPRAY  = 4
.const F_LEFT   = 5             // + the frame above
.const F_CLIMB  = 10
.const F_BUG    = 12
.const F_SQUISH = 14
.const F_PUFF   = 15            // 15,16 right; 17,18 left
.const F_DEAD   = 19

// jump: pixels up each frame, then falling: pixels down each frame
.const JUMP_LEN = 13
.const FALL_LEN = 11

.label zp  = $fb                // pointers
.label zp2 = $fd
.label cp  = $06
.label t0  = $02
.label t1  = $03
.label t2  = $04
.label t3  = $05
.label t4  = $08
.label t5  = $09

.macro Print(dest, src, col) {
        ldx #0
!:      lda src,x
        beq !+
        sta dest,x
        lda #col
        sta dest + $d400,x
        inx
        bne !-
!:
}

// unsigned |A - mem|, after "sec / sbc mem"
.macro Abs() {
        bcs !+
        eor #$ff
        adc #1
!:
}

// ---------------------------------------------------------------- room data checks
.function tileOf(c) {
    .var t = Hashtable().put(" ",T_EMPTY,"W",T_WALL,"=",T_PLAT,"H",T_LAD,"h",T_LADP,
        "1",T_M1,"2",T_M2,"3",T_M3,"R",T_TANK,"O",T_WIN,"C",T_CON,"P",T_PIPV,"-",T_PIPH,
        "K",T_KTOP,"k",T_KBOT,"T",T_LOO,"B",T_BOX,"b",T_EMPTY,"S",T_EMPTY)
    .errorif !t.containsKey(c), "unknown room character: '" + c + "'"
    .return t.get(c)
}
.function marks(map, ch) {
    .var out = List()
    .for (var y=0; y<ROOM_H; y++)
        .for (var x=0; x<ROOM_W; x++)
            .if (map.get(y).substring(x, x+1) == ch) .eval out.add(List().add(x, y))
    .return out
}
.errorif ROOM_MAPS.size() != NROOMS, "need " + NROOMS + " rooms"
.var START_ROOM = -1
.var START_COL = 0
.var START_ROW = 0
.for (var r=0; r<NROOMS; r++) {
    .var m = ROOM_MAPS.get(r)
    .errorif m.size() != ROOM_H, "room " + r + " needs 22 rows"
    .for (var y=0; y<ROOM_H; y++)
        .errorif m.get(y).size() != ROOM_W, "room " + r + " row " + y + " is not 40 wide"
    .errorif marks(m, "b").size() < 1, "room " + r + " needs at least one b"
    .var s = marks(m, "S")
    .if (s.size() > 0) {
        .eval START_ROOM = r
        .eval START_COL = s.get(0).get(0)
        .eval START_ROW = s.get(0).get(1)
    }
}
.errorif START_ROOM < 0, "put an S in a room"

// ================================================================= sprites
* = SPRITES "Sprites"
        SpriteMC(SPR_STAND)             // 0
        SpriteMC(SPR_WALK1)
        SpriteMC(SPR_WALK2)
        SpriteMC(SPR_JUMP)
        SpriteMC(SPR_SPRAY)
        SpriteMC(flip(SPR_STAND))       // 5
        SpriteMC(flip(SPR_WALK1))
        SpriteMC(flip(SPR_WALK2))
        SpriteMC(flip(SPR_JUMP))
        SpriteMC(flip(SPR_SPRAY))
        SpriteMC(SPR_CLIMB)             // 10
        SpriteMC(flip(SPR_CLIMB))
        SpriteMC(SPR_BUG1)              // 12
        SpriteMC(SPR_BUG2)
        SpriteMC(SPR_SQUISH)
        SpriteMC(SPR_PUFF1)             // 15
        SpriteMC(SPR_PUFF2)
        SpriteMC(flip(SPR_PUFF1))
        SpriteMC(flip(SPR_PUFF2))
        SpriteMC(SPR_DEAD)              // 19

// ================================================================= characters
* = CHARSET + 64*8 "Characters"         // 0-63 are copied from the ROM at start
        CharMC(CH_WALL)                 // 64
        CharMC(CH_PLAT)
        CharMC(CH_LAD)
        CharMC(CH_LADP)
        CharMC(CH_M1)                   // 68
        CharMC(CH_M2)
        CharMC(CH_M3A)
        CharMC(CH_TANK)
        CharMC(CH_WIN)                  // 72
        CharMC(CH_CON)
        CharMC(CH_PIPV)
        CharMC(CH_PIPH)
        CharMC(CH_KTOP)                 // 76
        CharMC(CH_KBOT)
        CharMC(CH_LOO)
        CharMC(CH_BOX)
        CharMC(CH_SPARE)                // 80
        .byte $fe,$fe,$fe,$fe,$fe,$fe,$fe,$00   // 81 map block (hi-res)
        .byte $00,$fe,$fe,$fe,$fe,$fe,$fe,$00   // 82 bar full
        .byte $00,$00,$00,$00,$00,$00,$aa,$00   // 83 bar empty
        .byte $00,$f0,$f0,$f0,$f0,$f0,$f0,$00   // 84 bar half

// ================================================================= code
BasicUpstart2(start)

* = $4000 "Code"
start:
        sei
        lda #$36                        // BASIC ROM out: RAM at $a000-$bfff
        sta $01
        cli
        lda #0
        sta $d020
        sta $d021
        sta $d017
        sta $d01b
        sta $d01d
        lda #$ff
        sta $d01c                       // all sprites multicolour
        lda #COL_SPR1
        sta $d025
        lda #COL_SPR3
        sta $d026
        lda #COL_JOHN
        sta $d027
        lda #COL_PUFF
        sta $d028
        ldx #3
        lda #COL_BUG
!:      sta $d029,x
        dex
        bpl !-
        jsr copy_font
        lda #$1e                        // screen $0400, characters $3800
        sta $d018
        lda #$18                        // multicolour text
        sta $d016
        lda #COL_MC1
        sta $d022
        lda #COL_MC2
        sta $d023
        lda #1
        sta seed
        jsr sid_init

// ---------------------------------------------------------------- title
title:
        lda #0
        sta $d015
        jsr clear_screen
        Print(SCREEN + 3*40 + 8, txt_t1, 7)
        Print(SCREEN + 5*40 + 9, txt_t2, 3)
        Print(SCREEN + 8*40 + 6, txt_t3, 1)
        Print(SCREEN + 9*40 + 7, txt_t4, 1)
        Print(SCREEN + 11*40 + 3, txt_t5, 1)
        Print(SCREEN + 14*40 + 3, txt_t6, 5)
        Print(SCREEN + 15*40 + 3, txt_t7, 5)
        Print(SCREEN + 16*40 + 3, txt_t8, 5)
        Print(SCREEN + 18*40 + 3, txt_t9, 2)
        Print(SCREEN + 19*40 + 3, txt_t10, 2)
        Print(SCREEN + 22*40 + 15, txt_fire, 1)
        jsr music_start
#if !SKIPTITLE
        jsr wait_fire
#endif
        jsr music_stop

// ---------------------------------------------------------------- new game
new_game:
        jsr clear_screen
        jsr init_rooms
        lda #0
        sta score
        sta score+1
        sta score+2
        sta won
        sta pstate
        sta dir
        sta anim
        sta dead_t
        sta spraying
        sta spray_snd
        sta inv
        lda #3
        sta lives
        lda #CAN_MAX
        sta can
        lda #START_ROOM
        sta room
        lda #START_COL*4 + 2
        sta px
        lda #(START_ROW+1)*8
        sta fy
        jsr draw_hud
        jsr enter_room
        lda #1                          // get ready
        jsr music_begin

// ---------------------------------------------------------------- main loop
loop:
        jsr wait_frame
        jsr update_sprites
        jsr sfx_update
        jsr music_play
        jsr animate_chars
        inc frame
        lda dead_t
        beq alive
        dec dead_t
        bne lp_rest
        lda lives
        bne !+
        jmp game_over
!:      jsr respawn
        jmp lp_rest
alive:
        jsr read_joy
        jsr move_player
        jsr do_spray
        jsr refill
        lda inv
        beq lp_rest
        dec inv
lp_rest:
        jsr move_bugs
        jsr grow
        jsr hud_update
        lda won
        bne win_game
        jmp loop

game_over:
        jsr spray_off
        lda #0
        sta $d015
        Print(SCREEN + 11*40 + 13, txt_over1, 2)
        Print(SCREEN + 12*40 + 13, txt_over2, 2)
        Print(SCREEN + 13*40 + 13, txt_over1, 2)
        lda #2
        jsr music_begin
        jmp end_wait

win_game:
        jsr spray_off
        lda #0
        sta $d015
        Print(SCREEN + 10*40 + 4, txt_win0, 7)
        Print(SCREEN + 11*40 + 4, txt_win1, 7)
        Print(SCREEN + 12*40 + 4, txt_win2, 7)
        Print(SCREEN + 13*40 + 4, txt_win0, 7)
        lda #1
        jsr music_begin
end_wait:
        lda #200
        sta t3
!:      jsr wait_frame
        jsr music_play
        dec t3
        bne !-
        jsr wait_fire
        jmp title

// ---------------------------------------------------------------- setup
copy_font:                              // ROM letters -> screen codes 0-63
        sei
        lda #$33                        // character ROM in at $d000
        sta $01
        ldx #0
!:      lda $d000,x
        sta CHARSET,x
        lda $d100,x
        sta CHARSET+$100,x
        inx
        bne !-
        lda #$36
        sta $01
        cli
        rts

clear_screen:
        ldx #0
!:      lda #32
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #1
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne !-
        rts

// copy X pages from (zp) to (zp2)
copy_pages:
        ldy #0
!:      lda (zp),y
        sta (zp2),y
        iny
        bne !-
        inc zp+1
        inc zp2+1
        dex
        bne !-
        rts

// fresh rooms: copy them from the templates, count mushrooms, place bugs
init_rooms:
        lda #<room_tpl
        sta zp
        lda #>room_tpl
        sta zp+1
        lda #<ROOMRAM
        sta zp2
        lda #>ROOMRAM
        sta zp2+1
        ldx #(NROOMS*ROOM_SIZE+255)/256
        jsr copy_pages
        ldx #NROOMS-1
!:      jsr count_mush
        lda spawn_n,x
        sta room_bugs,x
        dex
        bpl !-
        rts

// X = room: count its mushrooms (keeps X)
count_mush:
        lda #0
        sta room_mush,x
        sta t0
cm_row: lda t0
        jsr row_ptr
        ldy #ROOM_W-1
cm_col: lda (zp),y
        stx t1
        tax
        lda props,x
        ldx t1
        and #P_MUSH
        beq !+
        inc room_mush,x
!:      dey
        bpl cm_col
        inc t0
        lda t0
        cmp #ROOM_H
        bne cm_row
        rts

// ---------------------------------------------------------------- rooms
// zp = start of row A of room X (keeps X)
row_ptr:
        tay
        lda room_lo,x
        clc
        adc row40_lo,y
        sta zp
        lda room_hi,x
        adc row40_hi,y
        sta zp+1
        rts

// A = row, Y = column of John's room -> A = tile (keeps Y)
get_cell:
        cmp #ROOM_H
        bcs gc_out
        cpy #ROOM_W
        bcs gc_out
        sty t5
        ldx room
        jsr row_ptr
        ldy t5
        lda (zp),y
        rts
gc_out: lda #T_EMPTY
        rts

// A = row, Y = column -> A = what the tile is (P_ bits)
props_at:
        jsr get_cell
        tax
        lda props,x
        rts

// A = row, Y = column, t4 = new tile: change it in John's room and on screen
set_cell:
        sta t3
        sty t5
        ldx room
        jsr row_ptr
        ldy t5
        lda t4
        sta (zp),y
        ldx t3
        lda scr_lo+TOP,x
        sta zp2
        lda scr_hi+TOP,x
        sta zp2+1
        lda t4
        sta (zp2),y
        lda zp2+1
        clc
        adc #$d4
        sta zp2+1
        ldx t4
        lda colour_of,x
        sta (zp2),y
        rts

draw_room:
        lda #0
        sta t0
dr_row: ldx room
        lda t0
        jsr row_ptr
        ldx t0
        lda scr_lo+TOP,x
        sta zp2
        sta cp
        lda scr_hi+TOP,x
        sta zp2+1
        clc
        adc #$d4
        sta cp+1
        ldy #ROOM_W-1
dr_col: lda (zp),y
        sta (zp2),y
        tax
        lda colour_of,x
        sta (cp),y
        dey
        bpl dr_col
        inc t0
        lda t0
        cmp #ROOM_H
        bne dr_row
        rts

// John has just come into the room
enter_room:
        lda px
        sta entry_px
        lda fy
        sta entry_fy
        lda pstate
        sta entry_ps
        lda #0
        sta spraying
        jsr draw_room
        jsr draw_room_name
        jsr spawn_room_bugs
        lda #50
        sta inv
        rts

go_right:
        ldx room
        lda room_right,x
        sta room
        lda #3
        sta px
        jmp enter_room
go_left:
        ldx room
        lda room_left,x
        sta room
        lda #156
        sta px
        jmp enter_room
go_up:
        ldx room
        lda room_up,x
        sta room
        lda #FY_MAX-1
        sta fy
        jmp enter_room
go_down:
        ldx room
        lda room_down,x
        sta room
        lda #21
        sta fy
        jmp enter_room

// ---------------------------------------------------------------- John
read_joy:
#if JOYTEST
        ldx js_i                        // test build: a joystick script
        lda js_bits,x
        sta joy
        dec js_n
        bne !+
        inx
        stx js_i
        lda js_len,x
        sta js_n
!:      rts
js_i:   .byte 0
js_n:   .byte 16
js_len: .byte 16, 70, 60, 40, 40, 200
js_bits: .byte 8, 1, 8, 16, 4, 0
#else
        lda $dc00
        eor #$ff
        and #$1f
        sta joy                         // 1 up, 2 down, 4 left, 8 right, 16 fire
        rts
#endif

col_y:  lda px
        lsr
        lsr
        tay
        rts

// A != 0 when John stands on something
feet_solid:
        lda fy
        and #7
        bne fs_no
        jsr col_y
        lda fy
        lsr
        lsr
        lsr
        jsr props_at
        and #P_TOP
        rts
fs_no:  lda #0
        rts

ladder_body:                            // a ladder where John's legs are
        jsr col_y
        lda fy
        sec
        sbc #1
        lsr
        lsr
        lsr
        jsr props_at
        and #P_LAD
        rts

ladder_under:                           // a ladder under John's feet
        jsr col_y
        lda fy
        lsr
        lsr
        lsr
        jsr props_at
        and #P_LAD
        rts

// Y = column: A != 0 if a wall is in that column at John's body height
wall_rows:
        sty t2
        lda fy
        sec
        sbc #1
        lsr
        lsr
        lsr
        jsr props_at
        and #P_WALL
        bne wr_out
        lda fy
        sec
        sbc #9
        bcc wr_none
        lsr
        lsr
        lsr
        ldy t2
        jsr props_at
        and #P_WALL
        bne wr_out
        lda fy
        sec
        sbc #17
        bcc wr_none
        lsr
        lsr
        lsr
        ldy t2
        jsr props_at
        and #P_WALL
        bne wr_out
wr_none: lda #0
wr_out: sta t3
        ldy t2
        lda t3
        rts

step_right:
        lda px
        cmp #157
        bcc sr_in
        ldx room
        lda room_right,x
        bmi sr_x
        jmp go_right
sr_in:  clc
        adc #3
        lsr
        lsr
        tay
        jsr wall_rows
        bne sr_x
        inc px
sr_x:   rts

step_left:
        lda px
        cmp #3
        bcs sl_in
        ldx room
        lda room_left,x
        bmi sl_x
        jmp go_left
sl_in:  sec
        sbc #3
        lsr
        lsr
        tay
        jsr wall_rows
        bne sl_x
        dec px
sl_x:   rts

start_climb:
        lda px
        and #$fc
        ora #2
        sta px
        lda #2
        sta pstate
        lda #0
        sta spraying
        rts

start_fall:
        lda #1
        sta pstate
        lda #JUMP_LEN
        sta air_t
        lda #0
        sta fall_t
        sta hdx
        rts

move_player:
        lda pstate
        cmp #2
        bne !+
        jmp climb
!:      cmp #1
        bne ground
        jmp air

ground:
        lda #0
        sta spraying
        jsr feet_solid
        bne !+
        jmp start_fall
!:      lda joy
        and #$10
        beq g_nofire
        lda can
        beq g_nofire
        lda #1                          // spraying: stand still, may turn
        sta spraying
        lda joy
        and #$04
        beq !+
        lda #1
        sta dir
!:      lda joy
        and #$08
        beq !+
        lda #0
        sta dir
!:      rts
g_nofire:
        lda joy
        and #$01
        beq g_noup
        jsr ladder_body
        beq g_jump
        jmp start_climb
g_jump: lda #0
        sta hdx
        lda joy
        and #$04
        beq !+
        lda #$ff
        sta hdx
        lda #1
        sta dir
!:      lda joy
        and #$08
        beq !+
        lda #1
        sta hdx
        lda #0
        sta dir
!:      lda #1
        sta pstate
        lda #0
        sta air_t
        sta fall_t
        jmp sfx_jump
g_noup: lda joy
        and #$02
        beq g_nodown
        jsr ladder_under
        beq g_nodown
        jmp start_climb
g_nodown:
        lda joy
        and #$04
        beq !+
        lda #1
        sta dir
        inc anim
        jmp step_left
!:      lda joy
        and #$08
        beq !+
        lda #0
        sta dir
        inc anim
        jmp step_right
!:      lda #0
        sta anim
        rts

air:
        lda hdx
        beq a_vert
        bmi a_left
        jsr step_right
        jmp a_vert
a_left: jsr step_left
a_vert: ldx air_t
        cpx #JUMP_LEN
        bcs a_fall
        inc air_t
        lda jump_tab,x
        beq a_done
        sta t4
a_up:   lda fy
        cmp #22
        bcc a_peak
        jsr col_y
        lda fy
        sec
        sbc #22
        lsr
        lsr
        lsr
        jsr props_at
        and #P_WALL
        bne a_peak
        dec fy
        dec t4
        bne a_up
a_done: rts
a_peak: lda #JUMP_LEN
        sta air_t
        lda #0
        sta fall_t
        rts
a_fall: ldx fall_t
        cpx #FALL_LEN-1
        bcs !+
        inc fall_t
!:      lda fall_tab,x
        beq a_done
        sta t4
a_down: lda fy
        and #7
        bne a_move
        lda fy
        cmp #FY_MAX
        bcs a_land
        jsr col_y
        lda fy
        lsr
        lsr
        lsr
        jsr props_at
        and #P_TOP
        bne a_land
a_move: inc fy
        dec t4
        bne a_down
        rts
a_land: lda #0
        sta pstate
        sta anim
        rts

climb:
        lda joy
        and #$01
        beq c_noup
        lda fy
        cmp #21
        bcs c_up_in
        ldx room
        lda room_up,x
        bmi c_stop
        jmp go_up
c_up_in:
        jsr ladder_body
        beq c_top
        dec fy
        inc anim
        rts
c_top:  lda fy
        and #7
        bne c_stop
        lda #0
        sta pstate
        rts
c_noup: lda joy
        and #$02
        beq c_side
        lda fy
        cmp #FY_MAX
        bcc c_dn_in
        ldx room
        lda room_down,x
        bmi c_stop
        jmp go_down
c_dn_in:
        jsr col_y
        lda fy
        lsr
        lsr
        lsr
        jsr props_at
        sta t4
        and #P_LAD
        beq c_bottom
        inc fy
        inc anim
        rts
c_bottom:
        lda fy
        and #7
        bne c_fall
        lda t4
        and #P_TOP
        beq c_fall
        lda #0
        sta pstate
        rts
c_fall: jmp start_fall
c_side: lda joy
        and #$0c
        beq c_stop
        jsr feet_solid
        beq c_stop
        lda #0
        sta pstate
c_stop: rts

// ---------------------------------------------------------------- spray
do_spray:
        lda spraying
        bne ds_on
        jmp spray_off
ds_on:  lda spray_snd
        bne !+
        inc spray_snd
        jsr sfx_spray
!:      lda frame
        and #1
        bne !+
        lda can
        beq !+
        dec can
!:      lda frame
        and #7
        beq ds_hit
        rts
ds_hit: lda fy                          // the two rows by John's legs
        sec
        sbc #1
        lsr
        lsr
        lsr
        sta s_row
        lda #4
        sta s_k
ds_col: lda dir
        bne ds_l
        lda px
        clc
        adc s_k
        cmp #160
        bcs ds_next
        jmp ds_c
ds_l:   lda px
        sec
        sbc s_k
        bcc ds_next
ds_c:   lsr
        lsr
        sta s_col
        tay
        lda s_row
        jsr hit_cell
        lda s_row
        beq ds_next
        sec
        sbc #1
        ldy s_col
        jsr hit_cell
ds_next:
        lda s_k
        clc
        adc #4
        sta s_k
        cmp #16
        bcc ds_col
        ldx #MAXBUGS-1                  // and the bugs in the cloud
ds_bug: lda bst,x
        cmp #1
        bne ds_bn
        lda bfy,x
        sec
        sbc fy
        Abs()
        cmp #12
        bcs ds_bn
        lda dir
        bne ds_bl
        lda bx,x
        sec
        sbc px
        bcc ds_bn
        jmp ds_br
ds_bl:  lda px
        sec
        sbc bx,x
        bcc ds_bn
ds_br:  cmp #3
        bcc ds_bn
        cmp #17
        bcs ds_bn
        jsr kill_bug
ds_bn:  dex
        bpl ds_bug
        rts

spray_off:
        lda spray_snd
        beq !+
        lda #0
        sta spray_snd
        lda #$80
        sta $d412
!:      rts

// A = row, Y = column: spray that cell
hit_cell:
        sta h_row
        sty h_col
        jsr get_cell
        cmp #T_M1
        beq hc_kill
        cmp #T_M2
        beq hc_down
        cmp #T_M3
        beq hc_down
        rts
hc_down: sec
        sbc #1
        sta t4
        lda #$05
        jsr add_score
        jmp hc_put
hc_kill: lda #T_EMPTY
        sta t4
        ldx room
        dec room_mush,x
        lda #$10
        jsr add_score
        jsr sfx_pop
hc_put: lda h_row
        ldy h_col
        jmp set_cell

// X = bug
kill_bug:
        lda #20
        sta bst,x
        ldy room
        lda room_bugs,y
        beq !+
        sec
        sbc #1
        sta room_bugs,y
!:      lda #$50
        jsr add_score
        jmp sfx_squish

refill:
        lda pstate
        bne rf_x
        jsr col_y
        lda fy
        sec
        sbc #1
        lsr
        lsr
        lsr
        jsr props_at
        and #P_TANK
        beq rf_x
        lda can
        cmp #CAN_MAX
        bcs rf_x
        inc can
        lda frame
        and #3
        bne rf_x
        jmp sfx_refill
rf_x:   rts

kill_player:
        lda #80
        sta dead_t
        dec lives
        lda #0
        sta spraying
        jsr spray_off
        jmp sfx_die

respawn:
        lda entry_px
        sta px
        lda entry_fy
        sta fy
        lda entry_ps
        sta pstate
        lda #JUMP_LEN
        sta air_t
        lda #0
        sta fall_t
        sta hdx
        sta anim
        lda #100
        sta inv
        rts

// A = BCD points (up to 99)
add_score:
        sed
        clc
        adc score
        sta score
        lda score+1
        adc #0
        sta score+1
        lda score+2
        adc #0
        sta score+2
        cld
        rts

// ---------------------------------------------------------------- bugs
// A = column, Y = row the bug stands in. C set if all bug slots are used.
spawn_bug:
        sta t0
        sty t1
        ldx #MAXBUGS-1
!:      lda bst,x
        beq sb_found
        dex
        bpl !-
        sec
        rts
sb_found:
        lda t0
        asl
        asl
        ora #2
        sta bx,x
        lda t1
        clc
        adc #1
        asl
        asl
        asl
        sta bfy,x
        jsr rnd
        and #1
        sta bdir,x
        lda #1
        sta bst,x
        clc
        rts

spawn_room_bugs:
        ldx #MAXBUGS-1
        lda #0
!:      sta bst,x
        dex
        bpl !-
        ldx room
        lda room_bugs,x
        beq srb_x
        sta t2
        lda #0
        sta t3
srb_loop:
        lda room
        asl
        asl
        clc
        adc t3
        tay
        lda spawn_row,y
        pha
        lda spawn_col,y
        tax
        pla
        tay
        txa
        jsr spawn_bug
        inc t3
        ldx room
        lda t3
        cmp spawn_n,x
        bcc !+
        lda #0
        sta t3
!:      dec t2
        bne srb_loop
srb_x:  rts

move_bugs:
        ldx #MAXBUGS-1
mb_loop:
        stx bi
        lda bst,x
        bne !+
        jmp mb_next
!:      cmp #1
        beq mb_alive
        dec bst,x                       // squished: count down, then gone
        lda bst,x
        cmp #1
        bne !+
        lda #0
        sta bst,x
!:      jmp mb_next
mb_alive:
        inc banim,x
        lda dead_t
        bne mb_nochase
        lda inv
        bne mb_chase
        lda bx,x                        // touching John?
        sec
        sbc px
        Abs()
        cmp #4
        bcs mb_chase
        lda bfy,x
        sec
        sbc fy
        Abs()
        cmp #14
        bcs mb_chase
        jsr kill_player
        ldx bi
        jmp mb_nochase
mb_chase:
        lda pstate
        cmp #2
        beq mb_nochase
        lda bfy,x
        sec
        sbc fy
        Abs()
        cmp #10
        bcs mb_nochase
        lda #1
        sta chasing
        lda px
        cmp bx,x
        bcc !+
        lda #0
        sta bdir,x
        jmp mb_fast
!:      lda #1
        sta bdir,x
mb_fast:
        lda frame
        and #3
        beq mb_next
        jmp mb_move
mb_nochase:
        lda frame
        and #1
        bne mb_next
mb_move:
        lda bdir,x
        bne mb_l
        lda bx,x
        cmp #155
        bcs mb_turn
        clc
        adc #1
        sta b_new
        clc
        adc #2
        jmp mb_chk
mb_l:   lda bx,x
        cmp #5
        bcc mb_turn
        sec
        sbc #1
        sta b_new
        sec
        sbc #2
mb_chk: lsr
        lsr
        sta b_col
        lda bfy,x                       // floor ahead?
        lsr
        lsr
        lsr
        ldy b_col
        jsr props_at
        and #P_TOP
        beq mb_turnx
        ldx bi
        lda bfy,x                       // wall ahead?
        sec
        sbc #1
        lsr
        lsr
        lsr
        ldy b_col
        jsr props_at
        and #P_WALL
        bne mb_turnx
        ldx bi
        lda b_new
        sta bx,x
        jmp mb_next
mb_turnx:
        ldx bi
mb_turn:
        lda bdir,x
        eor #1
        sta bdir,x
mb_next:
        ldx bi
        dex
        bmi !+
        jmp mb_loop
!:      rts

// ---------------------------------------------------------------- the infestation
grow:
        lda #GROW_LOOKS
        sta g_n
!:      lda room
        jsr grow_one
        dec g_n
        bne !-
        jsr rnd
        and #NROOMS-1
        jmp grow_one

// A = room: look at one random cell of it
grow_one:
        sta g_room
        jsr rnd
        and #31
        cmp #ROOM_H
        bcs go_out
        sta g_row
        jsr rnd
        and #63
        cmp #ROOM_W
        bcs go_out
        sta g_col
        ldx g_room
        lda g_row
        jsr row_ptr
        ldy g_col
        lda (zp),y
        cmp #T_M1
        beq g_up
        cmp #T_M2
        beq g_up
        cmp #T_M3
        beq g_pop
        cmp #T_EMPTY
        bne go_out
        jmp g_seed
go_out: rts
g_up:   jsr rnd                         // grow a stage
        and #GROW_MASK
        bne go_out
        lda (zp),y
        clc
        adc #1
        jmp g_put
g_pop:  jsr rnd                         // a ripe one hatches a bug
        and #POP_MASK
        bne go_out
        lda g_room
        cmp room
        bne g_away
        lda g_col
        ldy g_row
        jsr spawn_bug
        bcs go_out
        ldx room
        inc room_bugs,x
        jsr sfx_hatch
        jmp g_reset
g_away: ldx g_room
        lda room_bugs,x
        cmp #MAXBUGS
        bcs go_out
        inc room_bugs,x
g_reset:
        ldx g_room
        lda g_row
        jsr row_ptr
        lda #T_M1
        jmp g_put
gs_out: rts
g_seed: lda g_row                       // an empty spot next to a ripe one
        cmp #ROOM_H-1
        bcs gs_out
        lda g_col
        beq gs_out
        cmp #ROOM_W-1
        bcs gs_out
        dey
        lda (zp),y
        cmp #T_M3
        beq g_nb
        iny
        iny
        lda (zp),y
        cmp #T_M3
        bne gs_out
g_nb:   ldx g_room                      // with floor under it
        lda g_row
        clc
        adc #1
        jsr row_ptr
        ldy g_col
        lda (zp),y
        tax
        lda props,x
        and #P_TOP
        beq gs_out
        jsr rnd
        and #SEED_MASK
        bne gs_out
        ldx g_room
        inc room_mush,x
        lda g_row
        jsr row_ptr
        lda #T_M1
g_put:  sta g_tile
        ldy g_col
        sta (zp),y
        lda g_room
        cmp room
        bne g_x
        ldx g_row                       // in John's room: on screen too
        lda scr_lo+TOP,x
        sta zp2
        lda scr_hi+TOP,x
        sta zp2+1
        lda g_tile
        sta (zp2),y
        lda zp2+1
        clc
        adc #$d4
        sta zp2+1
        ldx g_tile
        lda colour_of,x
        sta (zp2),y
g_x:    rts

// ripe mushrooms pulse
animate_chars:
        lda frame
        and #15
        bne ac_x
        lda frame
        and #16
        beq ac_b
        ldx #7
!:      lda ripe_a,x
        sta CHARSET+T_M3*8,x
        dex
        bpl !-
        rts
ac_b:   ldx #7
!:      lda ripe_b,x
        sta CHARSET+T_M3*8,x
        dex
        bpl !-
ac_x:   rts

// ---------------------------------------------------------------- sprites
// A = x in 2-pixel units (the sprite's middle), X = sprite. Leaves Y = X*2.
set_x:
        sta t0
        txa
        asl
        tay
        lda t0
        asl
        sta t1
        lda #0
        rol
        sta t2
        lda t1
        clc
        adc #12
        sta $d000,y
        lda t2
        adc #0
        beq !+
        lda msb
        ora bit_tab,x
        sta msb
!:      rts

update_sprites:
        lda #0
        sta msb
        sta en
        lda dead_t
        beq us_alive
        lda #F_DEAD
        jmp us_john
us_alive:
        lda pstate
        cmp #2
        bne !+
        lda anim
        lsr
        lsr
        lsr
        and #1
        clc
        adc #F_CLIMB
        jmp us_john
!:      cmp #1
        bne !+
        lda #F_JUMP
        jmp us_dir
!:      lda spraying
        beq !+
        lda #F_SPRAY
        jmp us_dir
!:      lda anim
        lsr
        lsr
        and #3
        tax
        lda walk_seq,x
us_dir: ldx dir
        beq us_john
        clc
        adc #F_LEFT
us_john:
        clc
        adc #PTR0
        sta SPRPTR
        lda inv                         // flicker while safe
        and #2
        bne !+
        lda #1
        sta en
!:      ldx #0
        lda px
        jsr set_x
        lda fy
        clc
        adc #SPR_Y
        sta $d001
        lda spraying                    // the spray cloud
        beq us_bugs
        lda frame
        lsr
        lsr
        and #1
        clc
        adc #F_PUFF+PTR0
        ldx dir
        beq !+
        clc
        adc #2
!:      sta SPRPTR+1
        lda dir
        bne us_pl
        lda px
        clc
        adc #10
        jmp us_px
us_pl:  lda px
        sec
        sbc #10
        bcc us_bugs
us_px:  ldx #1
        jsr set_x
        lda fy
        clc
        adc #SPR_Y
        sta $d003
        lda en
        ora #2
        sta en
us_bugs:
        ldx #MAXBUGS-1
us_b:   lda bst,x
        beq us_bn
        stx bi2
        cmp #1
        beq !+
        lda #F_SQUISH+PTR0
        jmp us_bf
!:      lda banim,x
        lsr
        lsr
        lsr
        and #1
        clc
        adc #F_BUG+PTR0
us_bf:  sta SPRPTR+2,x
        lda bx,x
        pha
        txa
        clc
        adc #2
        tax
        pla
        jsr set_x
        ldx bi2
        lda bfy,x
        clc
        adc #SPR_Y
        sta $d001,y
        lda bit_tab+2,x
        ora en
        sta en
us_bn:  dex
        bpl us_b
        lda msb
        sta $d010
        lda en
        sta $d015
        rts

// ---------------------------------------------------------------- status bar
draw_hud:
        Print(SCREEN, txt_hud0, 7)
        Print(SCREEN + 40 + 17, txt_spray, 3)
        Print(SCREEN + 80, txt_lives, 1)
        Print(SCREEN + 80 + 17, txt_mush, 5)
        rts

draw_room_name:
        lda room
        asl
        asl
        asl
        asl
        tax
        ldy #0
!:      lda room_names,x
        sta SCREEN+40,y
        lda #1
        sta COLRAM+40,y
        inx
        iny
        cpy #16
        bne !-
        rts

hud_update:
        ldx #2                          // score
        ldy #0
hu_s:   lda score,x
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta SCREEN+34,y
        lda #1
        sta COLRAM+34,y
        iny
        lda score,x
        and #$0f
        ora #$30
        sta SCREEN+34,y
        lda #1
        sta COLRAM+34,y
        iny
        dex
        bpl hu_s
        lda lives                       // lives
        ora #$30
        sta SCREEN+80+6
        lda #1
        sta COLRAM+80+6
        lda can                         // spray can: 10 blocks
        sta t0
        ldy #0
hu_b:   lda t0
        cmp #10
        bcc hu_part
        sbc #10
        sta t0
        lda #CH_FULL
        ldx #3
        jmp hu_put
hu_part:
        lda t0
        beq hu_empty
        lda #0
        sta t0
        lda #CH_HALF
        ldx #3
        jmp hu_put
hu_empty:
        lda #CH_EMPTY
        ldx #6
hu_put: sta SCREEN+40+23,y
        txa
        sta COLRAM+40+23,y
        iny
        cpy #10
        bne hu_b
        lda #0                          // mushrooms left, bugs left
        sta t0
        sta t1
        sta t2
        ldx #NROOMS-1
!:      lda room_mush,x
        clc
        adc t0
        sta t0
        bcc *+4
        inc t1
        lda room_bugs,x
        ora t2
        sta t2
        dex
        bpl !-
        lda t0
        ora t1
        ora t2
        bne !+
        lda #1
        sta won
!:      ldx #$30                        // three digits
hu_h:   lda t0
        sec
        sbc #100
        tay
        lda t1
        sbc #0
        bcc hu_hd
        sta t1
        sty t0
        inx
        jmp hu_h
hu_hd:  stx SCREEN+80+27
        ldx #$30
        lda t0
hu_t:   cmp #10
        bcc hu_td
        sbc #10
        inx
        jmp hu_t
hu_td:  stx SCREEN+80+28
        ora #$30
        sta SCREEN+80+29
        lda #1
        sta COLRAM+80+27
        sta COLRAM+80+28
        sta COLRAM+80+29
        ldx #NROOMS-1                   // the ship map
hu_m:   lda room_mush,x
        ora room_bugs,x
        beq !+
        lda #2
        jmp hu_mc
!:      lda #5
hu_mc:  cpx room
        bne !+
        ldy frame
        cpy #128
        bcc !+
        lda #1
!:      ldy map_pos,x
        sta COLRAM,y
        lda #CH_MAP
        sta SCREEN,y
        dex
        bpl hu_m
        rts

// ---------------------------------------------------------------- timing, input
wait_frame:
!:      lda $d012
        cmp #251
        bne !-
!:      lda $d012
        cmp #251
        beq !-
        rts

wait_fire:
!:      lda $dc00
        and #$10
        beq !-
!:      inc seed
        lda $dc00
        and #$10
        bne !-
        lda seed
        ora seed+1
        bne !+
        inc seed
!:      rts

// xorshift 16. Returns A, keeps X and Y.
rnd:
        lda seed+1
        lsr
        lda seed
        ror
        eor seed+1
        sta seed+1
        ror
        eor seed
        sta seed
        eor seed+1
        sta seed+1
        rts

// ---------------------------------------------------------------- sound
// voice 1: blips (shot_*), voice 2: pops (boom_t), voice 3: the spray hiss
sid_init:
        ldx #$18
        lda #0
!:      sta $d400,x
        dex
        bpl !-
        lda #$0f
        sta $d418
        rts

// A = start pitch, X = pitch change a frame, Y = frames
sfx_blip:
        sta shot_f
        stx shot_d
        sty shot_t
        lda #$09
        sta $d405
        lda #0
        sta $d406
        lda shot_f
        sta $d401
        lda #$20
        sta $d404
        lda #$21
        sta $d404
        rts

sfx_jump:
        lda #$10
        ldx #$02
        ldy #10
        jmp sfx_blip
sfx_refill:
        lda can
        lsr
        clc
        adc #$10
        ldx #0
        ldy #3
        jmp sfx_blip
sfx_hatch:
        lda #$30
        ldx #$fd
        ldy #12
        jmp sfx_blip
sfx_die:
        lda #$40
        ldx #$ff
        ldy #48
        jmp sfx_blip

sfx_pop:                                // a mushroom gone: keeps X and Y
        lda #$28
        jmp boom_go
sfx_squish:                             // a bug gone
        lda #$06
boom_go:
        sta $d408
        lda #$0a
        sta $d40c
        lda #0
        sta $d40d
        lda #$80
        sta $d40b
        lda #$81
        sta $d40b
        lda #16
        sta boom_t
        rts

sfx_spray:
        lda #0
        sta $d40e
        lda #$58
        sta $d40f
        lda #$00
        sta $d413
        lda #$a0
        sta $d414
        lda #$80
        sta $d412
        lda #$81
        sta $d412
        rts

sfx_update:
        lda shot_t
        beq s2
        dec shot_t
        bne s_sweep
        lda #$20
        sta $d404
        jmp s2
s_sweep:
        lda shot_f
        clc
        adc shot_d
        sta shot_f
        sta $d401
s2:     lda boom_t
        beq s3
        dec boom_t
        bne s3
        lda #$80
        sta $d40b
s3:     rts

#import "music.asm"

// ---------------------------------------------------------------- data
txt_t1:    .text "MUSHROOM FOR IMPROVEMENT"
           .byte 0
txt_t2:    .text "A WASTE OF SPACE GAME"
           .byte 0
txt_t3:    .text "SOMETHING IS GROWING ABOARD"
           .byte 0
txt_t4:    .text "THE MOTHERSHIP DILETTANTE."
           .byte 0
txt_t5:    .text "LT JOHN JOHNSON: CLEAR EVERY ROOM."
           .byte 0
txt_t6:    .text "LEFT RIGHT  WALK    UP  JUMP, CLIMB"
           .byte 0
txt_t7:    .text "FIRE        SPRAY  DOWN  CLIMB DOWN"
           .byte 0
txt_t8:    .text "STAND AT A GREEN TANK TO REFILL"
           .byte 0
txt_t9:    .text "RED MUSHROOMS SPREAD AND HATCH"
           .byte 0
txt_t10:   .text "BUGS. DON'T LET THEM TOUCH YOU."
           .byte 0
txt_fire:  .text "PRESS FIRE"
           .byte 0
txt_hud0:  .text "MUSHROOM FOR IMPROVEMENT    SCORE "
           .byte 0
txt_spray: .text "SPRAY"
           .byte 0
txt_lives: .text "LIVES"
           .byte 0
txt_mush:  .text "MUSHROOMS"
           .byte 0
txt_over1: .text "             "
           .byte 0
txt_over2: .text "  GAME OVER  "
           .byte 0
txt_win0:  .text "                                "
           .byte 0
txt_win1:  .text "  THE DILETTANTE IS CLEAN!      "
           .byte 0
txt_win2:  .text "  CAPTAIN JOSEF IS NEARLY HAPPY "
           .byte 0

room_names:
.for (var r=0; r<NROOMS; r++) {
        .var n = ROOM_NAMES.get(r)
        .errorif n.size() > 16, "room name longer than 16: " + n
        .text n
        .fill 16 - n.size(), 32
}

// neighbours ($ff: none). Doors and shafts must line up in rooms.asm.
//                 0     1     2     3     4     5     6     7
//              BRIDGE CORR GALLEY CREW  LAV  CARGO HYDRO ENGINE
room_left:  .byte $ff,    0,    1,    2,  $ff,    4,    5,    6
room_right: .byte    1,    2,    3,  $ff,    5,    6,    7,  $ff
room_up:    .byte  $ff,  $ff,  $ff,  $ff,    0,    1,    2,    3
room_down:  .byte    4,    5,    6,    7,  $ff,  $ff,  $ff,  $ff

map_pos:    .byte 40+35, 40+36, 40+37, 40+38, 80+35, 80+36, 80+37, 80+38

room_lo:    .fill NROOMS, <(ROOMRAM + i*ROOM_SIZE)
room_hi:    .fill NROOMS, >(ROOMRAM + i*ROOM_SIZE)
row40_lo:   .fill ROOM_H, <(i*ROOM_W)
row40_hi:   .fill ROOM_H, >(i*ROOM_W)
scr_lo:     .fill 25, <(SCREEN + i*40)
scr_hi:     .fill 25, >(SCREEN + i*40)
bit_tab:    .byte 1, 2, 4, 8, 16, 32, 64, 128
walk_seq:   .byte F_WALK1, F_STAND, F_WALK2, F_STAND
jump_tab:   .byte 4, 4, 3, 3, 3, 2, 2, 2, 1, 1, 1, 0, 0
fall_tab:   .byte 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4
.errorif fall_tab - jump_tab != JUMP_LEN, "jump_tab length"

ripe_a:     CharMC(CH_M3A)
ripe_b:     CharMC(CH_M3B)

.function propOf(i) {
    .if (i == T_WALL || i == T_BOX) .return P_TOP | P_WALL
    .if (i == T_PLAT) .return P_TOP
    .if (i == T_LAD) .return P_LAD
    .if (i == T_LADP) .return P_TOP | P_LAD
    .if (i >= T_M1 && i <= T_M3) .return P_MUSH
    .if (i == T_TANK) .return P_TANK
    .return 0
}
// a character's own colour: 8 + colour = multicolour; 0-7 = hi-res text
.function colOf(i) {
    .if (i == T_WALL) .return 8+6
    .if (i == T_PLAT || i == T_LAD || i == T_LADP) .return 8+7
    .if (i == T_M1) .return 8+5
    .if (i == T_M2) .return 8+4
    .if (i == T_M3) .return 8+2
    .if (i == T_TANK) .return 8+5
    .if (i == T_CON) .return 8+3
    .if (i == T_KTOP || i == T_KBOT) .return 8+2
    .if (i == T_LOO) .return 8+1
    .if (i == T_BOX) .return 8+7
    .if (i >= 64 && i <= 80) .return 8
    .return 1
}
props:      .fill 256, propOf(i)
colour_of:  .fill 256, colOf(i)

// bug start spots: up to 4 a room
spawn_n:
.for (var r=0; r<NROOMS; r++) .byte min(MAXBUGS, marks(ROOM_MAPS.get(r), "b").size())
spawn_col:
.for (var r=0; r<NROOMS; r++) {
    .var m = marks(ROOM_MAPS.get(r), "b")
    .for (var k=0; k<MAXBUGS; k++) .byte k < m.size() ? m.get(k).get(0) : 0
}
spawn_row:
.for (var r=0; r<NROOMS; r++) {
    .var m = marks(ROOM_MAPS.get(r), "b")
    .for (var k=0; k<MAXBUGS; k++) .byte k < m.size() ? m.get(k).get(1) : 0
}

// the rooms as they start (copied to ROOMRAM for each game)
room_tpl:
.for (var r=0; r<NROOMS; r++) {
    .var m = ROOM_MAPS.get(r)
    .for (var y=0; y<ROOM_H; y++)
        .for (var x=0; x<ROOM_W; x++)
            .byte tileOf(m.get(y).substring(x, x+1))
}
.errorif * > ROOMRAM, "program runs into the room working copies"

// ---------------------------------------------------------------- variables
frame:      .byte 0
seed:       .word 1
joy:        .byte 0
room:       .byte 0
px:         .byte 0             // John's middle, 2-pixel units (0-159)
fy:         .byte 0             // John's feet: y of the line under them, in the room
dir:        .byte 0             // 0 right, 1 left
pstate:     .byte 0             // 0 on the ground, 1 in the air, 2 on a ladder
air_t:      .byte 0
fall_t:     .byte 0
hdx:        .byte 0
anim:       .byte 0
spraying:   .byte 0
spray_snd:  .byte 0
can:        .byte 0
inv:        .byte 0
dead_t:     .byte 0
lives:      .byte 0
won:        .byte 0
score:      .byte 0, 0, 0       // BCD, low first
entry_px:   .byte 0
entry_fy:   .byte 0
entry_ps:   .byte 0
s_row:      .byte 0
s_col:      .byte 0
s_k:        .byte 0
h_row:      .byte 0
h_col:      .byte 0
g_room:     .byte 0
g_row:      .byte 0
g_col:      .byte 0
g_tile:     .byte 0
g_n:        .byte 0
bi:         .byte 0
bi2:        .byte 0
b_new:      .byte 0
b_col:      .byte 0
chasing:    .byte 0
msb:        .byte 0
en:         .byte 0
shot_f:     .byte 0
shot_d:     .byte 0
shot_t:     .byte 0
boom_t:     .byte 0
room_mush:  .fill NROOMS, 0
room_bugs:  .fill NROOMS, 0
bx:         .fill MAXBUGS, 0
bfy:        .fill MAXBUGS, 0
bdir:       .fill MAXBUGS, 0
bst:        .fill MAXBUGS, 0    // 0 none, 1 alive, 2+ squished (counting down)
banim:      .fill MAXBUGS, 0

// A Pain in the Asteroids - a Waste of Space game for the C64
// KickAssembler. Joystick in port 2.
//
// Big rocks fall straight down. Shoot one and it splits into two small
// rocks that fly diagonally down and vanish off the sides.
//
// Test builds:  -define SKIPTITLE  start without waiting for fire
//               -define DEMO       fire held, no steering
//               -define QUICK      2 big rocks a level
//               -define ONELIFE    one life (to hear game over)

.encoding "screencode_upper"

.const SCREEN      = $0400
.const SPRPTR      = SCREEN + $3f8
.const NUM_STARS   = 24
.const SHIP_MAXX   = 148        // x is in 2-pixel units: screen x = x*2 + 24
.const SHIP_MINY   = 140
.const SHIP_MAXY   = 226
.const SHIP_HOME_X = 74         // the middle
.const ROCK_GONE   = 250        // rocks past this y leave
.const MAX_BIG     = 3          // big rocks at once: 3 big = 6 small = all sprites
.const MOM_X       = 62         // mothership left edge: 36 units wide, centred

.const PTR_SHIP    = $2000/64
.const PTR_BULLET  = PTR_SHIP+1
.const PTR_ROCK    = PTR_SHIP+2 // two shapes
.const PTR_BOOM    = PTR_SHIP+4 // two frames
.const PTR_MOM     = PTR_SHIP+6 // six parts: 3 wide, 2 tall
.const PTR_SMALL   = PTR_SHIP+12

.const COL_SHARED1 = 11         // sprite pixels "1": dark grey
.const COL_SHARED2 = 1          // sprite pixels "3": white
.const COL_SHIP    = 14
.const COL_MOM     = 12

.label zp  = $fb                // $fb/$fc: screen pointer / copy source
.label zp2 = $fd                // $fd/$fe: copy destination

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

BasicUpstart2(start)

start:
        lda #0
        sta $d020
        sta $d021
        sta $d017
        sta $d01b
        sta $d01d
        jsr sid_init
        lda #COL_SHARED1
        sta $d025
        lda #COL_SHARED2
        sta $d026

title:
        lda #0
        sta $d015
        sta $d020
        jsr show_picture
        jsr music_start
#if !SKIPTITLE
        jsr wait_fire
#endif
        jsr music_stop
        jsr hide_picture

// ---------------------------------------------------------------- new game
new_game:
        jsr $e544
        Print(SCREEN, txt_hud, 1)
        lda #0
        sta score
        sta score+1
        lda #3
        sta lives
#if ONELIFE
        lda #1
        sta lives
#endif
        lda #1
        sta level
        jsr stars_init

next_level:
        lda level                       // big rocks to shoot: 6 + 4*level, max 95
        asl
        asl
        clc
        adc #6
        cmp #96
        bcc !+
        lda #95
!:      sta rocks_left
#if QUICK
        lda #2
        sta rocks_left
#endif
        lda level                       // rock speed bonus: (level-1)/2, max 2
        sec
        sbc #1
        lsr
        cmp #3
        bcc !+
        lda #2
!:      sta spd_bonus
        jsr draw_hud
        jsr level_intro
        jsr enter_play

// ---------------------------------------------------------------- main loop
loop:
        jsr tick
        jsr read_joy
        jsr move_bullet
        jsr move_rocks
        jsr check_hits
        jsr calc_en
        lda lives
        beq game_over
        lda rocks_left                  // level done when every rock is parked
        bne loop
        ldx #7
!:      lda rock_spd,x
        bne loop
        dex
        cpx #2
        bcs !-
        jsr level_outro
        inc level
        jmp next_level

game_over:
        lda #0
        sta $d015
        sta $d020
        Print(SCREEN + 12*40 + 15, txt_over, 2)
        lda #2                          // game over jingle
        jsr music_begin
        lda #190
        sta cnt
!:      jsr wait_frame
        jsr music_play
        dec cnt
        bne !-
        jsr wait_fire
        jmp title

// ---------------------------------------------------------------- title picture
// The Koala picture is stored after the sprites. To show it, copy it where
// the VIC looks in bank 2 ($8000-$bfff): screen colours at $8400, bitmap at
// $a000 (RAM under BASIC ROM: the VIC always sees RAM), colours to $d800.
show_picture:
        lda #$0b                        // screen off while copying
        sta $d011
        lda #<pic_bitmap
        ldy #>pic_bitmap
        sta zp
        sty zp+1
        lda #$00
        ldy #$a0
        ldx #32                         // 8000 bytes (32 pages)
        jsr copy_pages
        lda #<pic_screen
        ldy #>pic_screen
        sta zp
        sty zp+1
        lda #$00
        ldy #$84
        ldx #4
        jsr copy_pages
        lda #<pic_colour
        ldy #>pic_colour
        sta zp
        sty zp+1
        lda #$00
        ldy #$d8
        ldx #4
        jsr copy_pages
        lda pic_bg
        sta $d021
        lda $dd00                       // VIC bank 2
        and #%11111100
        ora #%00000001
        sta $dd00
        lda #$18                        // screen at +$0400, bitmap at +$2000
        sta $d018
        lda #$18                        // multicolour
        sta $d016
        lda #$3b                        // bitmap mode, screen on
        sta $d011
        rts

hide_picture:
        lda #$0b
        sta $d011
        lda $dd00                       // back to bank 0, text mode
        ora #%00000011
        sta $dd00
        lda #$15
        sta $d018
        lda #$08
        sta $d016
        lda #0
        sta $d021
        jsr $e544
        lda #$1b
        sta $d011
        rts

// zp = source, A/Y = destination low/high, X = pages
copy_pages:
        sta zp2
        sty zp2+1
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

// one frame: sprites, stars, sound
tick:
        jsr wait_frame
        jsr update_sprites
        inc frame
        jsr move_stars
        jsr music_play                  // jingles
        jmp sfx_update

// A = frames to wait (with stars and sound running)
wait_ticks:
        sta cnt
!:      jsr tick
        dec cnt
        bne !-
        rts

// ---------------------------------------------------------------- frame sync
wait_frame:
!:      lda $d012
        cmp #251
        bne !-
!:      lda $d012
        cmp #251
        beq !-
        rts

wait_fire:
!:      lda $dc00                       // wait until fire is released...
        and #$10
        beq !-
!:      inc seed                        // ...then pressed; the wait seeds rnd
        lda $dc00
        and #$10
        bne !-
        lda seed                        // xorshift must never be all zero
        ora seed+1
        bne !+
        inc seed
!:      rts

// xorshift 16 (John Metcalf). Returns A, keeps X and Y.
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

// ---------------------------------------------------------------- sprites
update_sprites:
        lda #0
        sta msb
        ldx #7
!:      txa
        asl
        tay
        lda spr_y,x
        sta $d001,y
        lda spr_x,x                     // screen x = x*2 + 24, 9 bits
        asl
        sta tmp
        lda #0
        rol
        sta hi
        lda tmp
        clc
        adc #24
        sta $d000,y
        lda hi
        adc #0
        lsr                             // bit 8 into carry
        rol msb
        dex
        bpl !-
        lda msb
        sta $d010
        lda spr_en
        sta $d015
        rts

// in play: rocks always on, bullet when flying, ship blinks while invulnerable
calc_en:
        lda bul_on
        asl
        ora #%11111100
        sta spr_en
        lda inv
        beq !+
        lda frame
        and #4
        bne !++
!:      lda spr_en
        ora #1
        sta spr_en
!:      rts

// ---------------------------------------------------------------- cutscenes
// Sprites 0-5 are the mothership, 7 is the ship: higher numbers are drawn
// behind lower ones, so the ship can hide inside the hull.
enter_cut:
        lda #0
        sta bul_on
        lda #$ff
        sta $d01c                       // all multicolour
        ldx #5
!:      txa
        clc
        adc #PTR_MOM
        sta SPRPTR,x
        lda #COL_MOM
        sta $d027,x
        dex
        bpl !-
        lda #PTR_SHIP
        sta SPRPTR+7
        lda #COL_SHIP
        sta $d02e
        lda #%10111111
        sta spr_en
        rts

set_mom:
        ldx #5
!:      lda mom_x
        clc
        adc mom_dx,x
        sta spr_x,x
        lda mom_y
        clc
        adc mom_dy,x
        sta spr_y,x
        dex
        bpl !-
        rts

tick_cut:
        jsr set_mom
        jmp tick

level_intro:
        lda #1                          // get ready jingle
        jsr music_begin
        jsr enter_cut
        lda #MOM_X
        sta mom_x
        lda #251
        sta mom_y
        lda #SHIP_HOME_X
        sta spr_x+7
        Print(SCREEN + 11*40 + 16, txt_level, 7)
        lda level
        jsr two_digits
        sty SCREEN + 11*40 + 22
        sta SCREEN + 11*40 + 23
li_rise:                                // the mothership rises from below
        dec mom_y
        lda mom_y                       // the ship sits inside
        clc
        adc #12
        sta spr_y+7
        jsr tick_cut
        lda mom_y
        cmp #186
        bne li_rise
        lda #20
        jsr wait_ticks
        jsr sfx_launch
li_launch:                              // the ship flies out of the nose
        lda spr_y+7
        sec
        sbc #2
        sta spr_y+7
        jsr tick_cut
        lda spr_y+7
        cmp #152
        bcs li_launch
li_drop:                                // the mothership drops back
        lda mom_y
        clc
        adc #2
        sta mom_y
        jsr tick_cut
        lda mom_y
        cmp #250
        bcc li_drop
        lda #%10000000                  // just the ship
        sta spr_en
        lda #25
        jsr wait_ticks
        Print(SCREEN + 11*40 + 16, txt_blank, 1)
        rts

level_outro:
        lda spr_x                       // the ship moves to sprite 7
        sta spr_x+7
        lda spr_y
        sta spr_y+7
        jsr enter_cut
        lda #MOM_X
        sta mom_x
        lda #8
        sta mom_y
        Print(SCREEN + 11*40 + 14, txt_clear, 7)
        clc                             // +100 for the level
        lda #1
        jsr add_score_hi
        jsr draw_hud
lo_come:                                // the mothership comes in ahead;
        lda #0                          // the ship lines up behind it
        sta moving
        lda mom_y
        cmp #70
        beq lo1
        inc mom_y
        inc moving
lo1:    lda spr_x+7
        cmp #SHIP_HOME_X
        beq lo3
        inc moving
        bcc lo2
        dec spr_x+7
        jmp lo3
lo2:    inc spr_x+7
lo3:    lda spr_y+7
        cmp #140
        beq lo5
        inc moving
        bcc lo4
        dec spr_y+7
        jmp lo5
lo4:    inc spr_y+7
lo5:    jsr tick_cut
        lda moving
        bne lo_come
        jsr sfx_dock
lo_dock:                                // into the back
        dec spr_y+7
        jsr tick_cut
        lda spr_y+7
        cmp #70+12
        bne lo_dock
        lda #20
        jsr wait_ticks
lo_leave:                               // and away
        lda mom_y
        sec
        sbc #2
        sta mom_y
        clc
        adc #12
        sta spr_y+7
        jsr tick_cut
        lda mom_y
        cmp #10
        bcs lo_leave
        lda #0
        sta spr_en
        lda #25
        jsr wait_ticks
        Print(SCREEN + 11*40 + 14, txt_blank, 1)
        rts

// ---------------------------------------------------------------- play
enter_play:
        lda spr_x+7                     // the ship back to sprite 0
        sta spr_x
        lda spr_y+7
        sta spr_y
        lda #PTR_SHIP
        sta SPRPTR
        lda #PTR_BULLET
        sta SPRPTR+1
        lda #COL_SHIP
        sta $d027
        lda #7
        sta $d028
        lda #%11111101                  // all multicolour but the bullet
        sta $d01c
        lda #0
        sta bul_on
        sta inv
        ldx #7                          // all rock slots free; big rocks
!:      jsr rock_park                   // come in by themselves
        dex
        cpx #2
        bcs !-
        rts

read_joy:
#if DEMO
        lda #%11101111
#else
        lda $dc00
#endif
        sta joy
        and #%00000100                  // left
        bne !+
        lda spr_x
        sec
        sbc #2
        bcs st_l
        lda #0
st_l:   sta spr_x
!:      lda joy
        and #%00001000                  // right
        bne !+
        lda spr_x
        clc
        adc #2
        cmp #SHIP_MAXX+1
        bcc st_r
        lda #SHIP_MAXX
st_r:   sta spr_x
!:      lda joy
        and #%00000001                  // up
        bne !+
        lda spr_y
        sec
        sbc #2
        cmp #SHIP_MINY
        bcs st_u
        lda #SHIP_MINY
st_u:   sta spr_y
!:      lda joy
        and #%00000010                  // down
        bne !+
        lda spr_y
        clc
        adc #2
        cmp #SHIP_MAXY+1
        bcc st_d
        lda #SHIP_MAXY
st_d:   sta spr_y
!:      lda joy
        and #%00010000                  // fire
        bne !+
        lda bul_on
        bne !+
        lda #1
        sta bul_on
        lda spr_x
        sta spr_x+1
        lda spr_y
        sec
        sbc #14
        sta spr_y+1
        jsr sfx_shot
!:      rts

move_bullet:
        lda bul_on
        beq !+
        lda spr_y+1
        sec
        sbc #7
        bcc off
        cmp #30
        bcc off
        sta spr_y+1
!:      rts
off:    lda #0
        sta bul_on
        rts

// ---------------------------------------------------------------- rocks
// Rock slots are sprites 2-7. A slot is parked (speed 0, out of sight),
// a big rock, or a small rock. All of these keep X.

rock_park:
        lda #0
        sta spr_y,x
        sta rock_state,x
        sta rock_spd,x
        sta rock_wait,x
        sta rock_size,x
        rts

rock_new_big:
        lda #0
        sta spr_y,x
        sta rock_state,x
        sta rock_size,x
!:      jsr rnd
        cmp #SHIP_MAXX+1
        bcs !-
        sta spr_x,x
        jsr rnd                         // speed 1-2, plus the level bonus
        and #1
        clc
        adc #1
        adc spd_bonus
        sta rock_spd,x
        jsr rnd
        and #63
        sta rock_wait,x
        txa                             // odd and even sprites: two shapes
        and #1
        clc
        adc #PTR_ROCK
        sta SPRPTR,x
        lda rock_cols,x
        sta $d027,x
        rts

// A big rock splits: it becomes the left-going small rock, and a parked
// slot (if any) becomes the right-going one.
rock_split:
        jsr sfx_crack
        lda spr_x,x
        sta xtmp
        lda #1
        sta rock_size,x
        lda #PTR_SMALL
        sta SPRPTR,x
        lda #0
        sta rock_xf,x
        sta rock_wait,x
        lda rock_spd,x                  // small rocks are a bit faster
        clc
        adc #1
        cmp #5
        bcc !+
        lda #4
!:      sta rock_spd,x
        jsr rnd                         // sideways: 0.62-0.87 units a frame
        and #$3f
        clc
        adc #$a0
        sta vtmp
        eor #$ff                        // left: minus that
        clc
        adc #1
        sta rock_vl,x
        lda #$ff
        sta rock_vh,x
        lda xtmp
        sec
        sbc #2
        bcs !+
        lda #0
!:      sta spr_x,x
        ldy #7                          // find a free slot
rs_find:
        lda rock_spd,y
        beq rs_found
        dey
        cpy #2
        bcs rs_find
        rts                             // none: just one piece
rs_found:
        lda #1
        sta rock_size,y
        lda #PTR_SMALL
        sta SPRPTR,y
        lda #0
        sta rock_xf,y
        sta rock_wait,y
        sta rock_state,y
        sta rock_vh,y
        lda vtmp
        sta rock_vl,y
        lda rock_spd,x
        sta rock_spd,y
        lda spr_y,x
        sta spr_y,y
        lda $d027,x
        sta $d027,y
        lda xtmp
        clc
        adc #2
        cmp #SHIP_MAXX+1
        bcc !+
        lda #SHIP_MAXX
!:      sta spr_x,y
        rts

rock_explode:
        lda #20
        sta rock_state,x
        lda #PTR_BOOM
        sta SPRPTR,x
        jmp sfx_boom

move_rocks:
        lda #0                          // count the big rocks
        sta big_count
        ldx #7
bc_l:   lda rock_spd,x
        beq bc_n
        lda rock_size,x
        bne bc_n
        inc big_count
bc_n:   dex
        cpx #2
        bcs bc_l

        ldx #7
rl:     lda rock_state,x
        beq alive
        dec rock_state,x                // exploding
        beq rdone
        lda rock_state,x
        lsr
        lsr
        tay
        lda boom_cols,y
        sta $d027,x
        lda rock_state,x
        cmp #10
        lda #PTR_BOOM                   // fire, then smoke
        bcs !+
        lda #PTR_BOOM+1
!:      sta SPRPTR,x
        jmp rnext
rdone:  jsr rock_park
        jmp rnext
alive:  lda rock_spd,x
        bne active
        lda big_count                   // a free slot: bring in a big rock?
        cmp #MAX_BIG
        bcs to_next
        cmp rocks_left                  // not more than are left to shoot
        bcs to_next
        jsr rock_new_big
        inc big_count
to_next:
        jmp rnext
active: lda rock_wait,x
        beq rmove
        dec rock_wait,x
        jmp rnext
rmove:  lda rock_size,x
        beq rdown
        lda rock_xf,x                   // small: sideways in 1/256 steps
        clc
        adc rock_vl,x
        sta rock_xf,x
        lda spr_x,x
        adc rock_vh,x
        sta spr_x,x
        cmp #SHIP_MAXX+1
        bcc rdown
        jsr rock_park                   // off a side: gone
        jmp rnext
rdown:  lda spr_y,x
        clc
        adc rock_spd,x
        sta spr_y,x
        cmp #ROCK_GONE
        bcc rnext
        jsr rock_park
rnext:  dex
        cpx #2
        bcc !+
        jmp rl
!:      rts

check_hits:
        ldx #7
hl:     lda rock_state,x
        beq !+
        jmp hnext
!:      lda rock_spd,x
        bne !+
        jmp hnext
!:      ldy rock_size,x                 // hit boxes by size
        lda bul_on
        beq ship_chk
        lda spr_x+1
        sec
        sbc spr_x,x
        Abs()
        cmp hit_bx,y
        bcs ship_chk
        lda spr_y+1
        sec
        sbc spr_y,x
        Abs()
        cmp hit_by,y
        bcs ship_chk
        lda #0                          // the bullet hits
        sta bul_on
        lda rock_size,x
        bne hit_small
        jsr rock_split                  // big: splits, 10 points
        lda #$10
        jsr add_score
        lda rocks_left
        beq !+
        dec rocks_left
!:      jsr draw_hud
        jmp hnext
hit_small:
        jsr rock_explode                // small: gone, 20 points
        lda #$20
        jsr add_score
        jsr draw_hud
        jmp hnext
ship_chk:
        lda inv
        bne hnext
        lda spr_x
        sec
        sbc spr_x,x
        Abs()
        cmp ship_bx,y
        bcs hnext
        lda spr_y
        sec
        sbc spr_y,x
        Abs()
        cmp ship_by,y
        bcs hnext
        jsr rock_explode                // a rock hits the ship
        dec lives
        jsr draw_hud
        lda #120
        sta inv
        lda #2
        sta $d020
        lda #8
        sta flash
hnext:  dex
        cpx #2
        bcc !+
        jmp hl
!:      rts

// ---------------------------------------------------------------- score
// A = points to add (BCD, tens and ones)
add_score:
        sed
        clc
        adc score
        sta score
        lda #0
add_score_hi:                           // A = hundreds to add (BCD)
        sed
        adc score+1
        sta score+1
        cld
        rts

// keeps X
draw_hud:
        lda score+1
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta SCREEN+6
        lda score+1
        and #$0f
        ora #$30
        sta SCREEN+7
        lda score
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta SCREEN+8
        lda score
        and #$0f
        ora #$30
        sta SCREEN+9
        lda level
        jsr two_digits
        sty SCREEN+18
        sta SCREEN+19
        lda rocks_left
        jsr two_digits
        sty SCREEN+28
        sta SCREEN+29
        lda lives
        ora #$30
        sta SCREEN+39
        rts

// A = 0..99 -> Y = tens digit, A = ones digit (screen codes). Keeps X.
two_digits:
        ldy #$2f
        sec
!:      iny
        sbc #10
        bcs !-
        adc #$3a
        rts

// ---------------------------------------------------------------- stars
// Stars only draw on empty cells and only erase themselves, so text stays.
stars_init:
        ldx #NUM_STARS-1
!:      jsr star_new
!:      jsr rnd
        and #31
        beq !-
        cmp #25
        bcs !-
        sta star_y,x
        jsr star_draw
        dex
        bpl !--
        rts

star_new:                               // random column
!:      jsr rnd
        and #63
        cmp #40
        bcs !-
        sta star_x,x
        rts

move_stars:
        ldx #NUM_STARS-1
ml:     lda frame
        and star_mask,x
        bne mnext
        jsr star_ptr                    // erase
        lda (zp),y
        cmp #$2e
        bne !+
        lda #$20
        sta (zp),y
!:      lda star_y,x
        clc
        adc #1
        cmp #25
        bcc !+
        jsr star_new
        lda #1
!:      sta star_y,x
        jsr star_draw
mnext:  dex
        bpl ml
        rts

star_ptr:                               // zp = row start, Y = column
        ldy star_y,x
        lda row_lo,y
        sta zp
        lda row_hi,y
        sta zp+1
        ldy star_x,x
        rts

star_draw:
        jsr star_ptr
        lda (zp),y
        cmp #$20
        bne !+
        lda #$2e
        sta (zp),y
        lda zp+1
        clc
        adc #$d4                        // screen -> colour RAM
        sta zp+1
        lda star_col,x
        sta (zp),y
!:      rts

// ---------------------------------------------------------------- sound
// voice 1: shot / launch / dock sweeps, voice 2: noise booms
sid_init:
        ldx #$18
        lda #0
!:      sta $d400,x
        dex
        bpl !-
        lda #$0a
        sta $d40c
        lda #$0f                        // volume 15
        sta $d418
        rts

sfx_shot:
        lda #$08
        sta $d405
        lda #$30
        sta shot_f
        lda #$fc
        sta shot_d
        lda #8
        sta shot_t
sfx_go:
        lda #0                          // no sustain (a jingle may have set one)
        sta $d406
        lda shot_f
        sta $d401
        lda #$20
        sta $d404
        lda #$21
        sta $d404
        rts

sfx_launch:                             // rising whoosh
        lda #$0b
        sta $d405
        lda #$06
        sta shot_f
        lda #$03
        sta shot_d
        lda #40
        sta shot_t
        jmp sfx_go

sfx_dock:                               // slow falling hum
        lda #$0b
        sta $d405
        lda #$38
        sta shot_f
        lda #$ff
        sta shot_d
        lda #50
        sta shot_t
        jmp sfx_go

sfx_crack:                              // a rock splitting: higher noise
        lda #$0e
        jmp boom_go
sfx_boom:                               // keeps X and Y
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
        lda #24
        sta boom_t
        rts

sfx_update:
        lda shot_t
        beq s2
        dec shot_t
        bne sweep
        lda #$20
        sta $d404
        jmp s2
sweep:  lda shot_f
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
s3:     lda flash
        beq s4
        dec flash
        bne s4
        lda #0
        sta $d020
s4:     lda inv
        beq s5
        dec inv
s5:     rts

// ---------------------------------------------------------------- data
txt_title: .text "A PAIN IN THE ASTEROIDS"
           .byte 0
txt_sub:   .text "A WASTE OF SPACE GAME"
           .byte 0
txt_fire:  .text "PRESS FIRE"
           .byte 0
txt_hud:   .text "SCORE 0000  LEVEL 00  ROCKS 00   LIVES 0"
           .byte 0
txt_over:  .text "GAME OVER"
           .byte 0
txt_level: .text "LEVEL 00"
           .byte 0
txt_clear: .text "LEVEL CLEAR"
           .byte 0
txt_blank: .text "           "
           .byte 0

frame:      .byte 0
joy:        .byte 0
bul_on:     .byte 0
lives:      .byte 0
inv:        .byte 0
flash:      .byte 0
score:      .byte 0, 0              // BCD
level:      .byte 0
rocks_left: .byte 0                 // big rocks still to shoot
spd_bonus:  .byte 0
big_count:  .byte 0
shot_t:     .byte 0
shot_f:     .byte 0
shot_d:     .byte 0
boom_t:     .byte 0
msb:        .byte 0
tmp:        .byte 0
hi:         .byte 0
cnt:        .byte 0
moving:     .byte 0
xtmp:       .byte 0
vtmp:       .byte 0
mom_x:      .byte 0
mom_y:      .byte 0
spr_en:     .byte 0
seed:       .byte 1, $a5

spr_x:      .fill 8, 0              // play: 0 ship, 1 bullet, 2-7 rocks
spr_y:      .fill 8, 0              // cutscenes: 0-5 mothership, 7 ship
rock_spd:   .fill 8, 0              // falling speed; 0: parked
rock_state: .fill 8, 0              // >0: exploding, frames left
rock_wait:  .fill 8, 0              // frames before it starts falling
rock_size:  .fill 8, 0              // 0 big, 1 small
rock_xf:    .fill 8, 0              // small: x fraction
rock_vl:    .fill 8, 0              // small: sideways speed, fraction
rock_vh:    .fill 8, 0              //   and whole part ($ff = going left)
rock_cols:  .byte 0, 0, 9, 12, 15, 9, 12, 15
boom_cols:  .byte 11, 2, 8, 7, 7    // by frames left / 4: smoke ... fire
hit_bx:     .byte 7, 5              // bullet hit box by size (x units, lines)
hit_by:     .byte 18, 12
ship_bx:    .byte 8, 6              // ship hit box by size
ship_by:    .byte 16, 12
mom_dx:     .byte 0, 12, 24, 0, 12, 24
mom_dy:     .byte 0, 0, 0, 21, 21, 21

star_x:     .fill NUM_STARS, 0
star_y:     .fill NUM_STARS, 0
star_mask:  .for (var i=0; i<NUM_STARS/3; i++) .byte 1, 3, 7      // parallax speeds
star_col:   .for (var i=0; i<NUM_STARS/3; i++) .byte 1, 15, 11

row_lo:     .fill 25, <(SCREEN + i*40)
row_hi:     .fill 25, >(SCREEN + i*40)

#import "music.asm"
#import "sprites.asm"

// ---- the title picture: art/title.kla, made with tools/img2c64.py
.var pic = LoadBinary("../art/title.kla", BF_KOALA)
* = $2400 "Title picture"
pic_bitmap: .fill 8000, pic.getBitmap(i)
pic_screen: .fill 1000, pic.getScreenRam(i)
pic_colour: .fill 1000, pic.getColorRam(i)
pic_bg:     .byte pic.getBackgroundColor()

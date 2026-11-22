// The crew, random encounters and turn-based fights.
//
// Each step there's a chance of a fight (none in the first few steps after one).
// Every crew member who is up picks F)ight, D)efend (half damage this round) or
// R)un (the whole crew tries to get away, half the time). Then the fighters hit
// the first monster still up, and every monster hits someone at random.
// Nobody dies for good: when it's over, the downed get back up with 1 HP.
// All the crew down = game over.

// ---------------------------------------------------------------- the crew
.var CREW_NAME = List().add("JOHNSON", "SHIN", "JIMMIE")
.var CREW_HP   = List().add(24, 18, 20)
.var CREW_ATK  = List().add(6, 8, 5)     // a hit does 1 to this
.const NCREW = 3

.const FIGHT_CHANCE = 24        // out of 256, each step
.const FIGHT_GRACE  = 4         // steps after a fight with none
.const REGEN_STEPS  = 6         // every so many steps, everyone up gets 1 HP back
.const PAUSE        = 40        // frames between fight lines (hold fire: faster)

.const SPRPTR = SCREEN + $3f8
.const MON_X  = 64              // the monster's top-left sprite position
.const MON_Y  = 108

// ---------------------------------------------------------------- set up
crew_init:
        ldx #NCREW-1
!:      lda crew_max,x
        sta crew_hp,x
        dex
        bpl !-
        lda #0
        sta steps
        sta regen
        sta mflash
        lda #$ff
        sta cur
        lda #1                  // one medkit to start with
        sta meds
        lda #0
        sta keys
        sta bonus
        // sprites: multicolour, doubled, in a 2 x 2 block; off for now
        lda #$1f                // + sprite 4: items in the view
        sta $d01c
        lda #$0f
        sta $d017
        sta $d01d
        lda #0
        sta $d015
        sta $d010
        sta $d01b
        sta $d025               // black
        lda #1
        sta $d026               // white
        lda #MON_X
        sta $d000
        sta $d004
        lda #MON_X + 48
        sta $d002
        sta $d006
        lda #MON_Y
        sta $d001
        sta $d003
        lda #MON_Y + 42
        sta $d005
        sta $d007
        // SID voice 3: noise for random numbers (switched off from the output)
        lda #$ff
        sta $d40e
        sta $d40f
        lda #$80
        sta $d412
        rts

// ---------------------------------------------------------------- after each step
after_step:
        inc regen
        lda regen
        cmp #REGEN_STEPS
        bcc no_regen
        lda #0
        sta regen
        ldx #NCREW-1
rg:     lda crew_hp,x
        beq rg_next             // down: stays down till a fight ends
        cmp crew_max,x
        bcs rg_next
        inc crew_hp,x
rg_next:
        dex
        bpl rg
        jsr draw_party
no_regen:
        inc steps
#if NOFIGHTS
        rts
#endif
#if FIGHTTEST
        jmp combat
#else
        lda steps
        cmp #FIGHT_GRACE
        bcc !+
        jsr rnd
        ldx deck
        cmp deck_fights,x
        bcs !+
        jmp combat
!:      rts
#endif

// ---------------------------------------------------------------- the fight
combat:
        lda #NMON
        jsr rand_n
        sta mtype
        tax
        lda mon_max,x
        jsr rand_n
        clc
        adc #1
        sta mcount
        ldx #0
!:      lda #0
        cpx mcount
        bcs mz
        ldy mtype
        lda mon_hp,y
mz:     sta mhp,x
        inx
        cpx #3
        bne !-
        jsr show_monster
        lda #$0c
        jsr sound
        jsr lb_start
        lda mcount
        jsr lb_num
        Say(txt_space)
        jsr lb_mon_name
        lda mcount
        cmp #2
        bcc !+
        Say(txt_s)
!:      Say(txt_block)
        jsr lb_say

round:
        // everyone up picks what to do
        ldx #NCREW-1
        lda #0
!:      sta act,x
        dex
        bpl !-
        lda #0
        sta who
pick:   ldx who
        lda crew_hp,x
        beq pick_next
        stx cur
        jsr draw_party
        jsr lb_start
        jsr lb_crew_name
        Say(txt_prompt)
        jsr lb_end
        jsr get_choice
        cmp #4
        bne !+
        jsr use_med             // a medkit is this one's turn
        bcs pm_used
        jmp pick                // none used: ask again
pm_used:
        ldx who
        lda #0
        sta act,x
        jmp pick_next
!:      ldx who
        sta act,x
        cmp #3
        bne pick_next
        // run for it
        lda #$ff
        sta cur
        jsr draw_party
        jsr rnd
        bmi run_fail
        Line(txt_run_ok)
        jmp fight_over
run_fail:
        Line(txt_run_fail)
        jmp monsters_turn
pick_next:
        inc who
        lda who
        cmp #NCREW
        bne pick
        lda #$ff
        sta cur
        jsr draw_party

        // the crew acts
        lda #0
        sta who
crew_turn:
        ldx who
        lda crew_hp,x
        bne !+
        jmp crew_next
!:      lda act,x
        cmp #2
        bne crew_hit
        jsr lb_start
        jsr lb_crew_name
        Say(txt_ducks)
        jsr lb_say
        jmp crew_next
crew_hit:
        ldx #0                  // the first monster still up
!:      lda mhp,x
        bne !+
        inx
        cpx #3
        bne !-
        jmp won                 // (can't happen: checked after each kill)
!:      stx target
        ldx who
        lda crew_atk,x
        clc
        adc bonus
        jsr rand_n
        clc
        adc #1
        sta dmg
        ldx target
        lda mhp,x
        sec
        sbc dmg
        bcs !+
        lda #0
!:      sta mhp,x
        lda #6
        sta mflash
        lda #$18
        jsr sound
        jsr lb_start
        jsr lb_crew_name
        Say(txt_hits)
        jsr lb_mon_name
        Say(txt_for)
        lda dmg
        jsr lb_num
        Say(txt_dot)
        jsr lb_say
        ldx target
        lda mhp,x
        bne crew_next
        jsr lb_start
        Say(txt_the)
        jsr lb_mon_name
        Say(txt_mon_down)
        jsr lb_say
        ldx #2                  // all down?
!:      lda mhp,x
        bne crew_next
        dex
        bpl !-
        jmp won
crew_next:
        inc who
        lda who
        cmp #NCREW
        beq monsters_turn
        jmp crew_turn

        // the monsters act
monsters_turn:
        lda #0
        sta mwho
mon_turn:
        ldx mwho
        lda mhp,x
        bne !+
        jmp mon_next
!:      lda #NCREW              // someone who's up
        jsr rand_n
        tax
        lda crew_hp,x
        beq !-
        stx who
        ldy mtype
        lda mon_atk,y
        jsr rand_n
        clc
        adc #1
        ldx who
        ldy act,x
        cpy #2                  // defending: half
        bne !+
        clc
        adc #1
        lsr
!:      sta dmg
        lda crew_hp,x
        sec
        sbc dmg
        bcs !+
        lda #0
!:      sta crew_hp,x
        lda #6
        sta flash
        lda #$06
        jsr sound
        jsr draw_party
        jsr lb_start
        Say(txt_the)
        jsr lb_mon_name
        Say(txt_space)
        ldy mtype
        lda verb_lo,y
        ldx verb_hi,y
        jsr lb_str
        Say(txt_space)
        jsr lb_crew_name
        Say(txt_for)
        lda dmg
        jsr lb_num
        Say(txt_dot)
        jsr lb_say
        ldx who
        lda crew_hp,x
        bne mon_next
        jsr lb_start
        jsr lb_crew_name
        Say(txt_crew_down)
        jsr lb_say
        ldx #NCREW-1            // everyone down?
!:      lda crew_hp,x
        bne mon_next
        dex
        bpl !-
        jmp game_over
mon_next:
        inc mwho
        lda mwho
        cmp #3
        beq !+
        jmp mon_turn
!:      jmp round

won:
        lda #0
        sta $d015
        Line(txt_won)
        jsr rnd                 // a third of the time: a medkit
        cmp #85
        bcs fight_over
        jsr add_med
        jsr status
        Line(txt_loot)
fight_over:
        lda #0
        sta $d015
        sta steps
        lda #$ff
        sta cur
        jsr show_item
        lda #0                  // the downed get back up
        sta who
up:     ldx who
        lda crew_hp,x
        bne up_next
        lda #1
        sta crew_hp,x
        jsr draw_party
        jsr lb_start
        jsr lb_crew_name
        Say(txt_gets_up)
        jsr lb_say
up_next:
        inc who
        lda who
        cmp #NCREW
        bne up
        jmp draw_party

game_over:
        lda #0
        sta $d015
        Line(txt_lost)
        jsr get_choice
        ldx #$ff
        txs
        jmp start

// ---------------------------------------------------------------- the monster
show_monster:
        ldx mtype
        lda mon_frame,x
        sta SPRPTR
        clc
        adc #1
        sta SPRPTR+1
        adc #1
        sta SPRPTR+2
        adc #1
        sta SPRPTR+3
        jsr mon_colour
        lda #$0f
        sta $d015
        rts

mon_colour:
        ldx mtype
        lda mon_col,x
        ldy #1                  // it stands 1 ahead: as foggy as that
        jsr fog_colour
set_mon_colour:
        sta $d027
        sta $d028
        sta $d029
        sta $d02a
        rts

// one frame: border flash, monster flash (call once a frame)
effects:
        jsr do_flash
        lda mflash
        beq !+
        dec mflash
        beq mon_colour
        lda #1
        jmp set_mon_colour
!:      rts

// ---------------------------------------------------------------- waiting

// a pause after a fight line; fire / space held: short
pause:
        lda #PAUSE
        sta pcount
pz:     jsr frame
        jsr effects
        lda $dc00
        and #$10
        beq pz_out
        lda $cb
        cmp #60                 // space
        beq pz_out
        dec pcount
        bne pz
pz_out: rts

// A = 1 fight, 2 defend, 3 run, 4 medkit (waits for a fresh press)
get_choice:
#if DEMO
        jsr pause
        lda #1
        rts
#endif
        lda #0
        sta armed
gc:     jsr frame
        jsr effects
        lda $dc00
        and #$10
        beq c_fight             // fire
        lda $cb
        cmp #21                 // F
        beq c_fight
        cmp #18                 // D
        beq c_defend
        cmp #17                 // R
        beq c_run
        cmp #36                 // M
        beq c_med
        cmp #60                 // space
        beq c_fight
        lda #1                  // nothing held: the next press counts
        sta armed
        bne gc
c_fight:
        lda #1
        bne c_got
c_defend:
        lda #2
        bne c_got
c_run:  lda #3
        bne c_got
c_med:  lda #4
c_got:  ldx armed
        beq gc
        rts

// ---------------------------------------------------------------- random
// A = 0-255
rnd:
        lda seed
        asl
        bcc !+
        eor #$1d
!:      eor $d41b
        eor $d012
        sta seed
        rts

// A = n (1-255) -> A = 0 to n-1
rand_n:
        sta t1
        jsr rnd
        sta t2
        lda #0
        ldx #8
        lsr t2
rn:     bcc rn_no
        clc
        adc t1
rn_no:  ror
        ror t2
        dex
        bne rn
        rts

// ---------------------------------------------------------------- the crew panel
// text row 20: name and HP (or DOWN) for each; green, yellow under half, red under a
// quarter. Whose turn it is: white.
draw_party:
        .for (var m=0; m<NCREW; m++) {
            ldx #7
!:          lda crew_pad + m*8,x
            sta SCREEN + 20*40 + 1 + m*13,x
            dex
            bpl !-
            ldx #m
            jsr crew_colour
            ldx #12
!:          sta COLRAM + 20*40 + 1 + m*13,x
            dex
            bpl !-
            lda crew_hp + m
            beq down
            jsr two_digits
            sta SCREEN + 20*40 + 1 + m*13 + 9
            lda t1
            sta SCREEN + 20*40 + 1 + m*13 + 8
            lda #32             // (the colour says how hurt)
            sta SCREEN + 20*40 + 1 + m*13 + 10
            sta SCREEN + 20*40 + 1 + m*13 + 11
            sta SCREEN + 20*40 + 1 + m*13 + 12
            jmp next
down:       ldx #4
!:          lda txt_down,x
            sta SCREEN + 20*40 + 1 + m*13 + 8,x
            dex
            bpl !-
next:
        }
        rts

// X = crew member -> A = colour
crew_colour:
        cpx cur
        bne !+
        lda #1                  // their turn
        rts
!:      lda crew_hp,x
        bne !+
        lda #11                 // down
        rts
!:      asl
        asl
        cmp crew_max,x          // under a quarter
        bcs !+
        lda #2
        rts
!:      lda crew_hp,x
        asl
        cmp crew_max,x          // under half
        bcs !+
        lda #7
        rts
!:      lda #5
        rts

// A = 0-99 -> A = ones digit, t1 = tens digit (a space for 0)
two_digits:
        ldx #0
td:     cmp #10
        bcc td_done
        sbc #10
        inx
        bne td
td_done:
        clc
        adc #48
        pha
        txa
        beq td_sp
        clc
        adc #48
        bne td_st
td_sp:  lda #32
td_st:  sta t1
        pla
        rts

// ---------------------------------------------------------------- building a log line
lb_start:
        lda #0
        sta lbp
        rts

// A/X = a 0-terminated string to add
lb_str:
        sta sp
        stx sp+1
        ldy #0
        ldx lbp
ls:     lda (sp),y
        beq ls_done
        cpx #LOG_W
        bcs ls_done
        sta linebuf,x
        inx
        iny
        bne ls
ls_done:
        stx lbp
        rts

// A = 0-99
lb_num:
        jsr two_digits
        pha
        lda t1
        cmp #32
        beq !+
        jsr lb_chr
!:      pla
lb_chr:
        ldx lbp
        sta linebuf,x
        inc lbp
        rts

lb_crew_name:
        ldx who
        lda crew_lo,x
        pha
        lda crew_hi,x
        tax
        pla
        jmp lb_str

lb_mon_name:
        ldy mtype
        lda mname_lo,y
        ldx mname_hi,y
        jmp lb_str

// end the line and show it
lb_end:
        ldx lbp
        lda #0
        sta linebuf,x
        lda #<linebuf
        ldx #>linebuf
        jmp message

// ... and wait a moment
lb_say:
        jsr lb_end
        jmp pause

linebuf: .fill LOG_W+1, 0

// ---------------------------------------------------------------- tables
crew_max:   .fill NCREW, CREW_HP.get(i)
crew_atk:   .fill NCREW, CREW_ATK.get(i)
crew_pad:
.for (var m=0; m<NCREW; m++) {
    .var s = CREW_NAME.get(m)
    .errorif s.size() > 7, "crew names: at most 7 letters"
    .text s
    .fill 8 - s.size(), 32
}
.var CREW_AT = List()
.for (var m=0; m<NCREW; m++) {
    .eval CREW_AT.add(*)
    .text CREW_NAME.get(m)
    .byte 0
}
crew_lo:    .fill NCREW, <CREW_AT.get(i)
crew_hi:    .fill NCREW, >CREW_AT.get(i)

mon_hp:     .fill NMON, MON_HP.get(i)
mon_atk:    .fill NMON, MON_ATK.get(i)
mon_max:    .fill NMON, MON_MAX.get(i)
mon_col:    .fill NMON, MON_COLOUR.get(i)
mon_frame:  .fill NMON, (MON_SPRITES - $c000)/64 + i*4
.var MNAME_AT = List()
.var VERB_AT = List()
.for (var m=0; m<NMON; m++) {
    .eval MNAME_AT.add(*)
    .text MON_NAME.get(m)
    .byte 0
    .eval VERB_AT.add(*)
    .text MON_VERB.get(m)
    .byte 0
}
mname_lo:   .fill NMON, <MNAME_AT.get(i)
mname_hi:   .fill NMON, >MNAME_AT.get(i)
verb_lo:    .fill NMON, <VERB_AT.get(i)
verb_hi:    .fill NMON, >VERB_AT.get(i)

txt_space:  .text " "
            .byte 0
txt_s:      .text "S"
            .byte 0
txt_dot:    .text "."
            .byte 0
txt_the:    .text "THE "
            .byte 0
txt_for:    .text " FOR "
            .byte 0
txt_block:  .text " BLOCK THE WAY!"
            .byte 0
txt_prompt: .text ": F)IGHT D)EFEND R)UN M)EDKIT"
            .byte 0
txt_ducks:  .text " DUCKS AND COVERS."
            .byte 0
txt_hits:   .text " HITS THE "
            .byte 0
txt_mon_down: .text " GOES DOWN."
            .byte 0
txt_crew_down: .text " IS DOWN!"
            .byte 0
txt_gets_up: .text " GETS BACK UP. OW."
            .byte 0
txt_run_ok: .text "YOU LEG IT. NOBODY SAW THAT."
            .byte 0
txt_run_fail: .text "NO WAY PAST. THEY CORNER YOU."
            .byte 0
txt_won:    .text "THE CREW WINS. BRAG ABOUT IT LATER."
            .byte 0
txt_lost:   .text "THE CREW IS LOST. FIRE TO START AGAIN."
            .byte 0
txt_down:   .text "DOWN "

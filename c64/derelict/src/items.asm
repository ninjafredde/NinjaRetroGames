// Decks, doors, items, medkits, the hatch and the end.

.const MED_HEAL = 12            // HP a medkit gives back
.const COL_DOOR   = 3           // cyan
.const COL_LOCKED = 2           // red

// ---------------------------------------------------------------- loading a deck
// deck = 0, 1, ...: unpack it into map + special, forget what was seen, go to its S
load_deck:
        ldx deck
        lda deck_lo,x
        sta sp
        lda deck_hi,x
        sta sp+1
        ldy #0
ld:     lda (sp),y
        pha
        and #3
        sta map,y
        pla
        lsr
        lsr
        sta special,y
        lda #0
        sta SEEN,y
        iny
        bne ld
        ldx deck
        lda deck_start,x
        sta pos
        lda deck_dir,x
        sta dir
        lda deck_floor,x
        sta $d022
        sta fog_floor
        lda deck_ceil,x
        sta $d023
        sta fog_ceil
        txa                     // the fog profile
        asl
        asl
        tay
        lda deck_fog,y
        sta fogtab
        lda deck_fog+1,y
        sta fogtab+1
        lda deck_fog+2,y
        sta fogtab+2
        lda deck_fog+3,y
        sta fogtab+3
        ldx deck
        lda deck_floor,x        // the screen byte: floor high, ceiling low
        asl
        asl
        asl
        asl
        ora deck_ceil,x
        sta view_scr
        lda pos
        sta prev_pos
        jsr set_dir
        jsr build_tabs
        jmp draw_minimap

// the view's colour tables for this deck: INKTAB[depth*16 + c] = c in this deck's colours
// (DECK_REMAP), dimmed for the fog at that depth; SCRTAB[depth][b] = both nibbles of b so
build_tabs:
        lda deck
        asl
        asl
        asl
        asl
        sta t0
        ldx #63
bi:     txa
        and #15
        ora t0
        tay
        lda deck_remap,y
        sta t1
        txa
        lsr
        lsr
        lsr
        lsr
        tay
        lda fogtab,y
        tay
        lda t1
        cpy #0
        beq bi_put
!:      stx fx
        tax
        lda ramp,x
        ldx fx
        dey
        bne !-
bi_put: sta INKTAB,x
        dex
        bpl bi
        lda #>SCRTAB
        sta bs_w+2
        lda #0
        sta d16
bs_d:   ldx #0
bs_b:   txa
        lsr
        lsr
        lsr
        lsr
        ora d16
        tay
        lda INKTAB,y
        asl
        asl
        asl
        asl
        sta t1
        txa
        and #15
        ora d16
        tay
        lda INKTAB,y
        ora t1
bs_w:   sta SCRTAB,x
        inx
        bne bs_b
        inc bs_w+2
        lda d16
        clc
        adc #16
        sta d16
        cmp #64
        bne bs_d
        rts

// ---------------------------------------------------------------- stepping on a cell
on_cell:
        ldx pos
        lda special,x
        bne !+
        jmp after_step
!:      cmp #SP_ITEM
        bcs oc_item
        tay                     // a note
        lda note_lo-1,y
        ldx note_hi-1,y
        jsr message
        jmp after_step
oc_item:
        cmp #SP_HATCH
        bcs oc_feature
        sec
        sbc #SP_ITEM
        tay
        lda #0                  // picked up: gone from the map
        sta special,x
        lda item_kind,y
        bne !+
        lda keys                // a keycard
        cmp #9
        bcs oc_said
        inc keys
        jmp oc_said
!:      cmp #1
        bne !+
        jsr add_med
        jmp oc_said
!:      lda bonus               // spanners
        clc
        adc #2
        sta bonus
oc_said:
        lda #$40
        jsr sound
        lda item_lo,y
        ldx item_hi,y
        jsr message
        jsr status
        jmp after_step
oc_feature:
        cmp #SP_HATCH
        bne the_end
        Line(txt_hatch)
        inc deck
        jsr load_deck
        jsr show_all
        lda #0
        sta steps
        Message(txt_deck2)
        rts

the_end:
        Line(txt_end1)
        Line(txt_end2)
        Line(txt_end3)
        jsr get_choice
        ldx #$ff
        txs
        jmp start

add_med:
        lda meds
        cmp #9
        bcs !+
        inc meds
!:      rts

// ---------------------------------------------------------------- medkits
// patch up whoever is missing the most HP (the downed too).
// C set = a medkit was used.
use_med:
        lda meds
        bne um_have
        Message(txt_no_med)
        clc
        rts
um_have:
        lda #0
        sta t1                  // the most missing so far
        ldx #NCREW-1
um_l:   lda crew_max,x
        sec
        sbc crew_hp,x
        beq um_n
        cmp t1
        bcc um_n
        sta t1
        stx t2                  // ... and who
um_n:   dex
        bpl um_l
        lda t1
        bne um_heal
        Message(txt_all_fine)
        clc
        rts
um_heal:
        dec meds
        ldx t2
        lda crew_hp,x
        clc
        adc #MED_HEAL
        cmp crew_max,x
        bcc !+
        lda crew_max,x
!:      sta crew_hp,x
        lda who
        pha
        stx who
        jsr lb_start
        jsr lb_crew_name
        Say(txt_patched)
        jsr lb_end
        pla
        sta who
        lda #$50
        jsr sound
        jsr draw_party
        jsr status
        sec
        rts

// ---------------------------------------------------------------- items in the view
// sprite 4: whatever lies 1 cell ahead (doubled), or else 2 cells ahead (normal size)
.const ITEM_SPR = 4
.const ITEM_X1 = 112 - 24       // one ahead: centred, standing on the floor
.const ITEM_Y1 = 148
.const ITEM_X2 = 112 - 12       // two ahead
.const ITEM_Y2 = 138
show_item:
        Cell(1, 0)
        bne si_none             // a wall or door right ahead
        lda special,x
        cmp #SP_ITEM
        bcs si_near
        Cell(2, 0)
        bne si_none
        lda special,x
        cmp #SP_ITEM
        bcc si_none
        sbc #SP_ITEM
        tax
        lda $d017               // normal size
        and #$ff - (1 << ITEM_SPR)
        sta $d017
        lda $d01d
        and #$ff - (1 << ITEM_SPR)
        sta $d01d
        lda #2
        sta si_depth
        lda #ITEM_X2
        ldy #ITEM_Y2
        jmp si_put
si_near:
        sbc #SP_ITEM
        tax
        lda $d017               // doubled
        ora #1 << ITEM_SPR
        sta $d017
        lda $d01d
        ora #1 << ITEM_SPR
        sta $d01d
        lda #1
        sta si_depth
        lda #ITEM_X1
        ldy #ITEM_Y1
si_put: sta $d000 + ITEM_SPR*2
        sty $d001 + ITEM_SPR*2
        txa
        clc
        adc #(ITEM_SPRITES - $c000)/64
        sta SPRPTR + ITEM_SPR
        lda item_col,x
        ldy si_depth
        jsr fog_colour
        sta $d027 + ITEM_SPR
        lda $d015
        ora #1 << ITEM_SPR
        sta $d015
        rts
si_none:
        lda $d015
        and #$ff - (1 << ITEM_SPR)
        sta $d015
        rts

item_col:   .fill NITEM_PICS, ITEM_COLOUR.get(i)

// ---------------------------------------------------------------- the view: doors
// A = piece; kind = what the cell is (1 wall, 2 door, 3 locked): doors in their colour
blit_k:
        ldx kind
        ldy door_col,x
        sty ovr
        jmp blit

// A = front piece 0-2 (the wall 1-3 ahead): the wall, then a door panel on it
blit_front:
        ldx #0
        stx ovr
        pha
        jsr blit
        pla
        ldx kind
        ldy door_col,x
        beq bf_done
        sty ovr
        cmp #2
        beq bf_far              // 3 ahead: the whole face in the door's colour
        clc
        adc #15                 // the door panel pieces
bf_far: jmp blit
bf_done:
        rts

door_col:   .byte 0, 0, COL_DOOR, COL_LOCKED
wall_col:   .byte 0, 12, COL_DOOR, COL_LOCKED   // minimap

// minimap: what a special cell looks like (1-9 notes, 10-13 items, hatch, end)
sp_char:    .byte 32
            .fill 9, 46 + ON_FLOOR              // .
            .fill 4, 42 + ON_FLOOR              // *
            .byte 8 + ON_FLOOR, 5 + ON_FLOOR    // H, E
sp_col:     .byte 0
            .fill 9, 7
            .fill 4, 13
            .byte 1, 1

// ---------------------------------------------------------------- tables
.var DECK_AT = List()
.for (var d=0; d<DECKS.size(); d++) {
    .var rows = DECKS.get(d)
    .errorif rows.size() != 16, "deck " + (d+1) + " needs 16 rows"
    .eval DECK_AT.add(*)
    .for (var y=0; y<16; y++) {
        .errorif rows.get(y).size() != 16, "deck " + (d+1) + " row " + y + " is not 16 wide"
        .for (var x=0; x<16; x++) .byte cellByte(rows.get(y).substring(x, x+1))
    }
}
.const NDECKS = DECKS.size()
deck_lo:    .fill NDECKS, <DECK_AT.get(i)
deck_hi:    .fill NDECKS, >DECK_AT.get(i)
deck_start: .fill NDECKS, findStart(DECKS.get(i))
deck_dir:   .fill NDECKS, DECK_DIR.get(i)
deck_floor: .fill NDECKS, DECK_FLOOR.get(i)
deck_ceil:  .fill NDECKS, DECK_CEIL.get(i)
deck_fights: .fill NDECKS, DECK_FIGHTS.get(i)
deck_lines: .fill NDECKS, DECK_LINES.get(i)
deck_lamps: .fill NDECKS, DECK_LAMPS.get(i)
deck_remap:
.for (var d=0; d<NDECKS; d++) .for (var c=0; c<16; c++) .byte DECK_REMAP.get(d).get(c)
deck_fog:
.for (var d=0; d<NDECKS; d++) .for (var k=0; k<4; k++) .byte DECK_FOG.get(d).get(k)

.const NITEMS = ITEM_KIND.size()
item_kind:  .fill NITEMS, ITEM_KIND.get(i)
.var ITEM_AT = List()
.for (var n=0; n<NITEMS; n++) {
    .errorif ITEM_TEXT.get(n).size() > LOG_W, "item line " + n + " is longer than " + LOG_W
    .eval ITEM_AT.add(*)
    .text ITEM_TEXT.get(n)
    .byte 0
}
item_lo:    .fill NITEMS, <ITEM_AT.get(i)
item_hi:    .fill NITEMS, >ITEM_AT.get(i)

txt_door:     .text "THE DOOR HISSES OPEN."
              .byte 0
txt_locked:   .text "LOCKED. THE READER WANTS A KEYCARD."
              .byte 0
txt_key_used: .text "THE KEYCARD WORKS. FINALLY."
              .byte 0
txt_no_med:   .text "NO MEDKITS LEFT."
              .byte 0
txt_all_fine: .text "EVERYONE IS FINE. NO MEDKIT USED."
              .byte 0
txt_patched:  .text " GETS PATCHED UP."
              .byte 0
txt_loot:     .text "IT DROPPED A MEDKIT. NICE."
              .byte 0
txt_hatch:    .text "DOWN THE HATCH YOU GO..."
              .byte 0
txt_deck2:    .text "A NEW DECK. IT SMELLS WORSE DOWN HERE."
              .byte 0
txt_end1:     .text "THE BRIDGE! THE CHAIR IS EMPTY."
              .byte 0
txt_end2:     .text "THE SHIP IS YOURS. WHAT A WASTE."
              .byte 0
txt_end3:     .text "THE END. FIRE TO PLAY AGAIN."
              .byte 0
txt_inv:      .text "MED  KEY"
              .byte 0

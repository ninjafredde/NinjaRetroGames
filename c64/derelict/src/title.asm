// The title screen: art/title.png, the whole screen in multicolour bitmap, until fire
// (or space). Shown at the start and after the end or a lost game.
//
// tools/art.py packs it (src/gen/title_art.asm): the bitmap a row of cells at a time
// (byte 0 of all 40 cells, then byte 1, ...), the screen bytes, the colours; each
// run-length packed (TITLE_ESC, count, value = a run; TITLE_ESC, 0 = the end).
// It's unpacked into bitmap B's place first (free until the game starts), then
// put in order into bitmap A.

.const COL_FIRE = 1
.const FIRE_ROW = 22
.const FIRE_COL = 15

#import "gen/title_art.asm"

title:
        sei                     // no interrupts at all on the title screen
        lda #0
        sta $d01a
        sta $d015               // no sprites
        lda #$ff
        sta $d019
        lda #$7f
        sta $dc0d
        lda $dc0d
        lda #$0b                // screen off while unpacking
        sta $d011
        lda $dd00               // bank 3
        and #$fc
        sta $dd00
        jsr copy_chars
        Unpack(title_bm, BITMAP_B)
        Unpack(title_scr, SCREEN)
        Unpack(title_col, COLRAM)
        jsr untangle
        BmText(txt_fire, FIRE_ROW, FIRE_COL, COL_FIRE)
        lda #$18
        sta $d016
        lda #$08
        sta $d018
        lda #$3b
        sta $d011
#if DEMO
        ldx #50                 // the demo: a second of it, then on
!:      jsr vsync
        dex
        bne !-
        rts
#endif
!:      jsr fire_down           // let go of fire first (from the last game)
        bne !-
        lda #0
        sta t0
t_wait: jsr vsync
        inc t0
        lda t0                  // PRESS FIRE blinks
        and #31
        bne t_key
        lda t0
        and #32
        beq !+
        lda #COL_FIRE
!:      ldx #9
!:      sta COLRAM + FIRE_ROW*40 + FIRE_COL,x
        dex
        bpl !-
t_key:  jsr fire_down
        beq t_wait
        rts

// A = 1 (Z clear) when fire (port 2) or space is down
fire_down:
        lda #$7f
        sta $dc00
        lda $dc00
        and #$10
        beq !+
        lda $dc01
        and #$10
        beq !+
        lda #0
        rts
!:      lda #1
        rts

// wait for the bottom of the screen
vsync:
!:      lda $d012
        cmp #250
        bne !-
!:      lda $d012
        cmp #250
        beq !-
        rts

// Unpack(src, dst)
.macro Unpack(src, dst) {
        lda #<src
        sta pp
        lda #>src
        sta pp+1
        lda #<dst
        sta dp
        lda #>dst
        sta dp+1
        jsr unpack
}

// pp = packed data -> dp on
unpack:
        ldy #0
unp_next:
        lda (pp),y
        jsr unp_inc
        cmp #TITLE_ESC
        beq unp_run
        sta (dp),y
        inc dp
        bne unp_next
        inc dp+1
        jmp unp_next
unp_run: lda (pp),y              // count (0: the end)
        beq unp_done
        tax
        jsr unp_inc
        lda (pp),y              // value
        jsr unp_inc
!:      sta (dp),y
        inc dp
        bne !+
        inc dp+1
!:      dex
        bne !--
        jmp unp_next
unp_done:
        rts
unp_inc: inc pp
        bne !+
        inc pp+1
!:      rts

// bitmap B's place (bytes in packing order) -> bitmap A (cells in order). $a000 is
// under the BASIC ROM: reading it needs BASIC switched out (interrupts are off)
untangle:
        lda #$36
        sta $01
        lda #<BITMAP
        sta dp
        lda #>BITMAP
        sta dp+1
        lda #<BITMAP_B
        sta rowa
        lda #>BITMAP_B
        sta rowa+1
        lda #25
        sta frx
ut_row: .for (var b=0; b<8; b++) {      // this row's 8 byte rows
            lda rowa
            clc
            adc #<(b*40)
            sta ut_src + b*7 + 1
            lda rowa+1
            adc #>(b*40)
            sta ut_src + b*7 + 2
        }
        ldx #0
ut_cell:
ut_src: .for (var b=0; b<8; b++) {      // 7 bytes each
            lda $ffff,x
            ldy #b
            sta (dp),y
        }
        lda dp
        clc
        adc #8
        sta dp
        bcc !+
        inc dp+1
!:      inx
        cpx #40
        bne ut_cell
        lda rowa
        clc
        adc #<320
        sta rowa
        lda rowa+1
        adc #>320
        sta rowa+1
        dec frx
        beq !+
        jmp ut_row
!:      lda #$37
        sta $01
        rts

txt_fire:   .text "PRESS FIRE"
            .byte 0


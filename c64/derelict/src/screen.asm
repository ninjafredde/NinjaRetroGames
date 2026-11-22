// The split screen: multicolour bitmap on top (rows 0-19: the frame, the view, the
// title, the minimap), ordinary text below (rows 20-24: crew, status, log). A raster
// interrupt switches the mode at row 20 and back at the top of every frame.
//
// The bitmap part is double buffered: two copies, A in VIC bank 3 and B in bank 2, laid
// out the same way 16K apart. The view is drawn into the one not on screen, and the
// interrupt flips to it below the view (and copies the view's colours into colour RAM,
// which there is only one of). The text rows always come from bank 3.
//
//   bank 3 (A)                         bank 2 (B)
//   $c000  screen A + the text rows    $8000  screen B
//   $c400  monster sprites             $8400  monster sprites (a copy)
//   $c800  the text rows' characters   $8800  (work memory: the VIC never looks here)
//   $cc00  item sprites                $8c00  item sprites (a copy)
//   $e000  bitmap A (under the KERNAL) $a000  bitmap B (under BASIC)
//
// A bitmap cell (8 x 8 pixels, 4 fat pixels wide) shows 4 colours: pixel value
// 00 black ($d021), 01 the screen byte's high nibble, 10 its low nibble, 11 the cell's
// colour RAM (the "ink").

.const SPLIT_LINE = 51 + 8*20 - 3       // the interrupt just before text row 20
.const TOP_LINE   = 8                   // ... and back to bitmap above the picture
.const BANK_B     = $4000               // copy B is this much lower than copy A
.const RAIL       = 112                 // the rails' characters (4)
.const RAIL_CHARS = 4
.const COL_RAIL   = 12

#import "gen/frame_art.asm"             // the frame (art/frame.png)

// ---------------------------------------------------------------- set up
screen_init:
        sei
        lda #$7f                // no CIA timer interrupts: ours drive the KERNAL's keyboard scan
        sta $dc0d
        lda $dc0d
        lda $dd00               // VIC bank 3
        and #$fc
        sta $dd00
        lda #<irq
        sta $0314
        lda #>irq
        sta $0315
        lda #SPLIT_LINE
        sta $d012
        lda #$3b
        sta $d011
        lda #$18
        sta $d016
        lda #$08
        sta $d018
        lda #0
        sta irq_top
        sta shown
        sta flip_req
        lda #1
        sta $d01a
        lda #$33                // the ROM characters -> $c800 (128 of them)
        sta $01
        ldx #0
!:      .for (var p=0; p<4; p++) {
            lda $d000 + p*256,x
            sta CHARSET + p*256,x
        }
        inx
        bne !-
        lda #$37
        sta $01
        cli
        ldx #RAIL_CHARS*8-1     // the rails down the sides of the text rows
!:      lda rail_chars,x
        sta CHARSET + RAIL*8,x
        dex
        bpl !-
        // the sprites, in both banks
        Copy(mon_sprite_data, MON_SPRITES, NMON*4*64)
        Copy(item_sprite_data, ITEM_SPRITES, NITEM_PICS*64)
        Copy(mon_sprite_data, MON_SPRITES - BANK_B, NMON*4*64)
        Copy(item_sprite_data, ITEM_SPRITES - BANK_B, NITEM_PICS*64)
        // clear both bitmaps, both screens and the colours; text rows: spaces
        lda #<BITMAP
        sta dp
        lda #>BITMAP
        sta dp+1
        lda #<BITMAP_B
        sta pp
        lda #>BITMAP_B
        sta pp+1
        ldx #32
        lda #0
        tay
!:      sta (dp),y
        sta (pp),y
        iny
        bne !-
        inc dp+1
        inc pp+1
        dex
        bne !-
        ldx #0
        lda #0
!:      .for (var p=0; p<4; p++) {
            sta SCREEN + p*$100,x
            sta SCREEN_B + p*$100,x
            sta COLRAM + p*$100,x
        }
        inx
        bne !-
        ldx #0                  // the text rows: spaces
!:      lda #32
        sta SCREEN + 20*40,x
        lda #COL_TEXT
        sta COLRAM + 20*40,x
        inx
        cpx #5*40
        bne !-
        .for (var r=20; r<25; r++) {
            lda #RAIL + (r & 1)
            sta SCREEN + r*40
            lda #RAIL + 2 + (r & 1)
            sta SCREEN + r*40 + 39
            lda #COL_RAIL
            sta COLRAM + r*40
            sta COLRAM + r*40 + 39
        }
        rts

// Copy(src, dst, bytes): a straight copy at start
.macro Copy(src, dst, bytes) {
        lda #<src
        sta pp
        lda #>src
        sta pp+1
        lda #<dst
        sta dp
        lda #>dst
        sta dp+1
        ldx #>(bytes + 255)
        ldy #0
!:      lda (pp),y
        sta (dp),y
        iny
        bne !-
        inc pp+1
        inc dp+1
        dex
        bne !-
}

// the rails (hi-res characters): left, left with a bolt, right, right with a bolt
rail_chars:
        .byte $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc
        .byte $fc, $fc, $fc, $cc, $cc, $fc, $fc, $fc
        .byte $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f
        .byte $3f, $3f, $3f, $33, $33, $3f, $3f, $3f

// ---------------------------------------------------------------- the interrupt
irq:
        lda $d019
        sta $d019
        lda irq_top
        bne irq_bitmap
        lda $dd00               // bank 3 for the text rows: already on the last line of
        and #$fc                // the frame's bottom bar (the same in both copies)
        tax
        lda #SPLIT_LINE + 2     // wait for that line (210)
!:      cmp $d012
        bne !-
        stx $dd00
        ldx #8                  // ... then to its right border (about cycle 57 of 63)
!:      dex
        bne !-
        lda #$1b                // text, all three switched in the border: line 210's
        ldx #$02                // right edge and 211's left edge (211 is a badline: the
        ldy #$08                // VIC stops the CPU from about cycle 12 on)
        sta $d011
        sty $d016
        stx $d018               // screen $c000, characters $c800
        lda #TOP_LINE
        sta $d012
        inc irq_top
        lda flip_req            // a new picture is ready: its colours, and show it next
        beq !+
        jsr copy_colours
        lda shown
        eor #1
        sta shown
        lda #0
        sta flip_req
!:      jmp $ea81               // just return
irq_bitmap:
        lda #$3b                // multicolour bitmap
        sta $d011
        lda #$18
        sta $d016
        lda #$08                // screen at +$0000, bitmap at +$2000 (in either bank)
        sta $d018
        lda $dd00               // bank 3 (A) or 2 (B)
        and #$fc
        ora shown
        sta $dd00
        lda #SPLIT_LINE
        sta $d012
        lda #0
        sta irq_top
        inc frames
        jmp $ea31               // the KERNAL's keyboard scan, then return

// the new picture's colours into colour RAM (called below the view)
copy_colours:
        ldx #VW-1
!:      .for (var r=0; r<NSHOW; r++) {
            lda CSH + r*VW,x
            sta COLRAM + (VIEW_R0 + r)*40 + VX,x
        }
        dex
        bmi !+
        jmp !-
!:      rts

// wait for the next frame
frame:
        lda frames
!:      cmp frames
        beq !-
        rts

// ---------------------------------------------------------------- drawing cells
// pat_out: the 8 bytes at pp into bitmap cell (cr, cc) of both copies, screen byte
// cscr, ink ccol
pat_out:
        ldx cr
        ldy cc
        lda bm_lo,x
        clc
        adc c8_lo,y
        sta dp
        lda bm_hi,x
        adc c8_hi,y
        sta dp+1
        ldy #7
!:      lda (pp),y
        sta (dp),y
        dey
        bpl !-
        lda dp+1
        sec
        sbc #>BANK_B
        sta dp+1
        ldy #7
!:      lda (pp),y
        sta (dp),y
        dey
        bpl !-
        lda scr_lo,x
        sta sr
        lda scr_hi,x
        sta sr+1
        ldy cc
        lda cscr
        sta (sr),y
        lda sr+1
        sec
        sbc #>BANK_B
        sta sr+1
        lda cscr
        sta (sr),y
        lda scr_hi,x
        clc
        adc #>(COLRAM-SCREEN)
        sta sr+1
        lda ccol
        sta (sr),y
        rts

// A = a view code, Y = ink: the code's pattern at (cr, cc)
cell_out:
        sty ccol
cell_out_c:
        tax
        lda mc_lo,x
        sta pp
        lda mc_hi,x
        sta pp+1
        jmp pat_out

// tp = a 0-terminated string, at (cr, cc) on, in ink ccol: ROM letters, fattened
bm_text:
        ldy #0
bt:     lda (tp),y
        bne !+
        rts
!:      sty bty
        ldx #0
        stx pp+1
        asl
        rol pp+1
        asl
        rol pp+1
        asl
        rol pp+1
        sta pp
        lda pp+1
        clc
        adc #>CHARSET
        sta pp+1
        ldy #7
!:      lda (pp),y
        tax
        lda fatten,x
        sta tmp8,y
        dey
        bpl !-
        lda #<tmp8
        sta pp
        lda #>tmp8
        sta pp+1
        jsr pat_out
        inc cc
        ldy bty
        iny
        bne bt
        rts

// ---------------------------------------------------------------- the view on screen
// The view's rows 1-18 (row 0 and 19 are under the frame), in two halves of 9 rows so
// a cell's number fits in X. Each cell: a piece's (BUFH 0/1: which 256 patterns) or the
// background's (BUFH $80); its screen byte and ink through this deck's tables (deck
// colours + fog) into SSH / CSH; its 8 pattern bytes straight into the hidden bitmap.
.const HALF = NSHOW/2*VW                // 180 cells

.macro Copy8(set) {
        .for (var b=0; b<8; b++) {
            .if (set == 0) lda pat0 + b*256,x
            .if (set == 1) lda pat1 + b*PAT1_N,x
            sta (dpb + b*2),y
        }
}

present:
        lda flip_req            // the last one isn't on screen yet: wait
        bne present
        lda shown               // draw into the other copy
        bne pr_toA
        lda #<(BITMAP_B + VIEW_R0*320 + VX*8)
        sta rowa
        lda #>(BITMAP_B + VIEW_R0*320 + VX*8)
        sta rowa+1
        jmp pr_go
pr_toA: lda #<(BITMAP + VIEW_R0*320 + VX*8)
        sta rowa
        lda #>(BITMAP + VIEW_R0*320 + VX*8)
        sta rowa+1
pr_go:  jsr set_rows
        .for (var h=0; h<2; h++) {
            .var o = h*HALF
            .var vo = VIEW_R0*VW + o
            Op(o1, BUFH + vo)
            Op(o6, BUFH + vo)
            Op(o2, BUFS + vo)
            Op(o4, BUFK + vo)
            Op(o7, BUFL + vo)
            Op(o8, BUFL + vo)
            Op(o3, SSH + o)
            Op(o10, SSH + o)
            Op(o5, CSH + o)
            Op(o12, CSH + o)
            Op(o9, bg_s + vo)
            Op(o11, bg_k + vo)
            Op(o13, bg_h + vo)
            Op(o14, bg_l + vo)
            Op(o15, bg_l + vo)
            lda #VW
            sta rowend
            ldx #0
            jsr pr_cell
        }
        lda shown               // the screen bytes into the hidden copy's screen
        bne pr_scrA
        CopyScreen(SCREEN_B)
        jmp pr_flip
pr_scrA:
        CopyScreen(SCREEN)
pr_flip:
        lda #1                  // show it (the interrupt flips below the view)
        sta flip_req
        rts

.macro Op(label, addr) {
        lda #<addr
        sta label+1
        lda #>addr
        sta label+2
}

.macro CopyScreen(scr) {
        ldx #VW-1
!:      .for (var r=0; r<NSHOW; r++) {
            lda SSH + r*VW,x
            sta scr + (VIEW_R0 + r)*40 + VX,x
        }
        dex
        bmi !+
        jmp !-
!:
}

// the 8 bitmap pointers for the row at rowa (rowa's low byte is a multiple of 8)
set_rows:
        lda rowa+1
        .for (var b=0; b<8; b++) sta dpb + b*2 + 1
        lda rowa
        sta dpb
        clc
        .for (var b=1; b<8; b++) {
            adc #1
            sta dpb + b*2
        }
        rts

pr_cell:
o1:     lda $ffff,x             // BUFH
        bpl !+
        jmp pr_bg
!:
o2:     ldy $ffff,x             // BUFS
        lda SCRT,y
o3:     sta $ffff,x             // SSH
o4:     ldy $ffff,x             // BUFK
        lda INKTAB,y
o5:     sta $ffff,x             // CSH
        ldy col8,x
        stx ci
o6:     lda $ffff,x             // BUFH
        bne pr_p1
o7:     lda $ffff,x             // BUFL
        tax
        Copy8(0)
        ldx ci
        jmp pr_next
pr_p1:
o8:     lda $ffff,x             // BUFL
        tax
        Copy8(1)
        ldx ci
        jmp pr_next
pr_bg:
o9:     ldy $ffff,x             // bg_s
        lda SCRT,y
o10:    sta $ffff,x             // SSH
o11:    ldy $ffff,x             // bg_k
        lda INKTAB,y
o12:    sta $ffff,x             // CSH
        ldy col8,x
        stx ci
o13:    lda $ffff,x             // bg_h
        bne pr_b1
o14:    lda $ffff,x             // bg_l
        tax
        Copy8(0)
        ldx ci
        jmp pr_next
pr_b1:
o15:    lda $ffff,x             // bg_l
        tax
        Copy8(1)
        ldx ci
pr_next:
        inx
        cpx rowend
        beq pr_row
        jmp pr_cell
pr_row: lda rowa                // the next row: 320 bytes on
        clc
        adc #<320
        sta rowa
        lda rowa+1
        adc #>320
        sta rowa+1
        jsr set_rows
        cpx #HALF
        beq !+
        lda rowend
        clc
        adc #VW
        sta rowend
        jmp pr_cell
!:      rts

col8:   .fill HALF, (i - VW*floor(i/VW))*8

// ---------------------------------------------------------------- the frame and the title
// (art/frame.png, see tools/art.py)
draw_frame:
        ldx #0
!:      stx frx
        lda fr_row,x
        sta cr
        lda fr_col,x
        sta cc
        lda fr_scr,x
        sta cscr
        lda fr_ink,x
        sta ccol
        lda fr_pl,x
        sta pp
        lda fr_ph,x
        sta pp+1
        jsr pat_out
        ldx frx
        inx
        cpx #NFRAME
        bne !-
        BmText(txt_title1, 0, MINI_COL, COL_TITLE)
        BmText(txt_title2, 1, MINI_COL, COL_TITLE)
        rts

.macro BmText(txt, row, col, ink) {
        lda #<txt
        sta tp
        lda #>txt
        sta tp+1
        lda #row
        sta cr
        lda #col
        sta cc
        lda #ink
        sta ccol
        jsr bm_text
}

// ---------------------------------------------------------------- the minimap (in the bitmap)
// X = a map cell: draw it (unseen: black, wall: block, floor, notes/items, you: an arrow)
mini_cell:
        stx mi
        txa
        lsr
        lsr
        lsr
        lsr
        clc
        adc #MINI_ROW
        sta cr
        txa
        and #15
        clc
        adc #MINI_COL
        sta cc
        lda view_scr
        sta cscr
        cpx pos
        beq mc_you
        lda SEEN,x
        beq mc_blank
        lda map,x
        bne mc_wall
        lda special,x
        bne mc_spec
        lda #C_FLOOR
        ldy #0
        jmp cell_out
mc_blank:
        lda #C_DARK
        ldy #0
        jmp cell_out
mc_wall:
        tay
        lda wall_col,y
        tay
        lda #G_SOLID
        jmp cell_out
mc_spec:
        tay
        lda sp_col,y
        sta ccol
        lda sp_char,y
        jmp cell_out_c
mc_you:
        ldy dir
        lda arrow_code,y
        ldy #7
        jmp cell_out

draw_minimap:
        ldx #0
!:      jsr mini_cell
        ldx mi
        inx
        bne !-
        rts

// ---------------------------------------------------------------- tables
bm_lo:  .fill 25, <(BITMAP + i*320)
bm_hi:  .fill 25, >(BITMAP + i*320)
scr_lo: .fill 25, <(SCREEN + i*40)
scr_hi: .fill 25, >(SCREEN + i*40)
c8_lo:  .fill 40, <(i*8)
c8_hi:  .fill 40, >(i*8)
// a ROM letter's bit pairs -> fat pixels in the ink (any lit pixel lights the pair)
fatten: .fill 256, (((i>>6)&3)!=0 ? $c0 : 0) | (((i>>4)&3)!=0 ? $30 : 0) | (((i>>2)&3)!=0 ? $0c : 0) | ((i&3)!=0 ? $03 : 0)
tmp8:   .fill 8, 0
mc_lo:  .fill 256, <(mc_patterns + i*8)
mc_hi:  .fill 256, >(mc_patterns + i*8)


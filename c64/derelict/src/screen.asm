// The split screen: multicolour bitmap on top (rows 0-19: the view, the title, the
// minimap), ordinary text below (rows 20-24: crew, status, log). A raster interrupt
// switches the mode at row 20 and back at the top of every frame.
//
// VIC bank 3 ($c000-$ffff):
//   $c000  screen matrix: bitmap colours in rows 0-19, characters in rows 20-24
//   $c400  monster sprites (copied there at start)
//   $c800  the character set for the text rows (copied from the ROM)
//   $cc00  item sprites
//   $e000  the bitmap (RAM under the KERNAL ROM: the VIC sees RAM, the CPU writes RAM)
//
// A bitmap cell (8 x 8 pixels, 4 fat pixels wide) shows 4 colours: pixel value
// 00 black ($d021), 01 the screen byte's high nibble (floor), 10 its low nibble
// (ceiling), 11 the cell's colour RAM (the "ink"). The view is still drawn as a grid
// of codes + inks (BUFC/BUFK); present turns every code into an 8-byte pattern.


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
        // the sprites
        Copy(mon_sprite_data, MON_SPRITES, NMON*4*64)
        Copy(item_sprite_data, ITEM_SPRITES, NITEM_PICS*64)
        // clear the bitmap, the screen and the colours; text rows: spaces
        lda #<BITMAP
        sta dp
        lda #>BITMAP
        sta dp+1
        ldx #32
        lda #0
        tay
!:      sta (dp),y
        iny
        bne !-
        inc dp+1
        dex
        bne !-
        ldx #0
        lda #0
!:      sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$300,x
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

// ---------------------------------------------------------------- the interrupt
irq:
        lda $d019
        sta $d019
        lda irq_top
        bne irq_bitmap
        lda #SPLIT_LINE + 2     // wait for the first line of text row 20
!:      cmp $d012
        bcs !-
        lda #$1b                // text
        sta $d011
        lda #$08
        sta $d016
        lda #$02                // screen $c000, characters $c800
        sta $d018
        lda #TOP_LINE
        sta $d012
        inc irq_top
        jmp $ea81               // just return
irq_bitmap:
        lda #$3b                // multicolour bitmap
        sta $d011
        lda #$18
        sta $d016
        lda #$08                // screen $c000, bitmap $e000
        sta $d018
        lda #SPLIT_LINE
        sta $d012
        lda #0
        sta irq_top
        inc frames
        jmp $ea31               // the KERNAL's keyboard scan, then return

// wait for the next frame
frame:
        lda frames
!:      cmp frames
        beq !-
        rts

// ---------------------------------------------------------------- drawing cells
// pat_out: the 8 bytes at pp into bitmap cell (cr, cc), screen byte cscr, ink ccol
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
        lda scr_lo,x
        sta sr
        lda scr_hi,x
        sta sr+1
        ldy cc
        lda cscr
        sta (sr),y
        lda sr+1
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
// every cell: its pattern into the bitmap, its screen byte and ink through this deck's
// tables for its depth (deck colours, fog)
present:
        lda #<BUFL
        sta bc
        lda #>BUFL
        sta bc+1
        lda #<BUFH
        sta bh
        lda #>BUFH
        sta bh+1
        lda #<BUFS
        sta bs
        lda #>BUFS
        sta bs+1
        lda #<BUFK
        sta bk
        lda #>BUFK
        sta bk+1
        lda #<BUFD
        sta bd
        lda #>BUFD
        sta bd+1
        lda #0
        sta stp
        lda #<(BITMAP + VX*8)
        sta dp
        lda #>(BITMAP + VX*8)
        sta dp+1
        lda #<(SCREEN + VY*40 + VX)
        sta sr
        lda #>(SCREEN + VY*40 + VX)
        sta sr+1
        lda #<(COLRAM + VY*40 + VX)
        sta crp
        lda #>(COLRAM + VY*40 + VX)
        sta crp+1
        lda #VH
        sta prow
pr_row: ldy #0
pr_cell:
        sty pcol
        lda (bc),y
        sta pp
        lda (bh),y
        sta pp+1
        lda (bd),y              // depth -> its tables
        tax
        lda scr_page,x
        sta stp+1
        lda ink_base,x
        sta ib
        lda (bk),y
        and #15
        ora ib
        tax
        lda INKTAB,x
        sta (crp),y
        lda (bs),y
        tay
        lda (stp),y
        ldy pcol
        sta (sr),y
        .for (var b=7; b>=0; b--) {
            ldy #b
            lda (pp),y
            sta (dp),y
        }
        lda dp
        clc
        adc #8
        sta dp
        bcc !+
        inc dp+1
!:      ldy pcol
        iny
        cpy #VW
        bne pr_cell
        .for (var n=0; n<5; n++) {      // next row: the five buffers
            .var zpv = List().add(bc, bh, bs, bk, bd).get(n)
            lda zpv
            clc
            adc #VW
            sta zpv
            bcc !+
            inc zpv+1
!:
        }
        lda sr
        clc
        adc #40
        sta sr
        bcc !+
        inc sr+1
!:      lda crp
        clc
        adc #40
        sta crp
        bcc !+
        inc crp+1
!:      lda dp
        clc
        adc #<(320 - VW*8)
        sta dp
        lda dp+1
        adc #>(320 - VW*8)
        sta dp+1
        dec prow
        beq !+
        jmp pr_row
!:      rts

scr_page:   .byte >SCRTAB, >SCRTAB + 1, >SCRTAB + 2, >SCRTAB + 3
ink_base:   .byte 0, 16, 32, 48

// the frame either side of the view, and the title
draw_frame:
        lda view_scr
        sta cscr
        ldx #VH-1
!:      stx cr
        lda #VX-1
        sta cc
        lda #G_SOLID
        ldy #COL_FRAME
        jsr cell_out
        lda #VX+VW
        sta cc
        lda #G_SOLID
        ldy #COL_FRAME
        jsr cell_out
        ldx cr
        dex
        bpl !-
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

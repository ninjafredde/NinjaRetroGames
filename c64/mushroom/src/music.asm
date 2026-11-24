#import "notes.asm"

// A tiny 3-voice music player and the title tune.
//
// A tune is three voices written as text, read left to right, looping:
//   a4:4    note a, octave 4, 4 rows long (no ":n" = 1 row)
//   c#5:2   sharps with #   (notes: c c# d d# e f f# g g# a a# b)
//   r:8     rest, 8 rows
//   @2      switch to instrument 2
//   |       bar line, ignored (for your eyes)
// One row is TEMPO frames (50 frames a second).
//
// music_start: begin playing from a raster interrupt (title screen)
// music_stop:  stop, and give the SID back to the sound effects

.const TEMPO = 6                // frames per row: 6 = 125 bpm in 16ths

// ---------------------------------------------------------------- instruments
// wave: $11 triangle, $21 saw, $41 pulse, $81 noise (the 1 = gate)
// ad/sr: SID envelope; pw: pulse width $000-$fff; sweep: added to pw each
// frame, bouncing between $200 and $e00; arp: 0 none, 1 major, 2 minor
.macro Instrument(wave, ad, sr, pw, sweep, arp) {
        .byte wave, ad, sr, <pw, >pw, sweep & $ff, arp, 0
}
inst_tab:
        Instrument($41, $0a, $a9, $0800,  16, 0)   // 0 lead: sweeping pulse
        Instrument($41, $00, $70, $0400,   0, 1)   // 1 major chord
        Instrument($41, $00, $70, $0400,   0, 2)   // 2 minor chord
        Instrument($41, $07, $00, $0400,  24, 0)   // 3 bass: plucked pulse

arp_tab:
        .byte 0, 0, 0                   // none
        .byte 0, 4, 7                   // major
        .byte 0, 3, 7                   // minor

// ---------------------------------------------------------------- the tune
.function pump(lo, hi) {                // a bar of eighth-note bass
    .return " "+lo+":2 "+lo+":2 "+hi+":2 "+lo+":2 "+lo+":2 "+hi+":2 "+lo+":2 "+hi+":2 |"
}

// something growing in the dark: E minor, sneaky
tune_v1:  Voice("@0 | e5:2 r:2 e5:2 g5:2 a5:4 g5:2 e5:2 | d5:4 b4:4 r:4 b4:2 d5:2 " +
                "| e5:2 r:2 e5:2 g5:2 b5:4 a5:2 g5:2 | a5:6 g5:2 e5:8 " +
                "| c5:4 e5:4 g5:4 e5:4 | d5:4 f#5:4 a5:4 f#5:4 " +
                "| e5:2 g5:2 b5:2 e6:2 d6:4 b5:4 | e5:12 r:4 |")

tune_v2:  Voice("@2 e4:16 | e4:16 | e4:16 | a4:16 | @1 c4:16 | d4:16 | @2 e4:16 | e4:16 |")

tune_v3:  Voice("@3 |" + pump("e2", "e3") + pump("e2", "e3") + pump("e2", "e3") + pump("a2", "a3") +
                         pump("c3", "c4") + pump("d3", "d4") + pump("e2", "e3") + pump("b1", "b2"))

// get ready: a rising A major fanfare, 12 rows (fits the mothership rising)
ready_v1: Voice("@0 a4:2 c#5:2 e5:2 a5:6 end")
ready_v2: Voice("@1 r:2 a3:10 end")
ready_v3: Voice("@3 e2:2 e2:2 e2:2 a2:6 end")

// game over: falling, A minor - E - A minor, 30 rows
over_v1:  Voice("@0 e5:3 d5:3 c5:3 b4:3 | a4:4 g#4:4 | a4:10 end")
over_v2:  Voice("@2 a3:12 | @1 e3:8 | @2 a3:10 end")
over_v3:  Voice("@3 a2:6 g2:6 | f2:4 e2:4 | a1:10 end")

// ---------------------------------------------------------------- player
// voice state, one byte per voice
m_ptr_lo:   .fill 3, 0
m_ptr_hi:   .fill 3, 0
m_wait:     .fill 3, 0          // frames left of this note
m_note:     .fill 3, 0
m_wave:     .fill 3, 0
m_pw_lo:    .fill 3, 0
m_pw_hi:    .fill 3, 0
m_sweep:    .fill 3, 0
m_arp:      .fill 3, 0
m_arp_i:    .byte 0
m_tmp:      .byte 0
m_start_lo: .fill 3, 0
m_start_hi: .fill 3, 0
m_on:       .fill 3, 0          // 0: voice finished or silent
// songs: 0 title, 1 get ready, 2 game over
song_lo:    .byte <tune_v1, <tune_v2, <tune_v3, <ready_v1, <ready_v2, <ready_v3, <over_v1, <over_v2, <over_v3
song_hi:    .byte >tune_v1, >tune_v2, >tune_v3, >ready_v1, >ready_v2, >ready_v3, >over_v1, >over_v2, >over_v3
m_voff:     .byte 0, 7, 14      // SID register offset of each voice
m_rows:     .fill 43, i*TEMPO   // rows -> frames

// A = song. In game, the frame loop calls music_play; on the title the
// interrupt does (music_start).
music_begin:
        sta m_tmp
        asl
        adc m_tmp
        tay
        ldx #0
!:      lda song_lo,y
        sta m_start_lo,x
        sta m_ptr_lo,x
        lda song_hi,y
        sta m_start_hi,x
        sta m_ptr_hi,x
        lda #1
        sta m_wait,x
        sta m_on,x
        lda #0
        sta m_note,x
        iny
        inx
        cpx #3
        bne !-
        lda #0                          // the sound effects let go of the SID
        sta shot_t
        sta boom_t
        lda #$0f
        sta $d418
        rts

music_start:
        jsr sid_init
        lda #0                          // the title tune
        jsr music_begin
        sei
        lda #$7f                        // no CIA timer interrupts
        sta $dc0d
        lda $dc0d
        lda #<music_irq
        sta $0314
        lda #>music_irq
        sta $0315
        lda #250                        // a raster interrupt at line 250
        sta $d012
        lda $d011
        and #$7f
        sta $d011
        lda #1
        sta $d01a
        sta $d019
        cli
        rts

music_irq:
        lda #$ff                        // acknowledge
        sta $d019
        jsr music_play
        jmp $ea81                       // restore registers, return

music_stop:
        sei
        lda #0
        sta m_on
        sta m_on+1
        sta m_on+2
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        lda #$31                        // the normal KERNAL interrupt
        sta $0314
        lda #$ea
        sta $0315
        lda #$81
        sta $dc0d
        cli
        jmp sid_init

// once a frame
music_play:
        ldx m_arp_i                     // arpeggio step 0, 1, 2
        inx
        cpx #3
        bcc !+
        ldx #0
!:      stx m_arp_i
        ldx #2
mp_voice:
        lda m_on,x
        bne !+
        jmp mp_done
!:      dec m_wait,x
        bne !+
        jsr m_next                      // this note is done: read the next
        jmp mp_fx
!:      lda m_wait,x                    // 2 frames before the end: let go
        cmp #2
        bne mp_fx
        ldy m_voff,x
        lda m_wave,x
        and #$fe
        sta $d404,y
mp_fx:  lda m_arp,x                     // arpeggio: note + 0/4/7 or 0/3/7
        beq mp_sweep
        lda m_note,x
        beq mp_sweep
        lda m_arp,x
        sta m_tmp
        asl
        adc m_tmp
        adc m_arp_i
        tay
        lda arp_tab,y
        clc
        adc m_note,x
        jsr m_freq
mp_sweep:
        lda m_sweep,x                   // pulse width sweep
        beq mp_done
        lda m_pw_lo,x
        clc
        adc m_sweep,x
        sta m_pw_lo,x
        lda m_sweep,x
        and #$80
        beq !+
        lda #$ff
!:      adc m_pw_hi,x
        sta m_pw_hi,x
        cmp #$0e                        // bounce between $200 and $e00
        bcc !+
        lda m_sweep,x
        bmi mp_pw
        jmp mp_flip
!:      cmp #$02
        bcs mp_pw
        lda m_sweep,x
        bpl mp_pw
mp_flip:
        lda m_sweep,x
        eor #$ff
        clc
        adc #1
        sta m_sweep,x
mp_pw:  ldy m_voff,x
        lda m_pw_lo,x
        sta $d402,y
        lda m_pw_hi,x
        sta $d403,y
mp_done:
        dex
        bmi !+
        jmp mp_voice
!:      rts

// read the next note of voice X (and any commands before it)
m_next:
        jsr m_read
        cmp #$ff                        // end: back to the start
        bne !+
        lda m_start_lo,x
        sta m_ptr_lo,x
        lda m_start_hi,x
        sta m_ptr_hi,x
        jmp m_next
!:      cmp #$fd                        // end of a one-shot tune
        bne !+
        lda #0
        sta m_on,x
        jmp m_rest
!:      cmp #$fe                        // instrument
        bne !+
        jsr m_read
        jsr m_inst
        jmp m_next
!:      sta m_note,x
        jsr m_read                      // length in rows
        tay
        lda m_rows,y
        sta m_wait,x
        lda m_note,x
        beq m_rest
        jsr m_freq
        ldy m_voff,x                    // gate off, then on: a new note
        lda m_wave,x
        and #$fe
        sta $d404,y
        ora #1
        sta $d404,y
        rts
m_rest: ldy m_voff,x
        lda m_wave,x
        and #$fe
        sta $d404,y
        rts

m_read:
        lda m_ptr_lo,x
        sta mr+1
        lda m_ptr_hi,x
        sta mr+2
mr:     lda $ffff                       // (address set above)
        inc m_ptr_lo,x
        bne !+
        inc m_ptr_hi,x
!:      rts

// A = note number -> frequency of voice X
m_freq:
        tay
        lda freq_lo,y
        pha
        lda freq_hi,y
        pha
        ldy m_voff,x
        pla
        sta $d401,y
        pla
        sta $d400,y
        rts

// A = instrument number for voice X
m_inst:
        asl
        asl
        asl
        tay
        lda inst_tab,y
        sta m_wave,x
        lda inst_tab+3,y
        sta m_pw_lo,x
        lda inst_tab+4,y
        sta m_pw_hi,x
        lda inst_tab+5,y
        sta m_sweep,x
        lda inst_tab+6,y
        sta m_arp,x
        lda inst_tab+1,y
        pha
        lda inst_tab+2,y
        pha
        ldy m_voff,x
        pla
        sta $d406,y
        pla
        sta $d405,y
        lda m_pw_lo,x
        sta $d402,y
        lda m_pw_hi,x
        sta $d403,y
        rts

// SID frequencies (PAL) for note numbers 1-96: c0 ... b7
freq_lo: .fill 97, <min(65535, round(440 * pow(2, (i-58)/12) * 16777216 / 985248))
freq_hi: .fill 97, >min(65535, round(440 * pow(2, (i-58)/12) * 16777216 / 985248))

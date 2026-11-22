// Waste of Space: Derelict - a first-person dungeon crawl for the C64
// KickAssembler. Joystick in port 2 or W A S D.
//
// Walk a 16 x 16 deck in first person. Up/W = step forward,
// down/S = step back, left/A and right/D = turn. The minimap fills in with
// what you have seen; the log at the bottom says what happens.
// Now and then something blocks the way: the crew fights (combat.asm).
// Doors, keycards, medkits (M), and a hatch down to the next deck (items.asm).
//
// The screen is split (screen.asm): a multicolour bitmap on top, text below.
//
// Test builds:  -define DEMO       walks a scripted route by itself (always fights)
//               -define FIGHTTEST  a fight on every step
//               -define NOFIGHTS   no fights at all
//               -define DECK2      start on deck 2

.encoding "screencode_upper"

#import "map.asm"
#import "monsters.asm"

// VIC bank 3 (see screen.asm)
.const SCREEN  = $c000
.const COLRAM  = $d800
.const BITMAP  = $e000
.const CHARSET = $c800          // the text rows' letters (from the ROM)
.const MON_SPRITES  = $c400     // the monster sprites (12)
.const ITEM_SPRITES = $cc00     // the item sprites (6)
.const SPLIT_LINE = 51 + 8*20 - 3       // the interrupt just before text row 20
.const TOP_LINE   = 8                   // ... and back to bitmap above the picture
.const MINI_ROW   = 3           // the minimap's top-left cell (in the bitmap)
.const MINI_COL   = 23
// work memory
.const BUFC    = $8000          // the view is drawn here (codes) ...
.const BUFK    = $8200          // ... and here (inks), then shown by present
.const BUFD    = $8400          // the view's depth per cell (for the fog)
.const FOGDUMMY = $8600         // blit writes depths here for pieces that keep the floor's
.const SEEN    = $8800          // 1 = a map cell you have seen (minimap)
.label map     = $8900          // this deck: 0 floor, 1 wall, 2 door, 3 locked door
.label special = $8a00          // this deck: notes, items, hatch, end (see map.asm)
.const LOG     = SCREEN + 22*40 + 1 // the 3 log lines (38 wide)
.const LOG_W   = 38
.const VX      = 1              // the view's top-left on the screen
.const VY      = 0

.const COL_FLOOR = 9            // brown deck plates
.const COL_CEIL  = 11           // dark grey
.const COL_FRAME = 6
.const COL_TEXT  = 15
.const COL_TITLE = 7

.label zp      = $fb
.label zp2     = $fd
.label pos     = $02            // y*16 + x
.label dir     = $03
.label dir12   = $04            // dir*12: where this direction's cells start in delta
.label lastact = $05
.label rep     = $06
.label flash   = $07
.label t0      = $08
.label demo_i  = $09
.label demo_t  = $0a
.label mp      = $0b            // message pointer
// the crew and fights (combat.asm)
.label steps   = $10
.label regen   = $11
.label mtype   = $12
.label mcount  = $13
.label mhp     = $14            // 3: each monster's HP
.label crew_hp = $17            // 3
.label act     = $1a            // 3: what each picked (1 fight, 2 defend, 3 run)
.label cur     = $1d            // whose turn ($ff: nobody's)
.label who     = $1e
.label mwho    = $1f
.label target  = $20
.label dmg     = $21
.label mflash  = $22
.label pcount  = $23
.label armed   = $24
.label seed    = $25
.label t1      = $26
.label t2      = $27
.label lbp     = $28
.label sp      = $29            // 2
// decks and items (items.asm)
.label deck    = $2b
.label meds    = $2c
.label keys    = $2d
.label bonus   = $2e            // + hit for the whole crew
.label kind    = $2f            // the cell being drawn: 1 wall, 2 door, 3 locked
.label ovr     = $30            // blit: draw in this colour instead (0: the piece's own)
.label zp3     = $31            // 2: blit's depth pointer
.label fogtab  = $33            // 4: this deck's fog level at depth 0-3
.label fog_floor = $37
.label fog_ceil  = $38
.label flvl    = $39
.label fcode   = $3a
.label fx      = $3b
.label si_depth = $3c
// the screen (screen.asm)
.label frames  = $3d            // counts frames (the interrupt)
.label irq_top = $3e
.label pp      = $40            // 2: a pattern
.label dp      = $42            // 2: a bitmap cell
.label cr      = $44            // the cell's row
.label cc      = $45            // ... column
.label ccol    = $46            // ... ink
.label cscr    = $47            // ... screen byte (floor/ceiling colours)
.label tp      = $48            // 2: text
.label prev_pos = $4a
.label view_scr = $4b           // floor << 4 | ceiling
.label bc      = $4c            // 2: present's pointers
.label bk      = $4e            // 2
.label sr      = $50            // 2
.label crp     = $52            // 2
.label pcol    = $54
.label mi      = $55
.label prow    = $56
.label bty     = $57

.macro Print(dest, src, col) {
        ldx #0
!:      lda src,x
        beq !+
        sta dest,x
        lda #col
        sta dest + (COLRAM - SCREEN),x
        inx
        bne !-
!:
}

// Z clear (bne) when the cell f ahead, s to the side (-1 left, 1 right) is a wall
.macro Cell(f, s) {
        ldy dir12
        lda delta + f*3 + s + 1,y
        clc
        adc pos
        tax
        lda map,x
}

// draw what is at depth f: the wall ahead at plane f+1 and both sides
.macro Depth(f) {
        Cell(f+1, 0)
        beq nofront
        sta kind
        lda #f
        jsr blit_front
nofront:
        Cell(f, -1)
        beq lopen
        sta kind
        lda #3+f
        jsr blit_k
        jmp right
lopen:  Cell(f+1, -1)
        beq right
        sta kind
        lda #6+f
        jsr blit_k
right:  Cell(f, 1)
        beq ropen
        sta kind
        lda #9+f
        jsr blit_k
        jmp done
ropen:  Cell(f+1, 1)
        beq done
        sta kind
        lda #12+f
        jsr blit_k
done:
}

BasicUpstart2(start)

#import "view.asm"           // the view pieces (data) and the cell patterns
#import "screen.asm"         // the split screen, drawing into the bitmap

start:
        lda #0
        sta $d020
        sta $d021
        jsr screen_init
        jsr crew_init

        lda #$0f                // SID: volume, voice 1 for thuds and steps
        sta $d418
        lda #$08
        sta $d405
        lda #$00
        sta $d406

        lda #0
#if DECK2
        lda #1
#endif
        sta deck
        jsr load_deck
        jsr draw_frame
        lda #0
        sta lastact
        sta flash
        sta mp+1
        sta demo_i
        lda #50
        sta demo_t
        jsr show_all
        jsr draw_party
        Message(txt_wake)
        Message(txt_help1)
        Message(txt_help2)

// ---------------------------------------------------------------- main loop
main:
        jsr frame
        jsr do_flash
        jsr read_input
        bne got
        sta lastact
        jmp main
got:    cmp lastact
        bne new
        cmp #5                  // the medkit key doesn't repeat
        beq main
        dec rep
        bne main
        ldx #8                  // held: again every 8 frames
        stx rep
        jmp do_act
new:    sta lastact
        ldx #16                 // first repeat after 16 frames
        stx rep
do_act: cmp #5
        bne !+
        jsr use_med
        jmp main
!:      cmp #1
        beq forward
        cmp #2
        beq back
        cmp #3
        beq turn_left
turn_right:
        inc dir
        jmp turned
turn_left:
        dec dir
turned: lda dir
        and #3
        sta dir
        jsr set_dir
        jmp moved

forward:
        ldy dir12
        lda delta + 1*3 + 1,y
        clc
        adc pos
        jmp try_step
back:
        ldy dir12
        lda pos
        sec
        sbc delta + 1*3 + 1,y
try_step:
        tax
        lda map,x
        beq walk
        cmp #1
        beq bump
        stx t0                  // a door
        cmp #3
        bne open_door
        lda keys
        bne use_key
        lda #$04
        jsr sound
        Once(txt_locked)
        jmp main
use_key:
        dec keys
        Message(txt_key_used)
open_door:
        ldx t0
        lda #0
        sta map,x
        jsr mini_cell
        lda #$60
        jsr sound
        Message(txt_door)
        jsr show_all
        jmp main
walk:
        stx pos
        lda #$30                // step: a short tick
        jsr sound
        jsr show_all
        jsr on_cell
        jmp main
bump:
        lda #$04                // a low thud and a red flash
        jsr sound
        lda #6
        sta flash
        Once(txt_bump)
        jmp main
moved:
        jsr show_all
        jmp main

show_all:
        jsr mark_seen
        jsr render
        jsr show_item
        ldx prev_pos            // the minimap: where you were, where you are
        jsr mini_cell
        ldx pos
        stx prev_pos
        jsr mini_cell
        jmp status

// ---------------------------------------------------------------- input
// A = 0 nothing, 1 forward, 2 back, 3 left, 4 right, 5 medkit
read_input:
#if DEMO
        dec demo_t
        bne none
        lda #30
        sta demo_t
        ldx demo_i
        lda demo_script,x
        bpl !+
        ldx #0
        lda demo_script
!:      inx
        stx demo_i
        rts
#else
        lda $dc00               // joystick port 2
        lsr
        bcc i_fwd
        lsr
        bcc i_back
        lsr
        bcc i_left
        lsr
        bcc i_right
        lda $cb                 // the key held down
        cmp #9                  // W
        beq i_fwd
        cmp #13                 // S
        beq i_back
        cmp #10                 // A
        beq i_left
        cmp #18                 // D
        beq i_right
        cmp #36                 // M
        beq i_med
#endif
none:   lda #0
        rts
i_fwd:  lda #1
        rts
i_back: lda #2
        rts
i_left: lda #3
        rts
i_right:
        lda #4
        rts
i_med:  lda #5
        rts

#if DEMO
demo_script:
        .byte 1,1,1,1,1, 4, 1,1,1,1,4,4,1,1, 3,3, 1,1,1,1, 3, 1,1,1,1,1,1, $ff
#endif

// ---------------------------------------------------------------- bits
set_dir:
        lda dir
        asl
        asl
        sta t0
        asl
        clc
        adc t0
        sta dir12
        rts

// A = frequency (high byte), noise
sound:
        sta $d401
        lda #0
        sta $d400
        lda #$80
        sta $d404
        lda #$81
        sta $d404
        rts

do_flash:
        lda flash
        beq !+
        dec flash
        lda flash
        and #2
        beq off
        lda #2
        sta $d020
        rts
off:    lda #0
        sta $d020
!:      rts

// text row 21: deck, facing, medkits, keys
.const STATUS = SCREEN + 21*40 + 1
status:
        Print(STATUS, txt_status, COL_TEXT)
        lda deck
        clc
        adc #49
        sta STATUS + 5
        lda dir
        asl
        sta t0
        asl
        clc
        adc t0                  // dir*6
        tay
        ldx #0
!:      lda dir_names,y
        sta STATUS + 15,x
        iny
        inx
        cpx #6
        bne !-
        lda meds
        clc
        adc #48
        sta STATUS + 30
        lda keys
        clc
        adc #48
        sta STATUS + 38
        rts

// ---------------------------------------------------------------- the log
.macro Message(txt) {
        lda #<txt
        ldx #>txt
        jsr message
}
// a line, unless it's already the newest one (bumping on and on)
.macro Once(txt) {
        lda mp
        cmp #<txt
        bne say
        lda mp+1
        cmp #>txt
        beq done
say:    Message(txt)
done:
}
// add to the line being built (combat.asm)
.macro Say(txt) {
        lda #<txt
        ldx #>txt
        jsr lb_str
}
// show a line and wait a moment
.macro Line(txt) {
        lda #<txt
        ldx #>txt
        jsr message
        jsr pause
}

// A/X = a 0-terminated line: the log scrolls up a line and it goes at the bottom
message:
        sta mp
        stx mp+1
        ldx #LOG_W-1
!:      lda LOG + 40,x
        sta LOG,x
        lda LOG + 80,x
        sta LOG + 40,x
        lda #32
        sta LOG + 80,x
        lda #11                 // older lines fade
        sta LOG + (COLRAM-SCREEN),x
        lda #12
        sta LOG + 40 + (COLRAM-SCREEN),x
        lda #1
        sta LOG + 80 + (COLRAM-SCREEN),x
        dex
        bpl !-
        ldy #0
!:      lda (mp),y
        beq !+
        sta LOG + 80,y
        iny
        bne !-
!:      rts

// ---------------------------------------------------------------- the minimap
// mark what the view shows: down the corridor until a wall, and both sides
// (a cell seen for the first time goes on the minimap)
.macro MarkSeen() {
        lda SEEN,x
        bne done
        lda #1
        sta SEEN,x
        jsr mini_cell
done:
}
mark_seen:
        .for (var f=0; f<4; f++) {
            Cell(f, 0)
            sta t0
            MarkSeen()
            lda t0
            beq !+
            jmp ms_done
!:          Cell(f, -1)
            MarkSeen()
            Cell(f, 1)
            MarkSeen()
        }
ms_done:
        rts

arrow_code: .byte 59 + ON_FLOOR, 61 + ON_FLOOR, 62 + ON_FLOOR, 63 + ON_FLOOR

#import "combat.asm"
#import "items.asm"

// ---------------------------------------------------------------- the fog
// over the whole view buffer: by each cell's depth and the deck's profile
.macro FogCell(base) {
        ldy BUFD+base,x
        lda fogtab,y
        beq done
        sta flvl
        lda BUFC+base,x
        sta fcode
        and #63
        tay
        lda glyph_fog,y
        beq done
        cmp #2
        beq dim
        ldy flvl                // dither: its colour on black
        lda dither_code,y
        sta BUFC+base,x
        lda fcode
        cmp #64
        bcc done                // a wall: keep its colour
        cmp #128
        bcc on_floor
        lda fog_ceil
        sta BUFK+base,x
        jmp done
on_floor:
        lda fog_floor
        sta BUFK+base,x
        jmp done
dim:    stx fx                  // a diagonal edge: darker colour
        lda BUFK+base,x
        and #15
        ldy flvl
!:      tax
        lda ramp,x
        dey
        bne !-
        ldx fx
        sta BUFK+base,x
done:
}

fog:
        ldx #0
fog1:   FogCell(0)
        inx
        cpx #VW*VH/2
        beq !+
        jmp fog1
!:      ldx #0
fog2:   FogCell(VW*VH/2)
        inx
        cpx #VW*VH/2
        beq !+
        jmp fog2
!:      rts

// A = a colour, Y = a depth -> A = the colour as the fog leaves it (dimmer)
fog_colour:
        and #15
        pha
        lda fogtab,y
        tay
        pla
        cpy #0
        beq !++
!:      tax
        lda ramp,x
        dey
        bne !-
!:      rts

// ---------------------------------------------------------------- the view
render:
        ldx #0                  // ceiling over the horizon, floor under it
!:      lda #C_CEIL
        sta BUFC,x
        lda #C_FLOOR
        sta BUFC + VW*VH/2,x
        lda bg_depth,x
        sta BUFD,x
        lda bg_depth + VW*VH/2,x
        sta BUFD + VW*VH/2,x
        inx
        cpx #VW*VH/2
        bne !-
        lda #C_DARK             // far down the corridor: dark
        sta BUFC + 9*VW + 9
        sta BUFC + 9*VW + 10
        sta BUFC + 10*VW + 9
        sta BUFC + 10*VW + 10
        ldx deck                // seams across floor and ceiling, then the lamps
        lda deck_lines,x
        sta ovr
        lda #P_SEAMS
        jsr blit
        ldx deck
        lda deck_lamps,x
        sta ovr
        lda #P_LAMPS
        jsr blit
        Depth(2)
        Depth(1)
        Depth(0)
        jsr fog
        jmp present

// A = piece number: write its cells into the buffers
blit:
        tax
        lda ovr                 // one colour for all of it?
        beq b_own
        sta s4+1
        lda #$a9                // s4 becomes: lda #ovr / nop
        sta s4
        lda #$ea
        sta s4+2
        bne b_go
b_own:  lda #$bd                // s4: lda the piece's colours,x
        sta s4
        lda pd_lo,x
        sta s4+1
        lda pd_hi,x
        sta s4+2
b_go:   lda p_count,x
        sta bn+1
        lda pa_lo,x
        sta s1+1
        lda pa_hi,x
        sta s1+2
        lda pb_lo,x
        sta s2+1
        lda pb_hi,x
        sta s2+2
        lda pc_lo,x
        sta s3+1
        lda pc_hi,x
        sta s3+2
        lda piece_depth,x       // the depth it writes ($ff: none, to a dummy page)
        sta dv+1
        ldy #>BUFD
        cmp #$ff
        bne !+
        ldy #>FOGDUMMY
!:      sty dh+1
        ldx #0
bl:
s1:     lda $ffff,x
        sta zp
        sta zp2
        sta zp3
s2:     lda $ffff,x
        tay
        ora #>BUFC
        sta zp+1
        ora #>BUFK
        sta zp2+1
        tya
dh:     ora #>BUFD
        sta zp3+1
        ldy #0
s3:     lda $ffff,x
        sta (zp),y
s4:     lda $ffff,x
        sta (zp2),y
dv:     lda #0
        sta (zp3),y
        inx
bn:     cpx #0
        bne bl
        rts

// ---------------------------------------------------------------- tables
txt_title1: .text "WASTE OF SPACE"
            .byte 0
txt_title2: .text "   DERELICT"
            .byte 0
txt_status: .text "DECK    FACING        MEDKITS    KEYS  "
            .byte 0
txt_wake:   .text "YOU WAKE UP ON A DEAD SHIP. ALONE..."
            .byte 0
txt_help1:  .text "W/S OR JOYSTICK: STEP FORWARD / BACK"
            .byte 0
txt_help2:  .text "A/D: TURN. M: MEDKIT. BUMP DOORS."
            .byte 0
txt_bump:   .text "BONK. A WALL."
            .byte 0
note_text:
.var NOTE_AT = List()
.for (var n=0; n<NOTES.size(); n++) {
    .errorif NOTES.get(n).size() > LOG_W, "note " + (n+1) + " is longer than " + LOG_W
    .eval NOTE_AT.add(*)
    .text NOTES.get(n)
    .byte 0
}
note_lo:    .fill NOTES.size(), <NOTE_AT.get(i)
note_hi:    .fill NOTES.size(), >NOTE_AT.get(i)
dir_names:  .text "NORTH EAST  SOUTH WEST  "

// what lies f ahead, s to the side, as an offset into the map (wraps in 256)
.var FWD = List().add(-16, 1, 16, -1)
delta:
.for (var d=0; d<4; d++)
    .for (var f=0; f<4; f++)
        .for (var s=-1; s<=1; s++)
            .byte (f*FWD.get(d) + s*FWD.get((d+1)&3)) & $ff


mon_sprite_data:
.for (var m=0; m<NMON; m++) MonsterSprites(MON_PICS.get(m))
item_sprite_data:
.for (var n=0; n<NITEM_PICS; n++) ItemSprite(ITEM_PICS.get(n))

.errorif * > BUFC, "the program runs into the work memory at $8000"

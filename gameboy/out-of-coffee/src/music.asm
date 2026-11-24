; A tiny 3-voice music player for the Game Boy's sound chip.
; voice 0 -> pulse 1 (lead), voice 1 -> pulse 2 (chords), voice 2 -> wave (bass)
; The tune and instruments come from art/music.txt (tools/music.py -> gen/music.asm).
;
; MusicStart: sound on, the tune from the top
; MusicPlay:  once a frame
; MusicStop:  sound off

; hl = \1 + current voice (wMusV). Keeps bc, de.
MACRO VOICE_HL
    ld a, [wMusV]
    ld hl, \1
    add l
    ld l, a
    jr nc, .nc\@
    inc h
.nc\@:
ENDM

SECTION "Music player", ROM0

MusicStart:
    ld a, $80
    ldh [rNR52], a
    ld a, $77
    ldh [rNR50], a
    ld a, $FF
    ldh [rNR51], a
    xor a
    ldh [rNR10], a
    ldh [rNR30], a          ; wave DAC off while its RAM is filled
    ld hl, WaveTriangle
    ld de, $FF30
    ld bc, 16
    call Memcpy
    ld hl, SongVoices
    ld de, wMusPtr
    ld bc, 6
    call Memcpy
    ld hl, SongVoices
    ld de, wMusStart
    ld bc, 6
    call Memcpy
    ld a, 1                 ; every voice reads its first note on the first frame
    ld hl, wMusWait
    ld [hli], a
    ld [hli], a
    ld [hl], a
    xor a
    ld hl, wMusInst
    ld [hli], a
    ld [hli], a
    ld [hl], a
    ld hl, wMusNote
    ld [hli], a
    ld [hli], a
    ld [hl], a
    ld [wMusArp], a
    ld a, 1
    ld [wMusOn], a
    ret

MusicStop:
    xor a
    ld [wMusOn], a
    ldh [rNR52], a
    ret

MusicPlay:
    ld a, [wMusOn]
    and a
    ret z
    ld hl, wMusFrame
    inc [hl]
    ld hl, wMusArp          ; 0, 1, 2, 0, ... for the chord arpeggio
    inc [hl]
    ld a, [hl]
    cp 3
    jr c, .arpOk
    xor a
    ld [hl], a
.arpOk:
    xor a
.voice:
    ld [wMusV], a
    call MusVoice
    ld a, [wMusV]
    inc a
    cp 3
    jr nz, .voice
    ret

; MusVoice: one frame of the current voice
MusVoice:
    VOICE_HL wMusAge
    inc [hl]
    VOICE_HL wMusWait
    dec [hl]
    jp z, MusNext
    VOICE_HL wMusNote       ; a note is held: its effects
    ld a, [hl]
    and a
    ret z
    call MusInstPtr
    inc hl                  ; skip duty, envelope
    inc hl
    ld a, [hli]             ; arp
    and a
    jr z, .noArp
    ld b, a
    add a, a
    add b                   ; arp * 3
    ld b, a
    ld a, [wMusArp]
    add b
    ld e, a
    ld d, 0
    push hl
    ld hl, ArpTab
    add hl, de
    ld b, [hl]              ; semitones up
    VOICE_HL wMusNote
    ld a, [hl]
    add b
    call MusSetFreq
    pop hl
.noArp:
    ld a, [hli]             ; wobble: duty steps 25-50-75-50%
    and a
    jr z, .noWobble
    push hl
    ld a, [wMusFrame]
    rrca
    rrca
    rrca
    and 3
    ld e, a
    ld d, 0
    ld hl, DutySeq
    add hl, de
    ld b, [hl]
    call MusRegBase
    inc c
    ld a, b
    ldh [c], a
    pop hl
.noWobble:
    ld a, [hl]              ; pluck: the wave voice fades 100 -> 50 -> 25%
    and a
    ret z
    VOICE_HL wMusAge
    ld a, [hl]
    cp 3
    ld b, $40
    jr z, .vol
    cp 7
    ld b, $60
    ret nz
.vol:
    ld a, b
    ldh [rNR32], a
    ret

; MusNext: read the voice's next note (and any instrument changes / loop)
MusNext:
    ld a, [wMusV]
    add a, a
    ld e, a
    ld d, 0
    ld hl, wMusPtr
    add hl, de
    ld a, [hli]
    ld h, [hl]
    ld l, a
.read:
    ld a, [hli]
    cp $FF
    jr z, .loop
    cp $FE
    jr z, .inst
    ld b, a                 ; note
    ld a, [hli]
    ld c, a                 ; frames
    push bc
    ld d, h                 ; remember where we are
    ld e, l
    ld a, [wMusV]
    add a, a
    ld c, a
    ld b, 0
    ld hl, wMusPtr
    add hl, bc
    ld [hl], e
    inc hl
    ld [hl], d
    pop bc
    VOICE_HL wMusWait
    ld [hl], c
    VOICE_HL wMusAge
    ld [hl], 0
    VOICE_HL wMusNote
    ld [hl], b
    jp MusTrigger
.inst:
    ld a, [hli]
    push hl
    ld b, a
    VOICE_HL wMusInst
    ld [hl], b
    pop hl
    jr .read
.loop:
    ld a, [wMusV]
    add a, a
    ld e, a
    ld d, 0
    ld hl, wMusStart
    add hl, de
    ld a, [hli]
    ld h, [hl]
    ld l, a
    jr .read

; MusTrigger: b = note (0 = rest). Starts it on the voice's channel.
MusTrigger:
    call MusRegBase         ; c = NRx0
    ld a, b
    and a
    jr z, .rest
    push bc
    call MusInstPtr
    pop bc
    ld a, [wMusV]
    cp 2
    jr z, .wave
    inc c
    ld a, [hli]
    ldh [c], a              ; NRx1 duty
    inc c
    ld a, [hl]
    ldh [c], a              ; NRx2 envelope
    jr .freq
.wave:
    ld a, $80
    ldh [rNR30], a          ; wave DAC on
    ld a, $20
    ldh [rNR32], a          ; 100%
    inc c
    inc c
.freq:
    push bc
    ld a, b
    call MusFreq
    pop bc
    inc c
    ld a, e
    ldh [c], a              ; NRx3
    inc c
    ld a, d
    or $80                  ; trigger
    ldh [c], a              ; NRx4
    ret
.rest:
    ld a, [wMusV]
    cp 2
    jr z, .waveOff
    inc c
    inc c
    xor a
    ldh [c], a              ; envelope 0 = silent
    ret
.waveOff:
    xor a
    ldh [rNR32], a
    ret

; MusSetFreq: a = note. New pitch on the voice's channel, no restart.
MusSetFreq:
    call MusFreq
    call MusRegBase
    inc c
    inc c
    inc c
    ld a, e
    ldh [c], a
    inc c
    ld a, d
    ldh [c], a
    ret

; MusFreq: a = note -> de = frequency register value for this voice's channel
MusFreq:
    ld e, a
    ld d, 0
    ld a, [wMusV]
    cp 2
    ld hl, PulseFreq
    jr nz, .tab
    ld hl, WaveFreq
.tab:
    add hl, de
    add hl, de
    ld a, [hli]
    ld e, a
    ld d, [hl]
    ret

; MusRegBase: c = low byte of the voice's first sound register ($10, $15, $1A)
MusRegBase:
    ld a, [wMusV]
    ld c, a
    add a, a
    add a, a
    add c
    add $10
    ld c, a
    ret

; MusInstPtr: hl = the voice's instrument in InstTab (5 bytes each)
MusInstPtr:
    VOICE_HL wMusInst
    ld a, [hl]
    ld b, a
    add a, a
    add a, a
    add b
    ld hl, InstTab
    add l
    ld l, a
    ret nc
    inc h
    ret


SECTION "Music vars", WRAM0
wMusPtr:   ds 6
wMusStart: ds 6
wMusWait:  ds 3
wMusNote:  ds 3
wMusInst:  ds 3
wMusAge:   ds 3
wMusV:     ds 1
wMusArp:   ds 1
wMusFrame: ds 1
wMusOn:    ds 1

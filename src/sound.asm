;; ===========================================================================
;; sound.asm - effects on the AY-3-8912, one channel's worth.
;;
;; The PSG is not on the bus. It hangs off the 8255 PPI exactly as the key
;; matrix does: the register number goes out on PPI port A, port C is told to
;; select it, the value goes out on port A, and port C is told to write it.
;; Port A has to be an output for that, which is where read_keyboard leaves it.
;;
;; Bit 6 of the mixer is the PSG's own port A direction, and the key matrix is
;; read through that port, so every mixer value here keeps it at 0. Setting it
;; would silently kill the keyboard.
;;
;; One channel, one effect at a time. Three channels and a music player would
;; be a different job, and this machine has 221 bytes left in it.
;;
;; An effect is a starting tone period, a signed amount added to it every 50 Hz
;; step, and a length. The volume is the length, capped at 15, so everything
;; fades out as it ends without costing a byte of state. Noise effects put the
;; noise pitch in the period's low byte, which the tone effects do not mind
;; because the mixer has their noise switched off.
;; ===========================================================================

SFX_JUMP        EQU 0
SFX_EAT         EQU 1
SFX_DIE         EQU 2
SFX_FLOP        EQU 3

SFX_SIZE        EQU 6

;; Mixer, register 7: a 0 bit enables. Bit 0 is tone A, bit 3 is noise A.
MIX_TONE        EQU %00111110   ; tone on A, nothing else
MIX_NOISE       EQU %00110111   ; noise on A, nothing else
MIX_SILENT      EQU %00111111

;; ---------------------------------------------------------------------------
;; sfx_tab - mixer, starting period, period step, length in 50 Hz frames.
;; ---------------------------------------------------------------------------
sfx_tab
    defb MIX_TONE               ; jump: 312 Hz up to about 650, eight frames
    defw 400
    defw -26
    defb 8

    defb MIX_TONE               ; eat: a short blip, high and rising
    defw 190
    defw -14
    defb 5

    defb MIX_TONE               ; die: 400 Hz sliding a long way down
    defw 300
    defw 44
    defb 25

    defb MIX_NOISE              ; belly-flop: a thud, the noise pitch low
    defw 24
    defw 0
    defb 10

;; ---------------------------------------------------------------------------
;; psg_set - A = PSG register, E = value.
;; Destroys AF, BC.
;;
;; Port C bits 6-7 are the PSG function: 11 select, 10 write, 00 inactive.
;; ---------------------------------------------------------------------------
psg_set
    ld bc,#F400
    out (c),a                   ; port A = the register number
    ld b,#F6
    ld a,#C0
    out (c),a                   ; select it
    xor a
    out (c),a                   ; inactive, so the latch holds
    ld b,#F4
    out (c),e                   ; port A = the value
    ld b,#F6
    ld a,#80
    out (c),a                   ; write it
    xor a
    out (c),a
    ret

;; ---------------------------------------------------------------------------
;; sfx_init - everything off. Called once, before interrupts.
;; Destroys AF, BC, DE.
;; ---------------------------------------------------------------------------
sfx_init
    xor a
    ld (sfx_len),a
    ld e,a
    ld a,8
    call psg_set                ; channel A silent
    ld e,MIX_SILENT
    ld a,7
    jp psg_set

;; ---------------------------------------------------------------------------
;; sfx_play - A = an SFX_* id. Starts it, cutting off whatever was playing.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
sfx_play
    ld l,a
    ld h,0
    add hl,hl                   ; x2
    ld d,h
    ld e,l
    add hl,hl                   ; x4
    add hl,de                   ; x6, the record size
    ld de,sfx_tab
    add hl,de

    ld e,(hl)                   ; the mixer
    inc hl
    ld a,7
    call psg_set

    ld e,(hl)                   ; the noise pitch rides in the period's low
    ld a,6                      ; byte; tone effects have noise switched off
    call psg_set

    ld de,sfx_per               ; period, step, length
    ld bc,SFX_SIZE-1
    ldir
    ret

;; ---------------------------------------------------------------------------
;; sfx_update - one 50 Hz step of whatever is playing. Called from the game's
;; logic step, not from the picture, so an effect lasts the same length of
;; time however often the screen is rebuilt.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
sfx_update
    ld a,(sfx_len)
    or a
    ret z
    dec a
    ld (sfx_len),a
    jr nz,sfx_update_on
    ld e,a                      ; the last frame: shut the channel up
    ld a,8
    jp psg_set

sfx_update_on
    ld hl,(sfx_per)
    ld de,(sfx_step)
    add hl,de
    ld (sfx_per),hl
    ld e,l
    xor a
    call psg_set                ; register 0, period low
    ld a,(sfx_per+1)
    and #0F                     ; the period is twelve bits
    ld e,a
    ld a,1
    call psg_set

    ld a,(sfx_len)              ; the volume is what is left of the length,
    cp 16                       ; so everything fades as it runs out
    jr c,sfx_update_vol
    ld a,15
sfx_update_vol
    ld e,a
    ld a,8
    jp psg_set

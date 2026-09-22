;; ===========================================================================
;; mitsossfx.asm - effects on a chip the music already owns.
;;
;; The first game has sound.asm and a channel to itself, because it has no
;; music while it is being played. This one has a tune running the whole time,
;; stepped from the interrupt, and a tracker replay does not share: it writes
;; every register it uses fifty times a second, whatever anyone else has put
;; in them since. An effect written from the game loop would last until the
;; next tick of the player and no longer - twenty milliseconds, once.
;;
;; Two things make it work anyway.
;;
;; The tune is one voice. Its linker gives channel B the melody and hands the
;; other two an empty track, so **channel A is free** in exactly the way it is
;; free in the other game, and nothing has to be taken away from anybody.
;;
;; And the effect is written *after* the player, on the same interrupt:
;; music_tick calls PLY_AKG_Play and falls into sfx_update, so the last word
;; on every register is this file's. The two the player would otherwise take
;; back - the mixer and the noise pitch - are put back on every tick for as
;; long as the effect lasts, and let go the moment it ends.
;;
;; The game only asks. sfx_play writes state and never touches the chip, so
;; there is exactly one writer and the interrupt is it. The length is written
;; last, by the LDIR, and the length is what arms the effect - a tick landing
;; in the middle of sfx_play sees a length of zero and does nothing, which is
;; the whole of the locking.
;;
;; A mixer bit is 0 to enable. **Bit 1 is tone B and it is 0 in every value
;; here**, because that is the melody and no effect is worth silencing it;
;; MIX_TONE and MIX_NOISE are in mitsosdata.asm with the table they belong to.
;; Bit 6 stays 0 in all of them, and in the player's own: it is the PSG's port
;; A direction, and the key matrix is read through that port.
;; ===========================================================================

SFX_JUMP        EQU 0
SFX_MEZE        EQU 1
SFX_CATNIP      EQU 2
SFX_BOUNCE      EQU 3
SFX_SWEEP       EQU 4
SFX_LOSE        EQU 5
SFX_BASKET      EQU 6
SFX_DONE        EQU 7

SFX_SIZE        EQU 6

    include "psg.asm"

;; ---------------------------------------------------------------------------
;; sfx_init - nothing playing. The player's own Init has already silenced the
;; chip, so there is nothing here to switch off: this only disarms the state,
;; which is uninitialised RAM below #4000 like the rest of the workspace.
;; Destroys AF.
;; ---------------------------------------------------------------------------
sfx_init
    xor a
    ld (sfx_len),a
    ret

;; ---------------------------------------------------------------------------
;; sfx_play - A = an SFX_* id. Asks for it; the next tick of the interrupt
;; starts it, cutting off whatever was playing.
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

    ld a,(hl)                   ; the mixer is kept, because the player takes
    ld (sfx_mix),a              ; it back on every one of its own ticks
    inc hl
    ld de,sfx_per               ; period, step, length - the length last, and
    ld bc,SFX_SIZE-1            ; the length is what arms it
    ldir
    ret

;; ---------------------------------------------------------------------------
;; sfx_update - one 50 Hz step, from the interrupt and immediately after the
;; player, so that what the chip is left holding is the effect and not the
;; tune. Nothing playing is a two-instruction return, and then the player has
;; the whole chip to itself again.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
sfx_update
    ld a,(sfx_len)
    or a
    ret z
    dec a
    ld (sfx_len),a
    jr nz,sfx_update_on
    ld e,a                      ; the last step: channel A silent, and the
    ld a,8                      ; mixer is the player's again from its next
    jp psg_set                  ; tick, twenty milliseconds away

sfx_update_on
    ld a,(sfx_mix)              ; the player wrote its own mixer a moment ago
    ld e,a                      ; and its own noise pitch with it, so both of
    ld a,7                      ; them have to go back every single tick
    call psg_set
    ld a,(sfx_per)              ; the noise pitch rides in the period's low
    ld e,a                      ; byte; a tone effect has its noise switched
    ld a,6                      ; off in the mixer and does not mind
    call psg_set

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

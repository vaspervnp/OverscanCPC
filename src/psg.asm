;; ===========================================================================
;; psg.asm - the one way onto the AY-3-8912, and both games take it.
;;
;; The PSG is not on the bus. It hangs off the 8255 PPI exactly as the key
;; matrix does, and every write to it is eight port writes. That is the whole
;; of this file, and it is its own file because two different sound engines
;; want it: sound.asm, which has the chip to itself, and mitsossfx.asm, which
;; has to take it back off a music player fifty times a second.
;; ===========================================================================

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

;; ===========================================================================
;; keys.asm - reading the key matrix.
;;
;; The matrix hangs off the AY-3-8912's port A, which is only reachable
;; through the 8255 PPI: put the PSG register number on PPI port A, tell the
;; PSG to select it, turn port A round to input, put the wanted matrix line on
;; PPI port C, and read it back. A pressed key reads as 0.
;;
;; PPI ports: #F4xx = A, #F5xx = B, #F6xx = C, #F7xx = control.
;; Port C bits 6-7 are the PSG function: 00 inactive, 01 read, 10 write,
;; 11 select. Bits 0-3 are the keyboard line.
;; ===========================================================================

KEY_L_LINE      EQU 4
KEY_L_BIT       EQU 4
KEY_SPACE_LINE  EQU 5
KEY_SPACE_BIT   EQU 7
KEY_FIRE_LINE   EQU 9
KEY_FIRE_BIT    EQU 4

CTL_FIRE        EQU 0           ; bit numbers in ctl_now / ctl_pressed
CTL_LANG        EQU 1

;; ---------------------------------------------------------------------------
;; read_key_line - A = matrix line 0..9 -> A = that line's eight keys,
;; a 0 bit meaning pressed.
;; Destroys AF, BC, DE.
;; ---------------------------------------------------------------------------
read_key_line
    or #40                      ; PSG function 01 = read register
    ld e,a
    ld bc,#F40E                 ; PPI port A = PSG register 14, the matrix
    out (c),c
    ld bc,#F6C0                 ; port C: function 11, select that register
    out (c),c
    ld bc,#F600                 ; back to inactive
    out (c),c
    ld bc,#F792                 ; PPI control: turn port A round to input
    out (c),c
    ld bc,#F600
    out (c),e                   ; port C: read, with the line in bits 0-3
    ld b,#F4
    in a,(c)                    ; the eight keys
    ld bc,#F782                 ; PPI control: port A back to output
    out (c),c
    ret

;; ---------------------------------------------------------------------------
;; read_controls - collapse the keys this game uses into ctl_now (held) and
;; ctl_pressed (went down this frame, so a menu key fires once per press).
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
read_controls
    xor a
    ld (ctl_now),a

    ld a,KEY_SPACE_LINE
    call read_key_line
    bit KEY_SPACE_BIT,a
    jr nz,read_controls_joy
    ld hl,ctl_now
    set CTL_FIRE,(hl)

read_controls_joy
    ld a,KEY_FIRE_LINE
    call read_key_line
    bit KEY_FIRE_BIT,a
    jr nz,read_controls_lang
    ld hl,ctl_now
    set CTL_FIRE,(hl)

read_controls_lang
    ld a,KEY_L_LINE
    call read_key_line
    bit KEY_L_BIT,a
    jr nz,read_controls_edges
    ld hl,ctl_now
    set CTL_LANG,(hl)

read_controls_edges
    ld a,(ctl_now)
    ld b,a
    ld a,(ctl_last)
    cpl
    and b                       ; down now, up last frame
    ld (ctl_pressed),a
    ld a,b
    ld (ctl_last),a
    ret

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

CTL_FIRE        EQU 0           ; bit numbers in ctl_now / ctl_pressed
CTL_LANG        EQU 1
CTL_UP          EQU 2
CTL_DOWN        EQU 3
CTL_LEFT        EQU 4
CTL_RIGHT       EQU 5
CTL_QUIT        EQU 6

;; ---------------------------------------------------------------------------
;; read_keyboard - cache all ten matrix lines in key_rows, after which any key
;; is a bit test on RAM.
;; Destroys AF, BC, HL, E.
;;
;; Selecting PSG register 14 and turning PPI port A round to input are part of
;; setting the keyboard up, not part of reading a line, so they happen once a
;; scan and not ten times. Only the line number going out on port C and the
;; eight keys coming back on port A have to be repeated. Doing the whole
;; eight-port sequence per line cost three quarters of a millisecond a frame -
;; twelve scanlines out of the budget the sprites are fighting for.
;; ---------------------------------------------------------------------------
read_keyboard
    ld bc,#F40E                 ; PPI port A = PSG register 14, the matrix
    out (c),c
    ld bc,#F6C0                 ; port C: function 11, select that register
    out (c),c
    ld bc,#F600                 ; back to inactive
    out (c),c
    ld bc,#F792                 ; PPI control: turn port A round to input
    out (c),c

    ld hl,key_rows
    ld e,#40                    ; port C: function 01 = read, matrix line 0
read_keyboard_loop
    ld bc,#F600
    out (c),e
    ld b,#F4
    in a,(c)                    ; the eight keys, a 0 bit meaning pressed
    ld (hl),a
    inc hl
    inc e
    ld a,e
    cp #4A                      ; ten lines
    jr nz,read_keyboard_loop

    ld bc,#F782                 ; PPI control: port A back to output
    out (c),c
    ret

;; ---------------------------------------------------------------------------
;; ctl_map - matrix line, key mask, control mask. Two entries for a control
;; means either input works, which is how the cursor keys and the joystick
;; both drive the same thing.
;; ---------------------------------------------------------------------------
ctl_map
    defb 5,#80,1<<CTL_FIRE      ; Space
    defb 9,#10,1<<CTL_FIRE      ; joystick fire 1
    defb 4,#10,1<<CTL_LANG      ; L
    defb 0,#01,1<<CTL_UP        ; cursor up
    defb 9,#01,1<<CTL_UP        ; joystick up
    defb 0,#02,1<<CTL_RIGHT     ; cursor right
    defb 9,#08,1<<CTL_RIGHT     ; joystick right
    defb 0,#04,1<<CTL_DOWN      ; cursor down
    defb 9,#02,1<<CTL_DOWN      ; joystick down
    defb 1,#01,1<<CTL_LEFT      ; cursor left
    defb 9,#04,1<<CTL_LEFT      ; joystick left
    defb 8,#04,1<<CTL_QUIT      ; Escape
    defb #FF

;; ---------------------------------------------------------------------------
;; read_controls - ctl_now (held) and ctl_pressed (went down this frame, so a
;; menu key fires once per press).
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
read_controls
    call read_keyboard
    xor a
    ld (ctl_now),a
    ld hl,ctl_map
read_controls_loop
    ld a,(hl)
    inc a
    jr z,read_controls_edges
    dec a
    push hl
    ld e,a
    ld d,0
    ld hl,key_rows
    add hl,de
    ld a,(hl)                   ; that line as it was read this frame
    pop hl
    inc hl
    and (hl)                    ; 0 means the key is down
    inc hl
    jr nz,read_controls_next
    ld a,(ctl_now)
    or (hl)
    ld (ctl_now),a
read_controls_next
    inc hl
    jr read_controls_loop

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

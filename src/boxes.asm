;; ===========================================================================
;; boxes.asm - furniture, painted once into the background.
;;
;; A box list is what a piece of furniture is: dx, dy, width in bytes, height
;; in scanlines and a pen, over and over, ending in #FF, drawn relative to
;; (prop_x),(prop_y). Boxes are almost free and a fridge is a box - and a
;; counter is a box, which is why both games on this engine draw their rooms
;; this way rather than out of bitmaps there is no room for.
;;
;; Where the box lists themselves live is each game's business: one keeps them
;; in its room tables, the other paints one room by hand.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; pen_bytes - the byte that fills a whole rectangle with one pen, by pen
;; number. Mode 0 spreads a pixel's four pen bits across the byte, so there is
;; no arithmetic shortcut and the sixteen are written out in config.asm.
;; ---------------------------------------------------------------------------
pen_bytes
    defb PEN0_BYTE,  PEN1_BYTE,  PEN2_BYTE,  PEN3_BYTE
    defb PEN4_BYTE,  PEN5_BYTE,  PEN6_BYTE,  PEN7_BYTE
    defb PEN8_BYTE,  PEN9_BYTE,  PEN10_BYTE, PEN11_BYTE
    defb PEN12_BYTE, PEN13_BYTE, PEN14_BYTE, PEN15_BYTE

;; ---------------------------------------------------------------------------
;; draw_boxes - HL = box list, drawn relative to (prop_x),(prop_y).
;; ---------------------------------------------------------------------------
draw_boxes
    ld a,(hl)
    inc a
    ret z
    dec a
    ld b,a                      ; dx
    ld a,(prop_x)
    add a,b
    ld (fill_x),a
    inc hl

    ld b,(hl)                   ; dy
    inc hl
    ld a,(prop_y)
    add a,b
    ld (box_top),a
    ld a,0                      ; ld does not touch the carry
    adc a,0                     ; 1 if the top ran past scanline 255
    ld (box_over),a

    ld a,(hl)                   ; width in bytes
    inc hl
    ld c,a
    ld b,0
    push hl
    ld h,b
    ld l,c
    ld (fill_w),hl
    pop hl

    ld a,(hl)                   ; height in scanlines
    inc hl
    ld (box_high),a

    ld a,(hl)                   ; pen
    inc hl
    push hl
    ld l,a
    ld h,0
    ld de,pen_bytes
    add hl,de
    ld a,(hl)
    ld (fill_b),a

    ;; Clip. line_tab has one entry per displayed scanline and the workspace
    ;; follows it, so a box that runs past the bottom would index off the end
    ;; and fill variables instead of screen. Do not trust the table.
    ld a,(box_over)
    or a
    jr nz,draw_boxes_next
    ld a,(box_top)
    ld c,a
    ld a,(box_high)
    ld b,a
    ld a,c
    add a,b
    jr nc,draw_boxes_fill
    xor a
    sub c                       ; only what fits above scanline 255
    ld b,a
    or a
    jr z,draw_boxes_next
draw_boxes_fill
    ld l,c                      ; line_tab entry for the top scanline
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    ld e,b
    ld d,0
    call fill_rows
draw_boxes_next
    pop hl
    jr draw_boxes

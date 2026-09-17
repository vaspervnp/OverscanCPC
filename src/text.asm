;; ===========================================================================
;; text.asm - drawing glyphs from the generated font, at two sizes.
;;
;; Small text is 1:1. A glyph row is 8 source pixels and mode 1 packs 4 pixels
;; per byte, so the row splits into two screen bytes with no shifting at all:
;; for pen 1 the mode 1 encoding puts pixel i's only set bit at bit 7-i, which
;; makes the left byte (row AND #F0) and the right byte (row rotated left 4).
;;
;; Big text scales each source pixel to whole bytes across and whole scanlines
;; down, so it also never shifts.
;;
;; Both OR the glyph onto the background, and in mode 1 that is not neutral: a
;; set source pixel contributes pen bit 0 while pen bit 1 survives from what
;; was underneath. Letters come out pen 1 over pen 0 and pen 3 over pen 2,
;; which is how text stays readable when it crosses a coloured band.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; get_msg - A = message id -> HL = the length-prefixed string, in the
;; language currently selected in txt_lang.
;; Destroys AF, DE, HL.
;; ---------------------------------------------------------------------------
get_msg
    push af
    ld hl,lang_tables
    ld a,(txt_lang)
    add a,a
    ld e,a
    ld d,0
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)               ; DE = this language's message pointer table
    pop af
    add a,a
    ld l,a
    ld h,0
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    ret

;; ---------------------------------------------------------------------------
;; glyph_addr - A = glyph index -> IX = its 8 bytes in the font.
;; ---------------------------------------------------------------------------
glyph_addr
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,font
    add hl,de
    push hl
    pop ix
    ret

;; ===========================================================================
;; Small text - 1:1, one 8x8 cell per character
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; msg_small - A = message id, (txt_row) = line_tab pointer for the top
;; scanline, (txt_x) = x in bytes.
;; ---------------------------------------------------------------------------
msg_small
    call get_msg
    jr print_small

;; ---------------------------------------------------------------------------
;; msg_small_centre - as msg_small but horizontally centred: x = 48 - length.
;; ---------------------------------------------------------------------------
msg_small_centre
    call get_msg
    ;; fall through

;; ---------------------------------------------------------------------------
;; small_centre - HL = length-prefixed string, centred: x = 48 - length.
;; ---------------------------------------------------------------------------
small_centre
    ld a,(hl)
    neg
    add a,CENTRE_HALF
    ld (txt_x),a
    ;; fall through

;; ---------------------------------------------------------------------------
;; print_small - HL = length-prefixed string.
;; ---------------------------------------------------------------------------
print_small
    ld a,(hl)
    inc hl
    or a
    ret z
    ld b,a
print_small_char
    push bc
    push hl
    ld a,(hl)
    call glyph_addr
    ld hl,(txt_row)
    call draw_glyph_small
    ld a,(txt_x)
    add a,SMALL_W_BYTES
    ld (txt_x),a
    pop hl
    inc hl
    pop bc
    djnz print_small_char
    ret

;; ---------------------------------------------------------------------------
;; draw_glyph_small - IX = glyph, HL = line_tab pointer, (txt_x) = x in bytes.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
draw_glyph_small
    ld b,8                          ; one scanline per source row
draw_glyph_small_line
    push bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(txt_x)
    add a,e
    ld e,a
    jr nc,draw_glyph_small_nc
    inc d
draw_glyph_small_nc
    ld a,(ix+0)
    inc ix
    ld c,a
    and #F0                         ; left 4 pixels
    ld b,a
    ld a,(de)
    or b
    ld (de),a
    inc de
    ld a,c
    rlca
    rlca
    rlca
    rlca
    and #F0                         ; right 4 pixels
    ld b,a
    ld a,(de)
    or b
    ld (de),a
    pop bc
    djnz draw_glyph_small_line
    ret

;; ---------------------------------------------------------------------------
;; print_glyph - A = glyph index. Draws it small at (txt_x),(txt_row) and
;; advances txt_x by one cell.
;; ---------------------------------------------------------------------------
print_glyph
    call glyph_addr
    ld hl,(txt_row)
    call draw_glyph_small
    ld a,(txt_x)
    add a,SMALL_W_BYTES
    ld (txt_x),a
    ret

;; ---------------------------------------------------------------------------
;; print_digit - A = a digit in the low nibble.
;; ---------------------------------------------------------------------------
print_digit
    and #0F
    add a,GL_0
    jr print_glyph

;; ---------------------------------------------------------------------------
;; print_digits - HL = packed BCD, most significant byte first, B = how many
;; bytes. Two digits per byte, which is why the score is kept in BCD: DAA
;; makes the arithmetic free and printing needs no division.
;; ---------------------------------------------------------------------------
print_digits
print_digits_loop
    push bc
    push hl
    ld a,(hl)
    push af
    rrca
    rrca
    rrca
    rrca
    call print_digit
    pop af
    call print_digit
    pop hl
    inc hl
    pop bc
    djnz print_digits_loop
    ret

;; ===========================================================================
;; Big text - (txt_xs) bytes per source pixel, (txt_ys) scanlines per row
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; msg_big_centre - A = message id, centred for the current txt_xs.
;; x = 48 - length*txt_xs*4
;; ---------------------------------------------------------------------------
msg_big_centre
    call get_msg
    ;; fall through

;; ---------------------------------------------------------------------------
;; big_centre - HL = length-prefixed string, centred for the current txt_xs.
;; ---------------------------------------------------------------------------
big_centre
    push hl
    ld a,(hl)
    ld b,a
    ld a,(txt_xs)
    add a,a
    add a,a
    add a,a                         ; 8 source pixels * txt_xs = bytes per cell
    ld c,a
    xor a
msg_big_width
    add a,c
    djnz msg_big_width
    srl a
    neg
    add a,CENTRE_HALF
    ld (txt_x),a
    pop hl
    ;; fall through

;; ---------------------------------------------------------------------------
;; print_big - HL = length-prefixed string.
;; ---------------------------------------------------------------------------
print_big
    ld a,(hl)
    inc hl
    or a
    ret z
    ld b,a
print_big_char
    push bc
    push hl
    ld a,(hl)
    call glyph_addr
    ld hl,(txt_row)
    call draw_glyph
    ld a,(txt_xs)               ; advance one whole cell
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(txt_x)
    add a,b
    ld (txt_x),a
    pop hl
    inc hl
    pop bc
    djnz print_big_char
    ret

;; ---------------------------------------------------------------------------
;; draw_glyph - IX = glyph, HL = line_tab pointer, (txt_x) = x in bytes.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
draw_glyph
    ld b,8                          ; 8 source rows
draw_glyph_row
    push bc
    ld a,(ix+0)
    inc ix
    push hl
    call dg_expand                  ; leaves IX alone
    pop hl
    ld a,(txt_ys)
    ld b,a                          ; each row covers txt_ys scanlines
draw_glyph_scan
    push bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(txt_x)
    add a,e
    ld e,a
    jr nc,draw_glyph_nocarry
    inc d
draw_glyph_nocarry
    push hl
    call dg_blit
    pop hl
    pop bc
    djnz draw_glyph_scan
    pop bc
    djnz draw_glyph_row
    ret

;; ---------------------------------------------------------------------------
;; dg_expand - A = 8 source pixels (bit 7 leftmost) -> dg_pat, repeating each
;; pixel (txt_xs) times. Clear pixels become zero, which blits transparently.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
dg_expand
    ld hl,dg_pat
    ld b,8
dg_expand_loop
    rlca                            ; 8 rotates leave A as it started
    ld c,0
    jr nc,dg_expand_store
    ld c,PEN1_BYTE
dg_expand_store
    push af
    ld a,(txt_xs)
dg_expand_rep
    ld (hl),c
    inc hl
    dec a
    jr nz,dg_expand_rep
    pop af
    djnz dg_expand_loop
    ret

;; ---------------------------------------------------------------------------
;; dg_blit - OR the expanded row onto the screen at DE.
;; Destroys AF, B, DE, HL.
;; ---------------------------------------------------------------------------
dg_blit
    ld hl,dg_pat
    ld a,(txt_xs)
    add a,a
    add a,a
    add a,a                         ; 8 source pixels * txt_xs
    ld b,a
dg_blit_loop
    ld a,(de)
    or (hl)
    ld (de),a
    inc hl
    inc de
    djnz dg_blit_loop
    ret

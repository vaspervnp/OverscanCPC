;; ===========================================================================
;; text.asm - blow an 8x8 glyph up to 64x96 pixels and OR it onto the screen.
;;
;; Each source pixel becomes 8 screen pixels wide, which in mode 1 is exactly
;; 2 bytes - no bit shifting anywhere. Clear source pixels are left
;; transparent so the letters sit on top of the background rather than boxing
;; it out.
;;
;; The glyph is OR-ed on, and in mode 1 that is not a neutral operation: a set
;; source pixel contributes pen bit 0 while pen bit 1 survives from whatever
;; was underneath. Over the black interior (pen 0) a letter comes out pen 1,
;; over the blue overscan region (pen 2) it comes out pen 3. That is
;; deliberate - the letters change colour exactly where they cross the edge of
;; the screen a normal CPC would have given us.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; draw_all_text
;; ---------------------------------------------------------------------------
draw_all_text
    ld a,TEXT_X
    ld (dg_x),a
    ld hl,line_tab+TEXT1_Y*2
    ld (dg_row),hl
    ld hl,txt_hello
    call draw_text

    ld a,TEXT_X
    ld (dg_x),a
    ld hl,line_tab+TEXT2_Y*2
    ld (dg_row),hl
    ld hl,txt_world
    jp draw_text

txt_hello   defb GL_H,GL_E,GL_L,GL_L,GL_O,#FF
txt_world   defb GL_W,GL_O,GL_R,GL_L,GL_D,#FF

;; ---------------------------------------------------------------------------
;; draw_text - HL = string of glyph indices, #FF terminated.
;; (dg_x) is advanced as it goes; (dg_row) is the top scanline of the line.
;; ---------------------------------------------------------------------------
draw_text
draw_text_loop
    ld a,(hl)
    inc a
    ret z
    dec a
    push hl
    ld l,a                  ; IX = font + glyph*8
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,font
    add hl,de
    push hl
    pop ix
    ld hl,(dg_row)
    call draw_glyph
    ld a,(dg_x)
    add a,GLYPH_ADV
    ld (dg_x),a
    pop hl
    inc hl
    jr draw_text_loop

;; ---------------------------------------------------------------------------
;; draw_glyph
;;   IX       = 8-byte glyph bitmap (advanced past it on return)
;;   HL       = pointer into line_tab for the glyph's top scanline
;;   (dg_x)   = x position in bytes
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
draw_glyph
    ld b,8                  ; 8 rows in the bitmap
draw_glyph_row
    push bc
    ld a,(ix+0)
    inc ix
    push hl
    call dg_expand
    pop hl
    ld b,SCALE_Y            ; each bitmap row covers SCALE_Y scanlines
draw_glyph_scan
    push bc
    ld e,(hl)               ; scanline address from the table
    inc hl
    ld d,(hl)
    inc hl
    ld a,(dg_x)
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
;; dg_expand - A = 8 source pixels (bit 7 leftmost) -> 16 bytes in dg_pat.
;; A set pixel becomes two solid pen-1 bytes, a clear one two zero bytes.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
dg_expand
    ld hl,dg_pat
    ld b,8
dg_expand_loop
    rlca                    ; carry = next source pixel; 8 rotates restore A
    ld c,0
    jr nc,dg_expand_store
    ld c,PEN1_BYTE
dg_expand_store
    ld (hl),c
    inc hl
    ld (hl),c
    inc hl
    djnz dg_expand_loop
    ret

;; ---------------------------------------------------------------------------
;; dg_blit - OR the 16 bytes of dg_pat onto the screen at DE. Clear source
;; pixels are zero in dg_pat, so they leave the background alone.
;; Destroys AF, B, DE, HL.
;; ---------------------------------------------------------------------------
dg_blit
    ld hl,dg_pat
    ld b,GLYPH_W_BYTES
dg_blit_loop
    ld a,(de)
    or (hl)
    ld (de),a
    inc hl
    inc de
    djnz dg_blit_loop
    ret

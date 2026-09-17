;; ===========================================================================
;; video.asm - scanline address table and rectangle fills.
;;
;; The CPC does not wire MA10/MA11 to the address bus, so consecutive
;; scanlines are 2048 bytes apart and only 1024 characters are addressable per
;; raster slice. Rather than recompute that for every plot, build a table of
;; the 272 scanline start addresses once and index it.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; build_line_tab - fill line_tab with the start address of each scanline.
;;
;; Scanline L: row = L/8, raster = L mod 8.
;;   row 0..20 : #8020 + raster*2048 + row*96      (page 2, #8000)
;;   row 21..33: #C000 + raster*2048 + (row-21)*96 (page 3, #C000)
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
build_line_tab
    ld hl,line_tab
    ld de,PAGE2_BASE
    ld c,PAGE2_ROWS
build_line_tab_p2
    call build_line_tab_row
    dec c
    jr nz,build_line_tab_p2

    ld de,PAGE3_BASE
    ld c,DISPLAY_ROWS-PAGE2_ROWS
build_line_tab_p3
    call build_line_tab_row
    dec c
    jr nz,build_line_tab_p3
    ret

;; One character row: 8 entries 2048 bytes apart, then step DE on by one row.
;; DE = row base, HL = table pointer. Preserves C.
build_line_tab_row
    push de
    ld b,8
build_line_tab_raster
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld a,d
    add a,8                 ; +2048: the next raster line of the same row
    ld d,a
    djnz build_line_tab_raster
    pop de
    ld a,e
    add a,BYTES_PER_LINE
    ld e,a
    ret nc
    inc d
    ret

;; ---------------------------------------------------------------------------
;; fill_rows - fill a byte-aligned rectangle.
;;   HL       = pointer into line_tab for the first scanline
;;   DE       = number of scanlines
;;   (fill_x) = x offset in bytes, (fill_w) = width in bytes
;;   (fill_b) = byte value to write
;; Destroys AF, BC, DE, HL.
;;
;; Every argument is clamped on the way in. A rectangle that hangs off the
;; screen is a data mistake and should draw wrong, not destroy the program,
;; and two of the ways it can go wrong here are silent:
;;
;;   * A count that walks past the end of line_tab has the loop read workspace
;;     bytes as a scanline address and smear over our own variables - fill_w
;;     among them, which the next row would then read back as a 64K LDIR.
;;   * A width of 1 leaves BC = 0 after the DEC, and LDIR takes that as 65536.
;; ---------------------------------------------------------------------------
fill_rows
    ld a,d
    or e
    ret z                       ; no scanlines
    push ix
    push hl                     ; table pointer
    push de                     ; scanlines asked for

    ;; --- the table pointer has to be inside line_tab -----------------------
    ld bc,line_tab
    or a
    sbc hl,bc                   ; HL = byte offset into the table
    jr c,fill_rows_bad          ; before the table
    ld bc,DISPLAY_LINES*2
    ld a,h
    cp b
    jr c,fill_rows_fits
    jr nz,fill_rows_bad
    ld a,l
    cp c
    jr nc,fill_rows_bad         ; at or past the end of the table
fill_rows_fits

    ;; --- clamp the count to the rows the table still holds ------------------
    ex de,hl                    ; DE = offset
    ld h,b
    ld l,c
    or a
    sbc hl,de                   ; HL = bytes left in the table
    srl h
    rr l                        ; HL = scanlines left, never zero here
    pop de                      ; scanlines asked for
    push hl
    or a
    sbc hl,de
    pop hl
    jr nc,fill_rows_rows_ok     ; asked for no more than there is
    ex de,hl                    ; clamp to what is left
fill_rows_rows_ok
    push de

    ;; --- clamp the width to what is left of the scanline --------------------
    ld a,(fill_x)
    cp BYTES_PER_LINE
    jr nc,fill_rows_bad         ; starts past the end of the line
    ld c,a
    ld a,BYTES_PER_LINE
    sub c
    ld c,a                      ; what is left of the line
    ld hl,(fill_w)
    ld a,h
    or a
    jr nz,fill_rows_clip        ; 256 or wider is certainly too wide
    ld a,l
    or a
    jr z,fill_rows_bad          ; nothing to draw
    cp c
    jr c,fill_rows_go
    jr z,fill_rows_go
fill_rows_clip
    ld l,c
    ld h,0
fill_rows_go
    dec hl
    push hl
    pop ix                      ; IX = LDIR count, out of reach of the smear
    pop de                      ; clamped scanline count
    pop hl                      ; table pointer
    jr fill_rows_loop

fill_rows_bad
    pop de
    pop hl
    pop ix
    ret

fill_rows_loop
    push de                 ; scanline counter
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl                 ; table pointer
    ex de,hl                ; HL = start of this scanline
    ld a,(fill_x)
    ld c,a
    ld b,0
    add hl,bc
    ld a,(fill_b)
    ld (hl),a               ; seed byte, then smear it with LDIR
    push ix
    pop bc
    ld a,b
    or c
    jr z,fill_rows_next     ; one byte wide - the seed is the whole row
    ld d,h
    ld e,l
    inc de
    ldir
fill_rows_next
    pop hl
    pop de
    dec de
    ld a,d
    or e
    jr nz,fill_rows_loop
    pop ix
    ret

;; ---------------------------------------------------------------------------
;; fill_screen - paint the whole overscan window in pen 2, then repaint the
;; area a normal 40x25 screen would have covered in pen 0. The colour change
;; is the point of the demo: everything blue was border a moment ago.
;; ---------------------------------------------------------------------------
fill_screen
    ld a,0
    ld (fill_x),a
    ld hl,BYTES_PER_LINE
    ld (fill_w),hl
    ld a,PEN2_BYTE
    ld (fill_b),a
    ld hl,line_tab
    ld de,DISPLAY_LINES
    call fill_rows

    ld a,INNER_X0
    ld (fill_x),a
    ld hl,INNER_W
    ld (fill_w),hl
    ld a,PEN0_BYTE
    ld (fill_b),a
    ld hl,line_tab+INNER_Y0*2
    ld de,INNER_H
    jp fill_rows

;; ---------------------------------------------------------------------------
;; clear_rows - fill whole scanlines with one pen, the common case.
;;   HL = pointer into line_tab for the first scanline
;;   DE = number of scanlines
;;   A  = byte value
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
clear_rows
    ld (fill_b),a
    xor a
    ld (fill_x),a
    push hl
    ld hl,BYTES_PER_LINE
    ld (fill_w),hl
    pop hl
    jp fill_rows

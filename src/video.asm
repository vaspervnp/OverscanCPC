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
;;   (fill_x) = x offset in bytes, (fill_w) = width in bytes (never 0)
;;   (fill_b) = byte value to write
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
fill_rows
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
    ld d,h
    ld e,l
    inc de
    ld bc,(fill_w)
    dec bc
    ldir
    pop hl
    pop de
    dec de
    ld a,d
    or e
    jr nz,fill_rows_loop
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

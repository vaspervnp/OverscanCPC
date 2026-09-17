;; ===========================================================================
;; sprite.asm - masked sprites with background save and restore.
;;
;; There is no double buffer: a second 32 KB overscan screen plus code does
;; not fit comfortably in 128 KB, and repainting 26 KB of background every
;; frame is out of the question. So each sprite keeps the patch of background
;; it covered, puts it back before it moves, and takes a fresh copy at the new
;; position. Static scenery underneath - a sausage on the floor - survives
;; being walked over for free, because it was part of what got saved.
;;
;; Drawing is  screen = (screen AND mask) OR data,  with mask and data
;; interleaved so both come off one advancing pointer.
;;
;; Sprites are byte aligned, so they step 4 pixels at a time horizontally and
;; one scanline at a time vertically. Pixel-exact horizontal movement needs
;; four pre-shifted copies of every frame; worth doing when it looks wrong,
;; not before.
;;
;; Every routine walks line_tab rather than computing addresses, so the 2048
;; byte scanline stride and the jump from page 2 to page 3 at row 21 cost
;; nothing here.
;;
;; The per-scanline work is what this costs, not the per-byte work, so it is
;; written to do as little of it as possible. There used to be a spr_row_addr
;; subroutine and three passes over every sprite - restore, save, blit - each
;; calling it once a scanline. A call and a return are 7 us, reloading spr_x is
;; another 4, and "ld e,(ix+0)" is 5 on its own because of the index prefix:
;; near 30 us a scanline, and there are about 200 scanlines of sprite in a
;; frame. The line table walk is now inlined, spr_x is held in C for the whole
;; sprite, and the save has been folded into the blit so the background is
;; copied out and the sprite dropped in on a single walk down the rows.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; spr_size - HL = sprite -> spr_w and spr_h set, HL left at the pixel data.
;; ---------------------------------------------------------------------------
spr_size
    ld a,(hl)
    ld (spr_w),a
    inc hl
    ld a,(hl)
    ld (spr_h),a
    inc hl
    ret

;; ---------------------------------------------------------------------------
;; spr_row_addr - IX = line_tab pointer -> DE = that scanline plus spr_x,
;; IX advanced to the next scanline.
;; Destroys AF.
;; ---------------------------------------------------------------------------
spr_row_addr
    ld e,(ix+0)
    ld d,(ix+1)
    inc ix
    inc ix
    ld a,(spr_x)
    add a,e
    ld e,a
    ret nc
    inc d
    ret

;; ---------------------------------------------------------------------------
;; spr_draw - save the background and draw over it in one walk down the rows.
;;   HL = pixel data (past the header), IX = line_tab pointer for the top
;;   scanline, DE = where to save the background, spr_x / spr_w / spr_h set.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
spr_draw
    ld (spr_src),hl
    ld (spr_bufp),de
    ld a,(spr_x)
    ld c,a                      ; x stays in C for the whole sprite
    ld a,(spr_h)
    ld b,a
spr_draw_row
    push bc
    ld e,(ix+0)                 ; the scanline, plus x
    ld d,(ix+1)
    inc ix
    inc ix
    ld a,c
    add a,e
    ld e,a
    jr nc,spr_draw_row_set
    inc d
spr_draw_row_set
    push de

    ex de,hl                    ; HL = screen, DE = the save buffer
    ld de,(spr_bufp)
    ld a,(spr_w)
    ld c,a
    ld b,0
    ldir
    ld (spr_bufp),de

    pop de                      ; back to the start of the row
    ld hl,(spr_src)
    ld a,(spr_w)
    ld b,a
spr_draw_col
    ld a,(de)
    and (hl)                    ; punch the sprite's hole in the background
    inc hl
    or (hl)                     ; drop the sprite into it
    inc hl
    ld (de),a
    inc de
    djnz spr_draw_col
    ld (spr_src),hl

    pop bc
    djnz spr_draw_row
    ret

;; ---------------------------------------------------------------------------
;; spr_blit - draw without keeping what was underneath, for the things that
;; are painted into the background once and left there.
;;   HL = pixel data, IX = line_tab pointer, spr_x / spr_w / spr_h set.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
spr_blit
    ld (spr_src),hl
    ld a,(spr_x)
    ld c,a
    ld a,(spr_h)
    ld b,a
spr_blit_row
    push bc
    ld e,(ix+0)
    ld d,(ix+1)
    inc ix
    inc ix
    ld a,c
    add a,e
    ld e,a
    jr nc,spr_blit_set
    inc d
spr_blit_set
    ld hl,(spr_src)
    ld a,(spr_w)
    ld b,a
spr_blit_col
    ld a,(de)
    and (hl)
    inc hl
    or (hl)
    inc hl
    ld (de),a
    inc de
    djnz spr_blit_col
    ld (spr_src),hl
    pop bc
    djnz spr_blit_row
    ret

;; ---------------------------------------------------------------------------
;; spr_restore - put a saved background back. HL = buffer, IX = line_tab
;; pointer, spr_x / spr_w / spr_h as they were when it was saved.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
spr_restore
    ld a,(spr_x)
    ld c,a
    ld a,(spr_h)
    ld b,a
spr_restore_row
    push bc
    ld e,(ix+0)
    ld d,(ix+1)
    inc ix
    inc ix
    ld a,c
    add a,e
    ld e,a
    jr nc,spr_restore_set
    inc d
spr_restore_set
    ld a,(spr_w)
    ld c,a
    ld b,0
    ldir                        ; buffer -> screen
    pop bc
    djnz spr_restore_row
    ret

;; ---------------------------------------------------------------------------
;; spr_row_ptr - A = scanline -> IX = line_tab entry for it.
;; Destroys AF, DE, HL, IX.
;; ---------------------------------------------------------------------------
spr_row_ptr
    ld l,a
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    push hl
    pop ix
    ret

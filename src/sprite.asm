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
;; spr_blit - draw. HL = pixel data (past the header), IX = line_tab pointer
;; for the top scanline, spr_x / spr_w / spr_h set.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
spr_blit
    ld a,(spr_h)
    ld b,a
spr_blit_row
    push bc
    call spr_row_addr
    ld a,(spr_w)
    ld b,a
spr_blit_col
    ld a,(de)
    and (hl)                    ; punch the sprite's hole in the background
    inc hl
    or (hl)                     ; drop the sprite into it
    inc hl
    ld (de),a
    inc de
    djnz spr_blit_col
    pop bc
    djnz spr_blit_row
    ret

;; ---------------------------------------------------------------------------
;; spr_save - copy the background into HL. IX = line_tab pointer, spr_x /
;; spr_w / spr_h set. HL is left past the end of the saved data.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
spr_save
    ld a,(spr_h)
    ld b,a
spr_save_row
    push bc
    call spr_row_addr
    ld a,(spr_w)
    ld c,a
    ld b,0
    ex de,hl                    ; HL = screen, DE = buffer
    ldir
    ex de,hl                    ; HL = next free byte of the buffer
    pop bc
    djnz spr_save_row
    ret

;; ---------------------------------------------------------------------------
;; spr_restore - put a saved background back. HL = buffer, IX = line_tab
;; pointer, spr_x / spr_w / spr_h as they were when it was saved.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
spr_restore
    ld a,(spr_h)
    ld b,a
spr_restore_row
    push bc
    call spr_row_addr
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

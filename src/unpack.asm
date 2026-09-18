;; ===========================================================================
;; unpack.asm - put a packed overscan picture on the screen.
;;
;; The whole screen is 96 bytes by 272 scanlines, which is 26,112 bytes. There
;; is nowhere in this machine to keep that: the screen itself is 32 KB of the
;; 64, the code and its tables are most of the rest, and a title screen cannot
;; have the only sixteen kilobytes left. Packed it is about seven, which fits.
;;
;; The format is LZSS - see the header of tools/mkscreen.py - and the thing
;; that makes it cheap here is that it keeps no window. A decompressor usually
;; needs the last N bytes of its own output to copy from, which means a buffer.
;; This one is writing to the screen, and the screen is the window: a back
;; reference of at most 2047 bytes is at most twenty-two rows up, and line_tab
;; already knows where every row is. So a match is two cursors walking the
;; picture, one behind the other, and no RAM at all beyond the eleven bytes of
;; state below.
;;
;; It runs once, when the title screen is built, and takes a good fraction of a
;; second. The palette is black while it works, which is why nobody sees it.
;; ===========================================================================

UNP_MINLEN      EQU 3           ; the shortest match worth two bytes

;; ---------------------------------------------------------------------------
;; unpack_pic - HL = the packed stream. Fills the whole screen.
;; ---------------------------------------------------------------------------
unpack_pic
    ld (unp_src),hl
    ld hl,line_tab
    ld (unp_drow),hl
    call unp_dest_row
    xor a
    ld (unp_dcol),a
    ld hl,DISPLAY_LINES
    ld (unp_rows),hl

unpack_flags
    call unp_fetch
    ld c,a                      ; eight bits of "literal or match"
    ld b,8
unpack_bit
    ld hl,(unp_rows)
    ld a,h
    or l
    ret z                       ; the picture is complete
    sla c
    jr nc,unpack_match
    call unp_fetch              ; 1: one byte, as it stands
    call unp_put
    jp unpack_next              ; the match below is well over a jr's reach

;; A match: an offset back through the output and a length. Both cursors are
;; (address, column, line_tab pointer), because a run can cross a row.
unpack_match
    push bc
    call unp_fetch
    ld e,a                      ; offset, low eight bits
    call unp_fetch
    push af
    and #1F
    add a,UNP_MINLEN
    ld (unp_len),a
    pop af
    rlca                        ; the top three bits are the offset's high ones
    rlca
    rlca
    and 7
    ld d,a

    ld a,(unp_dcol)             ; where that lands: this column, less the
    ld l,a                      ; offset, borrowing a whole row at a time
    ld h,0
    or a
    sbc hl,de
    ld de,(unp_drow)
unp_back
    bit 7,h
    jr z,unp_back_done
    ld bc,BYTES_PER_LINE
    add hl,bc
    dec de                      ; one line_tab entry back
    dec de
    jr unp_back
unp_back_done
    ld a,l
    ld (unp_scol),a
    ld (unp_srow),de
    ex de,hl
    ld e,(hl)                   ; the start of that scanline
    inc hl
    ld d,(hl)
    ld a,(unp_scol)
    add a,e
    ld e,a
    jr nc,unp_match_set
    inc d
unp_match_set
    ld (unp_sp),de

    ld a,(unp_len)
    ld b,a
unp_copy
    push bc
    ld hl,(unp_sp)
    ld a,(hl)
    call unp_put                ; read before write: an overlapping match,
                                ; which is how a run is encoded, comes out right
    ld hl,(unp_sp)
    inc hl
    ld (unp_sp),hl
    ld hl,unp_scol
    inc (hl)
    ld a,(hl)
    cp BYTES_PER_LINE
    jr c,unp_copy_next
    ld (hl),0                   ; off the end of that row: down to the next
    ld hl,(unp_srow)
    inc hl
    inc hl
    ld (unp_srow),hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (unp_sp),de
unp_copy_next
    pop bc
    djnz unp_copy
    pop bc

unpack_next
    dec b
    jp nz,unpack_bit
    jp unpack_flags

;; ---------------------------------------------------------------------------
;; unp_fetch - A = the next byte of the stream. Leaves BC and DE alone.
;; ---------------------------------------------------------------------------
unp_fetch
    push hl
    ld hl,(unp_src)
    ld a,(hl)
    inc hl
    ld (unp_src),hl
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; unp_put - A = one byte of picture, onto the screen and on with the cursor.
;; Leaves BC alone.
;; ---------------------------------------------------------------------------
unp_put
    push hl
    push de
    ld hl,(unp_dp)
    ld (hl),a
    inc hl
    ld (unp_dp),hl
    ld hl,unp_dcol
    inc (hl)
    ld a,(hl)
    cp BYTES_PER_LINE
    jr c,unp_put_count
    ld (hl),0
    ld hl,(unp_drow)
    inc hl
    inc hl
    ld (unp_drow),hl
    ld hl,(unp_rows)            ; counted by the row, not by the byte: this is
    dec hl                      ; the inner loop of 26,112 bytes of picture
    ld (unp_rows),hl
    call unp_dest_row
unp_put_count
    pop de
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; unp_dest_row - unp_dp = the start of the scanline unp_drow points at.
;; ---------------------------------------------------------------------------
unp_dest_row
    ld hl,(unp_drow)
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (unp_dp),de
    ret

;; ---------------------------------------------------------------------------
;; unpack_tables - HL = the packed tables, DE = where they go.
;;
;; The other decompressor in this file walks the screen, because a screen is
;; not linear. The tables are, and they always land at the same address, so a
;; match carries the address it is copied from rather than a distance back -
;; which makes the whole of what has already been unpacked the window, and
;; makes the copy an LDIR with no arithmetic in front of it.
;;
;; Flag byte, most significant bit first: 1 is a literal, 0 is a match of
;; length, address low, address high. A length of zero is the end.
;;
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
unpack_tables
    ld a,(hl)                   ; the next eight flags
    inc hl
    ld c,a
    ld b,8
unpack_tables_bit
    sla c
    jr nc,unpack_tables_match
    ld a,(hl)                   ; a literal
    inc hl
    ld (de),a
    inc de
    djnz unpack_tables_bit
    jr unpack_tables

unpack_tables_match
    ld a,(hl)                   ; how many bytes, and zero ends the stream
    or a
    ret z
    push bc                     ; the flags and what is left of the eight
    ld c,a
    ld b,0
    inc hl
    inc hl
    inc hl
    push hl                     ; the stream, three bytes on
    dec hl
    ld a,(hl)                   ; where it is copied from
    dec hl
    ld l,(hl)
    ld h,a
    ldir
    pop hl
    pop bc
    djnz unpack_tables_bit
    jr unpack_tables

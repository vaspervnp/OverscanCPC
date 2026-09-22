;; ===========================================================================
;; mitsospage.asm - the only code in the low block, and it has to be there.
;;
;; The 6128 has a second sixty-four kilobytes. Four of its banks can be paged
;; over **#4000-#7FFF** in place of bank 1 - port #7Fxx, values #C4 to #C7 -
;; and that window is exactly where this game's code and its title picture
;; live. So the routine that does the paging cannot be in the window: while
;; bank 4 is in, every byte from #4000 to #7FFF belongs to somebody else,
;; including the instruction that would page it back out. It runs from #0100
;; with the rest of the low block instead, and it is the one thing down there
;; that is executed rather than read.
;;
;; Two things have to be true across the window and both are arranged
;; elsewhere. **Interrupts are off**, because #0038 jumps to irq_handler at
;; #4000-something and the music player is up there with it. And **the stack
;; is below #4000** - MITSOS_STACK, not the other game's #7FFE - so a push or
;; a return inside the window reaches real memory rather than bank 4.
;;
;; The screen is not in the window. #8000-#FFFF is banks 2 and 3 in every one
;; of these configurations, so the picture on the tube does not flicker, tear
;; or notice.
;; ===========================================================================

CFG_ROOMS       EQU #C4         ; bank 4 over #4000-#7FFF
CFG_HOME        EQU #C0         ; and the ordinary sixty-four kilobytes

;; ---------------------------------------------------------------------------
;; rooms_to_bank - every room out of the file and into bank 4, once, at boot.
;; HL = where the file left the image, BC = how long it is.
;; Destroys AF, BC, DE, HL.
;;
;; The source is above #8000, which no configuration here touches, so this is
;; an ordinary LDIR with the window open underneath it. It has to happen
;; before anything looks at the screen, because that is where the file is.
;; ---------------------------------------------------------------------------
rooms_to_bank
    di
    ld a,CFG_ROOMS
    call page_set
    ld de,ROOM_BANK
    ldir
    jr page_home                ; and interrupts stay off: this is the twelfth
                                ; instruction of the game and irq_init has not
                                ; written the jump at #0038 yet. Enabling them
                                ; before it does lands the CPU on whatever is
                                ; down there, which with both ROMs off is the
                                ; low block, read as code

;; ---------------------------------------------------------------------------
;; room_read - A = which room, DE = where to put it. ROOM_USED bytes of it.
;; Destroys AF, BC, DE, HL.
;;
;; Called once a room and not once a frame, so the sixteen kilobytes going in
;; and out cost nothing worth counting - and it is called from room_start,
;; which is about to spend a second painting the place.
;; ---------------------------------------------------------------------------
room_read
    di
    ld l,a                      ; HL = the room x ROOM_BLOCK
    ld h,0
    add hl,hl                   ; x2
    add hl,hl                   ; x4
    add hl,hl                   ; x8
    add hl,hl                   ; x16
    add hl,hl                   ; x32
    add hl,hl                   ; x64
    ld b,h
    ld c,l
    add hl,hl                   ; x128
    add hl,bc                   ; and x192, which is the ROOM_BLOCK
                                ; mitsosshop.asm names and the one number
                                ; this multiply is written for
    ld bc,ROOM_BANK
    add hl,bc
    ld bc,ROOM_USED
    ld a,CFG_ROOMS
    call page_set
    ldir
    call page_home
    ei                          ; this one is called from room_start, with a
    ret                         ; handler at #0038 and a game running

;; ---------------------------------------------------------------------------
;; page_home / page_set - the ordinary map back, or A out on the Gate Array.
;;
;; **BC is kept**, and that is not tidiness: both callers are holding a length
;; for an LDIR across the call, and the Gate Array is addressed through BC. It
;; cost half an hour and a thirty-two kilobyte LDIR into the bank to find out.
;; The push and the pop straddle the switch, which is safe because the stack
;; is below #4000 and no configuration here moves that.
;;
;; Neither touches the interrupt state: whether it is safe to enable them
;; depends on who is asking, and both callers above know while this does not.
;; Destroys AF.
;; ---------------------------------------------------------------------------
page_home
    ld a,CFG_HOME
    ;; fall through
page_set
    push bc
    ld bc,#7F00
    ld c,a
    out (c),c
    pop bc
    ret

;; ===========================================================================
;; mitsosbank.asm - the rooms on their own, assembled where bank 4 will hold
;; them, so the image can be saved and carried.
;;
;; A third pass, for the same reason as the second: the game cannot assemble
;; these in place. They run at #4000-#7FFF, which is where its own code is,
;; and they only ever exist there with bank 4 paged in - a state the code
;; cannot be executing in. So they are built here, saved raw, carried in the
;; file above the screen, and put in the bank by rooms_to_bank at boot.
;;
;; Everything below #4000 is assembled first and only for its labels, because
;; a room's prop list points at box lists in mitsosfurniture.asm and its
;; pickups at sprites in mitsosart.asm - addresses that have to be right, and
;; that stay valid when the bank is paged out, which is the whole reason the
;; furniture stays down there and the rooms do not.
;; ===========================================================================

    include "config.asm"
    include "mitsosshop.asm"

    ORG DATA_ORG
    include "font.asm"
    include "mitsosstr.asm"
    include "mitsosart.asm"
pantomusic_song
    include "pantomusic.asm"
    include "mitsosdata.asm"
    include "mitsosfurniture.asm"
    include "mitsospage.asm"

    include "mitsosrooms.asm"       ; which ORGs itself into the bank

    SAVE "build/mitsosrooms.bin",ROOM_BANK,rooms_end-ROOM_BANK

;; ===========================================================================
;; lowblock.asm - the tables on their own, so they can be weighed and packed.
;;
;; This is the first of the two passes the build makes. It assembles exactly
;; the same six files the game's low block does, at exactly the address they
;; run at, and saves the result raw. tools/mkpack.py then packs that into
;; src/tablepack.asm, which is what the game actually carries.
;;
;; Nothing may be added here that is not in the game's own low block, and
;; nothing may be left out of it: the packed copy is checked back against this
;; binary, byte for byte, by make check.
;; ===========================================================================

    include "config.asm"

    ORG DATA_ORG
data_start
    include "font.asm"
    include "strings.asm"
    include "sprites.asm"
    include "artwork.asm"
    include "enemykind.asm"
    include "rooms.asm"
data_end

    SAVE "build/tables.bin",data_start,data_end-data_start

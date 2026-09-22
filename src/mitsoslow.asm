;; ===========================================================================
;; mitsoslow.asm - the second game's pictures on their own, so they can be
;; weighed and packed.
;;
;; The same two-pass arrangement lowblock.asm sets up for the first game, and
;; for the same reason: ten kilobytes of masked sprites is read-only, it goes
;; into place before anything else runs, and it has no business being carried
;; verbatim in a file that has twenty-six kilobytes to spend and wants a
;; title picture in them as well.
;;
;; The song rides down there with the pictures for the same reason: the AKG
;; player reads it and never executes it, and it is two hundred and forty-two
;; bytes of a sixteen kilobyte address space that has a title picture to fit
;; in as well. So do the box lists the shop is drawn from, the table that
;; stocks its shelves and the palette, which is another eight hundred.
;;
;; This pass assembles both files at exactly the address they run at and
;; saves it raw; tools/mkpack.py packs that into src/mitsosartpack.asm, which
;; is what the game actually carries. Nothing may be added here that is not
;; in the game's own low block and nothing left out of it - make check
;; compares what the Z80 unpacks against this binary, byte for byte.
;; ===========================================================================

    include "config.asm"
    include "mitsosshop.asm"

    ORG DATA_ORG
art_start
    include "font.asm"
    include "mitsosstr.asm"
    include "mitsosart.asm"
pantomusic_song
    include "pantomusic.asm"
    include "mitsosdata.asm"
    include "mitsosrooms.asm"
art_end

    SAVE "build/mitsosart.bin",art_start,art_end-art_start

;; ===========================================================================
;; enemykind.asm - what an enemy is, as opposed to what it does.
;;
;; There are only two behaviours in the game - something that walks a platform
;; and something that flies an arc across the room - but nineteen rooms of
;; back yards, playgrounds, corridors and rooftops want more than a robot
;; vacuum and a canary in them. So the type byte in a room's enemy table is an
;; index into this table rather than a branch in the movement code: it names
;; the art and which of the two behaviours drives it, and adding an enemy is
;; three bytes here plus its picture.
;;
;; Data, not code: it lives in the low block with the rest of the tables.
;; ===========================================================================

EB_WALK         EQU 0           ; patrols a platform at half the cat's speed
EB_FLY          EQU 1           ; bounces across the room on a sine

;; Type 0 is "no enemy", so the ids start at 1 and the table is indexed by
;; type-1. Keep the two originals first: room 1 to 10 name them by these ids
;; and the scripted run in make check depends on them.
ET_ROBOT        EQU 1           ; the house: a robot vacuum
ET_CANARY       EQU 2           ; the house: the canary, out of its cage
ET_DOG          EQU 3           ; back yard, pavement, the vet's: next door's terrier
ET_PIGEON       EQU 4           ; park, pavement, rooftops
ET_WASP         EQU 5           ; anywhere with flowers in it
ET_BALL         EQU 6           ; playground, gym, pitch
ET_PLANE        EQU 7           ; school: a paper plane that never lands
ET_MOP          EQU 8           ; school: the caretaker's bucket on wheels
ET_BLOB         EQU 9           ; the chemistry lab, and whatever was in the beaker
ET_SYRINGE      EQU 10          ; the vet's
ET_BAT          EQU 11          ; the rooftops after dark
ET_STRAY        EQU 12          ; the tom who thinks the roofs are his

ET_COUNT        EQU 12

enemy_kinds
    ;; sprite, behaviour
    defw spr_robot
    defb EB_WALK
    defw spr_canary
    defb EB_FLY

EK_SIZE         EQU 3

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
;;
;; A creature that walks or flies is drawn facing the way it is going, which
;; means a mirrored copy of its picture: flipping a mode 0 sprite at draw time
;; means shuffling four pen bits per pixel and reversing the row, three times a
;; frame, on a machine that has already spent its frame. The mirrors are made
;; once, when the art is converted.
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
    ;; the sprite when it is going right, the sprite when it is going left,
    ;; and which of the two behaviours drives it.
    ;;
    ;; Most of the art is drawn facing right, so the mirror is the left-hand
    ;; one and the pair reads in that order. The canary and the stray tom are
    ;; drawn facing left, so theirs is the other way round - which is the whole
    ;; reason the table names both rather than assuming one and flipping.
    ;; Something symmetric, like the robot vacuum or the bat, has the same
    ;; label twice and costs nothing extra: see tools/mkart.py.
    defw spr_robot,     spr_robot_l
    defb EB_WALK
    defw spr_canary_l,  spr_canary     ; drawn facing left
    defb EB_FLY
    defw spr_dog,       spr_dog_l
    defb EB_WALK
    defw spr_pigeon,    spr_pigeon_l
    defb EB_FLY
    defw spr_wasp,      spr_wasp_l
    defb EB_FLY
    defw spr_ball,      spr_ball_l
    defb EB_WALK
    defw spr_plane,     spr_plane_l
    defb EB_FLY
    defw spr_mop,       spr_mop_l
    defb EB_WALK
    defw spr_blob,      spr_blob_l
    defb EB_WALK
    defw spr_syringe,   spr_syringe_l
    defb EB_FLY
    defw spr_bat,       spr_bat_l
    defb EB_FLY
    defw spr_stray_l,   spr_stray      ; drawn facing left
    defb EB_WALK

EK_SIZE         EQU 5

;; ===========================================================================
;; mitsosshop.asm - the numbers the shop's tables are written in.
;;
;; Its own file because two assemblies need it: the game, and the pass in
;; mitsoslow.asm that weighs the low block. Everything that is only ever read
;; is down there now - the box lists that draw the shelving, the table that
;; stocks it, the rooms themselves - and every one of them is written in
;; scanlines off the floor and fields off the start of a record.
;;
;; Nothing in here is code and nothing in here is a decision; it is the
;; vocabulary. What a room actually says is in mitsosrooms.asm.
;; ===========================================================================

;; --- The shop --------------------------------------------------------------
;; Scanlines down and bytes across. A byte is two mode 0 pixels, which is four
;; pixels on the monitor, so the 96 bytes of a line are the full 384.
FLOOR_TOP       EQU 236                 ; the tiles start here
DADO_TOP        EQU 188                 ; and the painted lower wall here
GROUT_STEP      EQU 8                   ; a floor tile is this many bytes
SOAP_H          EQU 10                  ; how deep a puddle of it looks

;; The wall is brick, and at this scale a course is about
;; a hand's width: 16 scanlines to a course, 8 bytes to a brick - 32 pixels on
;; the monitor - and every other course offset by half a brick, which is what
;; makes it read as a wall rather than as a grid. The joints are a byte wide
;; because a byte is the narrowest thing a fill can put down: two mode 0
;; pixels, four on the tube.
BRICK_COURSE    EQU 16
BRICK_MORTAR    EQU 2
BRICK_W         EQU 8

;; The shelf boards, the counter top and the crate lids are all pen 2, and
;; they are 32 scanlines apart, because that is what a cat clears in a jump.
;; "Butter yellow means you can stand on it" is the visual grammar of both
;; games on this engine and it does not change from room to room.
SHELF_1         EQU 204
SHELF_2         EQU 172
SHELF_3         EQU 140
SHELF_4         EQU 108

;; --- What is after him -----------------------------------------------------
FOE_TICK        EQU 3                   ; frames between an enemy's steps
FOE_ANIM        EQU 6                   ; and between its two pictures
FOE_COUNT       EQU 3

;; One enemy. IY addresses these, because IX is the line table cursor inside
;; the sprite routines and there is only one of each.
E_KIND          EQU 0                   ; index into foe_kinds
E_X             EQU 1                   ; where it is, in bytes
E_Y             EQU 2                   ; and scanlines
E_Y0            EQU 3                   ; the line a flier bobs about
E_X0            EQU 4                   ; the ends of its beat
E_X1            EQU 5
E_DIR           EQU 6                   ; 1 or -1
E_TICK          EQU 7                   ; frames until its next step
E_FRAME         EQU 8                   ; which of its two pictures
E_ANIM          EQU 9                   ; frames until the other one
E_STUN          EQU 10                  ; frames left flat on its back
E_PHASE         EQU 11                  ; where it is in the bob
E_DRAWN         EQU 12                  ; is the buffer under it worth anything
E_OX            EQU 13                  ; and where its picture still is
E_OY            EQU 14
E_DIVE          EQU 15                  ; D_NONE, or which half of a dive
E_REST          EQU 16                  ; frames before it tries that again
E_CARRY         EQU 17                  ; a meze it has got hold of, plus one
E_OPOSE         EQU 18                  ; and which picture its picture is: the
                                        ; frame, with bit 7 for facing left.
                                        ; One that is showing the right one in
                                        ; the right place is left alone, and
                                        ; two and a half milliseconds of a
                                        ; twenty-millisecond frame is what
                                        ; that is worth
E_SIZE          EQU 19

;; What a kind of enemy is: two pictures each way round, a size, and whether
;; it flies. Three bytes and its art is what a new one costs.
K_SPR           EQU 0                   ; four words: A and B, right then left
K_W             EQU 8
K_H             EQU 9
K_FLY           EQU 10
K_SIZE          EQU 11

K_MOUSE         EQU 0
K_GULL          EQU 1

D_NONE          EQU 0                   ; on its beat
D_DOWN          EQU 1                   ; coming down
D_UP            EQU 2                   ; and going back up

STEAL_REST      EQU 200                 ; four seconds before it tries again
STEAL_START     EQU 250                 ; and five at the top of a life, so the
                                        ; first meze is not gone before he
                                        ; has had a chance at it

;; --- A room, as it sits in bank 4 ------------------------------------------
;; Fixed offsets in a fixed block, so room_read is one LDIR and every read
;; afterwards is an absolute address rather than an index through a pointer.
;; The room_rec labels in mitsos.asm's workspace are laid out to match and
;; assert that they do; tools/mkrooms.py writes the other side of it.
ROOM_BANK       EQU #4000       ; where a room is while its bank is paged in
ROOM_BLOCK      EQU 192         ; and how far apart they are

R_STARTX        EQU 0           ; where he comes in
R_BASKX         EQU 1           ; the way out, which opens on the last meze
R_BASKY         EQU 2
R_GRANX0        EQU 3           ; the two ends of Grandma's beat
R_GRANX1        EQU 4
R_WALL          EQU 5           ; the five pens the room is painted in, as
R_MORTAR        EQU 6           ; solid mode 0 bytes. Give any of them the pen
R_DADO          EQU 7           ; of the thing behind it and that feature
R_FLOOR         EQU 8           ; stops being there
R_GROUT         EQU 9
R_BORDER        EQU 10          ; and the frame round the lot
R_PLAT          EQU 12          ; 8 x (first column, last column, top) + #FF
R_PROPS         EQU 37          ; 6 x (x, y, box list) + #FF
R_SOAP          EQU 62          ; 3 x (first column, last column, top) + #FF
R_PICKS         EQU 72          ; PICK_COUNT whole pickup records
R_FOES          EQU 112         ; FOE_COUNT whole enemy records
ROOM_USED       EQU 169         ; and the rest of the block is spare

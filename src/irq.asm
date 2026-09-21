;; ===========================================================================
;; irq.asm - the 50 Hz heartbeat.
;;
;; The Gate Array raises an interrupt every 52 scanlines, which in a 312-line
;; frame is six times per frame, not once. Driving a music player or game
;; logic straight from HALT therefore runs it six times too fast - the handler
;; here counts the six and bumps frame_count once per frame.
;;
;; With both ROMs disabled #0038 is plain RAM, so the jump to the handler has
;; to be written there before interrupts are enabled. Enabling them without
;; doing that lands the CPU on whatever bytes happen to be sitting at #0038.
;;
;; CRTC type: nothing type-specific. The interrupt comes from the Gate Array
;; counting HSYNCs, so it only needs the frame to stay 312 lines.
;; ===========================================================================

IRQS_PER_FRAME  EQU 6

;; Which of the six carries the music, counting from the one inside VSYNC.
;; Not that one: the game is waiting on it, and everything the game does in a
;; frame is queued behind whatever this handler does first. The player is a
;; millisecond and a bit, which is half the blanked gap the sprite work has to
;; start in - so it is paid three interrupts later, a hundred and fifty
;; scanlines down the picture, where the only thing behind it is work that has
;; already missed nothing.
MUSIC_IRQ       EQU 3

;; ---------------------------------------------------------------------------
;; irq_init - install the handler, phase-lock the count to VSYNC, enable.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
irq_init
    di
    im 1
    ld a,#C3                    ; JP nn
    ld (#0038),a
    ld hl,irq_handler
    ld (#0039),hl

    call wait_vsync             ; start somewhere sane; the handler locks on
    xor a                       ; to VSYNC properly from the first frame
    ld (irq_count),a
    ld (frame_count),a
    ei
    ret

;; ---------------------------------------------------------------------------
;; irq_handler - one of six per frame, and one of the six is the frame.
;;
;; Counting to six and calling every sixth a frame is only right if you know
;; which one you started on, and you do not: the Gate Array resets its counter
;; two scanlines into VSYNC and issues an interrupt there if the count had got
;; far enough, so the first interrupt after a program starts may be that one or
;; may be any of the other five. Get it wrong and everything the game does
;; happens at a fixed offset into the picture instead of at the start of it -
;; and since the sprite work is ten milliseconds of a twenty millisecond frame,
;; that puts the erase-and-redraw straight under the beam. The bottom of the
;; screen flickers, because the sprites down there are the ones that are gone
;; the longest: erased first and redrawn last.
;;
;; So the frame is not counted, it is recognised. VSYNC is eight scanlines and
;; the interrupts are fifty-two apart, so exactly one of them can fall inside
;; it, and that one is the start of the frame. The count stays as a fallback in
;; case a machine never lands one there.
;; ---------------------------------------------------------------------------
irq_handler
    push af
    push bc
    push hl
    ld bc,#F500                 ; PPI port B, bit 0 = VSYNC
    in a,(c)
    rra
    jr nc,irq_handler_mid

    xor a                       ; inside VSYNC: this is the top of the frame
    ld (irq_count),a
    ld hl,frame_count
    inc (hl)
    jr irq_handler_done

irq_handler_mid
    ld hl,irq_count
    inc (hl)
    ld a,(hl)
    IFDEF HAS_MUSIC
    cp MUSIC_IRQ
    call z,irq_music
    ld hl,irq_count             ; the call had them
    ld a,(hl)
    ENDIF
    cp IRQS_PER_FRAME
    jr c,irq_handler_done
    ld (hl),0                   ; no interrupt has landed inside VSYNC, so fall
    ld hl,frame_count           ; back on counting - the game still runs
    inc (hl)

irq_handler_done
    pop hl
    pop bc
    pop af
    ei
    ret

    IFDEF HAS_MUSIC
;; ---------------------------------------------------------------------------
;; irq_music - one tick of the player, on the one interrupt in six MUSIC_IRQ
;; names. A game that wants music defines HAS_MUSIC and provides music_tick;
;; one that does not assembles exactly the bytes it always did.
;;
;; It is stepped from here rather than from the game loop because a tracker
;; replay wants fifty ticks a second and the loop comes round twenty-five -
;; and because from here it keeps its beat through a second-long repaint of
;; the room, which from the loop it could not. It can never be re-entered
;; either: the whole of it runs with interrupts off, which matters more than
;; it looks, because the player moves SP into the song while it reads.
;;
;; The price is everything it destroys. It uses both register sets, both index
;; registers and the alternate accumulator, and sprite.asm blits out of the
;; shadow set - so everything the handler has not already pushed is pushed
;; here. Sixteen pushes and pops is eighty microseconds on top of the player's
;; own millisecond.
;; ---------------------------------------------------------------------------
irq_music
    push de
    push ix
    push iy
    exx
    ex af,af'
    push af
    push bc
    push de
    push hl
    call music_tick
    pop hl
    pop de
    pop bc
    pop af
    ex af,af'
    exx
    pop iy
    pop ix
    pop de
    ret
    ENDIF

;; ---------------------------------------------------------------------------
;; wait_frame - block until the next 50 Hz tick.
;; Destroys AF, B.
;; ---------------------------------------------------------------------------
wait_frame
    ld a,(frame_count)
    ld b,a
wait_frame_loop
    ld a,(frame_count)
    cp b
    jr z,wait_frame_loop
    ret

;; ---------------------------------------------------------------------------
;; wait_render - block until FRAMES_PER_RENDER ticks have gone by since the
;; last one this returned on.
;; Destroys AF, HL.
;;
;; Counted from the last render rather than waiting for two ticks in a row, so
;; that a frame which overran does not push the next one a whole tick later
;; and keep doing it. If the work ever takes longer than the two frames it is
;; given, this returns straight away and the game drops a picture instead of
;; drifting out of step with the beam.
;; ---------------------------------------------------------------------------
wait_render
    ld hl,render_tick
wait_render_loop
    ld a,(frame_count)
    sub (hl)
    cp FRAMES_PER_RENDER
    jr c,wait_render_loop
    ld a,(frame_count)
    ld (hl),a
    ret

;; ---------------------------------------------------------------------------
;; wait_vsync - return as VSYNC begins. PPI port B bit 0.
;; Destroys AF, BC.
;; ---------------------------------------------------------------------------
wait_vsync
    ld bc,#F500
wait_vsync_off
    in a,(c)
    rra
    jr c,wait_vsync_off         ; inside a VSYNC already - let it finish
wait_vsync_on
    in a,(c)
    rra
    jr nc,wait_vsync_on
    ret

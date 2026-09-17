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

    call wait_vsync             ; the Gate Array resets its own counter just
    xor a                       ; after VSYNC, so start counting from here
    ld (irq_count),a
    ld (frame_count),a
    ei
    ret

;; ---------------------------------------------------------------------------
;; irq_handler - one of six per frame; every sixth is a new frame.
;; ---------------------------------------------------------------------------
irq_handler
    push af
    push hl
    ld hl,irq_count
    ld a,(hl)
    inc a
    cp IRQS_PER_FRAME
    jr c,irq_handler_store
    xor a
    ld (hl),a
    ld hl,frame_count
    inc (hl)
    pop hl
    pop af
    ei
    ret
irq_handler_store
    ld (hl),a
    pop hl
    pop af
    ei
    ret

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

;; ===========================================================================
;; workspace.asm - RAM the engine builds at run time.
;;
;; Engine variables only. Anything that needs a game's own constants - the
;; cat's background buffer needs SPR_MAX_BYTES - belongs to that game, past
;; its own include of this file.
;;
;; Included past the end of the code so none of it lands in the disc image.
;; Nothing here is initialised; anything that needs a starting value is set
;; by the program before first use.
;; ===========================================================================

line_tab    defs DISPLAY_LINES*2    ; start address of every scanline
dg_pat      defs GLYPH_MAX_BYTES    ; one expanded glyph row

txt_lang    defs 1                  ; LANG_EN / LANG_EL
txt_x       defs 1                  ; current x, in bytes
txt_row     defs 2                  ; line_tab pointer for the current text row
txt_xs      defs 1                  ; big text: bytes per source pixel
txt_ys      defs 1                  ; big text: scanlines per source row

fill_x      defs 1
fill_w      defs 2
fill_b      defs 1



;; irq.asm
irq_count   defs 1              ; 0..5 within the frame
frame_count defs 1              ; bumped once per 50 Hz frame, wraps at 256

;; keys.asm
ctl_now     defs 1              ; controls held this frame
ctl_last    defs 1
ctl_pressed defs 1              ; controls that went down this frame

;; title screen
press_state defs 1              ; blink phase of the "press fire" line



;; keys.asm
key_rows    defs 10             ; the matrix as it was read this frame

;; sprite.asm
spr_x       defs 1              ; x of the sprite being worked on, in bytes
spr_w       defs 1
spr_h       defs 1



workspace_end

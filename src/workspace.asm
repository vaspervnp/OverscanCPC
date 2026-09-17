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

txt_solid   defs 1              ; small text overwrites instead of blending
txt_lang    defs 1                  ; LANG_EN / LANG_EL
txt_x       defs 1                  ; current x, in bytes
txt_row     defs 2                  ; line_tab pointer for the current text row
txt_xs      defs 1                  ; big text: bytes per source pixel
txt_ys      defs 1                  ; big text: scanlines per source row
txt_big_pen defs 1                  ; big text: the byte a set pixel is drawn in
txt_big_solid defs 1                ; big text: write where set, rather than OR

pick_pend_n defs 1              ; pickups eaten and not yet rubbed out
pick_pend   defs 4*4              ; x, scanline, and where its background went

fill_x      defs 1
fill_w      defs 2
fill_b      defs 1



;; irq.asm
irq_count   defs 1              ; 0..5 within the frame
frame_count defs 1              ; bumped once per 50 Hz frame, wraps at 256
render_tick defs 1              ; frame_count at the last rendered picture

;; sound.asm
sfx_per     defs 2              ; the tone period, as it stands
sfx_step    defs 2              ; added to it every 50 Hz step
sfx_len     defs 1              ; steps left, and the volume while it lasts

;; keys.asm
ctl_now     defs 1              ; controls held this frame
ctl_last    defs 1
ctl_pressed defs 1              ; controls that went down this frame

;; title screen
press_state defs 1              ; blink phase of the "press fire" line



;; keys.asm
key_rows    defs 10             ; the matrix as it was read this frame

;; sprite.asm
spr_src     defs 2              ; sprite data cursor, across a fused row
spr_bufp    defs 2              ; and where the background is being saved to
spr_x       defs 1              ; x of the sprite being worked on, in bytes
spr_w       defs 1
spr_h       defs 1



;; unpack.asm - two cursors through the picture, one behind the other
unp_src     defs 2              ; the packed stream
unp_dp      defs 2              ; where the next byte goes
unp_dcol    defs 1              ; and which column that is
unp_drow    defs 2              ; line_tab entry for that row
unp_rows    defs 2              ; scanlines of picture still to come
unp_sp      defs 2              ; where a match is copying from
unp_scol    defs 1
unp_srow    defs 2
unp_len     defs 1

workspace_end

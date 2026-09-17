;; ===========================================================================
;; font.asm - just the seven glyphs HELLO WORLD needs, 8x8, 1 bit per pixel.
;; Drawn at 8x12 scale they end up 64x96 pixels each.
;; ===========================================================================

GL_H EQU 0
GL_E EQU 1
GL_L EQU 2
GL_O EQU 3
GL_W EQU 4
GL_R EQU 5
GL_D EQU 6

font
    ;; H
    defb %11000011
    defb %11000011
    defb %11000011
    defb %11111111
    defb %11111111
    defb %11000011
    defb %11000011
    defb %11000011
    ;; E
    defb %11111111
    defb %11111111
    defb %11000000
    defb %11111100
    defb %11111100
    defb %11000000
    defb %11111111
    defb %11111111
    ;; L
    defb %11000000
    defb %11000000
    defb %11000000
    defb %11000000
    defb %11000000
    defb %11000000
    defb %11111111
    defb %11111111
    ;; O
    defb %00111100
    defb %01111110
    defb %11100111
    defb %11000011
    defb %11000011
    defb %11100111
    defb %01111110
    defb %00111100
    ;; W
    defb %11000011
    defb %11000011
    defb %11000011
    defb %11011011
    defb %11011011
    defb %11111111
    defb %01111110
    defb %00100100
    ;; R
    defb %11111100
    defb %11111110
    defb %11000110
    defb %11000110
    defb %11111110
    defb %11111100
    defb %11011000
    defb %11001110
    ;; D
    defb %11111100
    defb %11111110
    defb %11000111
    defb %11000011
    defb %11000011
    defb %11000111
    defb %11111110
    defb %11111100

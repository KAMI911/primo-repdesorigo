; Repdeső Rigó -- game constants (pixels unless noted).
defc N_PIPES      = 3
defc PIPE_SZ      = 4                   ; x lo, x hi (signed), gap top, flags (bit 0 = scored)
defc N_LEVELS     = 3                   ; per level (speed_tab / space_tab): speed 2,3,4 px per game frame, pipe spacing 112,128,144, gravity 0x28,0x32,0x3C, terminal velocity 4,5,6
defc PIPE_X0      = 200                 ; first pipe at game start
defc PIPE_MIN_X   = -32                 ; below this the pipe is gone (one blank draw at x >= -32 wipes its last pixels)
defc GAP_H        = 60
defc GT_MIN       = 40                  ; gap top 40, 44 .. 92: a multiple of 4, so pipe edges fall on colour cell rows
defc GT_STEP      = 4
defc GT_RANGE     = 14                  ; number of values
defc BG_ROWS      = 8                   ; parallax theme = two layers of 8 rows above the ground
defc BG_Y_FAR     = 160                 ; far layer, rows 160..167 (a multiple of 8: the band starts on a 256 byte boundary)
defc BG_Y_NEAR    = 168                 ; near layer, rows 168..175
defc BAND_HI      = 20                  ; = BG_Y_FAR * 32 / 256: high byte offset of the band's first row (checked by the tests)
defc N_THEMES     = 3                   ; city, forest, field: one is picked at random per game
defc PLAY_TOP     = 16                  ; rows 0..15 = HUD
defc PLAY_BOT     = 176                 ; rows 176..191 = ground
defc BIRD_COL     = 8                   ; sprite is 2 bytes (16 px) wide, byte aligned
defc BIRD_X       = 64
defc BIRD_Y0      = 88
defc BIRD_YMAX    = 160                 ; sprite top at/under this = on the ground
defc HIT_X_MIN    = 44                  ; pipe x in HIT_X_MIN..HIT_X_MIN+HIT_X_N-1 overlaps the bird hitbox
defc HIT_X_N      = 33
defc HIT_TOP      = 2                   ; hitbox = sprite rows 2..13
defc HIT_BOT      = 14
defc SCORE_X      = 40                  ; pipe counts as passed when x < 40 (right edge left of the bird)
defc SCORE_MAX    = 999
defc FLAP_VY      = 0xFD00              ; -3.0 px/frame

; Repdeső Rigó -- game constants (pixels unless noted).
defc N_PIPES      = 3
defc PIPE_SZ      = 4                   ; x lo, x hi (signed), gap top, flags (bit 0 = scored)
defc N_LEVELS     = 3                   ; per level (speed_tab / space_tab): speed 2,3,4 px per game frame, pipe spacing 112,128,144, gravity 0x28,0x32,0x3C, terminal velocity 4,5,6
defc PIPE_X0      = 200                 ; first pipe at game start
defc PIPE_MIN_X   = -32                 ; below this the pipe is gone (one blank draw at x >= -32 wipes its last pixels)
defc GAP_H        = 60
defc GT_MIN       = 40                  ; gap top range 40..92 (53 values)
defc GT_RANGE     = 53
defc BG_ROWS      = 12                  ; parallax layers: 12 rows each, stacked above the ground
defc BG_Y_FAR     = 140                 ; city
defc BG_Y_MID     = 152                 ; forest
defc BG_Y_NEAR    = 164                 ; field
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

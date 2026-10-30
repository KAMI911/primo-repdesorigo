; RAM variables. Plain `defb/defw/defs` so they sit right behind the code and need no linker support.
; The image carries them as zeros; start-up code (re)initialises what it needs.
v_scr:      defw    0                   ; screen base: $E800 mono, $E700 colour (low byte always 0)
v_color:    defb    0
v_mono:     defb    0                   ; colour model only: 1 = colour off, plain mono picture (C in the menu)
v_bird:     defb    0                   ; selected bird 0..N_BIRDS-1
v_y:        defw    0                   ; bird top row, 8.8 fixed point (high byte = pixel row)
v_vy:       defw    0                   ; signed 8.8 pixels/frame
v_oldy:     defb    0                   ; pixel row the bird was drawn at last
v_anim:     defb    0
v_level:    defb    0                   ; difficulty 0..N_LEVELS-1
v_speed:    defb    2                   ; pipe speed, pixels per game frame (from speed_tab)
v_grav:     defb    0x28                ; gravity, 8.8 px/frame^2 (low byte; from grav_tab)
v_vmax:     defb    4                   ; terminal velocity, px/frame (from vmax_tab)
v_space:    defw    112                 ; distance between pipes (space_tab)
v_cycle:    defw    336                 ; N_PIPES * v_space: the jump of a recycled pipe
v_bests:    defs    N_LEVELS * 2        ; best score per level
v_score:    defw    0
v_best:     defw    0
v_new:      defb    0                   ; 1 = this game set a new record
v_prevkeys: defb    0
v_rng:      defw    0
v_cov:      defb    0                   ; bird columns wiped by pipe drawing this frame (bit0 col 8, bit1 col 9)
v_pipes:    defs    N_PIPES * PIPE_SZ
v_dig:      defs    3
v_frames:   defw    0                   ; headless runs only
; draw_pipe / seg scratch
v_s:        defb    0
v_k:        defb    0
v_n:        defb    0
v_dc:       defb    0
v_ovl:      defb    0
v_pb:       defw    0
v_src:      defw    0
v_n16:      defw    0
v_adj:      defb    0
v_theme:   defb    0                   ; parallax theme of this game 0..N_THEMES-1
v_bg:       defw    0                   ; its far layer (the near layer follows, BG_ROWS * 32 bytes later)
v_pt:       defw    0                   ; colour_setup: this theme's palette table
v_pcol:     defb    0                   ; 1 = colour model with colour on: pipes recolour the band cells under them
v_px:       defw    0                   ; pipe_colour scratch
v_pc:       defb    0
v_pn:       defb    0
v_skip:     defs    32                  ; bg_skipmap
v_seg:      defs    10
v_tmp:      defs    5                   ; seg: merged window of a clipped pipe
v_sbase:    defw    0
v_full:     defb    0                   ; draw_pipe: window is complete (5 bytes, unclipped)
v_q:        defb    0                   ; seg: rows left inside the parallax band
v_rows:     defb    0
            defs    96                  ; stack
stack_top:

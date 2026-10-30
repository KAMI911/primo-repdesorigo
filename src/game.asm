; Game logic: random numbers, pipes, physics, collision, score. No hardware access, unit-testable.

; rand8: step the 16-bit Galois LFSR (taps $B400, period 65535, state never 0) -> A = h ^ l.
; v_rng must be non-zero. Clobbers HL,F.
rand8:
        ld      hl,(v_rng)
        srl     h
        rr      l
        jr      nc,r8_nx
        ld      a,h
        xor     0xB4
        ld      h,a
r8_nx:  ld      (v_rng),hl
        ld      a,h
        xor     l
        ret

; gap_map  A = any byte -> A = gap top row in GT_MIN .. GT_MIN+GT_RANGE-1. Clobbers F.
gap_map:
        and     63
        cp      GT_RANGE
        jr      c,gm_ok
        sub     GT_RANGE                ; 53..63 -> 0..10
gm_ok:  add     a,GT_MIN
        ret

; gap_roll -> A = a fresh random gap top. Clobbers HL,F.
gap_roll:
        call    rand8
        jr      gap_map

; pipes_reset: pipes at PIPE_X0 + i*v_space with fresh gaps, nothing scored. Clobbers all.
pipes_reset:
        ld      ix,v_pipes
        ld      hl,PIPE_X0
        ld      b,N_PIPES
pr_loop:ld      (ix+0),l
        ld      (ix+1),h
        ld      (ix+3),0
        push    bc
        push    hl
        call    gap_roll
        ld      (ix+2),a
        pop     hl
        pop     bc
        ld      de,(v_space)
        add     hl,de
        ld      de,PIPE_SZ
        add     ix,de
        djnz    pr_loop
        ret

; speed_tab: pipe speed in pixels per game frame for each level
speed_tab:
        defb    2,3,4
space_tab:
        defw    112,128,144
; grav_tab / vmax_tab: the bird falls harder on the faster levels (gravity in 8.8 px/frame^2, terminal velocity in px/frame)
grav_tab:
        defb    0x28,0x32,0x3C
vmax_tab:
        defb    4,5,6
; bird_dg: signed gravity offset per bird (Rigó, Lúd, Kacsa, Kakukk): small differences in how each one drops
bird_dg:
        defb    0,-6,3,8

; level_setup  A = level -> v_level (out of range = 0), v_speed, v_grav, v_vmax, v_space, v_cycle and v_best = that level's best.
; Clobbers AF,BC,DE,HL.
level_setup:
        cp      N_LEVELS
        jr      c,ls_ok
        xor     a
ls_ok:  ld      (v_level),a
        ld      e,a
        ld      d,0
        ld      hl,speed_tab
        add     hl,de
        ld      a,(hl)
        ld      (v_speed),a
        ld      hl,grav_tab
        add     hl,de
        ld      a,(hl)
        ld      (v_grav),a
        ld      hl,vmax_tab
        add     hl,de
        ld      a,(hl)
        ld      (v_vmax),a
        ld      hl,space_tab
        add     hl,de
        add     hl,de
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ld      (v_space),bc
        ld      h,b
        ld      l,c
        add     hl,hl
        add     hl,bc
        ld      (v_cycle),hl            ; 3 * spacing
        ld      hl,v_bests
        add     hl,de
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (v_best),de
        ret

; best_store: v_best -> this level's slot in v_bests. Clobbers AF,DE,HL.
best_store:
        ld      a,(v_level)
        cp      N_LEVELS
        ret     nc
        ld      e,a
        ld      d,0
        ld      hl,v_bests
        add     hl,de
        add     hl,de
        ld      de,(v_best)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret

; pipes_step: every pipe moves v_speed pixels left; one that is gone (x < PIPE_MIN_X) jumps v_cycle to the
; right with a new gap and the scored flag cleared. Clobbers all.
pipes_step:
        ld      ix,v_pipes
        ld      b,N_PIPES
ps_loop:ld      l,(ix+0)
        ld      h,(ix+1)
        ld      a,(v_speed)
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        ld      a,h
        inc     a
        jr      nz,ps_keep              ; x >= 0
        ld      a,l
        cp      0xE0
        jr      nc,ps_keep              ; -32 <= x < 0
        ld      de,(v_cycle)
        add     hl,de
        push    hl
        push    bc
        call    gap_roll
        ld      (ix+2),a
        ld      (ix+3),0
        pop     bc
        pop     hl
ps_keep:ld      (ix+0),l
        ld      (ix+1),h
        ld      de,PIPE_SZ
        add     ix,de
        djnz    ps_loop
        ret

; bird_step: one frame of physics. vy += v_grav + bird_dg[v_bird] (capped at v_vmax), y += vy, clamped to PLAY_TOP .. BIRD_YMAX
; (vy = 0 when clamped). Clobbers AF,DE,HL.
bird_step:
        ld      a,(v_bird)
        and     3
        ld      e,a
        ld      d,0
        ld      hl,bird_dg
        add     hl,de
        ld      a,(v_grav)
        add     a,(hl)
        ld      e,a
        ld      hl,(v_vy)
        add     hl,de                   ; d is still 0
        bit     7,h
        jr      nz,bs_vok
        ld      a,(v_vmax)
        ld      e,a
        ld      a,h
        cp      e
        jr      c,bs_vok
        ld      h,e
        ld      l,0
bs_vok: ld      (v_vy),hl
        ld      de,(v_y)
        add     hl,de
        ld      a,h
        cp      BIRD_YMAX
        jr      c,bs_top
        ld      hl,BIRD_YMAX * 256
        jr      bs_zero
bs_top: cp      PLAY_TOP
        jr      nc,bs_store
        ld      hl,PLAY_TOP * 256
bs_zero:ld      de,0
        ld      (v_vy),de
bs_store:
        ld      (v_y),hl
        ret

; collide_all -> A = 1 if the bird's hitbox (x 66..77, rows y+2 .. y+13) touches any pipe outside its gap.
; Clobbers AF,BC,DE,IX.
collide_all:
        ld      ix,v_pipes
        ld      b,N_PIPES
ca_loop:ld      a,(ix+1)
        or      a
        jr      nz,ca_next              ; x < 0 or x >= 256
        ld      a,(ix+0)
        sub     HIT_X_MIN
        cp      HIT_X_N
        jr      nc,ca_next              ; no horizontal overlap
        ld      a,(v_y+1)
        add     a,HIT_TOP
        cp      (ix+2)
        jr      c,ca_hit                ; top of the hitbox above the gap
        ld      a,(ix+2)
        add     a,GAP_H
        ld      c,a
        ld      a,(v_y+1)
        add     a,HIT_BOT
        cp      c
        jr      z,ca_next
        jr      nc,ca_hit               ; bottom of the hitbox below the gap
ca_next:ld      de,PIPE_SZ
        add     ix,de
        djnz    ca_loop
        xor     a
        ret
ca_hit: ld      a,1
        ret

; score_check -> A = number of pipes that were passed since the last call (score += that, capped at 999).
; A pipe is passed once x < SCORE_X (its right edge is left of the bird); the scored flag stops double counting.
; Clobbers AF,BC,DE,HL,IX.
score_check:
        ld      ix,v_pipes
        ld      b,N_PIPES
        ld      c,0
sc_loop:bit     0,(ix+3)
        jr      nz,sc_next
        ld      a,(ix+1)
        bit     7,a
        jr      nz,sc_pass              ; negative x
        or      a
        jr      nz,sc_next              ; x >= 256
        ld      a,(ix+0)
        cp      SCORE_X
        jr      nc,sc_next
sc_pass:set     0,(ix+3)
        inc     c
        push    bc
        ld      hl,(v_score)
        ld      de,SCORE_MAX
        or      a
        sbc     hl,de
        jr      nc,sc_cap               ; already at the cap
        add     hl,de
        inc     hl
        ld      (v_score),hl
sc_cap: pop     bc
sc_next:ld      de,PIPE_SZ
        add     ix,de
        djnz    sc_loop
        ld      a,c
        ret

; render_pipes: draw all pipes (resets v_cov first). Clobbers all.
render_pipes:
        xor     a
        ld      (v_cov),a
        ld      ix,v_pipes
        ld      b,N_PIPES
rp_loop:push    bc
        call    draw_pipe
        ld      a,(v_pcol)
        or      a
        call    nz,pipe_colour
        pop     bc
        ld      de,PIPE_SZ
        add     ix,de
        djnz    rp_loop
        ret

; render_bird: wipe the old bird in the columns that draw_pipe did not already clean, then draw it at v_y.
; Erase and draw are back to back so the bird does not flicker. Clobbers all.
render_bird:
        ld      a,(v_oldy)
        call    row_addr
        ld      a,(v_cov)
        ld      c,a
        ld      a,l
        add     a,BIRD_COL
        ld      l,a
        bit     0,c
        call    z,clear_col16
        inc     hl
        bit     1,c
        call    z,clear_col16
        ld      a,(v_y+1)
        ld      (v_oldy),a
        ld      a,(v_bird)
        add     a,a
        ld      c,a
        ld      a,(v_anim)
        rrca
        and     1                       ; wing frame changes every 2 game frames
        or      c
        call    spr_ptr                 ; clobbers DE: load the position afterwards
        ld      a,(v_y+1)
        ld      d,a
        ld      e,BIRD_COL
        jp      draw_sprite

; render_frame: pipes, then the bird.
render_frame:
        call    render_pipes
        jr      render_bird

IF HEADLESS
; autopilot (emulator tests only): A = key mask, bit 0 = flap when the bird gets near the lower edge of the
; gap of the nearest unscored pipe. headless_bot = 0 means "press nothing".
autopilot:
        ld      a,(headless_bot)
        or      a
        ret     z
        cp      2
        jr      nz,ap_go
        ld      hl,(v_frames)           ; mode 2: play well for 150 frames, then give up
        ld      de,150
        or      a
        sbc     hl,de
        jr      c,ap_go
        xor     a
        ret
ap_go:        ld      ix,v_pipes
        ld      b,N_PIPES
        ld      de,0xFFFF               ; best x so far
        ld      c,70                    ; its gap top
ap_loop:bit     0,(ix+3)
        jr      nz,ap_next
        ld      l,(ix+0)
        ld      h,(ix+1)
        or      a
        sbc     hl,de
        jr      nc,ap_next              ; not nearer
        ld      e,(ix+0)
        ld      d,(ix+1)
        ld      c,(ix+2)
ap_next:push    de
        ld      de,PIPE_SZ
        add     ix,de
        pop     de
        djnz    ap_loop
        ld      a,c
        add     a,GAP_H - 6
        ld      b,a
        ld      a,(v_y+1)
        add     a,HIT_BOT
        cp      b
        ld      a,0
        ret     c
        inc     a
        ret
ENDIF

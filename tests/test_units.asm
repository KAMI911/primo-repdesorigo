; Unit tests for the Repdeső Rigó routines, run headless in z88dk-ticks.
; The asm only drives the routines with table-driven cases (build/cases.inc, written by run_tests.py) and stores
; the results in res_* buffers; tests/run_tests.py compares them with an independent Python model.
        include "hw.inc"
        include "game.inc"
        org     0x4400

t_start:
        ld      sp,stack_top
        ld      hl,VRAM_MONO
        ld      (v_scr),hl

; ---- bg_pick for themes 0, 1, 2 and an out-of-range value
        ld      hl,res_pick
        ld      (t_rp),hl
        ld      b,4
tpk_lp: push    bc
        ld      a,b
        ld      hl,tpk_in - 1
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(hl)
        call    bg_pick
        ld      hl,(v_bg)
        call    store_word
        pop     bc
        djnz    tpk_lp

; ---- parallax (theme 1): bg_rot x3 on the near layer, then bg_step for v_anim 2 (far), 7 (nothing), 4 (near)
        ld      hl,bg_t1
        ld      (v_bg),hl
        ld      hl,v_pipes              ; all pipes off-screen to the right
        ld      b,N_PIPES
tbg_pp: ld      (hl),0xE8
        inc     hl
        ld      (hl),3
        inc     hl
        inc     hl
        inc     hl
        djnz    tbg_pp
        ld      b,3
tbg_rot:push    bc
        ld      hl,(v_bg)
        ld      de,BG_ROWS * 32
        add     hl,de
        call    bg_rot
        pop     bc
        djnz    tbg_rot
        ld      hl,(v_bg)
        ld      de,BG_ROWS * 32
        add     hl,de
        ld      a,BG_Y_NEAR
        call    bg_blit
        ld      b,3
tbg_stp:push    bc
        ld      a,b
        ld      hl,tbg_anim - 1
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(hl)
        ld      (v_anim),a
        call    bg_step
        pop     bc
        djnz    tbg_stp
        ld      hl,(v_bg)
        ld      de,res_bg
        ld      bc,2 * BG_ROWS * 32
        ldir
        ld      hl,VRAM_MONO + BG_Y_FAR * 32    ; what the blits put on the screen
        ld      de,res_bgscr
        ld      bc,2 * BG_ROWS * 32
        ldir
        ld      a,0x55                  ; a pipe at x = 100 (window = byte columns 12..16): bg_step must not touch them
        call    fill_screen
        ld      hl,v_pipes
        ld      (hl),100
        inc     hl
        ld      (hl),0
        ld      a,4
        ld      (v_anim),a
        call    bg_step
        ld      hl,VRAM_MONO + BG_Y_NEAR * 32
        ld      de,res_bgskip
        ld      bc,BG_ROWS * 32
        ldir
        ld      hl,(v_bg)               ; from here on the layers are blank: the other tests see a plain screen
        ld      bc,2 * BG_ROWS * 32
        xor     a
        call    memfill
        xor     a
        call    fill_screen
        ld      hl,v_pipes
        ld      bc,N_PIPES * PIPE_SZ
        xor     a
        call    memfill

; ---- row_addr for all 192 rows
        ld      hl,res_rows
        ld      (t_rp),hl
        xor     a
        ld      (t_i),a
tra_loop:ld      a,(t_i)
        call    row_addr
        ex      de,hl
        ld      hl,(t_rp)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (t_rp),hl
        ld      a,(t_i)
        inc     a
        ld      (t_i),a
        cp      192
        jr      c,tra_loop

; ---- rand8: period of the generator starting at 1 (must be 65535); the zero state must never occur
        ld      hl,1
        ld      (v_rng),hl
        ld      de,0
trn_loop:push    de
        call    rand8
        pop     de
        inc     de
        ld      hl,(v_rng)
        ld      a,h
        or      l
        jr      nz,trn_nz
        ld      a,1
        ld      (res_zero),a
trn_nz:  ld      a,h
        or      a
        jr      nz,trn_loop
        ld      a,l
        cp      1
        jr      nz,trn_loop
        ld      (res_period),de

; ---- gap_map over all 256 input bytes
        ld      hl,res_gap
        ld      b,0
tgm_loop:ld      a,b
        push    hl
        call    gap_map
        pop     hl
        ld      (hl),a
        inc     hl
        inc     b
        jr      nz,tgm_loop

; ---- to_dec3 for 0..1100
        ld      hl,res_dec
        ld      (t_rp),hl
        ld      hl,0
        ld      (t_n),hl
td3_loop:ld      hl,(t_n)
        call    to_dec3
        ld      hl,(t_rp)
        ld      (hl),b
        inc     hl
        ld      (hl),c
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (t_rp),hl
        ld      hl,(t_n)
        inc     hl
        ld      (t_n),hl
        ld      de,1101
        or      a
        sbc     hl,de
        jr      c,td3_loop

; ---- draw_pipe: screen prefilled 0xFF, one pipe, others off-screen
        ld      hl,pipe_cases
        ld      de,res_pipe
        call    case_begin
tpc_loop:ld      hl,(t_n)
        ld      a,h
        or      l
        jr      z,tpc_done
        dec     hl
        ld      (t_n),hl
        ld      a,0xFF
        call    fill_screen
        call    setup_far
        ld      hl,(t_cp)
        ld      de,v_pipes
        ld      bc,3
        ldir
        ld      (t_cp),hl
        xor     a
        ld      (v_cov),a
        ld      ix,v_pipes
        call    draw_pipe
        ld      a,(v_cov)
        call    store_byte
        call    store_checksum
        jr      tpc_loop
tpc_done:

; ---- draw_pipe over a parallax background: layers = 0x33 + 5*i, screen prefilled 0xFF
        ld      hl,(v_bg)
        ld      bc,2 * BG_ROWS * 32
        ld      a,0x33
tpb_fill:ld     (hl),a
        add     a,5
        inc     hl
        dec     bc
        push    af
        ld      a,b
        or      c
        jr      z,tpb_fd
        pop     af
        jr      tpb_fill
tpb_fd: pop     af
        ld      hl,pipebg_cases
        ld      de,res_pipebg
        call    case_begin
tpb_loop:ld     hl,(t_n)
        ld      a,h
        or      l
        jr      z,tpb_done
        dec     hl
        ld      (t_n),hl
        ld      a,0xFF
        call    fill_screen
        call    setup_far
        ld      hl,(t_cp)
        ld      de,v_pipes
        ld      bc,3
        ldir
        ld      (t_cp),hl
        xor     a
        ld      (v_cov),a
        ld      ix,v_pipes
        call    draw_pipe
        ld      a,(v_cov)
        call    store_byte
        call    store_checksum
        jr      tpb_loop
tpb_done:

; ---- draw_sprite: screen prefilled 0x5A; cases (sprite index, row, column)
        ld      hl,spr_cases
        ld      de,res_spr
        call    case_begin
tsc_loop:ld      hl,(t_n)
        ld      a,h
        or      l
        jr      z,tsc_done
        dec     hl
        ld      (t_n),hl
        ld      a,0x5A
        call    fill_screen
        ld      hl,(t_cp)
        ld      a,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      (t_cp),hl
        call    spr_ptr
        ld      d,b
        ld      e,c
        call    draw_sprite
        call    store_checksum
        jr      tsc_loop
tsc_done:

; ---- text: screen cleared; cases (kind 0 draw_text / 1 draw_text_center / 2 draw_num3, row, col, ptr-or-value)
        ld      hl,text_cases
        ld      de,res_text
        call    case_begin
ttx_loop:ld      hl,(t_n)
        ld      a,h
        or      l
        jr      z,ttx_done
        dec     hl
        ld      (t_n),hl
        xor     a
        call    fill_screen
        ld      hl,(t_cp)
        ld      a,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (t_cp),hl
        ex      de,hl                   ; HL = string / value
        or      a
        jr      z,ttx_text
        cp      1
        jr      z,ttx_center
        call    draw_num3
        jr      ttx_sum
ttx_text:call    draw_text
        jr      ttx_sum
ttx_center:
        call    draw_text_center
ttx_sum: call    store_checksum
        jr      ttx_loop
ttx_done:

; ---- bird_step: (y, vy) -> (y, vy)
        ld      hl,step_cases
        ld      de,res_step
        call    case_begin
tst_loop:ld      hl,(t_n)
        ld      a,h
        or      l
        jr      z,tst_done
        dec     hl
        ld      (t_n),hl
        ld      hl,(t_cp)
        ld      de,v_y
        ld      bc,4
        ldir
        ld      a,(hl)                  ; level, then bird: level_setup sets gravity and terminal velocity
        inc     hl
        inc     hl
        ld      c,(hl)
        inc     hl
        inc     hl
        ld      b,a
        ld      a,c
        ld      (v_bird),a
        ld      a,b
        push    hl
        call    level_setup
        pop     hl
        ld      (t_cp),hl
        call    bird_step
        ld      hl,(v_y)
        call    store_word
        ld      hl,(v_vy)
        call    store_word
        jr      tst_loop
tst_done:

; ---- collide_all: (x, gap, bird row) -> A
        ld      hl,coll_cases
        ld      de,res_coll
        call    case_begin
tco_loop:ld      hl,(t_n)
        ld      a,h
        or      l
        jr      z,tco_done
        dec     hl
        ld      (t_n),hl
        call    setup_far
        ld      hl,(t_cp)
        ld      de,v_pipes
        ld      bc,3
        ldir
        ld      a,(hl)
        inc     hl
        ld      (v_y+1),a
        ld      (t_cp),hl
        call    collide_all
        call    store_byte
        jr      tco_loop
tco_done:

; ---- score_check: (x, flags, score) -> (A, flags, score)
        ld      hl,score_cases
        ld      de,res_score
        call    case_begin
tsk_loop:ld      hl,(t_n)
        ld      a,h
        or      l
        jr      z,tsk_done
        dec     hl
        ld      (t_n),hl
        call    setup_far
        ld      hl,(t_cp)
        ld      a,(hl)
        inc     hl
        ld      (v_pipes),a
        ld      a,(hl)
        inc     hl
        ld      (v_pipes+1),a
        ld      a,(hl)
        inc     hl
        ld      (v_pipes+3),a
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (v_score),de
        ld      (t_cp),hl
        call    score_check
        call    store_byte
        ld      a,(v_pipes+3)
        call    store_byte
        ld      hl,(v_score)
        call    store_word
        jr      tsk_loop
tsk_done:

; ---- pipes_step: (x, gap, flags) -> (x, gap, flags)
        ld      hl,pstep_cases
        ld      de,res_pstep
        call    case_begin
tps_loop:ld      hl,(t_n)
        ld      a,h
        or      l
        jr      z,tps_done
        dec     hl
        ld      (t_n),hl
        call    setup_far
        ld      hl,(t_cp)
        ld      de,v_pipes
        ld      bc,4
        ldir
        ld      a,(hl)
        inc     hl
        ld      (t_cp),hl
        call    level_setup             ; speed, spacing and cycle of the case's level
        call    pipes_step
        ld      hl,(v_pipes)
        call    store_word
        ld      a,(v_pipes+2)
        call    store_byte
        ld      a,(v_pipes+3)
        call    store_byte
        jr      tps_loop
tps_done:

; ---- pipes_reset
        ld      hl,0xACE1
        ld      (v_rng),hl
        xor     a
        call    level_setup
        call    pipes_reset
        ld      hl,v_pipes
        ld      de,res_reset
        ld      bc,N_PIPES * PIPE_SZ
        ldir
        ld      a,2
        call    level_setup
        call    pipes_reset
        ld      hl,v_pipes
        ld      de,res_reset + N_PIPES * PIPE_SZ
        ld      bc,N_PIPES * PIPE_SZ
        ldir

; ---- wait_vsync must keep BC (the game-over pause counts with djnz around it)
        ld      bc,0x1234
        call    wait_vsync
        ld      (res_bc),bc

t_done: halt
tpk_in:  defb   9,2,1,0                 ; indexed by the countdown 4..1: 0, 1, 2, 9
tbg_anim: defb  4,7,2                   ; indexed by the countdown 3..1, so it runs 2 (far), 7 (none), 4 (near)

; ---------------------------------------------------------------- helpers ---
; case_begin  HL = table (count word, then entries), DE = result buffer.
case_begin:
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      (t_n),bc
        ld      (t_cp),hl
        ld      (t_rp),de
        ret

; store_byte  A -> (t_rp)++ . Clobbers HL.
store_byte:
        ld      hl,(t_rp)
        ld      (hl),a
        inc     hl
        ld      (t_rp),hl
        ret

; store_word  HL -> (t_rp), (t_rp)+1 (little endian), t_rp += 2. Clobbers AF,DE,HL.
store_word:
        ex      de,hl
        ld      hl,(t_rp)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (t_rp),hl
        ret

; store_checksum: checksum of the mono screen -> two words at t_rp.
store_checksum:
        call    checksum
        push    hl
        ex      de,hl
        call    store_word
        pop     hl
        jr      store_word

; checksum: s1 = running byte sum, s2 = running sum of s1 (both mod 65536) over the whole mono screen
; -> DE = s1, HL = s2. Clobbers AF,BC,IX.
checksum:
        ld      ix,0
        ld      de,0
        ld      hl,VRAM_MONO
        ld      bc,VRAM_MONO_SZ
tcs_l:   ld      a,(hl)
        add     a,e
        ld      e,a
        jr      nc,tcs_n
        inc     d
tcs_n:   add     ix,de
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,tcs_l
        push    ix
        pop     hl
        ret

; fill_screen  A = value for the whole mono screen. Clobbers AF,BC,DE,HL.
fill_screen:
        ld      hl,VRAM_MONO
        ld      bc,VRAM_MONO_SZ
        jp      memfill

; setup_far: pipes 1 and 2 far off-screen to the right, already scored. Clobbers HL,DE.
setup_far:
        ld      hl,v_pipes + PIPE_SZ
        ld      b,2
tsf_loop:ld      (hl),0xE8               ; x = 1000
        inc     hl
        ld      (hl),0x03
        inc     hl
        ld      (hl),60
        inc     hl
        ld      (hl),1
        inc     hl
        djnz    tsf_loop
        ret

t_cp:   defw    0
t_rp:   defw    0
t_n:    defw    0
t_i:    defb    0

        include "lib.asm"
        include "gfx.asm"
        include "game.asm"
        include "data.inc"
        include "cases.inc"
        include "vars.asm"
res_rows:   defs 192 * 2
res_zero:   defb 0
res_period: defw 0
res_gap:    defs 256
res_dec:    defs 1101 * 3
res_pipe:   defs 1024 * 5
res_pipebg: defs 128 * 5
res_spr:    defs 256 * 4
res_text:   defs 64 * 4
res_step:   defs 1100 * 4
res_coll:   defs 1024
res_score:  defs 256 * 4
res_pstep:  defs 256 * 4
res_reset:  defs 2 * N_PIPES * PIPE_SZ
res_bc:     defw 0
res_pick:   defs 8
res_bg:     defs 2 * BG_ROWS * 32
res_bgscr:  defs 2 * BG_ROWS * 32
res_bgskip: defs BG_ROWS * 32

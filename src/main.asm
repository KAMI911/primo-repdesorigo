; Repdeső Rigó -- Flappy Bird for the Primo (Z80). Builds as universal (runtime colour/mono detect),
; -DTARGET_BW or -DTARGET_COLOR. -DHEADLESS builds a test version for z88dk-ticks (no menu, autopilot).
;
; Controls: SPACE / UP / RETURN = flap; LEFT / RIGHT = choose bird; M = back to the menu after a game.
; The ROM's 20 ms NMI is left running (we need no cycle-exact code); port 0 is only touched by `beep`,
; which restores the shadow value.
        include "hw.inc"
        include "game.inc"
        org     ORG

start:
        ld      sp,stack_top            ; own stack in plain RAM
        call    detect_color
        ld      (v_color),a
        or      a
        jr      nz,st_color
        ld      hl,(SCREEN_BASE_WORD)   ; the ROM keeps the pixel memory start here ($E800 on 64K, lower on smaller machines)
        ld      a,h
        cp      0x68
        jr      c,st_dflt               ; implausible (< $6800 or > $E800): assume $E800
        cp      0xE9
        jr      c,st_scr
st_dflt:ld      hl,VRAM_MONO
        jr      st_scr
st_color:
        ld      hl,VRAM_COLOR + COLOR_TOP * 32
st_scr: ld      (v_scr),hl
IF HEADLESS
        ld      hl,(headless_seed)
ELSE
        ld      hl,0xACE1               ; non-zero LFSR seed; the menu stirs it with key timing
ENDIF
        ld      (v_rng),hl
        ld      hl,0
        ld      (v_best),hl
        xor     a
        ld      (v_bird),a
IF HEADLESS
        ld      a,(headless_bird)
        ld      (v_bird),a
        ld      a,(headless_level)
        ld      (v_level),a
        ld      a,(headless_mono)
        ld      (v_mono),a
IF SHOT_MENU
        call    menu_screen
        jp      done
ENDIF
ELSE
main_menu:
        call    menu
ENDIF
game_loop:
        call    play
        or      a
        jr      nz,game_loop
IF HEADLESS
done:   halt
headless_bird:   defb 0
headless_level:  defb 0
headless_mono:   defb 0
headless_bot:    defb 1
headless_frames: defw 400
headless_seed:   defw 0xACE1
ELSE
        jr      main_menu
IF SCRIPTED
done:   halt                            ; test build: ends when the key script runs out
v_ksp:  defw    key_script
key_script: defs 128,0
        defb    0xFF
ENDIF
ENDIF

; ------------------------------------------------------------------ menu ---
; menu_screen: draw the static menu. menu: bird selection loop, returns when the player starts
; (v_bird = choice). Both clobber all.
menu_screen:
        ld      a,(v_color)
        call    clear_screen
        ld      hl,s_title
        ld      b,2
        call    draw_text_center
        ld      hl,s_choose
        ld      b,6
        call    draw_text_center
        ld      hl,s_keys
        ld      b,17
        call    draw_text_center
        ld      hl,s_keys2
        ld      b,19
        call    draw_text_center
        ld      hl,s_start
        ld      b,21
        call    draw_text_center
        ld      a,(v_color)
        or      a
        jr      z,ms_nocol
        ld      hl,s_colkey
        ld      b,4
        call    draw_text_center
ms_nocol:
        call    menu_level
        xor     a
        ld      (v_anim),a
        call    read_keys
        ld      (v_prevkeys),a
        call    menu_draw
        ret

; menu_level: difficulty line (row 15) and that level's best score (row 23) for v_level. Clobbers all.
menu_level:
        ld      a,(v_level)
        call    level_setup
        ld      a,120
        ld      b,8
        call    clear_rows
        ld      a,184
        ld      b,8
        call    clear_rows
        ld      a,(v_level)
        add     a,a
        ld      l,a
        ld      h,0
        ld      de,level_name_tab
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      b,15
        call    draw_text_center
        ld      bc,15 * 256 + 1
        call    text_dest
        ld      a,CH_CARET
        call    draw_glyph
        ld      bc,15 * 256 + 30
        call    text_dest
        ld      a,CH_V
        call    draw_glyph
        ld      hl,s_best
        ld      bc,23 * 256 + 10
        call    draw_text
        ld      hl,(v_best)
        ld      bc,23 * 256 + 19        ; label + 2 spaces + 3 digits = 12 columns: exactly centred
        jp      draw_num3

menu:
        call    menu_screen
mn_loop:call    wait_vsync
        ld      hl,v_anim
        inc     (hl)
        call    rand8                   ; stir the generator: the seed depends on how long the player dawdles
        call    read_keys
        call    key_edges
        ld      c,a
        bit     4,c
        jr      z,mn_down
        ld      a,(v_level)             ; UP: easier, wraps
        or      a
        jr      nz,mn_lvdec
        ld      a,N_LEVELS
mn_lvdec:
        dec     a
        jr      mn_lvset
mn_down:bit     5,c
        jr      z,mn_left
        ld      a,(v_level)             ; DOWN: harder, wraps
        inc     a
        cp      N_LEVELS
        jr      c,mn_lvset
        xor     a
mn_lvset:
        ld      (v_level),a
        call    menu_level
        jr      mn_loop
mn_left:bit     7,c                     ; C: colour on / off (colour model only)
        jr      z,mn_bird
        ld      a,(v_color)
        or      a
        jr      z,mn_bird
        ld      a,(v_mono)
        xor     1
        ld      (v_mono),a
        call    menu_screen             ; redraws everything with the new palette
        jr      mn_loop
mn_bird:bit     1,c
        jr      z,mn_right
        ld      a,(v_bird)
        or      a
        jr      nz,mn_dec
        ld      a,N_BIRDS
mn_dec: dec     a
        ld      (v_bird),a
        jr      mn_redraw
mn_right:
        bit     2,c
        jr      z,mn_start
        ld      a,(v_bird)
        inc     a
        cp      N_BIRDS
        jr      c,mn_inc
        xor     a
mn_inc: ld      (v_bird),a
        jr      mn_redraw
mn_start:
        bit     6,c                     ; SPACE or RETURN (UP only changes the difficulty here)
        ret     nz
        ld      a,(v_anim)
        and     7
        jr      nz,mn_loop              ; the selected bird flaps every 8 frames
mn_redraw:
        call    menu_draw
        jr      mn_loop

; menu_draw: the four birds (selected one flapping, underlined), and its name between < >.
menu_draw:
        ld      a,72
        ld      b,16
        call    clear_rows
        ld      a,90
        ld      b,16
        call    clear_rows
        ld      c,0
md_loop:push    bc
        ld      a,(v_bird)
        cp      c
        ld      b,0
        jr      nz,md_frame
        ld      a,(v_anim)
        rrca
        rrca
        rrca
        and     1
        ld      b,a                     ; wing frame of the selected bird
md_frame:
        ld      a,c
        add     a,a
        or      b
        call    spr_ptr
        pop     bc
        push    bc
        ld      a,c                     ; column = 4 + 7 * bird
        add     a,a
        add     a,a
        add     a,a
        sub     c
        add     a,4
        ld      e,a
        ld      d,72
        push    de
        call    draw_sprite
        pop     de
        pop     bc
        push    bc
        ld      a,(v_bird)
        cp      c
        jr      nz,md_next
        ld      a,91                    ; underline: two rows, two bytes
        call    row_addr
        ld      a,l
        add     a,e
        ld      l,a
        ld      (hl),0xFF
        inc     l
        ld      (hl),0xFF
        ld      de,31
        add     hl,de
        ld      (hl),0xFF
        inc     l
        ld      (hl),0xFF
md_next:pop     bc
        inc     c
        ld      a,c
        cp      N_BIRDS
        jr      c,md_loop
        ld      a,(v_bird)
        add     a,a
        ld      l,a
        ld      h,0
        ld      de,bird_name_tab
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      b,12
        call    draw_text_center
        ld      bc,12 * 256 + 1
        call    text_dest
        ld      a,CH_LT
        call    draw_glyph
        ld      bc,12 * 256 + 30
        call    text_dest
        ld      a,CH_GT
        jp      draw_glyph

; ------------------------------------------------------------------ play ---
; play: one whole game incl. the game-over screen. Returns A = 1 play again, 0 back to the menu.
play:
        ld      a,(v_level)
        call    level_setup             ; speed and this level's best
        ld      a,(v_color)
        call    clear_screen
        call    draw_ground
        call    pipes_reset
        ld      hl,BIRD_Y0 * 256
        ld      (v_y),hl
        ld      hl,0
        ld      (v_vy),hl
        ld      (v_score),hl
        ld      a,BIRD_Y0
        ld      (v_oldy),a
        xor     a
        ld      (v_anim),a
        ld      (v_new),a
        call    draw_hud
        ld      hl,s_ready1
        ld      b,4
        call    draw_text_center
        ld      hl,s_ready2
        ld      b,6
        call    draw_text_center
        call    render_frame
        call    read_keys
        ld      (v_prevkeys),a
IF SHOT_READY
        jp      done
ENDIF
IF HEADLESS
ELSE
pl_ready:
        call    wait_vsync
        call    wait_vsync
        ld      hl,v_anim
        inc     (hl)
        xor     a
        ld      (v_cov),a
        call    render_bird             ; hovering bird keeps flapping its wings (clobbers everything)
        call    read_keys
        call    key_edges
        bit     0,a
        jr      z,pl_ready
ENDIF
        ld      a,32                    ; remove the two hint lines (rows 32..55, columns 8..23)
        call    row_addr
        ld      de,8
        add     hl,de
        ld      b,24
pl_hint:push    bc
        push    hl
        ld      bc,16
        xor     a
        call    memfill
        pop     hl
        ld      de,32
        add     hl,de
        pop     bc
        djnz    pl_hint
        ld      hl,FLAP_VY              ; the key that started the game is the first flap
        ld      (v_vy),hl
        ld      bc,0x1818
        call    beep

pl_frame:
IF HEADLESS
        ld      hl,(v_frames)
        inc     hl
        ld      (v_frames),hl
        ld      de,(headless_frames)
        or      a
        sbc     hl,de
        jp      nc,done
ENDIF
        call    wait_vsync
        call    wait_vsync              ; 25 game frames per second
        ld      hl,v_anim
        inc     (hl)
        call    read_keys
IF HEADLESS
ELSE
        call    key_edges
ENDIF
        and     1
        jr      z,pl_noflap
        ld      hl,FLAP_VY
        ld      (v_vy),hl
        ld      bc,0x1818
        call    beep
pl_noflap:
        call    bird_step
        call    pipes_step
        call    score_check
        or      a
        jr      z,pl_draw
        call    draw_hud
        ld      bc,0x1228
        call    beep
        ld      bc,0x0C3C
        call    beep
pl_draw:call    render_frame
        call    collide_all
        or      a
        jr      nz,pl_dead
        ld      a,(v_y+1)
        cp      BIRD_YMAX
        jr      c,pl_frame
pl_dead:ld      bc,0x6440
        call    beep
pl_fall:ld      a,(v_y+1)
        cp      BIRD_YMAX
        jr      nc,pl_over
        call    wait_vsync
        call    bird_step
        call    render_frame
        jr      pl_fall

pl_over:
        ld      hl,(v_best)
        ld      de,(v_score)
        or      a
        sbc     hl,de
        jr      nc,pl_old               ; best >= score
        ld      (v_best),de
        call    best_store
        ld      a,1
        ld      (v_new),a
pl_old: call    draw_hud
        call    draw_panel
IF HEADLESS
        jp      done
ELSE
        call    read_keys
        ld      (v_prevkeys),a
        ld      b,40                    ; ignore keys for a moment so a held SPACE does not skip the screen
pl_pause:
        call    wait_vsync
        djnz    pl_pause
pl_key: call    wait_vsync
        call    read_keys
        call    key_edges
        bit     0,a
        jr      nz,pl_again
        bit     3,a
        jr      z,pl_key
        xor     a                       ; M: back to the menu
        ret
pl_again:
        ld      a,1
        ret
ENDIF

; draw_hud: PONT / REKORD counters on text row 0. Clobbers all.
draw_hud:
        ld      hl,s_score
        ld      bc,1
        call    draw_text
        ld      hl,(v_score)
        ld      bc,6
        call    draw_num3
        ld      hl,s_best
        ld      bc,19
        call    draw_text
        ld      hl,(v_best)
        ld      bc,27
        jp      draw_num3

; draw_panel: game-over box (pixel rows 48..151, bytes 5..26) with the result. Clobbers all.
draw_panel:
        ld      a,48
        call    row_addr
        ld      de,5
        add     hl,de
        ld      b,104
dpn_row:push    bc
        push    hl
        ld      bc,22
        xor     a
        call    memfill
        pop     hl
        ld      (hl),0x80               ; left and right frame lines
        ld      de,21
        add     hl,de
        ld      (hl),0x01
        ld      de,11
        add     hl,de                   ; start + 32: next row, same column
        pop     bc
        djnz    dpn_row
        ld      a,49                    ; top and bottom frame lines
        call    row_addr
        ld      de,5
        add     hl,de
        ld      bc,22
        ld      a,0xFF
        call    memfill
        ld      a,150
        call    row_addr
        ld      de,5
        add     hl,de
        ld      bc,22
        ld      a,0xFF
        call    memfill
        ld      hl,s_over
        ld      b,7
        call    draw_text_center
        ld      hl,s_score
        ld      bc,9 * 256 + 9
        call    draw_text
        ld      hl,(v_score)
        ld      bc,9 * 256 + 19
        call    draw_num3
        ld      hl,s_best
        ld      bc,11 * 256 + 9
        call    draw_text
        ld      hl,(v_best)
        ld      bc,11 * 256 + 19
        call    draw_num3
        ld      a,(v_new)
        or      a
        jr      z,dpn_old
        ld      hl,s_new
        ld      b,13
        call    draw_text_center
dpn_old:ld      hl,s_again
        ld      b,15
        call    draw_text_center
        ld      hl,s_menu
        ld      b,17
        jp      draw_text_center

        include "lib.asm"
        include "gfx.asm"
        include "game.asm"
        include "data.inc"
        include "vars.asm"

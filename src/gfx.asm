; Drawing routines. Screen = 32 bytes per pixel row, 1 bit per pixel, base in v_scr (256-aligned).
; Every routine range-checks its position arguments and draws nothing when they are out of range.

; text_dest  B = text row (0..23), C = text column (0..31) -> DE = address of the cell's top-left byte,
; carry set (DE undefined) if out of range. Clobbers AF,HL.
text_dest:
        ld      a,b
        cp      24
        jr      nc,td_bad
        ld      a,c
        cp      32
        jr      nc,td_bad
        ld      a,b
        add     a,a
        add     a,a
        add     a,a                     ; pixel row = 8*B (<= 184)
        call    row_addr
        ld      a,l                     ; (8*B)&7 = 0 -> L = 0, no carry possible
        add     a,c
        ld      e,a
        ld      d,h
        or      a                       ; clear carry
        ret
td_bad: scf
        ret

; draw_glyph  A = char code, DE = cell top-left -> 8 rows written, DE = next cell (DE+1). Codes >= N_CHARS
; draw a space. Clobbers AF,BC,HL.
draw_glyph:
        cp      N_CHARS
        jr      c,dg_ok
        xor     a
dg_ok:  ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      bc,font
        add     hl,bc
        push    de
        ld      b,8
dg_row: ld      a,(hl)
        ld      (de),a
        inc     hl
        ld      a,e
        add     a,32
        ld      e,a
        jr      nc,dg_nc
        inc     d
dg_nc:  djnz    dg_row
        pop     de
        inc     de
        ret

; draw_text  HL = 0xFF-terminated string, B = text row, C = text column. Stops at the right edge (col 32).
; Clobbers AF,BC,DE,HL.
draw_text:
        push    hl
        call    text_dest
        pop     hl
        ret     c
dt_loop:ld      a,(hl)
        cp      0xFF
        ret     z
        inc     hl
        push    hl
        push    bc
        call    draw_glyph
        pop     bc
        pop     hl
        inc     c
        ld      a,c
        cp      32
        jr      c,dt_loop
        ret

; str_len  HL = string -> A = length (at most 32). Clobbers F,B.
str_len:
        ld      b,0
sl_loop:ld      a,(hl)
        cp      0xFF
        jr      z,sl_end
        inc     hl
        inc     b
        ld      a,b
        cp      32
        jr      c,sl_loop
sl_end: ld      a,b
        ret

; draw_text_center  HL = string, B = text row. Clobbers AF,BC,DE,HL.
draw_text_center:
        push    hl
        push    bc
        call    str_len
        pop     bc
        pop     hl
        ld      c,a
        ld      a,32
        sub     c
        srl     a
        ld      c,a
        jp      draw_text

; to_dec3  HL = value -> B = hundreds, C = tens, A = ones (values above 999 show as 999). Clobbers F,DE,HL.
to_dec3:
        ld      de,1000
        or      a
        sbc     hl,de
        add     hl,de
        jr      c,d3_ok
        ld      hl,SCORE_MAX
d3_ok:  ld      b,0
d3_h:   ld      de,100
        or      a
        sbc     hl,de
        jr      c,d3_hd
        inc     b
        jr      d3_h
d3_hd:  add     hl,de                   ; HL < 100
        ld      a,l
        ld      c,0
d3_t:   cp      10
        jr      c,d3_td
        sub     10
        inc     c
        jr      d3_t
d3_td:  ret

; draw_num3  HL = value, B = text row, C = text column: three digits (leading zeros kept), clipped at column 32.
; Clobbers AF,BC,DE,HL.
draw_num3:
        push    bc
        call    to_dec3
        ld      (v_dig+2),a
        ld      a,b
        ld      (v_dig),a
        ld      a,c
        ld      (v_dig+1),a
        pop     bc
        call    text_dest
        ret     c
        ld      hl,v_dig
        ld      b,3
dn_loop:ld      a,c
        cp      32
        ret     nc
        push    hl
        push    bc
        ld      a,(hl)
        add     a,CH_DIGIT0
        call    draw_glyph
        pop     bc
        pop     hl
        inc     hl
        inc     c
        djnz    dn_loop
        ret

; spr_ptr  A = bird*2 + frame (0..2*N_BIRDS-1) -> HL = sprite data (64 bytes each). Out-of-range -> sprite 0.
; Clobbers AF,DE.
spr_ptr:
        cp      2 * N_BIRDS
        jr      c,sp_ok
        xor     a
sp_ok:  ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,bird_spr
        add     hl,de
        ret

; draw_sprite  HL = sprite (16 rows x [img0,keep0,img1,keep1]), D = top pixel row, E = byte column.
; Draws screen = (screen & keep) | img over 2 bytes x 16 rows. Draws nothing unless D <= 176 and E <= 30.
; Clobbers AF,BC,DE,HL.
draw_sprite:
        ld      a,d
        cp      177
        ret     nc
        ld      a,e
        cp      31
        ret     nc
        push    hl
        ld      a,d
        call    row_addr
        ld      a,l
        add     a,e                     ; L = (row&7)*32 + col <= 224+30: no carry
        ld      e,a
        ld      d,h
        pop     hl
        ld      b,16
ds_row: ld      c,(hl)
        inc     hl
        ld      a,(de)
        and     (hl)
        inc     hl
        or      c
        ld      (de),a
        inc     e
        ld      c,(hl)
        inc     hl
        ld      a,(de)
        and     (hl)
        inc     hl
        or      c
        ld      (de),a
        ld      a,e
        add     a,31                    ; back one byte, down one row (+32)
        ld      e,a
        jr      nc,ds_nc
        inc     d
ds_nc:  djnz    ds_row
        ret

; clear_col16  HL = address of a byte in some row -> that byte and the 15 below it cleared (rows inside the
; parallax band get the background byte back). HL preserved. Clobbers AF,BC,DE.
clear_col16:
        push    hl
        ld      a,(v_scr+1)
        add     a,BAND_HI
        ld      c,a                     ; high byte of the band's first row
        ld      b,16
cc_row: ld      a,h
        cp      c
        jr      c,cc_zero
        push    hl
        ld      e,l
        sub     c
        ld      d,a
        ld      hl,(v_bg)
        add     hl,de
        ld      a,(hl)
        pop     hl
        jr      cc_put
cc_zero:xor     a
cc_put: ld      (hl),a
        ld      de,32
        add     hl,de
        djnz    cc_row
        pop     hl
        ret

; draw_ground: separator line (row 15) and the ground (rows 176..191) from ground_tab. Clobbers all.
draw_ground:
        ld      a,15
        call    row_addr
        ld      bc,32
        ld      a,0xFF
        call    memfill
        ld      a,PLAY_BOT
        call    row_addr
        ld      de,ground_tab
        ld      b,16
dgr_row:push    bc
        push    de
        push    hl
        ld      a,(de)
        ld      bc,32
        call    memfill
        pop     hl
        ld      de,32
        add     hl,de
        pop     de
        inc     de
        pop     bc
        djnz    dgr_row
        ret

; ------------------------------------------------------------ parallax ----
; A theme (city / forest / field, picked at random per game by bg_pick) = two 12-row layers of 256 px, far then
; near, stacked above the ground. They live in RAM and are rotated in place, one pixel to the left per update, then
; copied to the screen. bg_step updates at most one layer per frame (near every 4th, far every 8th frame): 1/4 and
; 1/8 px per frame. Under the pipes the background shows through around the pipe (see seg).

; bg_pick  A = theme (out of range = 0) -> v_theme, v_bg = the theme's far layer. Clobbers AF,HL.
bg_pick:
        cp      N_THEMES
        jr      c,bp_ok
        xor     a
bp_ok:  ld      (v_theme),a
        add     a,a                     ; 2 * theme: a theme is 2 layers * 8 rows * 32 bytes = 2 * 256 bytes
        ld      hl,bg_t0
        add     a,h
        ld      h,a
        ld      (v_bg),hl
        ret

; bg_rot  HL = layer -> every row rotated one pixel left (circular). ~9000 T-states. Clobbers AF,BC,DE,HL.
bg_rot:
        ld      b,BG_ROWS
br_row: ld      a,(hl)                  ; first byte: its bit 7 wraps around into the last byte
        ld      de,31
        add     hl,de
        rla                             ; carry = bit 7 of the first byte (RLA's carry-out ignores carry-in)
        rept    32
        rl      (hl)
        dec     hl
        endr
        ld      de,33                   ; HL = row start - 1 -> next row start
        add     hl,de
        djnz    br_row
        ret

; bg_blit  HL = layer, A = first pixel row -> the layer's rows copied to the screen (rows are contiguous).
; Clobbers AF,BC,DE,HL.
bg_blit:
        push    hl
        call    row_addr
        ex      de,hl
        pop     hl
        ld      bc,BG_ROWS * 32
        ldir
        ret

; bg_draw_all: draw both layers as they are now. Clobbers all.
bg_draw_all:
        ld      hl,(v_bg)
        ld      a,BG_Y_FAR
        call    bg_blit
        ld      hl,(v_bg)
        ld      de,BG_ROWS * 32
        add     hl,de
        ld      a,BG_Y_NEAR
        jr      bg_blit

; bg_skipmap: v_skip[0..31] = 1 for the screen byte columns under a pipe's 5-byte window, and v_seg = the runs of
; free columns as (start, length) byte pairs ending with length 0. Clobbers all.
bg_skipmap:
        ld      hl,v_skip
        ld      bc,32
        xor     a
        call    memfill
        ld      ix,v_pipes
        ld      b,N_PIPES
sk_pipe:push    bc
        ld      l,(ix+0)
        ld      h,(ix+1)
        ld      a,h
        or      a
        jr      z,sk_ok
        inc     a
        jr      nz,sk_next              ; x >= 256 or x < -256
        ld      a,l
        cp      0xE0
        jr      c,sk_next               ; x < -32: gone
sk_ok:  sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l                       ; L = first window byte (-4..31)
        ld      a,l
        ld      b,5
sk_b:   bit     7,a
        jr      nz,sk_nx
        cp      32
        jr      nc,sk_nx
        ld      e,a
        ld      d,0
        ld      hl,v_skip
        add     hl,de
        ld      (hl),1
        ld      a,e
sk_nx:  inc     a
        djnz    sk_b
sk_next:ld      de,PIPE_SZ
        add     ix,de
        pop     bc
        djnz    sk_pipe
        ld      hl,v_skip               ; runs of free columns
        ld      de,v_seg
        ld      b,0                     ; B = column
        ld      c,0xFF                  ; C = start of the open run, 0xFF = none
sr_lp:  ld      a,(hl)
        or      a
        jr      nz,sr_busy
        ld      a,c
        cp      0xFF
        jr      nz,sr_nx
        ld      c,b                     ; a run starts here
        jr      sr_nx
sr_busy:ld      a,c
        cp      0xFF
        jr      z,sr_nx
        ld      (de),a                  ; close the run: start, length
        inc     de
        ld      a,b
        sub     c
        ld      (de),a
        inc     de
        ld      c,0xFF
sr_nx:  inc     hl
        inc     b
        ld      a,b
        cp      32
        jr      c,sr_lp
        ld      a,c
        cp      0xFF
        jr      z,sr_fin
        ld      (de),a                  ; the run that reaches the right edge
        inc     de
        ld      a,32
        sub     c
        ld      (de),a
        inc     de
sr_fin: xor     a
        ld      (de),a
        inc     de
        ld      (de),a                  ; terminator: length 0
        ret

; bg_blit_skip  HL = layer, A = first pixel row: like bg_blit, but the bytes under the pipes' windows are left
; alone (draw_pipe rewrites them right after; copying the background over them would let it show through for a
; moment, and the pipe blinks when the video beam passes in between). Clobbers all.
bg_blit_skip:
        push    hl
        push    af
        call    bg_skipmap
        pop     af
        call    row_addr
        ex      de,hl                   ; DE = screen row
        pop     hl                      ; HL = layer row
        ld      b,BG_ROWS
bk_row: push    bc
        push    hl
        push    de
        ld      ix,v_seg
bk_seg: ld      a,(ix+1)
        or      a
        jr      z,bk_end
        ld      c,a
        ld      b,0
        push    hl
        push    de
        ld      a,(ix+0)
        ld      d,0
        ld      e,a
        add     hl,de                   ; layer + start
        pop     de
        push    de                      ; (the row start stays saved for after the copy)
        ld      a,(ix+0)
        add     a,e
        ld      e,a                     ; screen + start (the row start's low byte is a multiple of 32: no carry)
        ldir                            ; HL = layer + start, DE = screen + start
        pop     de
        pop     hl
        inc     ix
        inc     ix
        jr      bk_seg
bk_end: pop     de
        pop     hl
        ld      bc,32
        add     hl,bc
        ex      de,hl
        add     hl,bc
        ex      de,hl
        pop     bc
        djnz    bk_row
        ret

; bg_step: scroll one layer according to v_anim & 15: 0,4,8,12 near; 2,10 far; others none. Clobbers all.
bg_step:
        ld      a,(v_anim)
        and     15
        ld      c,a
        and     3
        jr      z,bgs_near
        ld      a,c
        cp      2
        jr      z,bgs_far
        cp      10
        ret     nz
bgs_far:ld      hl,(v_bg)
        ld      a,BG_Y_FAR
        jr      bgs_go
bgs_near:ld     hl,(v_bg)
        ld      de,BG_ROWS * 32
        add     hl,de
        ld      a,BG_Y_NEAR
bgs_go: push    af
        push    hl
        call    bg_rot
        pop     hl
        pop     af
        jr      bg_blit_skip

; ---------------------------------------------------------------- pipes ----
; seg  HL = first source byte, B = rows (0 = none), DE = destination. Copies v_n bytes per row, rows are
; 32 bytes apart. Returns DE = start position of the next row. Needs v_n16 (= n) and v_adj (= 32 - n).
; ~210 T-states per row for n = 5. Clobbers AF,BC,HL.
; Rows from BG_Y_FAR down are in the parallax band: there the window is merged with the background instead of
; copied. Window byte 0 and 3 keep the background pixels outside the pipe's 24 px footprint (masks patched into
; merge5 by draw_pipe), bytes 1 and 2 are all pipe, byte 4 is background. A complete window (v_full: 5 bytes, nothing
; clipped) is merged straight into the screen (~320 T-states per row), a clipped one is merged into v_tmp and
; copied (~450).
seg:
        ld      a,b
        or      a
        ret     z
        ld      (v_src),hl
        ld      (v_rows),a
        xor     a
        ld      (v_q),a
        ld      a,(v_scr+1)             ; first row = (DE - screen base) / 32
        ld      c,a
        ld      a,d
        sub     c
        add     a,a
        add     a,a
        add     a,a
        ld      c,a
        ld      a,e
        rlca
        rlca
        rlca
        and     7
        or      c
        cp      BG_Y_FAR
        jr      nc,seg_band0            ; starts inside the band
        ld      c,a
        ld      a,BG_Y_FAR
        sub     c                       ; rows before the band
        ld      c,a
        ld      a,(v_rows)
        sub     c
        jr      c,seg_row               ; ends before the band
        jr      z,seg_row
        ld      (v_q),a                 ; rows inside the band
        ld      a,c
        ld      (v_rows),a              ; rows before it
        jr      seg_row
seg_band0:
        ld      a,(v_rows)
        ld      (v_q),a
        jr      seg_band
seg_row:ld      hl,(v_src)
        ld      bc,(v_n16)
        ldir
        ld      a,(v_adj)
        add     a,e
        ld      e,a
        jr      nc,seg_nc
        inc     d
seg_nc: ld      a,(v_rows)
        dec     a
        ld      (v_rows),a
        jr      nz,seg_row
        ld      a,(v_q)
        or      a
        ret     z
seg_band:                               ; v_q rows, DE = first of them
        ld      a,(v_scr+1)
        add     a,BAND_HI
        ld      b,a
        ld      a,d
        sub     b
        ld      b,a
        ld      c,e                     ; BC = DE - band start
        ld      hl,(v_bg)
        add     hl,bc
        ld      b,h
        ld      c,l                     ; BC = background byte under DE
        ld      a,(v_full)
        or      a
        jr      z,sb_gen
sb_row: ld      hl,(v_src)
        call    merge5
        ld      a,e
        add     a,28
        ld      e,a
        jr      nc,sb_n1
        inc     d
sb_n1:  ld      a,c
        add     a,28
        ld      c,a
        jr      nc,sb_n2
        inc     b
sb_n2:  ld      hl,v_q
        dec     (hl)
        jr      nz,sb_row
        ret
sb_gen:                                 ; clipped window: merge all 5 bytes into v_tmp, copy the n that are on screen
        push    de
        ld      hl,(v_src)
        ld      a,(v_k)
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        ld      (v_sbase),hl            ; pattern of window byte 0
        pop     de
sg2_row:push    de
        push    bc
        ld      a,(v_k)
        ld      l,a
        ld      a,c
        sub     l
        ld      c,a
        jr      nc,sg2_a
        dec     b
sg2_a:  ld      hl,(v_sbase)
        ld      de,v_tmp
        call    merge5
        ld      a,(v_k)
        ld      c,a
        ld      b,0
        ld      hl,v_tmp
        add     hl,bc                   ; first byte that is on screen
        pop     bc                      ; layer byte of the first stored byte
        pop     de                      ; its screen address
        push    bc
        ld      bc,(v_n16)
        ldir
        ld      a,(v_adj)
        add     a,e
        ld      e,a
        jr      nc,sg2_b
        inc     d
sg2_b:  pop     bc
        ld      hl,32
        add     hl,bc
        ld      b,h
        ld      c,l
        ld      hl,v_q
        dec     (hl)
        jr      nz,sg2_row
        ret

; merge5  HL = 5 pattern bytes, BC = 5 background bytes, DE = destination -> (bg & kL) | p0, p1, p2,
; (bg & kR) | p3, bg4 written. HL, BC, DE end on the last byte. Clobbers AF.
merge5:
        ld      a,(bc)
seg_kl: and     0                       ; patched: background bits left of the pipe
        or      (hl)
        ld      (de),a
        inc     bc
        inc     hl
        inc     de
        ld      a,(hl)
        ld      (de),a
        inc     bc
        inc     hl
        inc     de
        ld      a,(hl)
        ld      (de),a
        inc     bc
        inc     hl
        inc     de
        ld      a,(bc)
seg_kr: and     0                       ; patched: background bits right of the pipe
        or      (hl)
        ld      (de),a
        inc     bc
        inc     de
        ld      a,(bc)
        ld      (de),a                  ; trailing byte: background
        ret

; seg_gap  B = rows, DE = destination: v_n bytes per row (v_n16, v_adj as for seg) cleared, except in the band,
; where the background is restored. Returns DE = start of the next row. Clobbers AF,BC,HL.
seg_gap:
        ld      a,b
        or      a
        ret     z
        ld      (v_rows),a
sg_row: ld      a,(v_scr+1)
        add     a,BAND_HI
        ld      c,a
        ld      a,d
        cp      c
        jr      c,sg_zero
        sub     c                       ; background bytes: HL = (v_bg) + (DE - band start)
        ld      h,a
        ld      l,e
        ld      bc,(v_bg)
        add     hl,bc
        ld      bc,(v_n16)
        push    de
        ldir
        pop     de
        jr      sg_next
sg_zero:push    de
        ld      h,d
        ld      l,e
        ld      bc,(v_n16)
        ld      (hl),0
        dec     bc
        ld      a,b
        or      c
        jr      z,sg_zd
        inc     de
        ldir
sg_zd:  pop     de
sg_next:ld      a,e                     ; DE is the row start again: next row = +32
        add     a,32
        ld      e,a
        jr      nc,sg_nc
        inc     d
sg_nc:  ld      a,(v_rows)
        dec     a
        ld      (v_rows),a
        jr      nz,sg_row
        ret

; kl_tab: background bits left of the pipe in the window's first byte, by pixel shift (top s bits)
kl_tab: defb    0x00,0x80,0xC0,0xE0,0xF0,0xF8,0xFC,0xFE

; draw_pipe  IX = pipe (x signed 16 bit, gap top, flags). Draws the pipe's 5-byte-wide window (24 px pipe +
; 7 px shift + 1 byte trailing blank that erases what the 2 px step leaves behind) for rows 16..175, clipped to
; columns 0..31. Gap rows are only touched when the window covers a bird column (8 or 9): that wipes the old
; bird there, and v_cov records which bird columns were cleaned (bit 0 = col 8, bit 1 = col 9).
; Draws nothing when x < -32 or x >= 256. Clobbers all but IX.
draw_pipe:
        ld      l,(ix+0)
        ld      h,(ix+1)
        ld      a,h
        or      a
        jr      z,dp_pos
        inc     a
        ret     nz                      ; x >= 256 or x < -256
        ld      a,l
        cp      0xE0                    ; x < -32: gone (x -32..-24 still draws blank to wipe col 0)
        ret     c
        and     7
        ld      (v_s),a
        ld      a,l
        rrca
        rrca
        rrca
        and     0x1F                    ; 28..31 -> window starts 4..1 bytes left of the screen
        ld      c,a
        ld      a,32
        sub     c
        ld      (v_k),a                 ; k = bytes to skip
        ld      c,a
        ld      a,5
        sub     c
        ld      (v_n),a                 ; n = 5 - k
        xor     a
        ld      (v_dc),a
        jr      dp_geom
dp_pos: ld      a,l
        and     7
        ld      (v_s),a
        ld      a,l
        rrca
        rrca
        rrca
        and     0x1F
        ld      (v_dc),a
        ld      c,a
        xor     a
        ld      (v_k),a
        ld      a,32
        sub     c                       ; room to the right edge: 1..32
        cp      5
        jr      c,dp_n
        ld      a,5
dp_n:   ld      (v_n),a
dp_geom:
        ; --- which bird columns does the window cover?
        ld      a,(v_dc)
        ld      c,a                     ; C = first column
        ld      a,(v_n)
        add     a,c
        dec     a
        ld      d,a                     ; D = last column
        xor     a
        ld      (v_ovl),a
        ld      a,c
        cp      BIRD_COL + 2
        jr      nc,dp_nocov             ; starts right of the bird
        ld      a,d
        cp      BIRD_COL
        jr      c,dp_nocov              ; ends left of the bird
        ld      b,0
        ld      a,c
        cp      BIRD_COL + 1
        jr      nc,dp_c8
        set     0,b                     ; first <= 8 -> covers column 8
dp_c8:  ld      a,d
        cp      BIRD_COL + 1
        jr      c,dp_c9
        set     1,b                     ; last >= 9 -> covers column 9
dp_c9:  ld      a,(v_cov)
        or      b
        ld      (v_cov),a
        ld      a,1
        ld      (v_ovl),a
dp_nocov:
        ; --- masks for merge5 (background bits outside the 24 px footprint); complete window (5 bytes, none clipped)?
        ld      a,(v_s)
        ld      e,a
        ld      d,0
        ld      hl,kl_tab
        add     hl,de
        ld      a,(hl)
        ld      (seg_kl + 1),a
        cpl
        ld      (seg_kr + 1),a
        xor     a
        ld      (v_full),a
        ld      a,(v_n)
        cp      5
        jr      nz,dp_nf
        ld      a,(v_k)
        or      a
        jr      nz,dp_nf
        inc     a
        ld      (v_full),a
dp_nf:
        ; --- source pointers and copy parameters
        ld      a,(v_n)
        ld      (v_n16),a
        ld      c,a
        xor     a
        ld      (v_n16+1),a
        ld      a,32
        sub     c
        ld      (v_adj),a
        ld      a,(v_s)
        rlca
        rlca
        rlca
        rlca
        and     0xF0
        ld      e,a
        ld      d,0
        ld      hl,pipe_tab
        add     hl,de
        ld      a,(v_k)
        ld      e,a
        add     hl,de
        ld      (v_pb),hl               ; shifted BODY pattern, k bytes in
        ; --- destination: row 16, column dc
        ld      a,PLAY_TOP
        call    row_addr
        ld      a,(v_dc)
        add     a,l
        ld      e,a
        ld      d,h
        ; --- top body
        ld      a,(ix+2)
        sub     PLAY_TOP + 8            ; gap top - 24 rows
        ld      b,a
        ld      hl,(v_pb)
        call    seg
        call    dp_cap
        ; --- gap
        ld      a,(v_ovl)
        or      a
        jr      z,dp_skip
        ld      b,GAP_H
        call    seg_gap
        jr      dp_bot
dp_skip:ld      hl,GAP_H * 32
        add     hl,de
        ex      de,hl
dp_bot: call    dp_cap
        ; --- bottom body: rows gap top + 68 .. 175
        ld      a,PLAY_BOT - GAP_H - 8
        sub     (ix+2)
        ld      b,a
        ld      hl,(v_pb)
        jp      seg

; dp_cap: 8 cap rows (edge, 6 fill, edge). DE in/out as in seg. Clobbers AF,BC,HL.
dp_cap:
        ld      hl,(v_pb)
        ld      bc,5
        add     hl,bc
        ld      b,1
        call    seg                     ; edge
        ld      hl,(v_pb)
        ld      bc,10
        add     hl,bc
        ld      b,6
        call    seg                     ; fill
        ld      hl,(v_pb)
        ld      bc,5
        add     hl,bc
        ld      b,1
        jp      seg                     ; edge

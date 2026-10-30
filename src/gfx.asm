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

; clear_col16  HL = address of a byte in some row -> that byte and the 15 below it zeroed. HL preserved.
; Clobbers AF,BC,DE.
clear_col16:
        push    hl
        ld      de,32
        ld      b,16
        xor     a
cc_row: ld      (hl),a
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

; ---------------------------------------------------------------- pipes ----
; seg  HL = first source byte, B = rows (0 = none), DE = destination. Copies v_n bytes per row, rows are
; 32 bytes apart. Returns DE = start position of the next row. Needs v_n16 (= n) and v_adj (= 32 - n).
; ~210 T-states per row for n = 5. Clobbers AF,BC,HL.
seg:
        ld      a,b
        or      a
        ret     z
        ld      (v_src),hl
        ld      (v_rows),a
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
        ret

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
        ld      a,(v_k)
        ld      c,a
        ld      b,0
        ld      hl,pat_zero
        add     hl,bc
        ld      b,GAP_H
        call    seg
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

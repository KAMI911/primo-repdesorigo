; Generic routines. Inputs/outputs in registers; every routine lists what it clobbers.

; detect_color -> A = 1 colour model, 0 monochrome. Clobbers F.
; Reads ROM byte 0 (never writes). Build-time override avoids the check.
detect_color:
IF TARGET_BW
        xor     a
        ret
ELIF TARGET_COLOR
        ld      a,1
        ret
ELSE
        ld      a,(0)
        cp      COLOR_ROM0
        ld      a,0
        ret     nz
        inc     a
        ret
ENDIF

; memfill  HL = dest, BC = count (0 = no-op), A = value. Never writes outside [HL, HL+BC). Clobbers AF,BC,DE,HL.
; Caller guarantees HL+BC <= 0x10000.
memfill:
        ld      e,a
        ld      a,b
        or      c
        ret     z
        ld      (hl),e
        dec     bc
        ld      a,b
        or      c
        ret     z
        ld      d,h
        ld      e,l
        inc     de
        ldir
        ret

; wait_vsync: wait for the START of the next frame blanking (D5 low, then high), so two calls in a row
; take two full frames. Each phase gives up after ~2000 polls (about 40 ms) instead of hanging. Clobbers AF only. Headless (emulator test) builds have no frame signal.
wait_vsync:
IF NOHW
        ret
ELSE
        push    bc                      ; callers keep loop counters in BC (djnz)
        ld      bc,2000                 ; time-outs keep the game alive where the blanking bit never toggles
wv_low: in      a,(PORT0)
        and     IN_VSYNC
        jr      z,wv_hi
        dec     bc
        ld      a,b
        or      c
        jr      nz,wv_low
        pop     bc
        ret
wv_hi:  ld      bc,2000
wv_hi2: in      a,(PORT0)
        and     IN_VSYNC
        jr      nz,wv_out
        dec     bc
        ld      a,b
        or      c
        jr      nz,wv_hi2
wv_out: pop     bc
        ret
ENDIF

; row_addr  A = pixel row 0..191 -> HL = address of the first byte of that row. Clobbers AF.
; Rows are 32 bytes; the screen base (v_scr) is 256-aligned ($E700 / $E800), so only H needs the base.
; HL = base + (A>>3)<<8 + (A&7)<<5
row_addr:
        ld      l,a
        rrca
        rrca
        rrca
        and     0x1F                    ; A>>3 after three rotates: low 5 bits = row>>3
        ld      h,a
        ld      a,l
        rrca
        rrca
        rrca
        and     0xE0
        ld      l,a
        ld      a,(v_scr+1)
        add     a,h
        ld      h,a
        ret

; clear_rows  A = first pixel row, B = number of rows (0 = none). Zeroes whole 32-byte rows.
; Caller keeps A+B <= 192. Clobbers AF,BC,DE,HL.
clear_rows:
        inc     b
        dec     b
        ret     z
        call    row_addr
cr_loop:
        push    bc
        push    hl
        ld      bc,32
        xor     a
        call    memfill
        pop     hl
        ld      de,32
        add     hl,de
        pop     bc
        djnz    cr_loop
        ret

; clear_screen  A = 1 colour / 0 mono (v_mono = 1 on a colour model: wipe only, colour stays off). Clobbers AF,BC,DE,HL. Mono: pixels only. Colour: as Raktáros, wipes
; control, palette, colour RAM and pixels, then programs the palette (colour_setup).
clear_screen:
        or      a
        jr      nz,clear_color
        ld      hl,(v_scr)
        ld      bc,VRAM_MONO_SZ
        xor     a
        jp      memfill
clear_color:
        ld      hl,VRAM_CTRL
        ld      bc,VRAM_CTRL_SZ
        xor     a
        call    memfill
        ld      a,(v_mono)
        or      a
        ret     nz                      ; colour switched off (control $E001 = 0), mono picture at $E800
        jp      colour_setup

; colour_setup (colour model only): palette entries 0..15 = pixel 0 colour, 16..31 = pixel 1 colour, picked by
; the 4x4 cell nibble in colour RAM (see pal_tab, one table per parallax theme). Nibble 0 = night sky / white ink
; (everything), 1 = brown / yellow (ground), 2 / 3 = sky / far and near layer ink of the theme, 5 = sky / yellow
; (lower half of the menu letters). Palette bytes are stored inverted in all three banks. Clobbers AF,BC,DE,HL.
defc PAL_SKY    = 0x0B                  ; RRRGGGBB dark blue
defc PAL_WHITE  = 0xFF
defc PAL_BROWN  = 0x88
defc PAL_YELLOW = 0xFC
colour_setup:
        ld      a,(v_theme)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a                     ; * 32
        ld      e,a
        ld      d,0
        ld      hl,pal_tab
        add     hl,de
        ld      (v_pt),hl
        ld      hl,COL_PAL1
        ld      c,3                     ; three banks of 32 bytes
cs_bank:
        ld      de,(v_pt)
        ld      b,32
cs_ent: ld      a,(de)
        cpl
        ld      (hl),a
        inc     de
        inc     hl
        djnz    cs_ent
        dec     c
        jr      nz,cs_bank
        ld      a,0x81
        ld      (COL_CTRL),a
        ld      hl,COL_RAM + BG_COLROW * 32     ; layer cells, then the ground right below
        ld      bc,2 * 32
        ld      a,0x22
        call    memfill
        inc     hl                      ; memfill leaves HL on the last byte it wrote
        ld      bc,2 * 32
        ld      a,0x33
        call    memfill
        inc     hl
        ld      bc,4 * 32               ; ground = game rows 176..191 = colour rows 46..49
        ld      a,0x11
        jp      memfill

; pal_tab: per theme (city, forest, field): pixel 0 colours for nibble 0..15, then pixel 1 colours for nibble 0..15
; (not inverted). Ink 2 / 3 = far / near layer.
pal_tab:
        defb    PAL_SKY,PAL_BROWN,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY
        defb    PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY
        defb    PAL_WHITE,PAL_YELLOW,0x49,0xA5,PAL_WHITE,PAL_YELLOW,PAL_WHITE,PAL_WHITE      ; city: steel blue / brown
        defb    PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE
        defb    PAL_SKY,PAL_BROWN,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY
        defb    PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY
        defb    PAL_WHITE,PAL_YELLOW,0x10,0x1C,PAL_WHITE,PAL_YELLOW,PAL_WHITE,PAL_WHITE      ; forest: dark / bright green
        defb    PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE
        defb    PAL_SKY,PAL_BROWN,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY
        defb    PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY,PAL_SKY
        defb    PAL_WHITE,PAL_YELLOW,0x3C,0xB8,PAL_WHITE,PAL_YELLOW,PAL_WHITE,PAL_WHITE      ; field: green / olive
        defb    PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE,PAL_WHITE

; menu_colour (colour model): every text row gets two-tone letters: the upper 4 pixel lines white (nibble 0), the lower
; 4 yellow (nibble 5). One text row = two colour RAM rows of 4 lines. Clobbers all.
menu_colour:
        ld      hl,COL_RAM + (COLOR_TOP / 4) * 32
        ld      b,24
mc_row: push    bc
        push    hl
        ld      bc,32
        xor     a
        call    memfill
        pop     hl
        ld      de,32
        add     hl,de
        push    hl
        ld      bc,32
        ld      a,0x55
        call    memfill
        pop     hl
        ld      de,32
        add     hl,de
        pop     bc
        djnz    mc_row
        ret

; pipe_colour  IX = pipe (colour model): the four colour rows of the parallax band (2 per layer; gap bottoms are at
; most at row 152, so a window's band rows are always pipe) get nibble 0 (white ink) under the pipe's 24 px
; footprint, so the layer colours do not tint the pipe; the other cells of its 6-byte window get their layer's
; nibble back. Same x range as draw_pipe. Clobbers all but IX.
defc BG_COLROW  = COLOR_TOP / 4 + BG_Y_FAR / 4   ; first colour RAM row of the band
pipe_colour:
        ld      l,(ix+0)
        ld      h,(ix+1)
        ld      a,h
        or      a
        jr      z,pc_ok
        inc     a
        ret     nz                      ; x >= 256 or x < -256
        ld      a,l
        cp      0xD8
        ret     c                       ; x < -40: gone
pc_ok:  ld      (v_px),hl
        sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l                       ; L = first window byte, -5..31
        ld      a,l
        ld      (v_pc),a
        ld      a,6
        ld      (v_pn),a
pc_loop:ld      a,(v_pc)
        bit     7,a
        jr      nz,pc_next              ; left of the screen
        cp      32
        jr      nc,pc_next              ; right of it
        call    pc_byte
pc_next:ld      hl,v_pc
        inc     (hl)
        ld      hl,v_pn
        dec     (hl)
        jr      nz,pc_loop
        ret

; pc_byte  A = screen byte column -> the nine band cells of that column (3 layers x 3 colour rows).
pc_byte:
        ld      c,a
        ld      h,0
        ld      l,a
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; first pixel of the byte
        ld      de,(v_px)
        or      a
        sbc     hl,de                   ; relative to the pipe's left edge
        ld      de,3
        add     hl,de                   ; a cell [s, s+3] overlaps the 24 px footprint when 0 <= s - x + 3 < 27
        ld      b,0xFF                  ; B = nibbles that keep the layer colour
        ld      a,h
        or      a
        jr      nz,pb_r
        ld      a,l
        cp      27
        jr      nc,pb_r
        ld      b,0x0F                  ; left cell under the pipe
pb_r:   ld      de,4
        add     hl,de
        ld      a,h
        or      a
        jr      nz,pb_w
        ld      a,l
        cp      27
        jr      nc,pb_w
        ld      a,b
        and     0xF0
        ld      b,a                     ; right cell under the pipe
pb_w:   ld      hl,COL_RAM + BG_COLROW * 32
        ld      e,c
        ld      d,0
        add     hl,de
        ld      de,32
        ld      a,0x22
        and     b
        ld      (hl),a
        add     hl,de
        ld      (hl),a
        add     hl,de
        ld      a,0x33
        and     b
        ld      (hl),a
        add     hl,de
        ld      (hl),a
        ret

; beep  B = half-period delay (T ~ 16*B+30), C = number of half periods (1..255; 0 = 256).
; Toggles the speaker bit D4 starting from the shadow register value and restores it. NMI may click: harmless.
; Clobbers AF,DE,HL. Headless builds have no speaker.
beep:
IF NOHW
        ret
ELSE
        ld      a,(SHADOW_PORT0)
        ld      d,a
bp_half:xor     P0_SOUND
        out     (PORT0),a
        ld      e,b
bp_dly: dec     e
        jr      nz,bp_dly
        dec     c
        jr      nz,bp_half
        ld      a,d
        out     (PORT0),a
        ret
ENDIF

; read_keys -> A: bit0 = flap (SPACE, UP or RETURN), bit1 = LEFT, bit2 = RIGHT, bit3 = M, bit4 = UP, bit5 = DOWN,
; bit6 = start (SPACE or RETURN). Clobbers BCD.
; Scan: IN A,(code), bit 0 = 1 -> pressed. Headless builds use the autopilot instead (see game.asm).
read_keys:
IF HEADLESS
        jp      autopilot
ELIF SCRIPTED
        ld      hl,(v_ksp)              ; test builds: one scripted key mask per call, 0xFF ends the run
        ld      a,(hl)
        cp      0xFF
        jp      z,done
        inc     hl
        ld      (v_ksp),hl
        ret
ELSE
        ld      a,KEY_SPACE
        call    rd_key
        ld      d,a
        ld      a,KEY_RETURN
        call    rd_key
        or      d
        and     1
        ld      e,a                     ; E bit 0 = SPACE or RETURN
        rlca
        rlca
        rlca
        rlca
        rlca
        rlca
        ld      d,a                     ; bit 6 = start
        ld      a,KEY_UP
        call    rd_key
        and     1
        ld      c,a
        rlca
        rlca
        rlca
        rlca
        or      d
        ld      d,a                     ; bit 4 = UP
        ld      a,c
        or      e
        or      d
        ld      d,a                     ; bit 0 = flap (SPACE, RETURN or UP)
        ld      a,KEY_DOWN
        call    rd_key
        and     1
        rlca
        rlca
        rlca
        rlca
        rlca
        or      d
        ld      d,a                     ; bit 5 = DOWN
        ld      a,KEY_LEFT
        call    rd_key
        and     1
        rlca
        or      d
        ld      d,a
        ld      a,KEY_RIGHT
        call    rd_key
        and     1
        rlca
        rlca
        or      d
        ld      d,a
        ld      a,KEY_M
        call    rd_key
        and     1
        rlca
        rlca
        rlca
        or      d
        ld      d,a                     ; bit 3 = M
        ld      a,KEY_C
        call    rd_key
        and     1
        rrca                            ; bit 7 = C (colour / yellow mono)
        or      d
        ret

; rd_key  A = scan code (0..63) -> A = IN value. BC = code, so the whole 16-bit port address is the code.
rd_key:
        ld      c,a
        ld      b,0
        in      a,(c)
        ret
ENDIF

; key_edges  A = current key mask -> A = keys newly pressed since the previous call (updates v_prevkeys).
; Clobbers BC.
key_edges:
        ld      c,a
        ld      a,(v_prevkeys)
        cpl
        and     c
        ld      b,a
        ld      a,c
        ld      (v_prevkeys),a
        ld      a,b
        ret

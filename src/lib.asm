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
; the 4x4 cell nibble in colour RAM. Nibble 0 = night sky / white ink (everything), nibble 1 = brown / yellow
; (ground). Palette bytes are stored inverted in all three banks. Clobbers AF,BC,DE,HL.
defc PAL_SKY    = 0x0B                  ; RRRGGGBB dark blue
defc PAL_WHITE  = 0xFF
defc PAL_BROWN  = 0x88
defc PAL_YELLOW = 0xFC
colour_setup:
        ld      hl,COL_PAL1
        ld      c,3                     ; three banks of 32 bytes
cs_bank:
        ld      b,32
        ld      d,0                     ; palette byte number
cs_ent: ld      a,d
        cp      16
        ld      e,PAL_SKY
        jr      c,cs_lo
        ld      e,PAL_WHITE
cs_lo:  ld      a,d
        and     0x0F
        cp      1
        jr      nz,cs_put
        ld      a,d
        cp      16
        ld      e,PAL_BROWN
        jr      c,cs_put
        ld      e,PAL_YELLOW
cs_put: ld      a,e
        cpl
        ld      (hl),a
        inc     hl
        inc     d
        djnz    cs_ent
        dec     c
        jr      nz,cs_bank
        ld      a,0x81
        ld      (COL_CTRL),a
        ld      hl,COL_RAM + (COLOR_TOP / 4 + 44) * 32  ; ground = game rows 176..191 = colour rows 46..49
        ld      bc,4 * 32
        ld      a,0x11
        jp      memfill

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

; read_keys -> A: bit0 = flap (SPACE, UP or RETURN), bit1 = LEFT, bit2 = RIGHT, bit3 = ESC, bit4 = UP, bit5 = DOWN,
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
        ld      a,KEY_ESC
        call    rd_key
        and     1
        rlca
        rlca
        rlca
        or      d
        ld      d,a                     ; bit 3 = ESC
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

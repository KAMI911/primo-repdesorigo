#!/usr/bin/env python3
"""Test runner: Z80 unit tests (tests/test_units.asm) and headless gameplay runs, both in z88dk-ticks.

Unit tests: Python writes build/cases.inc (inputs), the asm drives the routines and stores results, and this file
compares them with an independent model of what the routines must do.  Gameplay runs: the real game loop with
an autopilot instead of the keyboard (-DHEADLESS), results read from the RAM dump.

    python3 tests/run_tests.py            # all tests
    python3 tests/run_tests.py --shots D  # also write PNG screenshots to D (needs Pillow)
"""
import os
import random
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_assets as G  # noqa: E402

IMG = os.environ.get("Z88DK_IMG", "z88dk/z88dk@sha256:2aab19402c1846858e5fb80b1bb7582af2a94375c41a592512a9bef4bc90719f")
RUN = [] if shutil.which("z88dk-z80asm") else ["docker", "run", "--rm", "--user", "%d:%d" % (os.getuid(), os.getgid()),
                                               "-v", ROOT + ":/src", "-w", "/src", IMG]
BUILD = "build"
os.makedirs(BUILD, exist_ok=True)

C = {}  # constants from src/game.inc
for name, val in re.findall(r"^defc\s+(\w+)\s*=\s*(\S+)", open("src/game.inc").read(), re.M):
    C[name] = int(val, 0)
VRAM = 0xE800
SPEED = [2, 3, 4]            # per level, mirrors speed_tab / space_tab in src/game.asm
SPACE = [112, 128, 144]
GRAV = [0x28, 0x32, 0x3C]
VMAX = [4, 5, 6]
BIRD_DG = [0, -6, 3, 8]      # mirrors bird_dg in src/game.asm
FAILS = []
G_THEMES = len(G.THEMES)


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print("FAIL", what)
        return False
    return True


def sh(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("command failed: %s\n%s%s" % (" ".join(cmd), r.stdout, r.stderr))
    return r.stdout


def assemble(src, out, defs=()):
    sh(RUN + ["z88dk-z80asm", "-b", "-mz80", "-Isrc", "-I" + BUILD, "-m"] + ["-D" + d for d in defs] + ["-o" + out, src])
    syms = {}
    for n, a in re.findall(r"^(\w+)\s+= \$([0-9A-Fa-f]+)", open(out.rsplit(".", 1)[0] + ".map").read(), re.M):
        syms[n] = int(a, 16)
    return syms


LAST_CYCLES = [0]


def run_ticks(binf, end, mem, counter=4_000_000_000):
    out = sh(RUN + ["z88dk-ticks", "-mz80", "-x", binf.rsplit(".", 1)[0] + ".map", "-pc", "0x4400", "-l", "0x4400",
              "-end", end, "-counter", str(counter), "-output", mem, binf])
    nums = re.findall(r"\d+", out)
    LAST_CYCLES[0] = int(nums[-1]) if nums else 0
    return open(mem, "rb").read()


# ------------------------------------------------------------------ models --
def s16(v):
    return v - 65536 if v & 0x8000 else v


def model_row_addr(y):
    return VRAM + (y >> 3) * 256 + (y & 7) * 32


def pattern_for_row(r, gt):
    """Pixel pattern (24 bools) of pipe row r, or None for gap rows."""
    cap = G.CAP_FILL
    if r < gt - 8:
        return G.BODY
    if r < gt:
        i = r - (gt - 8)
        return G.CAP_EDGE if i in (0, 7) else cap
    if r < gt + C["GAP_H"]:
        return None
    if r < gt + C["GAP_H"] + 8:
        i = r - (gt + C["GAP_H"])
        return G.CAP_EDGE if i in (0, 7) else cap
    return G.BODY


BG_Y = C["BG_Y_FAR"]           # first row of the parallax band
GT_VALUES = [C["GT_MIN"] + C["GT_STEP"] * i for i in range(C["GT_RANGE"])]


def bg_byte(bg, r, c):
    return bg[(r - BG_Y) * 32 + c] if bg is not None and r >= BG_Y else 0


def model_pipe(x, gt, screen, bg=None):
    """Draw one pipe into `screen` (bytearray, 32 bytes/row from row 0); returns v_cov. `bg` = the parallax layers
    (bytes from the band's first row on): in the band every window keeps the background outside the pipe's 24 px
    footprint, and restored gap rows show it."""
    if x < C["PIPE_MIN_X"] or x >= 256:
        return 0
    col = x // 8                       # floor
    lo, hi = max(col, 0), min(col + 4, 31)
    ovl = lo <= C["BIRD_COL"] + 1 and hi >= C["BIRD_COL"]
    cov = 0
    if ovl:
        cov = (1 if lo <= C["BIRD_COL"] else 0) | (2 if hi >= C["BIRD_COL"] + 1 else 0)
    for r in range(C["PLAY_TOP"], C["PLAY_BOT"]):
        pat = pattern_for_row(r, gt)
        if pat is None and not ovl:
            continue
        for c in range(lo, hi + 1):
            if pat is None:
                screen[r * 32 + c] = bg_byte(bg, r, c)         # gap row under the bird: restore
                continue
            b = 0
            keep = r >= BG_Y
            under = bg_byte(bg, r, c)
            for bit in range(8):
                px = c * 8 + bit - x
                if 0 <= px < 24:
                    if pat[px]:
                        b |= 0x80 >> bit
                elif keep and under & (0x80 >> bit):
                    b |= 0x80 >> bit
            screen[r * 32 + c] = b
    return cov


def checksum(screen):
    s1 = s2 = 0
    for b in screen:
        s1 = (s1 + b) & 0xFFFF
        s2 = (s2 + s1) & 0xFFFF
    return s1, s2


def model_sprite(idx, y, col, screen):
    if y > 176 or col > 30:
        return
    rows = G.sprite_rows(idx // 2, idx % 2)
    for i, (i0, k0, i1, k1) in enumerate(rows):
        a = (y + i) * 32 + col
        screen[a] = (screen[a] & k0) | i0
        screen[a + 1] = (screen[a + 1] & k1) | i1


def model_text(row, col, codes, screen):
    if row >= 24 or col >= 32:
        return
    for ch in codes:
        if col >= 32:
            break
        gb = G.glyph_bytes(G.CHARSET[ch])
        for i in range(8):
            screen[(row * 8 + i) * 32 + col] = gb[i]
        col += 1


def model_step(y, vy, lv, bird):
    vy = s16(vy)
    vy += GRAV[lv] + BIRD_DG[bird]
    if vy >= VMAX[lv] * 256:
        vy = VMAX[lv] * 256
    y += vy
    if (y >> 8) >= C["BIRD_YMAX"]:
        y, vy = C["BIRD_YMAX"] * 256, 0
    elif (y >> 8) < C["PLAY_TOP"]:
        y, vy = C["PLAY_TOP"] * 256, 0
    return y & 0xFFFF, vy & 0xFFFF


def model_hit(x, gt, y):
    if not 44 <= x <= 76:
        return 0
    return int(y + 2 < gt or y + 14 > gt + C["GAP_H"])


# ------------------------------------------------------------------- cases --
def rnd_gap(rng):
    return rng.choice(GT_VALUES)


def build_cases():
    rng = random.Random(1234)
    cases = {}
    cases["pipe"] = [(x & 0xFFFF, rnd_gap(rng)) for x in range(-40, 266)]
    cases["pipe"] += [(x & 0xFFFF, g) for x in (-32, -31, -25, -24, -23, -17, -16, 0, 7, 8, 64, 72, 248, 255)
                      for g in (GT_VALUES[0], GT_VALUES[-1])]
    cases["spr"] = [(i, y, c) for i in range(2 * len(G.BIRDS)) for y in (16, 88, 160, 176)
                    for c in (8, 30)]
    cases["spr"] += [(0, 177, 8), (0, 88, 31), (1, 255, 8), (2, 88, 255), (3, 0, 0)]
    # text cases: kind, row, col, string label or value
    cases["text"] = [(0, 2, 5, "s_title"), (1, 3, 0, "s_title"), (1, 4, 0, "bn_1"), (1, 5, 0, "bn_3"),
                     (0, 10, 28, "s_choose"), (0, 24, 0, "s_title"), (0, 3, 32, "s_title"), (0, 23, 31, "s_best"),
                     (2, 0, 6, 0), (2, 0, 6, 7), (2, 1, 3, 123), (2, 2, 4, 999), (2, 3, 4, 1000), (2, 4, 30, 456),
                     (2, 5, 31, 12), (1, 6, 0, "s_ready2"), (1, 7, 0, "s_again"), (1, 8, 0, "s_over"),
                     (1, 9, 0, "s_new"), (1, 10, 0, "s_menu"), (1, 11, 0, "s_keys")]
    cases["pipebg"] = [(x & 0xFFFF, g) for x in (-30, -9, -8, 0, 3, 8, 40, 56, 63, 64, 72, 77, 100, 183, 216, 220, 224, 231, 240, 250)
                       for g in (40, 64, 92)]
    cases["step"] = [(y << 8 | f, vy & 0xFFFF, lv, bird) for y in (16, 100, 159, 160)
                     for f in (0, 0xFF) for vy in (0, 0x28, -0x300, 0x3FF, 0x400, 0x500, 0x5FF, 0x600, 0x700, -0x100, -0x2F0)
                     for lv in range(len(GRAV)) for bird in range(len(BIRD_DG))]
    cases["coll"] = []
    for x in (-30, 0, 43, 44, 45, 60, 76, 77, 78, 300):
        for gt in (40, 70, 92):
            for y in (16, 38, 39, 40, 41, 100, 132, 133, 134, 137, 138, 139, 160):
                cases["coll"].append((x & 0xFFFF, gt, y))
    cases["score"] = [(x & 0xFFFF, fl, sc) for x in (-24, -1, 0, 39, 40, 41, 100, 255, 256, 310)
                      for fl in (0, 1) for sc in (0, 5, 998, 999)]
    cases["pstep"] = [(x & 0xFFFF, g, fl, sp) for x in (300, 200, 6, 4, 2, 0, -2, -22, -23, -28, -29, -30, -31, -32, -33, -34, -35, 255, 256, 257)
                      for g in (40, 92) for fl in (0, 1) for sp in (0, 1, 2)]
    return cases


def write_cases(cases):
    L = []

    def table(name, entries, enc):
        L.append("%s:\n        defw    %d" % (name, len(entries)))
        for e in entries:
            L.append("        " + enc(e))
    table("pipe_cases", cases["pipe"], lambda e: "defb %d,%d,%d" % (e[0] & 255, e[0] >> 8, e[1]))
    table("spr_cases", cases["spr"], lambda e: "defb %d,%d,%d" % e)
    table("text_cases", cases["text"],
          lambda e: "defb %d,%d,%d\n        defw %s" % (e[0], e[1], e[2], e[3]))
    table("pipebg_cases", cases["pipebg"], lambda e: "defb %d,%d,%d" % (e[0] & 255, e[0] >> 8, e[1]))
    table("step_cases", cases["step"], lambda e: "defw %d,%d,%d,%d" % e)
    table("coll_cases", cases["coll"], lambda e: "defb %d,%d,%d,%d" % (e[0] & 255, e[0] >> 8, e[1], e[2]))
    table("score_cases", cases["score"], lambda e: "defb %d,%d,%d\n        defw %d" % (e[0] & 255, e[0] >> 8, e[1], e[2]))
    table("pstep_cases", cases["pstep"], lambda e: "defb %d,%d,%d,%d,%d" % (e[0] & 255, e[0] >> 8, e[1], e[2], e[3]))
    open(os.path.join(BUILD, "cases.inc"), "w").write("\n".join(L) + "\n")


def rd(mem, addr, n):
    return mem[addr:addr + n]


def u16(b, i):
    return b[i] | b[i + 1] << 8


def str_codes(label):
    """Codes of the generator's string/name for a data label."""
    if label.startswith("bn_"):
        return G.enc(G.BIRD_NAMES[int(label[3:])])
    return G.enc(G.STRINGS[label])


# ------------------------------------------------------------- unit tests ---
def unit_tests():
    cases = build_cases()
    write_cases(cases)
    sym = assemble("tests/test_units.asm", BUILD + "/test_units.bin")
    mem = run_ticks(BUILD + "/test_units.bin", "t_done", BUILD + "/test_units.mem")
    print("unit test binary: %d bytes, symbols %d" % (os.path.getsize(BUILD + "/test_units.bin"), len(sym)))

    r = rd(mem, sym["res_rows"], 192 * 2)
    check(all(u16(r, 2 * y) == model_row_addr(y) for y in range(192)), "row_addr matches base + (y>>3)*256 + (y&7)*32")

    check(u16(mem, sym["res_period"]) == 65535 and mem[sym["res_zero"]] == 0, "rand8: period 65535, state never 0")

    g = rd(mem, sym["res_gap"], 256)
    check(all(g[i] == GT_VALUES[(i & 15) if (i & 15) < C["GT_RANGE"] else (i & 15) - C["GT_RANGE"]] for i in range(256)),
          "gap_map matches model")
    check(sorted(set(g)) == GT_VALUES and all(v % 4 == 0 for v in GT_VALUES), "gap_map covers exactly 40, 44 .. 92 (multiples of 4)")
    check(GT_VALUES[-1] + C["GAP_H"] + 8 <= C["PLAY_BOT"] - 16, "gap range leaves >= 16 px of bottom pipe")
    check(GT_VALUES[-1] + C["GAP_H"] <= C["BG_Y_FAR"], "gaps end at or above the parallax band (band rows are always pipe)")
    check(C["BAND_HI"] == C["BG_Y_FAR"] * 32 // 256 and C["BG_Y_FAR"] % 8 == 0 and C["BG_Y_NEAR"] == C["BG_Y_FAR"] + C["BG_ROWS"]
          and C["BG_Y_NEAR"] + C["BG_ROWS"] == C["PLAY_BOT"] and C["BG_ROWS"] * 32 == 256 and C["BG_ROWS"] % 4 == 0 and C["GAP_H"] % 4 == 0 and C["PLAY_TOP"] % 4 == 0
          and C["PLAY_BOT"] % 4 == 0, "band geometry: a layer is 256 bytes (bg_pick strides by 2 pages), starts on a 256 byte boundary, ends at the ground, all edges on 4 line colour rows")
    check(C["GT_MIN"] - 8 - C["PLAY_TOP"] >= 16, "gap range leaves >= 16 px of top pipe")

    d = rd(mem, sym["res_dec"], 1101 * 3)
    ok = all((d[3 * v], d[3 * v + 1], d[3 * v + 2]) == tuple(int(c) for c in "%03d" % min(v, 999)) for v in range(1101))
    check(ok, "to_dec3 0..1100 (values above 999 show as 999)")

    r = rd(mem, sym["res_pipe"], len(cases["pipe"]) * 5)
    bad = []
    for i, (x16, gt) in enumerate(cases["pipe"]):
        scr = bytearray([0xFF]) * 6144
        cov = model_pipe(s16(x16), gt, scr)
        s1, s2 = checksum(scr)
        got = (r[5 * i], u16(r, 5 * i + 1), u16(r, 5 * i + 3))
        if got != (cov, s1, s2):
            bad.append((s16(x16), gt, got, (cov, s1, s2)))
    check(not bad, "draw_pipe == pixel model for %d cases (first bad: %s)" % (len(cases["pipe"]), bad[:2]))

    bgl = [(0x33 + 5 * i) & 0xFF for i in range(2 * G.BG_ROWS * 32)]
    r = rd(mem, sym["res_pipebg"], len(cases["pipebg"]) * 5)
    bad = []
    for i, (x16, gt) in enumerate(cases["pipebg"]):
        scr = bytearray([0xFF]) * 6144
        cov = model_pipe(s16(x16), gt, scr, bgl)
        s1, s2 = checksum(scr)
        got = (r[5 * i], u16(r, 5 * i + 1), u16(r, 5 * i + 3))
        if got != (cov, s1, s2):
            bad.append((s16(x16), gt, got, (cov, s1, s2)))
    check(not bad, "draw_pipe over the parallax band == model for %d cases (first bad: %s)" % (len(cases["pipebg"]), bad[:2]))

    r = rd(mem, sym["res_spr"], len(cases["spr"]) * 4)
    bad = []
    for i, (idx, y, col) in enumerate(cases["spr"]):
        scr = bytearray([0x5A]) * 6144
        model_sprite(idx, y, col, scr)
        s1, s2 = checksum(scr)
        if (u16(r, 4 * i), u16(r, 4 * i + 2)) != (s1, s2):
            bad.append((idx, y, col))
    check(not bad, "draw_sprite == model (incl. clipping) for %d cases (bad: %s)" % (len(cases["spr"]), bad[:3]))

    r = rd(mem, sym["res_text"], len(cases["text"]) * 4)
    bad = []
    for i, (kind, row, col, what) in enumerate(cases["text"]):
        scr = bytearray(6144)
        if kind == 2:
            v = min(what, 999)
            model_text(row, col, [1 + int(c) for c in "%03d" % v], scr)
        elif kind == 0:
            model_text(row, col, str_codes(what), scr)
        else:
            codes = str_codes(what)
            model_text(row, (32 - len(codes)) // 2, codes, scr)
        s1, s2 = checksum(scr)
        if (u16(r, 4 * i), u16(r, 4 * i + 2)) != (s1, s2):
            bad.append((kind, row, col, what))
    check(not bad, "text routines == model for %d cases (bad: %s)" % (len(cases["text"]), bad[:3]))

    r = rd(mem, sym["res_step"], len(cases["step"]) * 4)
    bad = [(c, (u16(r, 4 * i), u16(r, 4 * i + 2)), model_step(*c)) for i, c in enumerate(cases["step"])
           if (u16(r, 4 * i), u16(r, 4 * i + 2)) != model_step(*c)]
    check(not bad, "bird_step == model for %d states (bad: %s)" % (len(cases["step"]), bad[:2]))

    r = rd(mem, sym["res_coll"], len(cases["coll"]))
    bad = [(s16(c[0]), c[1], c[2], r[i]) for i, c in enumerate(cases["coll"]) if r[i] != model_hit(s16(c[0]), c[1], c[2])]
    check(not bad, "collide_all == model for %d cases (bad: %s)" % (len(cases["coll"]), bad[:3]))

    r = rd(mem, sym["res_score"], len(cases["score"]) * 4)
    bad = []
    for i, (x16, fl, sc) in enumerate(cases["score"]):
        x = s16(x16)
        passed = (not fl & 1) and x < C["SCORE_X"]
        exp = (int(passed), fl | int(passed), min(sc + int(passed), 999) if sc < 999 else sc)
        got = (r[4 * i], r[4 * i + 1], u16(r, 4 * i + 2))
        if got != exp:
            bad.append((x, fl, sc, got, exp))
    check(not bad, "score_check == model for %d cases (bad: %s)" % (len(cases["score"]), bad[:2]))

    r = rd(mem, sym["res_pstep"], len(cases["pstep"]) * 4)
    bad = []
    for i, (x16, gt, fl, sp) in enumerate(cases["pstep"]):
        x = s16(x16) - SPEED[sp]
        if x < C["PIPE_MIN_X"]:
            x += 3 * SPACE[sp]
            ok = r[4 * i + 2] in GT_VALUES and r[4 * i + 3] == 0
        else:
            ok = r[4 * i + 2] == gt and r[4 * i + 3] == fl
        if not ok or s16(u16(r, 4 * i)) != x:
            bad.append((s16(x16), gt, fl, sp, s16(u16(r, 4 * i)), r[4 * i + 2], r[4 * i + 3]))
    check(not bad, "pipes_step (move, recycle, new gap, flag reset) for %d cases (bad: %s)" % (len(cases["pstep"]), bad[:2]))

    r = rd(mem, sym["res_reset"], 24)
    for lv in (0, 2):
        xs = [s16(u16(r, 12 * (lv // 2) + 4 * i)) for i in range(3)]
        want = [200 + i * SPACE[lv] for i in range(3)]
        check(xs == want and all(r[12 * (lv // 2) + 4 * i + 2] in GT_VALUES and r[12 * (lv // 2) + 4 * i + 3] == 0 for i in range(3)),
              "pipes_reset level %d places pipes %s (want %s) with legal gaps" % (lv, xs, want))

    tn = list(rd(mem, sym["res_tn"], 12))
    want = [(prev + 1 + (b & 1)) % 3 for prev in range(3) for b in range(4)]
    check(tn == want and all(tn[4 * p + i] != p for p in range(3) for i in range(4)),
          "theme_next never repeats the previous theme and uses both others: %s" % tn)

    pk = [u16(rd(mem, sym["res_pick"], 8), 2 * i) for i in range(4)]
    check(pk == [sym["bg_t0"], sym["bg_t1"], sym["bg_t2"], sym["bg_t0"]], "bg_pick selects themes 0, 1, 2 (9 -> 0): %s" % [hex(v) for v in pk])
    # parallax: layers rotate one pixel left per update and are copied to their screen rows
    def rot(layer, n):
        out = []
        for y in range(G.BG_ROWS):
            v = int.from_bytes(bytes(layer[y * 32:y * 32 + 32]), "big")
            for _ in range(n):
                v = ((v << 1) | (v >> 255)) & ((1 << 256) - 1)
            out += list(v.to_bytes(32, "big"))
        return out
    _, far_fn, near_fn = G.THEMES[1]                    # the test runs theme 1 (forest)
    art = [G._layer(far_fn), G._layer(near_fn)]
    want = [rot(art[0], 1), rot(art[1], 4)]
    n = G.BG_ROWS * 32
    r = rd(mem, sym["res_bg"], 2 * n)
    got = [list(r[i * n:(i + 1) * n]) for i in range(2)]
    check(got == want, "parallax layers rotate: far x1, near x4 (bg_pick / bg_rot / bg_step phases)")
    rs = rd(mem, sym["res_bgscr"], 2 * n)
    shown = [list(rs[i * n:(i + 1) * n]) for i in range(2)]
    check(shown == want, "parallax layers are blitted to their screen rows (far 160, near 168)")
    sk = list(rd(mem, sym["res_bgskip"], n))
    near5 = rot(art[1], 5)
    want_sk = [0x55 if 12 <= c <= 16 else near5[y * 32 + c] for y in range(G.BG_ROWS) for c in range(32)]
    check(sk == want_sk, "bg_step leaves the bytes under a pipe window (columns 12..16) alone")
    check(u16(mem, sym["res_bc"]) == 0x1234, "wait_vsync preserves BC (res_bc=%#x)" % u16(mem, sym["res_bc"]))

    # the whole image stays below the second screen page
    check(sym["stack_top"] < 0xC800, "test image below $C800")
    return len(cases["pipe"])


# --------------------------------------------------------- gameplay runs ----
def screen_image(mem, base=VRAM):
    from PIL import Image
    img = Image.new("1", (256, 192))
    px = img.load()
    for y in range(192):
        for xb in range(32):
            b = mem[base + y * 32 + xb]
            for i in range(8):
                px[xb * 8 + i, y] = (b >> (7 - i)) & 1
    return img


def headless(defs, bird=0, frames=400, bot=1, seed=0xACE1, tag="head", level=0, mono=0, theme=0):
    out = "%s/%s.bin" % (BUILD, tag)
    sym = assemble("src/main.asm", out, ["HEADLESS", "NOHW"] + list(defs))
    data = bytearray(open(out, "rb").read())

    def poke(name, val, n=1):
        a = sym[name] - 0x4400
        data[a:a + n] = val.to_bytes(n, "little")
    poke("headless_bird", bird)
    poke("headless_level", level)
    poke("headless_mono", mono)
    poke("headless_theme", theme)
    poke("headless_bot", bot)
    poke("headless_frames", frames, 2)
    poke("headless_seed", seed, 2)
    open(out, "wb").write(data)
    mem = run_ticks(out, "done", "%s/%s.mem" % (BUILD, tag))
    w = lambda n: mem[sym[n]] | mem[sym[n] + 1] << 8
    return dict(score=w("v_score"), best=w("v_best"), frames=w("v_frames"), y=mem[sym["v_y"] + 1], new=mem[sym["v_new"]],
                mem=mem, sym=sym)


def gameplay(shots):
    for bird in range(len(G.BIRDS)):
        r = headless([], bird=bird, frames=700, tag="head%d" % bird)
        check(r["frames"] == 700 and r["score"] >= 700 // 60 - 2,
              "bird %d: autopilot survives 700 frames and passes pipes (score %d, frames %d)" % (bird, r["score"], r["frames"]))
        if shots and bird == 0:
            screen_image(r["mem"]).resize((768, 576)).save(os.path.join(shots, "play.png"))
    for theme in range(G_THEMES):
        r = headless([], theme=theme, frames=700, tag="theme%d" % theme)
        check(r["frames"] == 700 and r["score"] >= 700 // 60 - 2,
              "theme %d (%s): autopilot survives 700 frames (score %d)" % (theme, G.THEMES[theme][0], r["score"]))
        if shots:
            screen_image(r["mem"]).resize((768, 576)).save(os.path.join(shots, "play_%s.png" % G.THEMES[theme][0]))
    for seed in (1, 0x1234, 0xBEEF, 0x7777, 0xFFFF):
        r = headless([], seed=seed, frames=1500, tag="seed")
        check(r["frames"] == 1500 and r["score"] >= 1500 // 60 - 3, "seed %#x: 1500 frames alive, score %d" % (seed, r["score"]))
    for level in range(3):
        need = 1500 * SPEED[level] // SPACE[level] - 3
        r = headless([], level=level, frames=1500, tag="level%d" % level)
        check(r["frames"] == 1500 and r["score"] >= need,
              "level %d (speed %d, spacing %d): autopilot survives 1500 frames, score %d >= %d" % (level, SPEED[level], SPACE[level], r["score"], need))
        if shots:
            screen_image(r["mem"]).resize((768, 576)).save(os.path.join(shots, "play_level%d.png" % level))
    for seed in (1, 0x1234, 0xBEEF, 0x7777):
        r = headless([], level=2, seed=seed, frames=1500, tag="hardseed")
        check(r["frames"] == 1500 and r["score"] >= 38, "hardest level, seed %#x: 1500 frames alive, score %d" % (seed, r["score"]))
    r = headless([], frames=4000, tag="long")
    check(r["frames"] == 4000 and r["score"] >= 40, "long run: 4000 frames, score %d (pipes recycle many times)" % r["score"])
    per = LAST_CYCLES[0] // 4000
    print("game frame cost: %d T-states on average (budget: 2 frames = 40 ms)" % per)
    check(per < 90000, "average game frame stays under 90000 T-states (2 vsync periods at 2.5 MHz = 100000), is %d" % per)
    r = headless([], bot=0, frames=400, tag="idle")
    check(r["frames"] < 400 and r["score"] == 0 and r["new"] == 0 and r["y"] == C["BIRD_YMAX"],
          "no input: the bird falls and the game ends on the ground (frames %d, y %d)" % (r["frames"], r["y"]))
    if shots:
        screen_image(r["mem"]).resize((768, 576)).save(os.path.join(shots, "gameover.png"))
    r = headless([], bot=2, frames=1000, tag="giveup")
    check(r["frames"] < 1000 and r["score"] >= 1 and r["best"] == r["score"] and r["new"] == 1,
          "bot gives up after 150 frames: game over with a new record (score %d, best %d)" % (r["score"], r["best"]))
    if shots:
        screen_image(r["mem"]).resize((768, 576)).save(os.path.join(shots, "gameover_record.png"))
        for bird in range(len(G.BIRDS)):
            r = headless(["SHOT_MENU"], bird=bird, tag="menu%d" % bird)
            screen_image(r["mem"]).resize((768, 576)).save(os.path.join(shots, "menu%d.png" % bird))
        r = headless(["SHOT_READY"], tag="ready")
        screen_image(r["mem"]).resize((768, 576)).save(os.path.join(shots, "ready.png"))
    # colour build: palette programmed, pixels start at $E800 (colour picture origin + 8 lines), bird plays the same
    r = headless(["TARGET_COLOR"], frames=300, tag="colour")
    m = r["mem"]
    check(m[0xE001] == 0x81 and r["frames"] == 300 and r["score"] >= 1, "colour build runs (control byte %#x, score %d)" % (m[0xE001], r["score"]))
    check(m[0xE020] == 0xF4 and m[0xE030] == 0x00 and m[0xE021] == 0x77 and m[0xE031] == 0x03,
          "colour palette: sky/white, ground brown/yellow, stored inverted")
    check(all(m[0xE080 + 46 * 32 + i] == 0x11 for i in range(128)) and m[0xE080] == 0, "colour RAM: ground cells use palette group 1")
    # pipes keep white ink over the parallax band: cells under a pipe's 24 px footprint have nibble 0, all others
    # their layer's nibble (2 far, 3 near; two colour rows each, starting at colour row 42)
    pipes = [(s16(m[r["sym"]["v_pipes"] + 4 * i] | m[r["sym"]["v_pipes"] + 4 * i + 1] << 8)) for i in range(C["N_PIPES"])]
    bad = []
    for cr in range(4):
        layer = 2 + cr // 2
        for b in range(32):
            want = 0
            for half in (0, 1):
                s = b * 8 + half * 4
                hit = any(-32 <= px < 256 and s + 3 >= px and s <= px + 23 for px in pipes)
                want |= 0 if hit else layer << (4 if half == 0 else 0)
            got = m[0xE080 + (42 + cr) * 32 + b]
            if got != want:
                bad.append((cr, b, got, want))
    check(not bad, "colour RAM: pipes (x=%s) recolour the band cells under them (bad: %s)" % (pipes, bad[:3]))
    # colour menu: two-tone letters (upper 4 lines nibble 0, lower 4 lines nibble 5) on all 24 text rows
    r2 = headless(["SHOT_MENU", "TARGET_COLOR"], tag="menu_colour")
    m2 = r2["mem"]
    check(all(m2[0xE080 + (2 + 2 * t) * 32 + b] == 0x00 and m2[0xE080 + (3 + 2 * t) * 32 + b] == 0x55
              for t in range(24) for b in range(32)) and m2[0xE001] == 0x81,
          "colour menu: every text row has white upper / yellow lower letter halves")
    # colour model, colour switched off (C in the menu): control area wiped ($E001 = 0, no palette, no colour RAM),
    # the picture is the plain mono one at $E800
    r = headless(["TARGET_COLOR"], frames=300, tag="mono_on_colour", mono=1)
    m = r["mem"]
    check(not any(m[0xE000:0xE700]) and r["frames"] == 300 and r["score"] >= 1 and any(m[0xE800:0xF800]),
          "colour off: control area zero (control %#x), game runs on the $E800 picture (score %d)" % (m[0xE001], r["score"]))
    if shots:
        screen_image(m, 0xE800).resize((768, 576)).save(os.path.join(shots, "play_colour_pixels.png"))


def scripted(script, tag):
    """The real (non-headless) menu / ready / play flow with a scripted keyboard: one key mask per read_keys call."""
    out = "%s/%s.bin" % (BUILD, tag)
    sym = assemble("src/main.asm", out, ["SCRIPTED", "NOHW"])
    data = bytearray(open(out, "rb").read())
    a = sym["key_script"] - 0x4400
    assert len(script) < 120
    data[a:a + len(script)] = bytes(script)
    data[a + len(script)] = 0xFF
    open(out, "wb").write(data)
    mem = run_ticks(out, "done", "%s/%s.mem" % (BUILD, tag))
    w = lambda n: mem[sym[n]] | mem[sym[n] + 1] << 8
    return dict(level=mem[sym["v_level"]], speed=mem[sym["v_speed"]], bird=mem[sym["v_bird"]], y=mem[sym["v_y"] + 1], vy=w("v_vy"), anim=mem[sym["v_anim"]], score=w("v_score"), mem=mem)


def real_flow():
    F, L, R, U, D = 0x41, 2, 4, 0x11, 0x20
    # menu_screen reads once; menu loop: nothing, RIGHT, nothing, SPACE -> play: 1 read, ready loop: nothing x2, SPACE
    r = scripted([0, 0, R, 0, F, 0, 0, 0, F, 0, 0], "flow1")
    check(r["bird"] == 1, "menu: RIGHT selects the 2nd bird (v_bird %d)" % r["bird"])
    check(r["anim"] >= 1 and r["y"] != 88, "ready screen: SPACE starts the flight (bird row %d, wing counter %d)" % (r["y"], r["anim"]))
    r = scripted([0, 0, L, 0, F, 0, 0, 0, F, 0], "flow2")
    check(r["bird"] == 3, "menu: LEFT from the first bird wraps to the last (v_bird %d)" % r["bird"])
    # SPACE still held when the menu hands over: must not start by itself, needs release + press
    r = scripted([0, 0, F, F, F, F, F, F, F, 0], "flow3")
    check(r["y"] == 88 and r["anim"] >= 3, "held SPACE does not skip the ready screen (row %d)" % r["y"])
    # game over: fall without flapping, then SPACE must start a new game (bird back at the start row, ready screen)
    r = scripted([0, 0, F, 0, 0, F] + [0] * 70 + [F, 0, 0, 0], "flow5")
    check(r["y"] == 88, "game over: SPACE starts a new game (bird row %d, 160 would mean it stayed on the game-over screen)" % r["y"])
    r = scripted([0, 0, F, 0, 0, F] + [0] * 70 + [8, 0, 0, 0], "flow6")
    check(r["anim"] < 10, "game over: M returns to the menu (frame counter restarted: %d)" % r["anim"])
    r = scripted([0, 0, D, 0, D, 0, F, 0, 0, F, 0, 0], "flow7")
    check(r["level"] == 2 and r["speed"] == 4, "menu: DOWN twice selects the hardest level, speed 4 (level %d, speed %d)" % (r["level"], r["speed"]))
    r = scripted([0, 0, U, 0, F, 0, 0, F, 0, 0], "flow8")
    check(r["level"] == 2, "menu: UP from the easiest level wraps to the hardest (level %d)" % r["level"])
    r = scripted([0, 0, D, 0, F, 0, 0, F, 0, 0], "flow9")
    check(r["level"] == 1 and r["speed"] == 3, "menu: DOWN once gives the middle level, speed 3 (level %d, speed %d)" % (r["level"], r["speed"]))
    r = scripted([0, 0, 0x11, 0, 0, 0, 0, 0], "flow10")
    check(r["level"] == 2 and r["anim"] < 10, "menu: UP alone must not start the game (still in the menu, level %d)" % r["level"])
    r = scripted([0, 0, F, 0, 0, 0, 0, 0], "flow4")
    check(r["y"] == 88, "without SPACE the bird keeps hovering on the ready screen (row %d)" % r["y"])


def main():
    shots = None
    if "--shots" in sys.argv:
        shots = sys.argv[sys.argv.index("--shots") + 1]
        os.makedirs(shots, exist_ok=True)
    n = unit_tests()
    print("unit tests done (%d draw_pipe cases)" % n)
    real_flow()
    gameplay(shots)
    if FAILS:
        print("\n%d FAILED" % len(FAILS))
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()

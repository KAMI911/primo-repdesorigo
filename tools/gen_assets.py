#!/usr/bin/env python3
"""Generate src/data.inc (font, bird sprites, pipe shift tables, ground, strings).

Pure stdlib. `make` re-runs this when it changes; the output is committed so that
the build also works without Python's Pillow.  `--preview out.png` needs Pillow.
"""
import math
import sys

# ---------------------------------------------------------------- font -------
# Cell = 8x8 pixels, glyph = 5x7 in rows 1..7, accent in row 0, glyph in bits 6..2.
GLYPHS = {
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110",
    "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111",
    "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110",
    "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 10001 11001 10101 10011 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110",
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010",
    "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100",
    "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110",
    "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111",
    "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010",
    "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110",
    "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110",
    "9": "01110 10001 10001 01111 00001 00010 01100",
    " ": "00000 00000 00000 00000 00000 00000 00000",
    ".": "00000 00000 00000 00000 00000 01100 01100",
    ":": "00000 01100 01100 00000 01100 01100 00000",
    "!": "00100 00100 00100 00100 00100 00000 00100",
    "-": "00000 00000 00000 11111 00000 00000 00000",
    "<": "00010 00100 01000 10000 01000 00100 00010",
    ">": "01000 00100 00010 00001 00010 00100 01000",
    "^": "00100 01110 10101 00100 00100 00100 00100",
}
ACUTE, DACUTE, UMLAUT = "00010", "00101", "01010"
ACCENTED = {  # char -> (base glyph, accent row)
    "Á": ("A", ACUTE), "É": ("E", ACUTE), "Í": ("I", ACUTE), "Ó": ("O", ACUTE), "Ú": ("U", ACUTE),
    "Ö": ("O", UMLAUT), "Ü": ("U", UMLAUT), "Ő": ("O", DACUTE), "Ű": ("U", DACUTE),
}
# Code order: index in this string = byte used in the strings and the font table.
CHARSET = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.:!-<>^ÁÉÍÓÚÖÜŐŰ"


def glyph_bytes(ch):
    if ch in ACCENTED:
        base, acc = ACCENTED[ch]
        rows = GLYPHS[base].split()
        return [int(acc, 2) << 2] + [int(r, 2) << 2 for r in rows]
    rows = GLYPHS[ch].split()
    return [0] + [int(r, 2) << 2 for r in rows]


# ---------------------------------------------------------------- birds ------
W = H = 16


def ell(cx, cy, rx, ry):
    return {(x, y) for y in range(H) for x in range(W)
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0}


def rect(x0, y0, x1, y1):
    return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)}


def pts(*p):
    return set(p)


def outline(mask):
    """Border of a filled silhouette (pixels with a 4-neighbour outside)."""
    return {(x, y) for (x, y) in mask
            if any((x + dx, y + dy) not in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}


def wing(frame, cx):
    """Wing shapes: frame 0 = up (sticks out above the back), 1 = down (hangs below the belly)."""
    return ell(cx, 6.5, 2.3, 3.2) if frame == 0 else ell(cx, 12.5, 2.6, 2.6)


def bird_rigo(frame):  # thrush: round, speckled breast, short beak
    m = ell(8, 9.5, 5.5, 4) | ell(11.5, 6, 3, 3) | pts((14, 6), (15, 6), (14, 7)) | rect(0, 8, 3, 9) | wing(frame, 6)
    d = pts((12, 5)) | {(x, y) for (x, y) in ((8, 11), (10, 12), (9, 13), (11, 10), (7, 12), (12, 9)) if (x, y) in m}
    return m, d


def bird_lud(frame):  # goose: long neck, big body, broad beak
    m = ell(6.5, 10.5, 6.2, 4) | rect(10, 4, 12, 10) | ell(12, 3.5, 2.5, 2.2) | rect(14, 3, 15, 4) | rect(0, 8, 1, 10) | wing(frame, 6)
    d = pts((12, 3)) | {(x, y) for (x, y) in ((4, 12), (6, 13), (8, 12), (10, 12), (11, 7), (11, 9)) if (x, y) in m}
    return m, d


def bird_kacsa(frame):  # duck: flat bill, tail tuft up, neck ring
    m = ell(7, 10.5, 6.2, 3.8) | ell(11, 5.5, 3, 3) | rect(13, 6, 15, 7) | pts((0, 7), (1, 7), (1, 8), (0, 6), (2, 8)) | wing(frame, 6)
    d = pts((11, 4)) | {(x, y) for (x, y) in ((10, 8), (11, 8), (12, 8), (8, 12), (10, 12), (6, 13)) if (x, y) in m}
    return m, d


def bird_kakukk(frame):  # cuckoo: slim, long barred tail, curved bill
    m = ell(9, 9, 4.8, 3) | ell(12.5, 6, 2.6, 2.6) | pts((15, 6), (15, 7), (14, 7)) | rect(0, 10, 5, 11) | wing(frame, 8)
    d = pts((12, 5)) | {(x, y) for (x, y) in ((1, 10), (3, 11), (5, 10), (9, 11), (11, 10), (7, 12), (10, 12)) if (x, y) in m}
    return m, d


BIRDS = [bird_rigo, bird_lud, bird_kacsa, bird_kakukk]
BIRD_NAMES = ["REPDESŐ RIGÓ", "LEBEGŐ LÚD", "KACSÁZÓ KACSA", "KAPKODÓ KAKUKK"]


def sprite_rows(bird, frame):
    """16 rows x [img0, keep0, img1, keep1]; keep = ~silhouette."""
    mask, details = BIRDS[bird](frame)
    img = outline(mask) | details | {(x, y) for (x, y) in mask if (x + y) % 2 == 0 and y >= 9}
    out = []
    for y in range(H):
        row = []
        for half in (0, 1):
            i = k = 0
            for b in range(8):
                x = half * 8 + b
                if (x, y) in img:
                    i |= 0x80 >> b
                if (x, y) not in mask:
                    k |= 0x80 >> b
            row += [i, k]
        out.append(row)
    return out


# ---------------------------------------------------------------- pipes ------
# 24 px cap, 20 px body (offset 2); tables for the 8 pixel shifts, 5 bytes each.
def px_row(spec):
    return [c == "1" for c in spec]


CAP_EDGE = px_row("1" * 24)
CAP_FILL = px_row("1" + "0" + "1" * 3 + "0" * 2 + "1" * 14 + "0" + "1" + "1")
BODY = px_row("00" + "1" + "0" + "1" * 3 + "0" * 2 + "1" * 8 + "0" + "11" + "0" + "1" + "00")
assert len(CAP_EDGE) == len(CAP_FILL) == len(BODY) == 24


def shifted(bits, s):
    full = [False] * s + list(bits)
    full += [False] * (40 - len(full))
    return [sum((1 << (7 - j)) for j in range(8) if full[b * 8 + j]) for b in range(5)]


def pipe_table():
    t = []
    for s in range(8):
        for pat in (BODY, CAP_EDGE, CAP_FILL):
            t += shifted(pat, s)
        t.append(0)  # pad: stride 16 per shift
    return t


GROUND = [0xFF, 0x00, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55]

# ---------------------------------------------------------------- strings ----
STRINGS = {
    "s_title": "REPDESŐ RIGÓ",
    "s_choose": "VÁLASSZ MADARAT!",
    "s_keys": "BALRA-JOBBRA: MADÁR",
    "s_keys2": "FEL-LE: NEHÉZSÉG",
    "s_lvl0": "TOJÁSHÉJAS - KÖNNYŰ",
    "s_lvl1": "SZÁRNYPRÓBA - KÖZEPES",
    "s_lvl2": "LEVEGŐ URA - NEHÉZ",
    "s_start": "SPACE: INDÍTÁS",
    "s_best": "REKORD:",
    "s_ready1": "KÉSZÜLJ!",
    "s_ready2": "SPACE: REPÜLÉS",
    "s_over": "VÉGE A JÁTÉKNAK",
    "s_again": "SPACE: ÚJRA",
    "s_menu": "ESC: MENÜ",
    "s_score": "PONT:",
    "s_new": "ÚJ REKORD!",
}


def enc(text):
    return [CHARSET.index(c) for c in text]


# ---------------------------------------------------------------- output -----
def db(vals, per=16):
    lines = []
    for i in range(0, len(vals), per):
        lines.append("        defb    " + ",".join("$%02X" % v for v in vals[i:i + per]))
    return "\n".join(lines)


def build():
    o = ["; GENERATED by tools/gen_assets.py -- do not edit.", ""]
    for name, ch in (("CH_SPACE", " "), ("CH_DIGIT0", "0"), ("CH_COLON", ":"), ("CH_LT", "<"), ("CH_GT", ">"), ("CH_CARET", "^"), ("CH_V", "V")):
        o.append("defc %-10s = %d" % (name, CHARSET.index(ch)))
    o += ["defc N_CHARS    = %d" % len(CHARSET), "defc N_BIRDS    = %d" % len(BIRDS), "", "font:"]
    for ch in CHARSET:
        o.append(db(glyph_bytes(ch), 8) + "  ; '%s'" % ch)
    o += ["", "; bird sprites: bird*2+frame, 16 rows x [img0,keep0,img1,keep1] = 64 bytes each", "bird_spr:"]
    for b in range(len(BIRDS)):
        for f in (0, 1):
            flat = [v for r in sprite_rows(b, f) for v in r]
            o.append("        ; bird %d frame %d" % (b, f))
            o.append(db(flat, 16))
    o += ["", "; pipe patterns: shift*16 + {0 body, 5 cap edge, 10 cap fill}, 5 bytes each", "pipe_tab:", db(pipe_table(), 16)]
    o += ["pat_zero:", "        defs    5,0", "", "ground_tab:", db(GROUND, 16), ""]
    o += ["; bird names, one per bird, 0xFF-terminated", "bird_names:"]
    for i, n in enumerate(BIRD_NAMES):
        o.append("bn_%d:" % i)
        o.append(db(enc(n) + [0xFF], 16))
    o += ["bird_name_tab:"] + ["        defw    bn_%d" % i for i in range(len(BIRDS))] + [""]
    o += ["level_name_tab:"] + ["        defw    s_lvl%d" % i for i in range(3)] + [""]
    for label, text in STRINGS.items():
        o.append(label + ":")
        o.append(db(enc(text) + [0xFF], 16))
    return "\n".join(o) + "\n"


def preview(path):
    """Debug image: bird frames (ink white, silhouette grey), a text sample, a pipe."""
    from PIL import Image
    sc = 8
    img = Image.new("L", (8 * 17 * sc, 12 * sc * 4), 60)
    px = img.load()

    def dot(x, y, v):
        for j in range(sc):
            for i in range(sc):
                if x * sc + i < img.width and y * sc + j < img.height:
                    px[x * sc + i, y * sc + j] = v

    for b in range(len(BIRDS)):
        for f in (0, 1):
            ox = (b * 2 + f) * 17
            for y, r in enumerate(sprite_rows(b, f)):
                for x in range(16):
                    bit = 0x80 >> (x % 8)
                    byte = x // 8
                    ink, keep = r[byte * 2] & bit, r[byte * 2 + 1] & bit
                    dot(ox + x, y, 255 if ink else (90 if not keep else 20))
    for i, ch in enumerate("REPDESŐ RIGÓ 0123456789 LÚD ÁÉÍÓÚÖÜŐŰ"):
        for y, row in enumerate(glyph_bytes(ch)):
            for x in range(8):
                if row & (0x80 >> x):
                    dot(i * 8 + x, 18 + y, 255)
    tab = pipe_table()
    for k, (name, off) in enumerate((("edge", 5), ("fill", 10), ("body", 0))):
        for s in (0, 5):
            for x in range(40):
                if tab[s * 16 + off + x // 8] & (0x80 >> (x % 8)):
                    dot(x + s * 12, 28 + k * 2, 255)
                    dot(x + s * 12, 29 + k * 2, 255)
    img.save(path)


def main(argv):
    if len(argv) >= 3 and argv[1] == "--preview":
        preview(argv[2])
        return 0
    out = argv[1] if len(argv) > 1 else "src/data.inc"
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(build())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

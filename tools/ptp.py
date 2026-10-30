#!/usr/bin/env python3
"""Primo .ptp tool: build, verify and convert to WAV. Pure stdlib, no deps.

Format (verified against the z88dk appmake writer, PTP2WAV.PAS and real dt80asm output):
  file   : FF <total file length u16 LE, incl. these 3 bytes> <block>...
  block  : <55|AA> <size u16 LE> <size bytes> [<crc>, only for the autostart block]
           55 = normal block, AA = last block
  name   : 83 00 <n> <name n bytes> <crc=(n+sum(name))&255>          (size = n+4)
  data   : F9 <bn BCD> <addr u16> <nb (0=256)> <data> <crc>          (size = nb+6)
           crc = (bn + addr_lo + addr_hi + nb + sum(data)) & 255
  start  : AA 04 00  B9 <bn BCD> <addr u16>  <crc=(bn+lo+hi)&255>   (machine-code autostart)
"""
import argparse, struct, sys, wave

MAX_NAME = 16
MAX_DATA_BLOCK = 256


def bcd(n):
    n %= 100
    return (n // 10) << 4 | n % 10


def build(code, org=0x4400, start=None, name="prg"):
    if not 0 < len(code) <= 0x10000 - org:
        raise ValueError("code size %d does not fit at $%04X" % (len(code), org))
    nm = name.encode("latin-1")[:MAX_NAME]
    start = org if start is None else start
    blocks = bytearray()
    body = bytes([0x83, 0x00, len(nm)]) + nm
    blocks += b"\x55" + struct.pack("<H", len(body) + 1) + body + bytes([(len(nm) + sum(nm)) & 255])
    bn = 1
    for off in range(0, len(code), MAX_DATA_BLOCK):
        chunk = code[off:off + MAX_DATA_BLOCK]
        addr = org + off
        nb = len(chunk) & 255  # 256 -> 0
        crc = (bcd(bn) + (addr & 255) + (addr >> 8) + nb + sum(chunk)) & 255
        blk = bytes([0xF9, bcd(bn)]) + struct.pack("<H", addr) + bytes([nb]) + chunk + bytes([crc])
        blocks += b"\x55" + struct.pack("<H", len(blk)) + blk
        bn += 1
    lo, hi = start & 255, start >> 8
    blocks += b"\xAA\x04\x00" + bytes([0xB9, bcd(bn), lo, hi, (bcd(bn) + lo + hi) & 255])
    return b"\xFF" + struct.pack("<H", len(blocks) + 3) + bytes(blocks)


def parse(d):
    """Return (name, [(type, bn, addr, data)], start, problems)."""
    prob, name, segs, start = [], None, [], None
    if len(d) < 3 or d[0] != 0xFF:
        return None, [], None, ["missing FF file header"]
    if struct.unpack_from("<H", d, 1)[0] != len(d):
        prob.append("header length %d != file length %d" % (struct.unpack_from("<H", d, 1)[0], len(d)))
    p, last = 3, False
    while p < len(d) and not last:
        if d[p] not in (0x55, 0xAA) or p + 3 > len(d):
            prob.append("bad block id at %d" % p); break
        last = d[p] == 0xAA
        size = struct.unpack_from("<H", d, p + 1)[0]
        blk = d[p + 3:p + 3 + size]
        if len(blk) != size:
            prob.append("truncated block at %d" % p); break
        p += 3 + size
        t = blk[0]
        if t == 0x83:
            n = blk[2]; name = blk[3:3 + n].decode("latin-1")
            if (n + sum(blk[3:3 + n])) & 255 != blk[-1]: prob.append("name crc")
        elif t in (0xF9, 0xF1):
            addr, nb = struct.unpack_from("<HB", blk, 2); ln = nb or 256
            data = blk[5:5 + ln]
            if len(blk) != ln + 6: prob.append("block %02X size mismatch" % blk[1])
            elif (blk[1] + (addr & 255) + (addr >> 8) + nb + sum(data)) & 255 != blk[-1]:
                prob.append("block %02X crc (addr $%04X)" % (blk[1], addr))
            segs.append((t, blk[1], addr, data))
        elif t == 0xB9:
            start = blk[2] | blk[3] << 8
            if d[p:p + 1] and (blk[1] + blk[2] + blk[3]) & 255 != d[p]: prob.append("autostart crc")
            p += 1  # trailing crc byte lies outside the declared size
        elif t == 0xB1:
            pass
        else:
            prob.append("unknown block type %02X" % t)
    if not last: prob.append("no AA closing block")
    if p != len(d): prob.append("%d stray bytes after last block" % (len(d) - p))
    return name, segs, start, prob


def to_wav(ptp, path):
    """Same signal as PTP2WAV.PAS: 8 kHz 8-bit mono, 0-bit 16 samples, 1-bit 6 samples."""
    name, segs, start, prob = parse(ptp)
    if prob and any("crc" not in x for x in prob): raise ValueError("; ".join(prob))
    P, N = 0xF8, 0x08
    b1, b0 = bytes([P] * 3 + [N] * 3), bytes([P] * 8 + [N] * 8)
    def byte(v): return b"".join(b1 if v >> (7 - i) & 1 else b0 for i in range(8))
    out = bytearray(b"\x80" * 2000) + b"".join(byte(0xAA) for _ in range(512))
    p = 3
    while True:
        out += b"".join(byte(0xFF) for _ in range(96)) + byte(0xD3) * 3
        last = ptp[p] == 0xAA; size = struct.unpack_from("<H", ptp, p + 1)[0]
        out += b"".join(byte(v) for v in ptp[p + 3:p + 3 + size]); p += 3 + size
        if last: break
    out += b"\x80" * 2000
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(1); w.setframerate(8000); w.writeframes(bytes(out))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build"); b.add_argument("bin"); b.add_argument("ptp")
    b.add_argument("--name", required=True); b.add_argument("--org", type=lambda x: int(x, 0), default=0x4400)
    b.add_argument("--start", type=lambda x: int(x, 0))
    v = sub.add_parser("verify"); v.add_argument("ptp"); v.add_argument("--max-end", type=lambda x: int(x, 0))
    v.add_argument("--z88dk", action="store_true", help="tolerate z88dk's known bad CRC on its free-memory block ($40F9)")
    w = sub.add_parser("wav"); w.add_argument("ptp"); w.add_argument("wav")
    a = ap.parse_args(argv)
    if a.cmd == "build":
        open(a.ptp, "wb").write(build(open(a.bin, "rb").read(), a.org, a.start, a.name))
    elif a.cmd == "verify":
        name, segs, start, prob = parse(open(a.ptp, "rb").read())
        if a.z88dk: prob = [x for x in prob if "(addr $40F9)" not in x]
        end = max(((0x43EA if s[0] == 0xF1 else 0) + s[2] + len(s[3]) for s in segs if s[2] != 0x40F9), default=0)  # F1 = BASIC-area offsets (z88dk)
        print("name=%r blocks=%d start=%s end=$%04X" % (name, len(segs), None if start is None else "$%04X" % start, end))
        if a.max_end is not None and end > a.max_end: prob.append("image ends at $%04X > limit $%04X" % (end, a.max_end))
        for x in prob: print("PROBLEM:", x, file=sys.stderr)
        return 1 if prob else 0
    else:
        to_wav(open(a.ptp, "rb").read(), a.wav)
    return 0


if __name__ == "__main__":
    sys.exit(main())

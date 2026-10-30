import os, sys, unittest
here = os.path.dirname(os.path.abspath(__file__))
for rel in (".", "../tools"):  # skill scripts/ dir, or a project's tests/ -> tools/
    sys.path.insert(0, os.path.join(here, rel))
import ptp


class PtpTests(unittest.TestCase):
    def test_roundtrip(self):
        code = bytes(range(256)) * 3 + b"xyz"
        name, segs, start, prob = ptp.parse(ptp.build(code, name="demo"))
        self.assertEqual((name, start, prob), ("demo", 0x4400, []))
        self.assertEqual(b"".join(s[3] for s in segs), code)
        self.assertEqual(segs[1][2], 0x4500)

    def test_exact_256_block_uses_nb_zero(self):
        d = ptp.build(b"\x01" * 256, name="x")
        self.assertEqual(ptp.parse(d)[3], [])

    def test_corruption_is_detected(self):
        d = bytearray(ptp.build(b"\x01" * 10, name="x"))
        d[30] ^= 0xFF
        self.assertTrue(ptp.parse(bytes(d))[3])

    def test_truncation_is_detected(self):
        d = ptp.build(b"\x01" * 600, name="x")
        self.assertTrue(ptp.parse(d[:-9])[3])

    def test_rejects_oversize_and_empty(self):
        with self.assertRaises(ValueError): ptp.build(b"", name="x")
        with self.assertRaises(ValueError): ptp.build(b"\0" * 0xC000, org=0x4400, name="x")

    def test_name_is_truncated_to_16(self):
        self.assertEqual(ptp.parse(ptp.build(b"\0", name="a" * 40))[0], "a" * 16)

    def test_wav_header(self):
        import tempfile, wave
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "o.wav"); ptp.to_wav(ptp.build(b"\1" * 8, name="x"), p)
            with wave.open(p) as w: self.assertEqual((w.getframerate(), w.getnchannels(), w.getsampwidth()), (8000, 1, 1))


if __name__ == "__main__":
    unittest.main()

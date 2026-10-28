import tempfile
import unittest
from pathlib import Path

from tools.lift import Lifter, RawLifter
from test_inspect_pe import minimal_pe


class LifterTests(unittest.TestCase):
    def test_lock_prefixed_decrement_is_lifted(self):
        lifter=RawLifter(bytes.fromhex('f0ff08c3'))
        code,calls=lifter.lift(0x401000)
        self.assertIn('MR32',code)
        self.assertIn('FLAGS',code)

    def test_lifts_pacode_without_claiming_the_gap_is_executable(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'image.exe'
            p.write_bytes(minimal_pe())
            lifter = Lifter(p)
            self.assertTrue(lifter.in_text(0x402000))
            self.assertFalse(lifter.in_text(0x401800))
            code, calls = lifter.lift(0x402000)
        self.assertIn('sub_00402000', code)
        self.assertIn('POP32', code)
        self.assertEqual(calls, set())


if __name__ == '__main__':
    unittest.main()

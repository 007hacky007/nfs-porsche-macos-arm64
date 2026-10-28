import struct
import tempfile
import unittest
from pathlib import Path

from tools.inspect_pe import inspect_pe, require_supported, UnsupportedImage


def minimal_pe():
    data = bytearray(0x600)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3c, 0x80)
    data[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<HHIIIHH', data, 0x84, 0x14c, 2, 0, 0, 0, 224, 0x102)
    opt = 0x98
    struct.pack_into('<H', data, opt, 0x10b)
    for offset, value in [(16,0x1000),(20,0x1000),(28,0x400000),(32,4096),(36,512),(56,0x3000),(60,512),(92,16)]:
        struct.pack_into('<I', data, opt + offset, value)
    for index, name in enumerate((b'.text', b'PACODE')):
        pos = opt + 224 + index * 40
        data[pos:pos+len(name)] = name
        struct.pack_into('<IIII', data, pos+8, 16, 0x1000+index*4096, 512, 512+index*512)
        struct.pack_into('<I', data, pos+36, 0x60000020)
        data[512+index*512] = 0xc3
    return bytes(data)


class InspectTests(unittest.TestCase):
    def test_reports_all_executable_sections_and_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'game.exe'
            p.write_bytes(minimal_pe())
            info = inspect_pe(p)
        self.assertEqual(info['machine'], 0x14c)
        self.assertEqual(info['entry'], 0x401000)
        self.assertEqual([s['name'] for s in info['sections'] if s['executable']], ['.text','PACODE'])
        self.assertEqual(len(info['sha256']), 64)

    def test_unknown_image_is_not_accepted_as_supported(self):
        with self.assertRaises(UnsupportedImage):
            require_supported({'sha256':'0' * 64, 'machine':0x14c, 'protection':[]})

    def test_protected_image_is_rejected_even_if_hash_is_listed(self):
        from tools.inspect_pe import SUPPORTED
        with self.assertRaisesRegex(UnsupportedImage, 'protected'):
            require_supported({'sha256':next(iter(SUPPORTED), '0' * 64),
                               'machine':0x14c, 'protection':['SafeDisc']})


if __name__ == '__main__':
    unittest.main()

import struct
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import patch

from tools import package


def resource(identifier, entries=None, data=None):
    if entries is not None:
        return NS(id=identifier, directory=NS(entries=entries))
    return NS(id=identifier, data=NS(struct=NS(OffsetToData=data[0], Size=len(data[1]))))


def icon_pe():
    # Synthetic blue 32x32 icon, including an opaque Windows AND mask.
    bitmap = struct.pack('<IiiHHIIIIII', 40, 32, 64, 1, 32, 0, 4096, 0, 0, 0, 0)
    bitmap += bytes((255, 0, 0, 255)) * 1024 + bytes(128)
    group = struct.pack('<HHHBBBBHHIH', 0, 1, 1, 32, 32, 0, 0, 1, 32, len(bitmap), 7)
    entries = [resource(16, []),
               resource(3, [resource(7, [resource(1033, data=(200, bitmap))])]),
               resource(14, [resource(101, [resource(1033, data=(100, group))])])]
    blobs = {100: group, 200: bitmap}
    return NS(DIRECTORY_ENTRY_RESOURCE=NS(entries=entries), close=lambda: None,
              get_data=lambda offset, size: blobs[offset][:size]), bitmap


class AppIconTests(unittest.TestCase):
    def test_reconstructs_windows_icon_from_group_and_image_resources(self):
        pe, bitmap = icon_pe()
        with patch('tools.package.pefile.PE', return_value=pe):
            ico = package.windows_icon(Path('supplied/Porsche.exe'))
        self.assertEqual(struct.unpack_from('<HHH', ico), (0, 1, 1))
        self.assertEqual(struct.unpack_from('<BBBBHHII', ico, 6),
                         (32, 32, 0, 0, 1, 32, len(bitmap), 22))
        self.assertEqual(ico[22:], bitmap)

    def test_reports_missing_original_icon(self):
        with patch('tools.package.pefile.PE', return_value=NS(close=lambda: None)):
            with self.assertRaisesRegex(ValueError, 'icon'):
                package.windows_icon(Path('supplied/Porsche.exe'))

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS icon conversion')
    def test_converts_extracted_icon_to_icns_without_leaving_intermediates(self):
        pe, _ = icon_pe()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch('tools.package.pefile.PE', return_value=pe):
                icon = package.windows_icon(Path('supplied/Porsche.exe'))
            package.write_app_icon(icon, root / 'NFSV.icns')
            icon = (root / 'NFSV.icns').read_bytes()
            self.assertEqual(icon[:4], b'icns')
            self.assertEqual(struct.unpack_from('>I', icon, 4)[0], len(icon))
            self.assertEqual(list(root.iterdir()), [root / 'NFSV.icns'])

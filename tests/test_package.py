import tempfile
import unittest
from pathlib import Path

from tools import package


class PackageTests(unittest.TestCase):
    def test_bundles_only_prepared_game_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'prepared'
            for name in ('GameData/car.bin', 'FEData/movie.bin', 'Porsche.exe', 'fe.txt', 'install.txt',
                         'version.txt', 'patch-manifest.json', 'build-input.json', 'PatchNotices/readme.txt'):
                p = source / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(b'fixture')
            (source / 'private.log').write_bytes(b'private')
            (source / 'PatchSources').mkdir()
            (source / 'PatchSources/archive.zip').write_bytes(b'not part of the app')
            target = root / 'bundle/Game'
            package.copy_game_files(source, target)
            self.assertTrue((target / 'GameData/car.bin').is_file())
            self.assertTrue((target / 'Porsche.exe').is_file())
            self.assertFalse((target / 'private.log').exists())
            self.assertFalse((target / 'PatchSources').exists())

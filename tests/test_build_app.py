import subprocess
import tempfile
import unittest
from pathlib import Path

from tools import build_app
from test_disc import image

ROOT = Path(__file__).resolve().parents[1]


class BuildAppTests(unittest.TestCase):
    def test_single_entry_help_works_from_another_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = subprocess.run([str(ROOT / 'build.sh'), '--help'], cwd=tmp,
                                 text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('.iso', run.stdout)
        self.assertIn('.cue', run.stdout)

    def test_folder_is_not_extracted_or_changed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'my game'
            folder.mkdir()
            (folder / 'keep').write_bytes(b'original')
            with build_app.source_directory(folder, root) as source:
                self.assertEqual(source, folder)
            self.assertEqual((folder / 'keep').read_bytes(), b'original')

    def test_iso_bin_and_cue_have_equivalent_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'disc.iso').write_bytes(image(raw=False))
            (root / 'disc.bin').write_bytes(image())
            (root / 'disc.cue').write_text('FILE "disc.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n')
            for extension in ('iso', 'bin', 'cue'):
                with self.subTest(extension=extension):
                    with build_app.source_directory(root / f'disc.{extension}', root) as source:
                        self.assertEqual((source / 'Simulation/cop356_german.crp').read_bytes(), b'asset')
                        extracted = source
                    self.assertFalse(extracted.exists())
            self.assertEqual((root / 'disc.bin').read_bytes(), image())

    def test_rejects_bad_game_before_fetching_patches(self):
        from unittest.mock import patch
        from test_game_source import GameSourceTests
        fixture = GameSourceTests(methodName='test_refuses_existing_destination')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        with patch('tools.downloads.fetch_patches') as download:
            with self.assertRaisesRegex(ValueError, 'checksum'):
                build_app.prepared_game(fixture.game, fixture.root / 'cache', fixture.root / 'project')
            download.assert_not_called()

    def test_unsupported_file_type_has_actionable_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'copy.zip'
            source.write_bytes(b'unsupported')
            with self.assertRaisesRegex(ValueError, 'folder.*iso.*bin.*cue'):
                with build_app.source_directory(source, root):
                    self.fail('unsupported file accepted')

import contextlib
import io
import json
import subprocess
import sys
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

    def test_progress_mode_emits_events_and_error(self):
        run = subprocess.run([sys.executable, str(ROOT / 'tools/build_app.py'), '--progress', '/nonexistent/game'],
                             text=True, capture_output=True)
        self.assertEqual(run.returncode, 1)
        events = [json.loads(l[len('NFSV-EVENT '):]) for l in run.stdout.splitlines() if l.startswith('NFSV-EVENT ')]
        self.assertEqual(events[-1], {'error': 'game copy does not exist'})

    def test_progress_mode_shows_plain_message_for_failed_step(self):
        from unittest.mock import patch
        def failing():
            build_app.PROGRESS = True
            subprocess.run([sys.executable, '-c', 'import sys; sys.exit(3)'], check=True)
        self.addCleanup(setattr, build_app, 'PROGRESS', build_app.PROGRESS)
        out, err = io.StringIO(), io.StringIO()
        with patch.object(build_app, 'main', failing), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(build_app.cli(), 1)
        events = [json.loads(l[len('NFSV-EVENT '):]) for l in out.getvalue().splitlines() if l.startswith('NFSV-EVENT ')]
        self.assertEqual(events, [{'error': 'This step stopped with an error. Click Copy log and include it in a bug report.'}])
        self.assertIn('sys.exit(3)', err.getvalue())
        self.assertIn('exit status 3', err.getvalue())

    def test_step_emits_event_only_in_progress_mode(self):
        for progress in (False, True):
            self.addCleanup(setattr, build_app, 'PROGRESS', build_app.PROGRESS)
            build_app.PROGRESS = progress
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                build_app.step('Hello', 'verify')
            self.assertEqual('NFSV-EVENT {"step": "verify", "title": "Hello"}' in out.getvalue(), progress)
            self.assertIn('\nHello\n', out.getvalue())

    def test_setup_only_needs_no_game(self):
        run = subprocess.run([sys.executable, str(ROOT / 'tools/build_app.py'), '--setup-only', '--help'],
                             text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('--setup-only', run.stdout)

    def test_unsupported_file_type_has_actionable_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'copy.zip'
            source.write_bytes(b'unsupported')
            with self.assertRaisesRegex(ValueError, 'folder.*iso.*bin.*cue'):
                with build_app.source_directory(source, root):
                    self.fail('unsupported file accepted')

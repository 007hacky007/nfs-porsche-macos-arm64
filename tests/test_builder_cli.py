import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import builder_cli
from tools.game_source import GameSource, file_sha256


def run(*argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = builder_cli.main(list(argv))
    events = [json.loads(l[len('NFSV-EVENT '):]) for l in out.getvalue().splitlines() if l.startswith('NFSV-EVENT ')]
    return code, events


def snapshot(folder):
    return sorted((str(p), p.read_bytes()) for p in folder.rglob('*') if p.is_file())


class BuilderCliTests(unittest.TestCase):
    def test_check_game_rejects_bad_copy_without_fetching(self):
        from test_game_source import GameSourceTests
        fixture = GameSourceTests(methodName='test_refuses_existing_destination')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        before = snapshot(fixture.game)
        with patch('tools.downloads.fetch_patches') as download:
            code, events = run('check-game', str(fixture.game))
            download.assert_not_called()
        self.assertEqual(code, 1)
        self.assertIn('checksum', events[-1]['error'])
        self.assertEqual(before, snapshot(fixture.game))

    def test_check_game_reports_missing_path(self):
        self.assertEqual(run('check-game', '/nonexistent/game'), (1, [{'error': 'game copy does not exist'}]))

    def test_check_game_accepts_supported_copy(self):
        with tempfile.TemporaryDirectory() as tmp, \
                patch('tools.game_source.verify_game', return_value=GameSource({}, 'USA v3.4', 'a', 'b')):
            self.assertEqual(run('check-game', tmp), (0, [{'game': 'ok', 'version': 'USA v3.4'}]))

    def test_patches_status_reports_missing_then_ready(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'NFSV_CACHE_DIR': tmp}):
            self.assertEqual(run('patches', 'status'), (0, [{'patches': 'missing'}]))
            cache = Path(tmp) / 'patches'
            cache.mkdir()
            combined, silent = cache / 'NFS5-Combined-Patch-v1.1.zip', cache / 'SilentPatchNFS90s.zip'
            combined.write_bytes(b'combined')
            silent.write_bytes(b'silent')
            self.assertEqual(run('patches', 'status'), (0, [{'patches': 'missing'}]))
            with patch('tools.downloads.COMBINED_SHA', file_sha256(combined)), \
                    patch('tools.downloads.SILENT_SHA', file_sha256(silent)):
                self.assertEqual(run('patches', 'status'), (0, [{'patches': 'ready'}]))

    def test_patches_fetch_reports_ready_and_error(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'NFSV_CACHE_DIR': tmp}):
            with patch('tools.downloads.fetch_patches') as fetch:
                self.assertEqual(run('patches', 'fetch'), (0, [{'patches': 'ready'}]))
                self.assertEqual(fetch.call_args.args[0], Path(tmp) / 'patches')
            with patch('tools.downloads.fetch_patches', side_effect=ValueError('offline')):
                self.assertEqual(run('patches', 'fetch'), (1, [{'error': 'offline'}]))


if __name__ == '__main__':
    unittest.main()

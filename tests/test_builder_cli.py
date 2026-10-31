import contextlib
import io
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import builder_cli, game_source
from tools.game_source import GameSource, file_sha256

ROOT = Path(__file__).resolve().parents[1]
SLOW_CHECK = '''
import contextlib, sys, time
sys.path.insert(0, sys.argv[1])
from tools import builder_cli
@contextlib.contextmanager
def slow(source, parent):
    print('inside', parent, flush=True)
    time.sleep(30)
    yield source
builder_cli.source_directory = slow
sys.exit(builder_cli.main(['check-game', sys.argv[2]]))
'''


def run(*argv, err=None):
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err or io.StringIO()):
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
        err = io.StringIO()
        with patch('tools.downloads.fetch_patches') as download:
            code, events = run('check-game', str(fixture.game), err=err)
            download.assert_not_called()
        self.assertEqual(code, 1)
        self.assertIn('does not match a supported release', events[-1]['error'])
        detected = game_source.assets_digest(game_source.game_files(fixture.game))
        self.assertNotIn(detected, events[-1]['error'])
        self.assertIn(detected, err.getvalue())
        self.assertEqual(before, snapshot(fixture.game))

    def test_cancel_removes_temporary_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            game = Path(tmp) / 'game'
            game.mkdir()
            child = subprocess.Popen([sys.executable, '-c', SLOW_CHECK, str(ROOT), str(game)], text=True,
                                     stdout=subprocess.PIPE, env={**os.environ, 'TMPDIR': tmp})
            self.addCleanup(child.kill)
            self.assertIn('nfsv-check-', child.stdout.readline())
            child.send_signal(signal.SIGTERM)
            self.assertEqual(child.wait(timeout=10), 143)
            child.stdout.close()
            self.assertEqual(sorted(p.name for p in Path(tmp).iterdir()), ['game'])

    def test_supported_lists_the_readme_release_tables(self):
        code, events = run('supported')
        self.assertEqual(code, 0)
        supported = events[0]['supported']
        readme = (ROOT / 'README.md').read_text()
        data = [{'version': v, 'files': int(f), 'bytes': int(b), 'sha256': s} for v, f, b, s in
                re.findall(r'^\| (USA v3\.\d) \| (\d+) \| (\d+) \| `([0-9a-f]{64})` \|$', readme, re.M)]
        exes = [{'version': v, 'name': n, 'bytes': int(b), 'sha256': s} for v, n, b, s in
                re.findall(r'^\| ((?:Supported )?USA v3\.\d[^|]*?) \| `(Porsche\.exe)` \| (\d+) \| `([0-9a-f]{64})` \|$',
                           readme, re.M)]
        self.assertEqual(len(data), 2)
        self.assertEqual(len(exes), 3)
        self.assertEqual(supported['data'], data)
        self.assertEqual(supported['executables'], exes)
        for word in ('folder', 'ISO', 'BIN/CUE', 'GameData', 'FEData', 'fe.txt', 'install.txt', 'Porsche.exe'):
            self.assertIn(word, supported['summary'])
        self.assertNotIn('\n', supported['summary'])

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
            with patch('tools.downloads.COMBINED_ORIGINAL_SHA', file_sha256(combined)), \
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

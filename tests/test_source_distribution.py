"""Guard against accidentally committing game payloads or translated functions."""
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SourceDistributionTests(unittest.TestCase):
    def test_tracked_tree_excludes_game_payloads_and_generated_game_functions(self):
        result = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, capture_output=True)
        if result.returncode:
            self.skipTest('source archive has no git metadata')
        forbidden = {'.exe', '.dll', '.asi', '.icd', '.iso', '.bin', '.cue', '.mdf', '.mds',
                     '.fsh', '.crp', '.mad', '.sav', '.zip', '.7z', '.rar', '.ico', '.icns'}
        for name in result.stdout.decode().split('\0'):
            if not name:
                continue
            with self.subTest(path=name):
                path = Path(name)
                self.assertNotIn(path.suffix.casefold(), forbidden)
                self.assertNotIn(path.parts[0], ('gen', 'out', 'local', 'game_backup', 'game_backup2'))
                self.assertFalse(any(part.endswith('.app') for part in path.parts))
                if path.suffix in ('.c', '.h', '.m') and (ROOT / path).is_file():
                    text = (ROOT / path).read_text()
                    self.assertIsNone(re.search(r'^void sub_[0-9a-f]{8}\(CPU\b', text, re.M))

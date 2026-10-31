import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import make_builder  # noqa: E402


class MakeBuilderTests(unittest.TestCase):
    def test_bundle_sources_cover_pipeline_and_exclude_private_dirs(self):
        names = {p.as_posix() for p in make_builder.build_sources(ROOT)}
        for required in ('build.sh', 'requirements.txt', 'tools/build_app.py', 'tools/builder_cli.py',
                         'tools/win32_args.json', 'runtime/scene.metal', 'launcher/main.m'):
            self.assertIn(required, names)
        self.assertFalse(any(n.split('/')[0] in ('tests', 'docs', 'gen', 'out', 'local', 'builder') for n in names))
        self.assertFalse(any('__pycache__' in n for n in names))

    def test_top_level_entries_match_swift_bundled_source_entries(self):
        swift = (ROOT / 'builder/Sources/BuilderCore/Workspace.swift').read_text()
        match = re.search(r'bundledSourceEntries\s*=\s*\[([^\]]*)\]', swift)
        declared = set(re.findall(r'"([^"]+)"', match.group(1)))
        bundled = {p.parts[0] for p in make_builder.build_sources(ROOT)}
        if not (ROOT / 'third_party').exists():
            declared.discard('third_party')
        self.assertEqual(bundled, declared)

    def test_minos_parser(self):
        out = 'Load command 9\n      cmd LC_BUILD_VERSION\n    platform 1\n       minos 11.0\n         sdk 15.0\n'
        self.assertEqual(make_builder.parse_minos(out), '11.0')


if __name__ == '__main__':
    unittest.main()

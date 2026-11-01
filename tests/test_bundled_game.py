import hashlib
import io
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

from tools import bundled_game
from tools.game_source import DATA_VERSIONS, EXECUTABLES, assets_digest, game_files
from tools.patches import COMBINED_MIRROR_SHA, SILENT_SHA

LINKED = b'linked fixture executable'
LINKED_SHA = hashlib.sha256(LINKED).hexdigest()
PATCH_FILES = {'GameData/Render/common.fsh': b'patched shine', 'Drivers/dx7/thrash.ini': b'[THRASH]\nFile=dx7z.dll\n'}


def patch_archive():
    data = io.BytesIO()
    with ZipFile(data, 'w') as archive:
        for name, content in PATCH_FILES.items():
            archive.writestr('Copy/' + name, content)
        archive.writestr('Copy/nfs5.exe', b'not installed')
        archive.writestr('Readme.txt', b'notice')
    return ZipFile(io.BytesIO(data.getvalue()))


def make_app(root, files=None, **overrides):
    app = Path(root) / 'NFSV.app'
    game = app / 'Contents/Resources/Game'
    for name, content in {'GameData/car.viv': b'car', 'FEData/menu.fsh': b'menu', 'fe.txt': b'fe',
                          'install.txt': b'install', 'Porsche.exe': LINKED, 'SaveData/profile': b'save',
                          'version.txt': b'3.5', 'DirectX/dxsetup.exe': b'windows extra',
                          'PatchNotices/Readme.txt': b'notice', **PATCH_FILES, **(files or {})}.items():
        path = game / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    info = {'prepare_revision': bundled_game.PREPARE_REVISION, 'source_version': 'USA v3.2',
            'source_assets_sha256': DATA_VERSIONS[0]['sha256'], 'source_exe_sha256': EXECUTABLES[0]['sha256'],
            'linked_exe_sha256': LINKED_SHA, 'prepared_assets_sha256': assets_digest(game_files(game)),
            'prepared_files_sha256': bundled_game.prepared_files_digest(game),
            'combined_sha256': COMBINED_MIRROR_SHA, 'silent_sha256': SILENT_SHA, **overrides}
    (game / 'build-input.json').write_text(json.dumps({k: v for k, v in info.items() if v is not None}))
    (app / 'Contents/Resources/NFSV.icns').write_bytes(b'icon')
    with (app / 'Contents/Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleIdentifier': 'org.nfsv.local', 'NFSBuilderVersion': '1.2.0'}, f)
    return app


def snapshot(root):
    return {p.relative_to(root).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns)
            for p in sorted(Path(root).rglob('*')) if p.is_file()}


class BundledGameTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_accepts_an_unchanged_app_and_reads_its_stamp(self):
        app = make_app(self.root)
        self.assertTrue(bundled_game.is_app(app))
        game = bundled_game.verify_bundled_game(app, LINKED_SHA)
        self.assertEqual((game.version, game.builder_version), ('USA v3.2', '1.2.0'))

    def test_apps_from_builders_that_left_files_out_are_not_reused(self):
        """Revision 1 (also apps without the field) left the extras of the copy out of the app."""
        for index, revision in enumerate((None, 1)):
            with self.subTest(revision=revision):
                app = make_app(self.root / str(index), prepare_revision=revision, prepared_files_sha256=None)
                with self.assertRaisesRegex(ValueError, 'prepares the game differently'):
                    bundled_game.verify_bundled_game(app, LINKED_SHA)

    def test_rejects_what_this_builder_would_not_produce(self):
        cases = {'prepares the game differently': {'prepare_revision': bundled_game.PREPARE_REVISION + 1},
                 'does not accept': {'source_assets_sha256': '0' * 64},
                 'different patches': {'combined_sha256': '1' * 64},
                 'not the one this Builder translates': {'linked_exe_sha256': '2' * 64}}
        for index, (message, override) in enumerate(cases.items()):
            with self.subTest(message):
                folder = self.root / str(index)
                with self.assertRaisesRegex(ValueError, message + '.*original game folder'):
                    bundled_game.verify_bundled_game(make_app(folder, **override), LINKED_SHA)

    def test_rejects_changed_or_missing_game_files(self):
        """No file of the prepared game is ignored: the extras and patch notices count too."""
        for index, name in enumerate(('DirectX/dxsetup.exe', 'PatchNotices/Readme.txt', 'Drivers/dx7/thrash.ini')):
            with self.subTest(name):
                app = make_app(self.root / str(index))
                (app / 'Contents/Resources/Game' / name).unlink()
                with self.assertRaisesRegex(ValueError, 'incomplete or were changed'):
                    bundled_game.verify_bundled_game(app, LINKED_SHA)
                (app / 'Contents/Resources/Game' / name).write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'incomplete or were changed'):
                    bundled_game.verify_bundled_game(app, LINKED_SHA)
        app = make_app(self.root)
        (app / 'Contents/Resources/Game/GameData/car.viv').write_bytes(b'modded')
        with self.assertRaisesRegex(ValueError, 'were changed'):
            bundled_game.verify_bundled_game(app, LINKED_SHA)
        (app / 'Contents/Resources/Game/fe.txt').unlink()
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            bundled_game.verify_bundled_game(app, LINKED_SHA)
        (app / 'Contents/Resources/Game/build-input.json').unlink()
        with self.assertRaisesRegex(ValueError, 'does not record'):
            bundled_game.verify_bundled_game(app, LINKED_SHA)

    def test_rejects_an_app_without_game_files(self):
        app = self.root / 'Empty.app'
        (app / 'Contents').mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, 'inside Empty.app.*missing'):
            bundled_game.verify_bundled_game(app, LINKED_SHA)
        self.assertEqual(bundled_game.builder_version(app), '')

    def test_reuse_reads_the_app_only_and_keeps_every_file(self):
        app = make_app(self.root)
        before = snapshot(app)
        game = bundled_game.verify_bundled_game(app, LINKED_SHA)
        target = self.root / 'prepared'
        bundled_game.reuse_bundled_game(app, game, patch_archive(), target)
        self.assertEqual(snapshot(app), before)
        game_files_of = lambda root: {k for k in snapshot(root) if k not in bundled_game.BUILD_FILES}
        self.assertEqual(game_files_of(target), game_files_of(app / 'Contents/Resources/Game'))
        self.assertEqual((target / 'OriginalGame.icns').read_bytes(), b'icon')
        self.assertEqual((target / 'Porsche.exe').read_bytes(), LINKED)
        self.assertEqual((target / 'DirectX/dxsetup.exe').read_bytes(), b'windows extra')

    def test_reuse_rejects_files_that_differ_from_the_patch(self):
        app = make_app(self.root, files={'Drivers/dx7/thrash.ini': b'changed'})
        game = bundled_game.verify_bundled_game(app, LINKED_SHA)  # recorded as prepared
        target = self.root / 'prepared'
        with self.assertRaisesRegex(ValueError, 'thrash.ini differs from the patch'):
            bundled_game.reuse_bundled_game(app, game, patch_archive(), target)
        self.assertFalse(target.exists())

    def test_reuse_rejects_missing_patched_game_data(self):
        app = make_app(self.root)
        game = bundled_game.verify_bundled_game(app, LINKED_SHA)
        (app / 'Contents/Resources/Game/GameData/Render/common.fsh').unlink()
        with self.assertRaisesRegex(ValueError, 'missing GameData/Render/common.fsh'):
            bundled_game.reuse_bundled_game(app, game, patch_archive(), self.root / 'prepared')


if __name__ == '__main__':
    unittest.main()

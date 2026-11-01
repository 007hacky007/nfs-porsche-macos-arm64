import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import game_source, package


def tree(root):
    return sorted(p.relative_to(root).as_posix() for p in Path(root).rglob('*') if p.is_file() or p.is_symlink())


def quarantine(path):
    r = subprocess.run(['/usr/bin/xattr', '-p', 'com.apple.quarantine', str(path)], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_bundles_the_whole_prepared_game(self):
        source = self.root / 'prepared'
        names = ('GameData/car.bin', 'FEData/movie.bin', 'Porsche.exe', 'fe.txt', 'install.txt', 'version.txt',
                 'patch-manifest.json', 'build-input.json', 'PatchNotices/readme.txt', 'drivers/dx7/thrash.ini',
                 'SaveData/profile', 'DirectX/DXSETUP.EXE', 'setup/data1.cab', 'AutoRun.inf', 'gimme.dll',
                 'Thumbs.db')
        for name in names + ('OriginalGame.ico', 'OriginalGame.icns', '.DS_Store', 'GameData/.DS_Store'):
            p = source / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(b'fixture')
        target = self.root / 'bundle/Game'
        package.copy_game_files(source, target)
        self.assertEqual(tree(target), sorted(names))

    def test_no_macos_code_from_the_copy_and_its_quarantine_stays(self):
        """A downloaded copy may hide a Mac program: it never goes into the app, and the files
        copied from the copy keep the download's quarantine (only what the build made loses it)."""
        from test_game_source import GameSourceTests
        fixture = GameSourceTests(methodName='test_refuses_existing_destination')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.allow_fixture()
        copy = fixture.game
        (copy / 'DirectX').mkdir()
        (copy / 'DirectX/DXSETUP.EXE').write_bytes(b'MZ windows extra')
        shutil.copy('/usr/bin/true', copy / 'readme.txt')                      # a Mach-O under another name
        (copy / 'Tool.app/Contents/MacOS').mkdir(parents=True)
        shutil.copy('/usr/bin/true', copy / 'Tool.app/Contents/MacOS/Tool')
        (copy / 'setup').mkdir()
        (copy / 'setup/run.command').write_text('#!/bin/sh\n')
        (copy / 'setup/data1.cab').write_bytes(b'cab')
        (copy / 'setup/readme.dat').write_text('#!/bin/sh\necho hidden\n')          # a script under a game name
        (copy / 'Helper/Contents/MacOS').mkdir(parents=True)                         # a bundle without an extension
        (copy / 'Helper/Contents/Info.plist').write_bytes(b'<plist/>')
        (copy / 'Helper/Contents/MacOS/Helper').write_bytes(b'data')
        (copy / 'setup/tool.JAR').write_bytes(b'PK')
        (copy / 'setup/Open.terminal').write_bytes(b'<plist/>')
        (copy / 'DirectX/DXSETUP.EXE').chmod(0o755)
        (copy / 'link').symlink_to('/usr/bin')
        (copy / '.DS_Store').write_bytes(b'finder')
        mark = '0081;00000000;Test;'
        subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', mark, str(copy / 'DirectX/DXSETUP.EXE')], check=True)
        subprocess.run(['/usr/bin/xattr', '-wx', 'com.apple.FinderInfo', '00' * 31 + '01', str(copy / 'install.txt')],
                       check=True)
        prepared = self.root / 'prepared'
        game_source.copy_game(game_source.verify_game(copy), prepared)
        expected = ['DirectX/DXSETUP.EXE', 'FEData/movie.bin', 'GameData/track.bin', 'Porsche.exe', 'fe.txt',
                    'install.txt', 'setup/data1.cab']
        self.assertEqual(tree(prepared), expected)

        app = self.root / 'NFSV.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        shutil.copy('/usr/bin/true', app / 'Contents/MacOS/NFSV')
        with (app / 'Contents/Info.plist').open('wb') as f:
            plistlib.dump({'CFBundleIdentifier': 'org.nfsv.test', 'CFBundleExecutable': 'NFSV'}, f)
        game = app / 'Contents/Resources/Game'
        package.copy_game_files(prepared, game)
        self.assertEqual(tree(game), expected)
        self.assertEqual(quarantine(game / 'DirectX/DXSETUP.EXE'), mark, 'game data keeps its quarantine')
        for path in game.rglob('*'):
            if path.is_file():
                self.assertFalse(path.stat().st_mode & 0o111, f'{path.name} is not executable')
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True,
                       capture_output=True)

    def test_a_fallback_copy_keeps_the_quarantine_or_fails(self):
        """When cp cannot clone, the plain copy keeps the quarantine; a copy that would lose it
        fails instead of putting unchecked files into the app."""
        source = self.root / 'copy'
        (source / 'GameData').mkdir(parents=True)
        (source / 'GameData/car.bin').write_bytes(b'car')
        mark = '0081;00000000;Test;'
        for path in (source / 'GameData', source / 'GameData/car.bin'):
            subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', mark, str(path)], check=True)
        real = subprocess.run
        calls = []

        def no_clones(command, **kwargs):
            calls.append(command[1])
            if command[:2] == ['/bin/cp', '-cR']:
                raise subprocess.CalledProcessError(1, command)
            return real(command, **kwargs)
        with mock.patch.object(game_source.subprocess, 'run', no_clones):
            game_source.clone_tree(source / 'GameData', self.root / 'kept')
        self.assertEqual(calls, ['-cR', '-pR'])
        self.assertIsNotNone(quarantine(self.root / 'kept'))
        self.assertIsNotNone(quarantine(self.root / 'kept/car.bin'))

        def losing(command, **kwargs):
            if command[:2] == ['/bin/cp', '-cR']:
                raise subprocess.CalledProcessError(1, command)
            result = real(command, **kwargs)
            real(['/usr/bin/xattr', '-cr', command[-1]], check=True)
            return result
        with mock.patch.object(game_source.subprocess, 'run', losing):
            with self.assertRaisesRegex(OSError, 'lost its quarantine'):
                game_source.clone_tree(source / 'GameData', self.root / 'lost')


if __name__ == '__main__':
    unittest.main()

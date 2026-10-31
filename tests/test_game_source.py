import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import game_source


class GameSourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.game = self.root / 'copy'
        for name, data in {'gamedata/track.bin': b'track', 'FEDATA/movie.bin': b'movie',
                           'FE.TXT': b'fe', 'install.txt': b'install', 'PORSCHE.EXE': b'original'}.items():
            p = self.game / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)

    def allow_fixture(self):
        digest = hashlib.sha256()
        for name, data in sorted({'gamedata/track.bin': b'track', 'fedata/movie.bin': b'movie',
                                  'fe.txt': b'fe', 'install.txt': b'install'}.items()):
            digest.update(name.encode() + b'\0' + hashlib.sha256(data).digest())
        self.enterContext(patch.dict(game_source.SUPPORTED_DATA, {digest.hexdigest(): 'fixture'}))
        self.enterContext(patch.dict(game_source.SUPPORTED_EXES, {hashlib.sha256(b'original').hexdigest(): 'fixture exe'}))

    def test_copies_case_insensitive_inputs_and_verifies_before_patching(self):
        self.allow_fixture()
        source = game_source.verify_game(self.game)
        self.assertEqual(source.version, 'fixture')
        game_source.copy_game(source, self.root / 'working')
        self.assertEqual((self.root / 'working/GameData/track.bin').read_bytes(), b'track')
        self.assertEqual((self.root / 'working/Porsche.exe').read_bytes(), b'original')
        self.assertEqual((self.game / 'PORSCHE.EXE').read_bytes(), b'original')

    def test_rejects_changed_game_data(self):
        self.allow_fixture()
        (self.game / 'gamedata/track.bin').write_bytes(b'changed')
        with self.assertRaises(ValueError) as caught:
            game_source.verify_game(self.game)
        self.assertEqual(str(caught.exception), "This copy's game data does not match a supported release. "
                         'NFSV needs the unmodified English USA PC release, version 3.2 or 3.4.')
        detected = game_source.assets_digest(game_source.game_files(self.game))
        self.assertIn(detected, caught.exception.detail)

    def test_rejects_wrong_executable_even_with_valid_assets(self):
        self.allow_fixture()
        (self.game / 'PORSCHE.EXE').write_bytes(b'wrong version')
        with self.assertRaises(ValueError) as caught:
            game_source.verify_game(self.game)
        self.assertEqual(str(caught.exception), 'Porsche.exe is not a supported USA v3.2, v3.4 or v3.5 executable.')
        self.assertIn(hashlib.sha256(b'wrong version').hexdigest(), caught.exception.detail)

    def test_ignores_os_and_source_control_metadata(self):
        self.allow_fixture()
        for name in ['.DS_Store', 'vssver.scc', '._movie.bin', 'Thumbs.db']:
            (self.game / 'FEDATA' / name).write_bytes(b'not game content')
        self.assertEqual(game_source.verify_game(self.game).version, 'fixture')

    def test_rejects_asset_symlinks(self):
        self.allow_fixture()
        (self.game / 'FEDATA/movie.bin').unlink()
        (self.game / 'FEDATA/movie.bin').symlink_to(self.game / 'gamedata/track.bin')
        with self.assertRaisesRegex(ValueError, 'symbolic'):
            game_source.verify_game(self.game)

    def test_refuses_existing_destination(self):
        self.allow_fixture()
        source = game_source.verify_game(self.game)
        with self.assertRaises(FileExistsError):
            game_source.copy_game(source, self.game)

    def test_accepted_checksums_come_from_the_release_tables(self):
        self.assertEqual(game_source.SUPPORTED_DATA, {d['sha256']: d['version'] for d in game_source.DATA_VERSIONS})
        self.assertEqual(set(game_source.SUPPORTED_EXES), {e['sha256'] for e in game_source.EXECUTABLES})

    def test_catches_source_changed_between_verification_and_copy(self):
        self.allow_fixture()
        source = game_source.verify_game(self.game)
        (self.game / 'gamedata/track.bin').write_bytes(b'mutated')
        with self.assertRaisesRegex(ValueError, 'supported release|checksum changed'):
            game_source.copy_game(source, self.root / 'working')
        self.assertFalse((self.root / 'working').exists())

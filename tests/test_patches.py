import hashlib
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

import pefile

from tools import patches

BACKUP = Path(__file__).resolve().parents[1] / 'game_backup2'


class PatchTests(unittest.TestCase):
    def test_recovers_callback_immediates_from_stripped_executables(self):
        from test_inspect_pe import minimal_pe
        from tools.prepare import pointer_seeds
        data = bytearray(minimal_pe())
        data[512:519] = bytes.fromhex('906800204000c3')
        self.assertIn(0x402000, pointer_seeds(pefile.PE(data=bytes(data))))

    def test_recovers_unaligned_indirect_jump_tables(self):
        import struct
        from test_inspect_pe import minimal_pe
        from tools.prepare import pointer_seeds
        data = bytearray(minimal_pe())
        data[512:521] = bytes.fromhex('ff2485091040009090')
        struct.pack_into('<II', data, 521, 0x402000, 0x401000)
        self.assertIn(0x402000, pointer_seeds(pefile.PE(data=bytes(data))))

    def test_recovers_callbacks_after_inline_data(self):
        import struct
        from test_inspect_pe import minimal_pe
        from tools.prepare import pointer_seeds
        # A linear decoder consumes the callback's MOV as part of the inline data.
        for prefix in (bytes.fromhex('eb03b80000'), bytes.fromhex('c390b80000')):
            with self.subTest(prefix=prefix.hex()):
                data = bytearray(minimal_pe())
                data[512:528] = prefix + bytes.fromhex('c7050030400000204000c3')
                if prefix[0] == 0xc3:
                    struct.pack_into('<I', data, 1028, 0x401005)
                self.assertIn(0x402000, pointer_seeds(pefile.PE(data=bytes(data))))

    def test_overlay_resolves_existing_directory_and_filename_casing(self):
        from pathlib import PurePosixPath
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = root / 'FEData/data/NFS5.CAR'
            original.parent.mkdir(parents=True)
            original.write_bytes(b'original')
            target = patches.overlay_path(root, PurePosixPath('FEData/Data/nfs5.car'))
            self.assertEqual(target, original)
            target.write_bytes(b'patched')
            self.assertEqual(original.read_bytes(), b'patched')
            self.assertEqual(list((root / 'FEData').iterdir()), [original.parent])
            self.assertEqual(patches.overlay_path(root, PurePosixPath('fedata/DATA/new.car')),
                             original.parent / 'new.car')

    def test_rejects_unknown_archive_before_creating_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bad = root / 'bad.zip'
            with ZipFile(bad, 'w') as z:
                z.writestr('../escape', b'bad')
            with self.assertRaises(ValueError):
                patches.prepare_game(root, bad, bad, root / 'game')
            self.assertFalse((root / 'game').exists())

    def test_refuses_existing_game_without_modifying_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            game = root / 'game'
            game.mkdir()
            (game / 'profile.sav').write_bytes(b'keep')
            with self.assertRaises(FileExistsError):
                patches.prepare_game(root, root, root, game)
            self.assertEqual((game / 'profile.sav').read_bytes(), b'keep')

    @unittest.skipUnless((BACKUP / 'patches/NFS5-Combined-Patch-v1.1.zip').exists(), 'local patch archives absent')
    def test_prepares_a_verified_folder_without_copying_private_saves(self):
        from test_game_source import GameSourceTests
        fixture = GameSourceTests(methodName='test_refuses_existing_destination')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.allow_fixture()
        (fixture.game / 'SaveData').mkdir()
        (fixture.game / 'SaveData/private.sav').write_bytes(b'private save')
        result = fixture.root / 'prepared'
        patches.prepare_game(fixture.game, BACKUP / 'patches/NFS5-Combined-Patch-v1.1.zip',
                             BACKUP / 'patches/SilentPatchNFS90s.zip', result)
        self.assertFalse((result / 'SaveData/private.sav').exists())
        self.assertEqual((fixture.game / 'SaveData/private.sav').read_bytes(), b'private save')
        self.assertTrue((result / 'GameData/CarModel/959.crp').is_file())

    @unittest.skipUnless((BACKUP / 'patches/NFS5-Combined-Patch-v1.1.zip').exists(), 'local patch archives absent')
    def test_installs_native_thrash_descriptor_with_patched_assets(self):
        from test_disc import image
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            disc = root / 'disc.bin'
            disc.write_bytes(image())
            game = root / 'game'
            patches.prepare_game(disc, BACKUP / 'patches/NFS5-Combined-Patch-v1.1.zip',
                                 BACKUP / 'patches/SilentPatchNFS90s.zip', game)
            self.assertIn('File=dx7z.dll', (game / 'Drivers/dx7/thrash.ini').read_text())
            self.assertEqual((game / 'GameData/CarModel/959.crp').stat().st_size, 1379762)

    @unittest.skipUnless((BACKUP / 'patches/NFS5-Combined-Patch-v1.1.zip').exists(), 'local patch archives absent')
    def test_links_actual_patch_code_and_preserves_original_sources(self):
        archive = BACKUP / 'patches/NFS5-Combined-Patch-v1.1.zip'
        before = hashlib.sha256(archive.read_bytes()).hexdigest()
        with ZipFile(archive) as z:
            exe = z.read('Copy/nfs5.exe')
            dll = z.read('Copy/nfs5.dll')
        data, report = patches.link_patch(exe, dll)
        pe = pefile.PE(data=data)
        self.assertEqual(pe.get_data(0x5a2df4 - 0x400000, 1), b'\xe9')  # native configuration startup hook
        self.assertEqual(pe.get_data(0x44dfb0 - 0x400000, 1), b'\xe9')  # car detail fix
        self.assertIn(b'\x90' * 7, pe.get_data(0x4dbe0a - 0x400000, 7))  # gimme.dll removed
        self.assertTrue(any(s.VirtualAddress == 0x301000 and s.Characteristics & 0x20000000 for s in pe.sections))
        self.assertEqual(pe.get_string_at_rva(0x3060e0), b'dx7z.dll')
        self.assertEqual(pe.get_dword_at_rva(0x306114), 1)  # D3D-compatible Thrash path
        self.assertGreater(report['changed_bytes'], 400)
        self.assertEqual(pe.get_data(0x302882, 5), b'\x90' * 5)  # no runtime self-modification
        source = pefile.PE(data=exe)
        version = next(m.imports[0].address - 0x400000 for m in source.DIRECTORY_ENTRY_IMPORT if m.dll == b'NFS5.dll')
        self.assertEqual(pe.get_dword_at_rva(version), 0x7035e0)
        self.assertEqual(data, patches.link_patch(exe, dll)[0])
        self.assertEqual(before, hashlib.sha256(archive.read_bytes()).hexdigest())
        self.assertFalse(any(m.dll.lower() == b'nfs5.dll' for m in pe.DIRECTORY_ENTRY_IMPORT))
        with self.assertRaises(ValueError):
            patches.link_patch(exe[:-1] + bytes([exe[-1] ^ 1]), dll)


if __name__ == '__main__':
    unittest.main()

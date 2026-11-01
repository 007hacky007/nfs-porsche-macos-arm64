#!/usr/bin/env python3
"""Internal app packaging step. Use ./build.sh to build the app."""
import argparse
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import pefile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.bundled_game import clone_tree  # noqa: E402


def windows_icon(executable):
    """Reconstruct an ICO from the supplied executable's original resources."""
    pe = pefile.PE(str(executable))
    try:
        resources = {entry.id: entry for entry in
                     getattr(getattr(pe, 'DIRECTORY_ENTRY_RESOURCE', None), 'entries', [])}
        if 3 not in resources or 14 not in resources:
            raise ValueError('supplied game executable has no Windows app icon')

        def read(entry):
            data = entry.directory.entries[0].data.struct
            return pe.get_data(data.OffsetToData, data.Size)

        group = read(resources[14].directory.entries[0])
        reserved, kind, count = struct.unpack_from('<HHH', group)
        if (reserved, kind) != (0, 1) or not count or len(group) != 6 + 14 * count:
            raise ValueError('invalid Windows app icon group')
        images = {entry.id: entry for entry in resources[3].directory.entries}
        directory, payload = bytearray(group[:6]), bytearray()
        for index in range(count):
            width, height, colors, reserved, planes, bits, size, identifier = struct.unpack_from(
                '<BBBBHHIH', group, 6 + 14 * index)
            bitmap = read(images[identifier])
            if len(bitmap) != size:
                raise ValueError('Windows app icon resource size mismatch')
            directory.extend(struct.pack('<BBBBHHII', width, height, colors, reserved,
                                         planes, bits, size, 6 + 16 * count + len(payload)))
            payload.extend(bitmap)
        return bytes(directory + payload)
    finally:
        pe.close()


def write_app_icon(icon, destination):
    destination = Path(destination)
    with tempfile.TemporaryDirectory(prefix='.icon-', dir=destination.parent) as temporary:
        source = Path(temporary) / 'original.ico'
        source.write_bytes(icon)
        subprocess.run(['sips', '-s', 'format', 'icns', str(source), '--out', str(destination)],
                       check=True, capture_output=True)


def copy_game_files(source, destination):
    source, destination = Path(source), Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    for name in ('GameData', 'FEData', 'SaveData', 'Drivers', 'PatchNotices'):
        path = source / name
        if path.is_dir():
            clone_tree(path, destination / name)
    for name in ('Porsche.exe', 'fe.txt', 'install.txt', 'version.txt', 'patch-manifest.json', 'build-input.json'):
        path = source / name
        if path.is_file():
            shutil.copyfile(path, destination / name)


def package(game, builder_version=''):
    os.chdir(ROOT)
    if not Path('out/nfsv').is_file() or not Path('gen/all/image.h').is_file():
        raise ValueError('native compilation inputs are missing; run ./build.sh with your game copy')
    app = ROOT / 'out/NFSV.app'
    with tempfile.TemporaryDirectory(prefix='.package-', dir=ROOT / 'out') as temporary:
        staged = Path(temporary) / 'NFSV.app'
        contents = staged / 'Contents'
        macos = contents / 'MacOS'
        macos.mkdir(parents=True)
        subprocess.run(['clang', '-O2', '-fobjc-arc', '-arch', 'arm64', '-mmacosx-version-min=11.0',
                        '-Igen/all', 'launcher/main.m', 'launcher/game.m', 'launcher/settings.m', 'launcher/update.m', 'runtime/display.c',
                        '-framework', 'Cocoa', '-o', str(macos / 'NFSV')], check=True)
        shutil.copy2('out/nfsv', macos / 'NFSVEngine')
        copy_game_files(game, contents / 'Resources/Game')
        if (Path(game) / 'OriginalGame.ico').is_file():
            write_app_icon((Path(game) / 'OriginalGame.ico').read_bytes(), contents / 'Resources/NFSV.icns')
        else:  # reused from the app being updated, whose original executable is gone
            shutil.copyfile(Path(game) / 'OriginalGame.icns', contents / 'Resources/NFSV.icns')
        notices = contents / 'Resources/ThirdPartyNotices'
        notices.mkdir()
        for path in (ROOT / 'third_party').glob('*LICENSE'):
            shutil.copyfile(path, notices / path.name)
        plist = {
            'CFBundleIdentifier': 'org.nfsv.local', 'CFBundleName': 'NFSV', 'CFBundleDisplayName': 'NFSV',
            'CFBundleExecutable': 'NFSV', 'CFBundlePackageType': 'APPL',
            'CFBundleIconFile': 'NFSV.icns',
            'CFBundleShortVersionString': '0.1', 'CFBundleVersion': '1',
            'LSMinimumSystemVersion': '11.0', 'LSMultipleInstancesProhibited': True,
            'NSHighResolutionCapable': True,
        }
        if builder_version:  # lets the launcher look for a newer Builder and the Builder update this app
            plist['NFSBuilderVersion'] = builder_version
        with (contents / 'Info.plist').open('wb') as f:
            plistlib.dump(plist, f)
        for target in (macos / 'NFSVEngine', staged):
            subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(staged)], check=True)
        backup = Path(temporary) / 'previous.app'
        if app.exists():
            app.rename(backup)
        try:
            staged.rename(app)
        except BaseException:
            if backup.exists():
                backup.rename(app)
            raise
    print('Built out/NFSV.app (ARM64, with your private game files)')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--game-folder', required=True, type=Path)
    p.add_argument('--builder-version', default='')
    args = p.parse_args()
    package(args.game_folder.resolve(), args.builder_version)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Internal app packaging step. Use ./build.sh to build the app."""
import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def copy_game_files(source, destination):
    source, destination = Path(source), Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    for name in ('GameData', 'FEData', 'SaveData', 'PatchNotices'):
        path = source / name
        if path.is_dir():
            shutil.copytree(path, destination / name)
    for name in ('Porsche.exe', 'fe.txt', 'install.txt', 'version.txt', 'patch-manifest.json', 'build-input.json'):
        path = source / name
        if path.is_file():
            shutil.copyfile(path, destination / name)


def package(game):
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
                        '-Igen/all', 'launcher/main.m', '-framework', 'Cocoa', '-o', str(macos / 'NFSV')], check=True)
        shutil.copy2('out/nfsv', macos / 'NFSVEngine')
        copy_game_files(game, contents / 'Resources/Game')
        notices = contents / 'Resources/ThirdPartyNotices'
        notices.mkdir()
        for path in (ROOT / 'third_party').glob('*LICENSE'):
            shutil.copyfile(path, notices / path.name)
        plist = {
            'CFBundleIdentifier': 'org.nfsv.local', 'CFBundleName': 'NFSV', 'CFBundleDisplayName': 'NFSV',
            'CFBundleExecutable': 'NFSV', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.1', 'CFBundleVersion': '1',
            'LSMinimumSystemVersion': '11.0', 'LSMultipleInstancesProhibited': True,
            'NSHighResolutionCapable': True,
        }
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
    args = p.parse_args()
    package(args.game_folder.resolve())


if __name__ == '__main__':
    main()

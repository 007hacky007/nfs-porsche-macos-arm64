#!/usr/bin/env python3
"""Build NFSV.app from your own game folder, .iso, .bin or .cue disc image."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.disc import Disc
from tools.game_source import assets_digest, file_sha256, game_files, verify_game


PROGRESS = False
STEP_FAILED = 'This step stopped with an error. Click Copy log and include it in a bug report.'


def emit(event):
    print('NFSV-EVENT ' + json.dumps(event), flush=True)


def step(message, ident=None):
    print(f'\n{message}', flush=True)
    if PROGRESS and ident:
        emit({'step': ident, 'title': message})


def cache_directory():
    return Path(os.environ.get('NFSV_CACHE_DIR', str(Path.home() / 'Library/Caches/NFSV')))


def check_platform():
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('building requires an Apple Silicon Mac and an ARM64 Python installation')
    if sys.version_info < (3, 10):
        raise ValueError('Python 3.10 or newer is required')


def preflight():
    check_platform()
    if not shutil.which('xcrun') or not shutil.which('codesign'):
        raise ValueError('install Xcode command line tools with: xcode-select --install')
    result = subprocess.run(['xcrun', '--find', 'clang'], capture_output=True, text=True)
    if result.returncode:
        raise ValueError('install Xcode command line tools with: xcode-select --install')


def dependencies():
    venv = ROOT / '.venv'
    python = venv / 'bin/python'
    stamp = venv / '.build-requirements-sha256'
    digest = file_sha256(ROOT / 'requirements.txt')
    ready = Path(sys.prefix).resolve() == venv.resolve() and all(
        importlib.util.find_spec(name) for name in ('pefile', 'capstone', 'unicorn'))
    if ready and stamp.is_file() and stamp.read_text() == digest:
        return
    step('Setting up Python build dependencies in .venv')
    if not python.is_file():
        subprocess.run([sys.executable, '-m', 'venv', str(venv)], check=True)
    subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check',
                    '-r', str(ROOT / 'requirements.txt')], check=True)
    stamp.write_text(digest)
    os.execv(str(python), [str(python), str(Path(__file__).resolve()), *sys.argv[1:]])


@contextmanager
def source_directory(source, temporary_parent):
    source = Path(source)
    if source.is_dir():
        yield source
        return
    if not source.is_file():
        raise ValueError('game copy does not exist')
    if source.suffix.casefold() not in ('.iso', '.bin', '.cue'):
        raise ValueError('select a game folder, .iso, .bin or .cue file')
    with tempfile.TemporaryDirectory(prefix='.extract-', dir=temporary_parent) as temporary:
        destination = Path(temporary) / 'disc'
        step(f'Extracting {source.name}', 'extract')
        with Disc(source) as disc:
            disc.extract(destination)
        yield destination


def prepared_game(source, cache, project=ROOT):
    from tools.downloads import COMBINED_SHA, SILENT_SHA, fetch_patches
    from tools.inspect_pe import inspect_pe, require_supported
    from tools.package import windows_icon
    from tools.patches import prepare_game

    project, cache = Path(project), Path(cache).expanduser().resolve()
    if cache.is_relative_to(project.resolve()):
        raise ValueError('patch download cache must be outside the repository')
    local = project / 'local/builds'
    local.mkdir(parents=True, exist_ok=True)
    with source_directory(source, local) as folder:
        step('Checking all game-data and source-executable checksums', 'verify')
        original = verify_game(folder)
        icon = windows_icon(original.files[Path('Porsche.exe')])
        print(f'Accepted {original.version}: {original.assets_sha256}', flush=True)
        step('Fetching verified patches (or checking their download cache)', 'patches')
        combined, silent = fetch_patches(cache / 'patches')
        key = hashlib.sha256((original.assets_sha256 + original.exe_sha256 + COMBINED_SHA + SILENT_SHA).encode()).hexdigest()
        destination = local / key
        marker = destination / 'build-input.json'
        if destination.exists():
            if not marker.is_file():
                raise ValueError('prepared game cache is incomplete; remove that local/builds entry and retry')
            saved = json.loads(marker.read_text())
            actual = assets_digest(game_files(destination))
            image = require_supported(inspect_pe(destination / 'Porsche.exe'))
            if saved.get('prepared_assets_sha256') != actual or 'native-linked' not in image:
                raise ValueError('prepared game cache checksum changed; remove that local/builds entry and retry')
            (destination / 'OriginalGame.ico').write_bytes(icon)
            print('Reusing verified prepared game files.', flush=True)
            return destination
        step('Applying Combined Patch v1.1 and preparing native patch behavior', 'prepare')
        with tempfile.TemporaryDirectory(prefix='.prepare-', dir=local) as temporary:
            working = Path(temporary) / 'game'
            report = prepare_game(folder, combined, silent, working)
            image = require_supported(inspect_pe(working / 'Porsche.exe'))
            if 'native-linked' not in image:
                raise ValueError('patch preparation did not produce the supported linked executable')
            info = {'source_version': original.version, 'source_assets_sha256': original.assets_sha256,
                    'source_exe_sha256': original.exe_sha256, 'linked_exe_sha256': report['sha256'],
                    'prepared_assets_sha256': assets_digest(game_files(working)),
                    'combined_sha256': report['combined_sha256'], 'silent_sha256': report['silent_sha256']}
            (working / 'build-input.json').write_text(json.dumps(info, indent=2) + '\n')
            (working / 'OriginalGame.ico').write_bytes(icon)
            working.rename(destination)
        return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     epilog='Your game copy is required and is never modified. Output: out/NFSV.app')
    parser.add_argument('game_copy', type=Path, nargs='?', help='folder containing GameData/FEData/Porsche.exe, or .iso/.bin/.cue')
    parser.add_argument('--progress', action='store_true', help='print NFSV-EVENT JSON progress lines')
    parser.add_argument('--setup-only', action='store_true', help='only check the Mac and set up Python dependencies')
    args = parser.parse_args()
    global PROGRESS
    PROGRESS = args.progress
    if args.setup_only:
        check_platform()
        dependencies()
        return
    if args.game_copy is None:
        parser.error('the game_copy argument is required')
    source = args.game_copy.expanduser().resolve()
    if not source.exists():
        raise ValueError('game copy does not exist')
    preflight()
    dependencies()
    cache = cache_directory()
    game = prepared_game(source, cache)
    os.chdir(ROOT)
    step('Translating the verified game and patch code to C', 'translate')
    subprocess.run([sys.executable, 'tools/prepare.py', str(game / 'Porsche.exe')], check=True)
    step('Compiling native ARM64 code', 'compile')
    subprocess.run([sys.executable, 'tools/compile.py'], check=True)
    step('Packaging and signing the macOS app with your private game files', 'package')
    subprocess.run([sys.executable, 'tools/package.py', '--game-folder', str(game)], check=True)
    print('\nReady: out/NFSV.app\nOpen it in Finder to play. Your original game copy and existing saves were not changed.', flush=True)
    if PROGRESS:
        emit({'done': str(ROOT / 'out/NFSV.app')})


def cli():
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Build failed: {error}', file=sys.stderr, flush=True)
        if PROGRESS:
            emit({'error': STEP_FAILED if isinstance(error, subprocess.CalledProcessError) else str(error)})
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(cli())

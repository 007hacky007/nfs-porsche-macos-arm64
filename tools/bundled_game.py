"""Reuse the prepared game files inside an existing NFSV.app when updating it.

A built app carries the prepared game (the original files with Combined Patch v1.1 applied and the
linked Porsche.exe), not the original copy, so the usual game-copy check cannot run on it. It is
reused only when this Builder would prepare exactly the same files: the recorded original copy and
patch archives are ones this Builder accepts, preparation has not changed since (PREPARE_REVISION),
the linked executable is the one this Builder translates, every file the patch installs is
byte-identical to the pinned archive and every file of the prepared game, none missing, still
matches its recorded checksum. Otherwise the original game copy is needed again.
"""
import json
import plistlib
import shutil
from pathlib import Path
from typing import NamedTuple

from tools.game_source import (SUPPORTED_DATA, SUPPORTED_EXES, assets_digest, clone_tree, file_sha256,
                               game_files, tree_digest)
from tools.inspect_pe import SUPPORTED as SUPPORTED_IMAGES
from tools.patches import COMBINED_MIRROR_SHA, COMBINED_SHA, SILENT_SHA, installed_entries, overlay_path

# Bump whenever tools/patches.py prepare_game() would produce different files, so apps prepared by
# an older Builder are no longer reused. build-input.json files without the field were written
# by revision 1. Revision 2 copies the whole game copy, its Windows-only extras included, and
# records prepared_files_sha256.
PREPARE_REVISION = 2
LINKED_EXE_SHA = next(sha for sha, name in SUPPORTED_IMAGES.items() if 'native-linked' in name)
# The original icon the Builder writes beside a prepared game for packaging (it becomes NFSV.icns,
# so it is not copied into the game folder) and the record itself: the only names
# prepared_files_sha256 leaves out.
ICON_FILES = ('OriginalGame.ico', 'OriginalGame.icns')
BUILD_FILES = ('build-input.json', *ICON_FILES)
CHOOSE_ORIGINAL = 'Choose your original game folder, .iso, .bin or .cue instead.'


class BundledGame(NamedTuple):
    folder: Path
    version: str
    info: dict
    builder_version: str


def is_app(path):
    return Path(path).suffix.casefold() == '.app' and Path(path).is_dir()


def game_folder(app):
    return Path(app) / 'Contents/Resources/Game'


def builder_version(app):
    """The Builder version stamped into the app, or '' for a Terminal build or an older app."""
    try:
        with (Path(app) / 'Contents/Info.plist').open('rb') as f:
            value = plistlib.load(f).get('NFSBuilderVersion', '')
    except (OSError, ValueError, plistlib.InvalidFileException):
        return ''
    return value if isinstance(value, str) else ''


def not_reusable(app, reason):
    return ValueError(f'The game inside {Path(app).name} cannot be reused: {reason} {CHOOSE_ORIGINAL}')


def verify_bundled_game(app, linked_sha=None):
    """Check the prepared game inside `app` without changing it."""
    app, linked_sha = Path(app), linked_sha or LINKED_EXE_SHA
    folder = game_folder(app)
    if not folder.is_dir():
        raise not_reusable(app, 'its game files are missing.')
    try:
        info = json.loads((folder / 'build-input.json').read_text())
        if not isinstance(info, dict):
            raise ValueError
    except (OSError, ValueError):
        raise not_reusable(app, 'it does not record how its game files were prepared.')
    if info.get('prepare_revision', 1) != PREPARE_REVISION:
        raise not_reusable(app, 'it was prepared by an NFSV Builder that prepares the game differently.')
    if info.get('source_assets_sha256') not in SUPPORTED_DATA or info.get('source_exe_sha256') not in SUPPORTED_EXES:
        raise not_reusable(app, 'it was built from a game copy this Builder does not accept.')
    if info.get('combined_sha256') not in (COMBINED_SHA, COMBINED_MIRROR_SHA) or info.get('silent_sha256') != SILENT_SHA:
        raise not_reusable(app, 'it was built with different patches.')
    if info.get('linked_exe_sha256') != linked_sha:
        raise not_reusable(app, 'its Porsche.exe is not the one this Builder translates.')
    try:
        files = game_files(folder)
    except ValueError:
        raise not_reusable(app, 'its game files are incomplete.')
    if file_sha256(files[Path('Porsche.exe')]) != linked_sha:
        raise not_reusable(app, 'its Porsche.exe was changed.')
    if assets_digest(files) != info.get('prepared_assets_sha256'):
        raise not_reusable(app, 'its game files were changed.')
    if prepared_files_digest(folder) != info.get('prepared_files_sha256'):
        raise not_reusable(app, 'its game files are incomplete or were changed.')
    return BundledGame(folder, SUPPORTED_DATA[info['source_assets_sha256']], info, builder_version(app))


def prepared_files_digest(folder):
    """Every file of a prepared game, none left out, except BUILD_FILES."""
    return tree_digest(folder, BUILD_FILES)


def check_patch_files(folder, patch, app='NFSV.app'):
    """Compare every file the patch installs with the verified archive `patch` (a ZipFile); a
    missing or different file rejects the folder."""
    for entry, relative in installed_entries(patch):
        target = overlay_path(folder, relative)
        if not target.is_file():
            raise not_reusable(app, f'it is missing {relative}.')
        if target.read_bytes() != patch.read(entry):
            raise not_reusable(app, f'its {relative} differs from the patch.')


def reuse_bundled_game(app, bundled, patch, destination):
    """Build a prepared game folder at `destination` from the app's game. The app is only read."""
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise FileExistsError('game destination already exists')
    clone_tree(bundled.folder, destination)
    try:
        check_patch_files(destination, patch, app)
        files = game_files(destination)
        if (file_sha256(files[Path('Porsche.exe')]) != bundled.info['linked_exe_sha256']
                or assets_digest(files) != bundled.info['prepared_assets_sha256']
                or prepared_files_digest(destination) != bundled.info['prepared_files_sha256']):
            raise ValueError('game checksum changed while copying')
        icon = Path(app) / 'Contents/Resources/NFSV.icns'
        if icon.is_file():
            shutil.copyfile(icon, destination / 'OriginalGame.icns')
    except BaseException:
        shutil.rmtree(destination)
        raise
    return destination

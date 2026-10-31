"""Validate user-owned game files without storing any game bytes in source control."""
import hashlib
import shutil
from pathlib import Path
from typing import NamedTuple

# The accepted releases, as listed in the README tables "Checksums and byte sizes". Sizes are exact
# byte counts of the extracted files; the data fingerprint is assets_digest() of GameData, FEData,
# fe.txt and install.txt.
DATA_VERSIONS = (
    {'version': 'USA v3.2', 'files': 1568, 'bytes': 528771197,
     'sha256': 'e5b118ac8e7910049f7fc9bde3274b44f7eb5911e30efece7e3b33d68ea20747'},
    {'version': 'USA v3.4', 'files': 1567, 'bytes': 528742714,
     'sha256': '57f3f4d1405e7b41b2581c47558ef4aa8b31e3d8c29fb1038334a0d34a30a1b8'},
)
EXECUTABLES = (
    {'version': 'USA v3.2 disc loader', 'name': 'Porsche.exe', 'bytes': 249119,
     'sha256': '6c862baecb74ad15be61fe54dd4ee0e4401719d369c74432dbfe9381c1812f11'},
    {'version': 'USA v3.4 disc loader', 'name': 'Porsche.exe', 'bytes': 341279,
     'sha256': '4b7bc7fc134f3e6145b9ad5dea1938085e9562344a088279d216f08a1543e9d8'},
    {'version': 'Supported USA v3.5 executable', 'name': 'Porsche.exe', 'bytes': 2129965,
     'sha256': '02437ddbf41af86dffe14251b28ed8889bd1c4c904fe77ff730d8912257ec90d'},
)
SUMMARY = ('Choose a folder, ISO or BIN/CUE image of the unmodified English USA PC release, version 3.2 or 3.4. '
           'A folder must contain GameData, FEData, fe.txt, install.txt and Porsche.exe.')
SUPPORTED_DATA = {d['sha256']: d['version'] for d in DATA_VERSIONS}
SUPPORTED_EXES = {e['sha256']: e['version'] for e in EXECUTABLES}


class UnsupportedGame(ValueError):
    """A rejected game copy; `detail` names the detected checksum for the log."""
    def __init__(self, message, detail):
        super().__init__(message)
        self.detail = detail


class GameSource(NamedTuple):
    files: dict
    version: str
    assets_sha256: str
    exe_sha256: str


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def metadata(name):
    return name.casefold() in ('.ds_store', 'thumbs.db', 'desktop.ini', 'vssver.scc') or name.startswith('._')


def game_files(root):
    root = Path(root)
    children = {}
    for p in root.iterdir():
        key = p.name.casefold()
        if key in children:
            raise ValueError(f'duplicate case-insensitive game path: {p.name}')
        children[key] = p
    files, seen = {}, set()
    for name in ('GameData', 'FEData', 'fe.txt', 'install.txt', 'Porsche.exe'):
        p = children.get(name.casefold())
        if p is None:
            raise ValueError(f'game copy is missing {name}; select the folder containing GameData and FEData')
        if p.is_symlink():
            raise ValueError(f'symbolic links are not accepted in game files: {name}')
        paths = sorted(p.rglob('*')) if name in ('GameData', 'FEData') else [p]
        if name in ('GameData', 'FEData') and not p.is_dir():
            raise ValueError(f'{name} must be a directory')
        for f in paths:
            relative = Path(name) / f.relative_to(p) if f != p else Path(name)
            if f.is_symlink():
                raise ValueError(f'symbolic links are not accepted in game files: {relative}')
            if metadata(f.name):
                continue
            key = relative.as_posix().casefold()
            if key in seen:
                raise ValueError(f'duplicate case-insensitive game path: {relative}')
            seen.add(key)
            if f.is_file():
                files[relative] = f
            elif not f.is_dir():
                raise ValueError(f'game path is not a regular file: {relative}')
    return files


def assets_digest(files):
    digest = hashlib.sha256()
    for name, path in sorted(files.items(), key=lambda pair: pair[0].as_posix().casefold()):
        if name.as_posix() == 'Porsche.exe':
            continue
        digest.update(name.as_posix().casefold().encode('utf-8') + b'\0' + bytes.fromhex(file_sha256(path)))
    return digest.hexdigest()


def verify_game(root):
    files = game_files(root)
    assets = assets_digest(files)
    if assets not in SUPPORTED_DATA:
        raise UnsupportedGame("This copy's game data does not match a supported release. "
                              'NFSV needs the unmodified English USA PC release, version 3.2 or 3.4.',
                              f'Detected game-data fingerprint: {assets} ({len(files) - 1} files)')
    exe = file_sha256(files[Path('Porsche.exe')])
    if exe not in SUPPORTED_EXES:
        raise UnsupportedGame('Porsche.exe is not a supported USA v3.2, v3.4 or v3.5 executable.',
                              f'Detected Porsche.exe SHA-256: {exe}')
    return GameSource(files, SUPPORTED_DATA[assets], assets, exe)


def copy_game(source, destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    try:
        for relative, original in source.files.items():
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, target)
        copied = verify_game(destination)
        if copied.assets_sha256 != source.assets_sha256 or copied.exe_sha256 != source.exe_sha256:
            raise ValueError('game checksum changed while copying')
    except BaseException:
        shutil.rmtree(destination)
        raise

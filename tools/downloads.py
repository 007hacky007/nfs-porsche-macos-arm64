"""Pinned, checksum-verified patch downloads. No patch payload is tracked."""
import os
import tempfile
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

from tools.game_source import file_sha256

COMBINED_URL = ('https://raw.githubusercontent.com/legluondunet/MyLittleLutrisScripts/'
                '2544370ac45b736a6ba8dc0dbb26e31c4c7f23b2/'
                'Need%20for%20Speed%20-%20Porsche%20Unleashed/NFS5-Combined-Patch-v1.1.zip')
COMBINED_SHA = 'cc3087b5f8914dd47ab4e2b54da2e68c4caa03ab4871c11183a4720eba193d66'
SILENT_URL = 'https://github.com/CookiePLMonster/SilentPatchNFS90s/releases/download/BUILD-1/SilentPatchNFS90s.zip'
SILENT_SHA = '6c3b181301f3b6e646f4f42ad8e89f74dd3fea95cc028d055c56ddab7e0fd1b8'


def fetch(url, expected_sha, destination, *, opener=urllib.request.urlopen):
    if urlsplit(url).scheme != 'https':
        raise ValueError('patch downloads require HTTPS')
    destination = Path(destination)
    if destination.is_symlink():
        raise ValueError('patch cache must not be a symbolic link')
    if destination.is_file() and file_sha256(destination) == expected_sha:
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'NFSV-build'})
        with opener(request, timeout=60) as response:
            if urlsplit(getattr(response, 'geturl', lambda: url)()).scheme != 'https':
                raise ValueError('patch download redirected away from HTTPS')
            with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.download-', delete=False) as f:
                temporary = Path(f.name)
                total = 0
                for block in iter(lambda: response.read(1024 * 1024), b''):
                    total += len(block)
                    if total > 64 * 1024 * 1024:
                        raise ValueError('patch download exceeds 64 MiB')
                    f.write(block)
        if file_sha256(temporary) != expected_sha:
            raise ValueError(f'patch checksum mismatch for {destination.name}; download was not installed')
        os.replace(temporary, destination)
        temporary = None
        return destination
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def fetch_patches(cache):
    cache = Path(cache)
    combined = fetch(COMBINED_URL, COMBINED_SHA, cache / 'NFS5-Combined-Patch-v1.1.zip')
    silent = fetch(SILENT_URL, SILENT_SHA, cache / 'SilentPatchNFS90s.zip')
    return combined, silent

#!/usr/bin/env python3
"""Machine-readable helpers for the NFSV Builder app. Prints NFSV-EVENT JSON lines."""
import argparse
import signal
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import downloads, game_source
from tools.build_app import cache_directory, emit, source_directory

ARCHIVES = (('NFS5-Combined-Patch-v1.1.zip', 'COMBINED_SHA'), ('SilentPatchNFS90s.zip', 'SILENT_SHA'))


def patches_ready():
    cache = cache_directory() / 'patches'
    return all((cache / name).is_file() and game_source.file_sha256(cache / name) == getattr(downloads, sha)
               for name, sha in ARCHIVES)


def run(args):
    if args.command == 'check-game':
        source = args.path.expanduser().resolve()
        if not source.exists():
            raise ValueError('game copy does not exist')
        with tempfile.TemporaryDirectory(prefix='nfsv-check-') as temporary, \
                source_directory(source, temporary) as folder:
            emit({'game': 'ok', 'version': game_source.verify_game(folder).version})
    elif args.action == 'status':
        emit({'patches': 'ready' if patches_ready() else 'missing'})
    else:
        downloads.fetch_patches(cache_directory() / 'patches')
        emit({'patches': 'ready'})


def main(argv=None):
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))  # Cancel: unwind temporary folders
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('check-game', help='verify a game folder, .iso, .bin or .cue').add_argument('path', type=Path)
    commands.add_parser('patches', help='inspect or download the pinned patches').add_argument(
        'action', choices=('status', 'fetch'))
    args = parser.parse_args(argv)
    try:
        run(args)
    except (ValueError, OSError) as error:
        emit({'error': str(error)})
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

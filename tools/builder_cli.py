#!/usr/bin/env python3
"""Machine-readable helpers for the NFSV Builder app. Prints NFSV-EVENT JSON lines."""
import argparse
import signal
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import bundled_game, downloads, game_source
from tools.build_app import cache_directory, emit, source_directory

ARCHIVES = (('NFS5-Combined-Patch-v1.1.zip', ('COMBINED_SHA', 'COMBINED_ORIGINAL_SHA')),
            ('SilentPatchNFS90s.zip', ('SILENT_SHA',)))


def patches_ready():
    cache = cache_directory() / 'patches'
    return all((cache / name).is_file() and game_source.file_sha256(cache / name) in {getattr(downloads, s) for s in shas}
               for name, shas in ARCHIVES)


def run(args):
    if args.command == 'check-game':
        source = args.path.expanduser().resolve()
        if not source.exists():
            raise ValueError('game copy does not exist')
        if bundled_game.is_app(source):
            bundled = bundled_game.verify_bundled_game(source)
            emit({'game': 'ok', 'version': bundled.version, 'app': True})
            return
        with tempfile.TemporaryDirectory(prefix='nfsv-check-') as temporary, \
                source_directory(source, temporary) as folder:
            emit({'game': 'ok', 'version': game_source.verify_game(folder).version})
    elif args.command == 'supported':
        emit({'supported': {'summary': game_source.SUMMARY, 'data': list(game_source.DATA_VERSIONS),
                            'executables': list(game_source.EXECUTABLES)}})
    elif args.action == 'status':
        emit({'patches': 'ready' if patches_ready() else 'missing'})
    else:
        downloads.fetch_patches(cache_directory() / 'patches')
        emit({'patches': 'ready'})


def main(argv=None):
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))  # Cancel: unwind temporary folders
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('check-game', help='verify a game folder, .iso, .bin, .cue or the game inside an NFSV.app').add_argument('path', type=Path)
    commands.add_parser('patches', help='inspect or download the pinned patches').add_argument(
        'action', choices=('status', 'fetch'))
    commands.add_parser('supported', help='list the accepted game releases and their checksums')
    args = parser.parse_args(argv)
    try:
        run(args)
    except (ValueError, OSError) as error:
        if getattr(error, 'detail', None):
            print(error.detail, file=sys.stderr, flush=True)
        emit({'error': str(error)})
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

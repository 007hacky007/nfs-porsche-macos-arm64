# NFSV native Metal port

Local Apple Silicon port of the original Windows NFS Porsche Unleashed game code. The executable is statically lifted to C and compiled to ARM64. Metal, Cocoa and CoreAudio provide the native platform services. The game does not run under Wine or Rosetta.

The original menus, garage, movies, audio and a playable race have been exercised. Evolution and Factory Driver progression still need verification. This is a work in progress.

## Play

Open `out/NFSV.app` and choose the extracted game folder, currently `local/game`. Game assets remain outside the app.

- Fullscreen is enabled on startup. Use Control-Command-F, F11 or the green window button to toggle it.
- Choose the race resolution in **Options > Graphics > Screen size**. The renderer exposes HD, 1440p and 4K modes in 16 and 32 bit color, plus the original modes.
- The Mac cursor is invisible inside the game view. The original game draws its own pointer. AppKit restores the Mac cursor outside the game.
- Menus and original movies retain their original resolution and aspect ratio. Increasing the race resolution does not replace their source artwork.

The app stores saves and its log in `~/Library/Application Support/NFSV`. Development sessions use the directory selected by `NFSV_SAVE_DIR`; these save directories are separate. Do not overwrite one with another without keeping a backup.

## Build

Requires an Apple Silicon Mac, macOS 11 or newer, Xcode command line tools and Python 3. The tested executable is v3.5 USA, SHA-256 `02437ddbf41af86dffe14251b28ed8889bd1c4c904fe77ff730d8912257ec90d`. Other executables are rejected. The current working assets are the supplied v3.4 disc data with that executable.

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python tools/prepare.py local/game/Porsche.exe
.venv/bin/python build.py
.venv/bin/python pack.py
```

To extract the supplied raw disc into a new directory:

```sh
.venv/bin/python tools/disc.py "game_backup/NFS V.mdf" local/disc
```

Keep the backup and extracted disc unchanged. The working game directory needs `GameData`, `FEData`, `fe.txt`, `install.txt`, the supported `Porsche.exe` and the supplied game files. Executable provenance is recorded locally in `local/patches/provenance.json`. Game data and binaries are ignored by git. Imported compiler/runtime notices are in `third_party`.

## Development checks

```sh
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python tools/check_native.py
```

Native checks need access to Metal and local UDP sockets; a restrictive application sandbox can deny these independently of game correctness. `requirements-dev.txt` additionally installs the test-only x86 codec oracle. It is never linked into the game.

For an interactive development run without a time limit:

```sh
NFSV_SAVE_DIR=out/saves NFSV_TIMEOUT=0 out/nfsv local/game/Porsche.exe
```

Use `NFSV_FULLSCREEN=0` to start windowed. Automatic screenshots are off by default; `NFSV_CAPTURE=120` requests one every 120 presentations for diagnosis. PNG encoding runs in the background, but reading a large framebuffer still has a cost. Leave capture disabled for performance testing. An optional `NFSV_CONTROL` FIFO accepts game-only test inputs through `tools/control.py`; do not use it while someone is playing.

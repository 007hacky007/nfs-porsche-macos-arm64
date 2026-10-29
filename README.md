# NFSV native Metal port

Local Apple Silicon port of the original Windows NFS Porsche Unleashed game code. The executable is statically lifted to C and compiled to ARM64. Metal, Cocoa and CoreAudio provide the native platform services. The game does not run under Wine or Rosetta.

The original menus, garage, movies, audio and a playable race have been exercised. Evolution and Factory Driver progression still need verification. This is a work in progress.

## Play

Open `out/NFSV.app` and choose the extracted game folder, currently `local/game-patched`. Game assets remain outside the app.

- Fullscreen is enabled on startup. Use Control-Command-F, F11 or the green window button to toggle it.
- Choose the race resolution in **Options > Graphics > Screen size**. The renderer exposes HD, 1440p and 4K modes in 16 and 32 bit color, plus the original modes.
- The Mac cursor is invisible inside the game view. The original game draws its own pointer. AppKit restores the Mac cursor outside the game.
- Menus and original movies retain their original resolution and aspect ratio. Increasing the race resolution does not replace their source artwork.

The app stores saves and its log in `~/Library/Application Support/NFSV`. Development sessions use the directory selected by `NFSV_SAVE_DIR`; these save directories are separate. Do not overwrite one with another without keeping a backup.

## Build

Requires an Apple Silicon Mac, macOS 11 or newer, Xcode command line tools and Python 3. The default input is the USA BIN/CUE disc in `game_backup2`, with Combined Patch v1.1 and SilentPatch Build 1 from `game_backup2/patches`.

Prepare a new asset folder, then compile and package:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python tools/patches.py \
  "game_backup2/Need for Speed - Porsche Unleashed (USA).cue" \
  game_backup2/patches local/game-patched
.venv/bin/python tools/prepare.py local/game-patched/Porsche.exe
.venv/bin/python build.py
.venv/bin/python pack.py
```

Preparation validates the exact patch archives, extracts the CUE's BIN data track and applies the Combined Patch assets. Verok's executable and DLL are linked with their instruction changes resolved before static translation. Unicorn runs only the patch initialization during preparation; the finished app is ARM64 and does not contain it. Some restrictive sandboxes block this build-time interpreter's executable memory.

The output directory must not already exist. Original backups, previous asset folders and existing save overlays remain unchanged. The patch's sample profile and HUD defaults are used only when no saved file already overrides them. The generated `patch-manifest.json` records hashes and installed files. Upstream patch archives and notices are retained locally in `PatchSources`.

The app validates the prepared executable against its build. After upgrading, select `local/game-patched` if the launcher asks for a game folder. The old v3.5 USA image remains supported when explicitly rebuilding for it; an app and game folder must use the same image.

For extraction without patches:

```sh
.venv/bin/python tools/disc.py "game_backup2/Need for Speed - Porsche Unleashed (USA).cue" local/disc-bin
```

The reader supports the supplied single-track MODE1/2352 BIN/CUE, raw MODE1 images and 2048-byte ISOs. It rejects unsupported CUE layouts. Game assets, binaries, backups and local manifests are ignored by git. Imported compiler/runtime notices are in `third_party`. See [patch coverage](docs/patches.md) for what runs natively and which Windows components are replaced.

## Development checks

```sh
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python tools/check_native.py
```

Native checks need access to Metal and local UDP sockets; a restrictive application sandbox can deny these independently of game correctness. The build-time Unicorn dependency also serves as an x86 codec oracle. It is never linked into the game.

For an interactive development run without a time limit:

```sh
NFSV_SAVE_DIR=out/saves NFSV_TIMEOUT=0 out/nfsv local/game-patched/Porsche.exe
```

Use `NFSV_FULLSCREEN=0` to start windowed. Automatic screenshots are off by default; `NFSV_CAPTURE=120` requests one every 120 presentations for diagnosis. PNG encoding runs in the background, but reading a large framebuffer still has a cost. Leave capture disabled for performance testing. An optional `NFSV_CONTROL` FIFO accepts game-only test inputs through `tools/control.py`; do not use it while someone is playing.

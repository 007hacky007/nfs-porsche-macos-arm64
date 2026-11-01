# Changelog

What each version of NFSV Builder brings. The newest version is first.

## 1.3.0 - 2026-11-01

### Added
- The launcher tells you when a newer NFSV Builder is out, with What's new, Download and Not now. It checks once a day, and turning off Check for updates stops all network requests.
- NFSV Builder can update an installed NFSV.app using the game inside it, so you do not need your original game copy again. The button reads Update NFSV.app with the old and new version, and saves and settings are kept.

### Changed
- NFSV.app now holds your whole game copy, Windows-only extras included. It never asks for a game folder and keeps working wherever you move it. Apps made by earlier Builders need your original game copy one more time.
- If the game files inside NFSV.app are missing or do not match, the app says so and asks you to build it again, instead of asking for a game folder.
- Mac programs hidden in a game copy are left out of the app, and files from your game copy keep their download quarantine.
- Remove build files is now Delete temporary files. It shows how much space it frees and says what it deletes and what it keeps.

## 1.2.0 - 2026-10-31

### Added
- Stick sensitivity in the launcher sets how a controller's sticks respond: lower steers more gently around the center, higher reaches full lock sooner.

### Fixed
- Controller vibration now plays. In 1.1.0 it stayed silent.

## 1.1.0 - 2026-10-31

### Added
- Game controllers: PS4 (DualShock 4), PS5 (DualSense), Xbox, Switch Pro and other gamepads that macOS supports, over Bluetooth or USB. The game's own default bindings fit the pad, and every control can be rebound.
- Controller vibration from the game's force feedback (crashes, landings, road and engine), with a switch in the launcher. It is on by default.

## 1.0.0 - 2026-10-31

### Added
- NFSV Builder makes NFSV.app on your Mac from your own English USA PC copy of Need for Speed: Porsche Unleashed (v3.2 or v3.4), given as a folder, an ISO or a BIN/CUE pair. It downloads and applies the patches the game needs.
- A checklist that fixes each missing item with one button. No Terminal needed.
- The game runs as native Apple Silicon code with Metal graphics and CoreAudio sound. No Wine, Rosetta or emulator.
- The whole original game: menus, garage, Quick Race, Evolution and Factory Driver, with the original sound, music and movies.
- HD, 1440p and 4K race resolutions, with optional 4x antialiasing and 16x anisotropic filtering.
- A race HUD that scales with the resolution, with an adjustable size.
- A launcher before each game for race resolution, fullscreen or window, frame-rate limit, HUD size, Mac cursor and enhanced graphics. Your choices are remembered.
- Fullscreen by default. Control-Command-F, F11 or the green window button switches to a window and back while you play.
- Keyboard and mouse controls and paste with Command-V. Switching to another app releases held keys and keeps the picture and sound running.
- Your saves are kept apart from the game files, so rebuilding keeps your careers.

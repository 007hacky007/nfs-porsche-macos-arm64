# Supplied patch coverage

Run `./build.sh` with your own supported game folder or disc image. The builder verifies your files and fetches pinned patch versions. Archives stay in the external download cache; extracted files and generated game code stay in ignored build directories. Upstream notices are retained in `PatchNotices` with the privately prepared files and bundled app.

## Combined Patch v1.1

The automatic builder uses the pinned, checksum-verified community mirror authorized for this project, because the original author download is unavailable. These checksums cover the complete ZIP file, before extraction:

| Archive variant | Exact filename | Exact size (bytes) | SHA-256 of ZIP file |
| --- | --- | ---: | --- |
| Mirror used by the builder | `NFS5-Combined-Patch-v1.1.zip` | 14026990 | `cc3087b5f8914dd47ab4e2b54da2e68c4caa03ab4871c11183a4720eba193d66` |
| Previously inspected archive, accepted by the internal preparation tool | `NFS5-Combined-Patch-v1.1.zip` | 14023356 | `bb69d935b49dfe7ab71e22608102d01b985a4ca41c9e8559e765ed2d0149d5a2` |

All 147 original archive members match; the mirror's additional `Copy/fe_out.txt` is ignored.

| Component | Native integration |
| --- | --- |
| NFS5 Essentials and Combined Patch game data | Apply every supplied FEData and GameData file, including car/part/race databases, layouts, locale strings, models, textures, simulations and Monte Carlo police data. |
| Four official extra cars | Install the supplied 928 GTS, 959, GT2 and GT3 files and the updated Evolution purchase/race data. |
| Smooth Shines and Lights | Install the supplied `GameData/Render/common.fsh`. |
| HUD and sample save | Install the supplied defaults in the asset folder. Existing save overlays take precedence. Existing careers are never replaced or reset. Some fixes stored inside a profile require a new patched profile. |
| Verok game executable and DLL | Link the verified code, resolve its initialization changes before lifting, then compile the original game and patch functions to ARM64. This includes its car detail, CPU calculation, texture, dashboard, Normandie, widescreen projection and avatar-decoding changes. |
| DirectX, Glide, nGlide and OpenGL drivers | The native Metal Thrash renderer provides graphics. The Windows drivers and their DLL loader do not execute. |
| Windows configuration program | Native fullscreen and graphics settings remain in use. Preparation selects English, the native-compatible dx7 Thrash path, movies, fog and filtering enabled, automatic CPU calculation and the archive's default car-control setting. Windows affinity and error-reporting options do not configure macOS. |

The Combined Patch readme says it includes the Enhanced Patch's bug fixes, not all of that older patch's gameplay enhancements. Its archived Enhanced Patch document is not a feature checklist for this combined package.

Data fixes come from NFS5 Essentials by ND4SPD Racer, the Combined Patch contributors and Smooth Shines and Lights by KrazyBoy. Verok's patch documentation is included in the archive. Required compiler/runtime notices remain in `third_party`.

## Combined Patch v1.0 (not used)

[Combined Patch v1.0](https://www.nfsaddons.com/downloads/nfspu/tools/3824/nfs-porsche-unleashed-combined-patch-v10.html) by A Future Pilot (April 2019) is the predecessor of v1.1. It was downloaded and compared file by file with the v1.1 archive:

| Archive | Exact size (bytes) | SHA-256 of ZIP file |
| --- | ---: | --- |
| `nfs5-combined-patch.zip` from NFSAddons | 16402927 | `24576fc539320c0b5ac22f6d867f9e4f72a320c2bc2ea12a9396cac7dde029aa` |

| v1.0 component | Status in this port |
| --- | --- |
| FEData and GameData files, including `GameData/Render/common.fsh` | Byte-identical to the files in v1.1, which are already applied. |
| `Porsche.exe` from the "Complete" patch (v3.5 with byte patches) | Superseded by Verok's code in v1.1. Lens flare: the same byte change is in the linked executable. Night dashboard and texture quality on fast CPUs: Verok fixes these in his own way (rewritten dashboard code, replaced CPU calculation). 32-bit menu colors: not needed for 3D, because Metal always renders into a 32-bit target; menu screens still pick the game's 16-bit mode. Pits "B button": the `b` key still presses the menu Back button. This is an input change, not a graphics one, and is not applied. |
| `gimme.dll`, `Porsche.sdb` | Not needed. Verok's code decodes driver avatars without `gimme.dll`, and the compatibility shim only affects Windows. |
| nGlide installer, Voodoo drivers and registry files | Windows-only. The native Metal renderer replaces them. |
| "Add anisotropic filtering and anti-aliasing through your graphics driver" | Implemented natively. See below. |

The v1.0 readme also suggests a 0.7 gamma in the nGlide configurator. The v1.1 readme returns to 1.0, which this port keeps.

## Enhanced graphics

Both Combined Patch readmes ask players to force antialiasing and anisotropic filtering in the graphics driver, because the game's own renderers cannot. In this port the Metal renderer is the driver, so the launcher's **Enhanced graphics** option (on by default) does this directly:

| Setting | Effect |
| --- | --- |
| 4x multisample antialiasing | Smooths polygon edges of cars, scenery and the garage. Every render pass resolves into the normal back buffer, so the game's pixel reads (sun glare test), movie frames and menu blits behave as before. Writes from the game are copied back into all samples. |
| 16x anisotropic filtering | Applied to every linearly filtered, mipmapped texture, keeping road and terrain textures sharp at shallow angles. |

The option sets `NFSV_ENHANCED_GRAPHICS` for the engine. With `0`, rendering is identical to earlier builds. Alpha-tested textures such as foliage are not smoothed by multisampling.

## Other patches reviewed

| Patch | Decision |
| --- | --- |
| [NFS5 Enhanced](https://github.com/iArtorias/nfs5_enhanced) v1.3.0 by iArtorias (GPL-3.0) | Not applied. It is a Windows ASI plugin with a Direct3D 11 driver that targets the unpatched v3.5 executable, not the Verok-linked executable this port uses. Its antialiasing, anisotropic filtering, HUD scaling, widescreen and SilentPatch fixes already have native equivalents here. Candidates for future native work: longer draw distance and far clip, lamp-glow depth bias, wheels on distant car models and frame interpolation above 64 Hz. Each needs addresses checked against the linked executable and play testing. |
| Verok's NFSV Patch | Already applied, as the core of Combined Patch v1.1. |
| SilentPatchNFS90s | Already covered, see above. |
| Track and sky texture packs on NFSAddons, such as New Atmospheric Skyboxes | Not included. They change the game's art direction rather than fix it, have no stated redistribution terms and are best left as a personal choice. |

## SilentPatch Build 1

The complete downloaded ZIP file is verified before extraction:

| Exact filename | Exact size (bytes) | SHA-256 of ZIP file |
| --- | ---: | --- |
| `SilentPatchNFS90s.zip` | 1122658 | `6c3b181301f3b6e646f4f42ad8e89f74dd3fea95cc028d055c56ddab7e0fd1b8` |

The Windows ASI and proxy DirectInput DLL are not loaded into the ARM64 app. Its NFS Porsche fixes are implemented through native platform services:

| NFS Porsche behavior | Native equivalent |
| --- | --- |
| Thread affinity and stability | Original game execution is serialized by the guest lock, with explicit release during blocking host operations. CoreAudio and Metal retain their native workers. Windows CPU-affinity hooks are unnecessary. |
| DirectInput enumeration and rebinding | Enumerate the native keyboard, mouse and one virtual game controller directly, without Windows device enumeration. No Windows 10 controller scan occurs. The controller is backed by macOS GameController and is always listed, so its bindings keep their device. |
| Keyboard after switching apps | Release held keys and buttons, post input-focus messages and clear the original game's keyboard buffer on focus loss. Keep native display and audio active, avoiding the Windows display suspend/restart path. |
| OpenGL race-transition leak | Metal owns graphics resources; the native Thrash surface allocations are freed on video-mode changes and checked by repeated 4K/menu cycles. The affected OpenGL drivers do not run. |
| Alt+F4 | Option-F4 closes the game through its normal close-message path. Command-Q and the Mac window close button also work. |
| Lock keys | Native input does not synthesize lock-key changes. |
| Clipboard paste | Command-V and Control-V insert clipboard text through original character messages. Delimiters preserve repeated characters, matching SilentPatch's workaround. Delivery is paced for the original UI's small character queue. Unsupported characters and control characters are omitted. |

Fixes labeled only for NFS2SE, NFS3 or NFS4 in SilentPatch are outside this game's scope. Native macOS game controller support comes from the port's own DirectInput joystick, not from a Windows DirectInput patch.

Reference: [SilentPatchNFS90s Build 1 source](https://github.com/CookiePLMonster/SilentPatchNFS90s/tree/0b8b7149f0cc0914c10c0ad6996636b9e6d726ce). Its behavior is reimplemented natively; no SilentPatch code is included. The upstream ReadMe from the verified download is kept with the prepared files.

## Verification scope

Preparation verifies archive and binary identities and records each applied data file. Regression checks cover CUE parsing, deterministic code linkage, callback discovery, native input/focus and the graphics/platform services. These checks do not establish that every patched car, track or career event behaves correctly. Gameplay progression and long sessions still require play testing, especially with existing profiles whose saved state predates the data fixes.

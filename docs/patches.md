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

## SilentPatch Build 1

The complete downloaded ZIP file is verified before extraction:

| Exact filename | Exact size (bytes) | SHA-256 of ZIP file |
| --- | ---: | --- |
| `SilentPatchNFS90s.zip` | 1122658 | `6c3b181301f3b6e646f4f42ad8e89f74dd3fea95cc028d055c56ddab7e0fd1b8` |

The Windows ASI and proxy DirectInput DLL are not loaded into the ARM64 app. Its NFS Porsche fixes are implemented through native platform services:

| NFS Porsche behavior | Native equivalent |
| --- | --- |
| Thread affinity and stability | Original game execution is serialized by the guest lock, with explicit release during blocking host operations. CoreAudio and Metal retain their native workers. Windows CPU-affinity hooks are unnecessary. |
| DirectInput enumeration and rebinding | Enumerate the native keyboard/mouse interfaces directly, without Windows device enumeration. No Windows 10 controller scan occurs. |
| Keyboard after switching apps | Release held keys and buttons, post input-focus messages and clear the original game's keyboard buffer on focus loss. Keep native display and audio active, avoiding the Windows display suspend/restart path. |
| OpenGL race-transition leak | Metal owns graphics resources; the native Thrash surface allocations are freed on video-mode changes and checked by repeated 4K/menu cycles. The affected OpenGL drivers do not run. |
| Alt+F4 | Option-F4 closes the game through its normal close-message path. Command-Q and the Mac window close button also work. |
| Lock keys | Native input does not synthesize lock-key changes. |
| Clipboard paste | Command-V and Control-V insert clipboard text through original character messages. Delimiters preserve repeated characters, matching SilentPatch's workaround. Delivery is paced for the original UI's small character queue. Unsupported characters and control characters are omitted. |

Fixes labeled only for NFS2SE, NFS3 or NFS4 in SilentPatch are outside this game's scope. Native macOS gamepad support is not added by installing a Windows DirectInput patch.

Reference: [SilentPatchNFS90s Build 1 source](https://github.com/CookiePLMonster/SilentPatchNFS90s/tree/0b8b7149f0cc0914c10c0ad6996636b9e6d726ce). The MIT notice is retained in `third_party/SilentPatchNFS90s-LICENSE`.

## Verification scope

Preparation verifies archive and binary identities and records each applied data file. Regression checks cover CUE parsing, deterministic code linkage, callback discovery, native input/focus and the graphics/platform services. These checks do not establish that every patched car, track or career event behaves correctly. Gameplay progression and long sessions still require play testing, especially with existing profiles whose saved state predates the data fixes.

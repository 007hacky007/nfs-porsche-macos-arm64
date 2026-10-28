# NFSV native Apple Silicon research

Research date: 2026-10-28. This records inspection, not a working port.

## Requested result

Run the PC version of Need for Speed: Porsche Unleashed natively on Apple Silicon using Metal, preserving the original menus, races and game modes through static recompilation.

## Supplied backup

Disc inputs: `game_backup/NFS V.mdf` and `game_backup/NFS V.mds`.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| NFS V.mdf | 705621168 | cbf40045c4d8941561a0d816fb0d854372014d5b64b23bd4cc2cdf841e1e7cf7 |
| NFS V.mds | 2858 | 7671549c9e62d56cc2f760b019cc508831371bab8542ddb317f4ef111900bfe8 |

The MDF contains 300009 raw MODE1/2352 sectors. User data begins at byte 16 in each sector and occupies 2048 bytes. The disc has ISO9660 descriptors at sectors 16 and 17, a Joliet supplementary descriptor at sector 18, and a terminator at sector 19.

Use the Joliet tree. The primary tree truncates names such as `Simulation` to `SIMULA~1` and `cop356_german.crp` to `COP356~1.CRP`; extracting only primary names will break asset lookup.

The Joliet tree contains 1726 files. `GameData` holds 846 files totaling 334926978 bytes; `FEData` holds 744 files totaling 193824049 bytes. Both directories are loose on the CD, so they do not require the Windows installer. `version.txt` contains `3.4`; this is a disc version observation, not a claim about the decrypted game executable's version.

## Executables and graphics boundary

| Disc file | Bytes | SHA-256 | Finding |
| --- | ---: | --- | --- |
| Porsche.exe | 341279 | 4b7bc7fc134f3e6145b9ad5dea1938085e9562344a088279d216f08a1543e9d8 | PE32 x86 loader, entry 0x419fe0 |
| PORSCHE.ICD | 2129965 | d29edd10735246553b8d783e9a930d790b14c684b6c2b178266cb39af44eb7b6 | Protected game image, base 0x400000, entry 0x5a2d1a |
| Setup/Thrash/dx7z.dll | 155648 | 0433cc93106603e9e0a81168e2fa44c40e3121a71b7ae9cd6f3b1f7551f3fc18 | Thrash renderer module with 41 exported functions |
| gimme.dll | 4599863 | 3a43b0f6a1608f69adc3a5009c9fe055a24e17197e85c4045c2c43e37eb75f6b | Large conversion library exporting ConvertFile; runtime necessity not established |

The ICD code section has entropy 7.92 bits/byte, its entry bytes do not resemble an ordinary CRT entry, and the disc includes `secdrv.sys` and SafeDisc support files. Together these establish a protected executable path; feeding it directly into the lifter would translate encrypted bytes rather than the game.

The ICD retains 56746 IMAGE_REL_BASED_HIGHLOW relocation entries. These are useful for code discovery after obtaining a usable plaintext image, but they are not themselves a decryption mechanism.

The game resolves named `_THRASH_*` functions dynamically. `dx7z.dll` exports 41 functions covering device description, video modes, render state, primitive drawing, textures, window lock/unlock, rectangle transfers and presentation. Its imports include `DirectDrawCreateEx` and `DirectDrawEnumerateExA`. The supplied readme specifies DirectX 7, with Glide for Voodoo 1.

Inference: replacing the Thrash module with native functions is likely a smaller graphics boundary than implementing all of DirectDraw and Direct3D 7. This still requires validating structures, state values, guest callbacks and calling conventions against the supported executable. The game itself imports DirectDraw, so a Thrash bridge alone does not prove all DirectDraw behavior can be omitted.

## What the sibling NFSU2 project provides

Reference source files: `README.md`, `PROJECT.md`, `LITERATURE.md`, `LIFTER_EFFICIENCY.md`, `GRAPHICS_RESEARCH.md`, `WINE_COMPARISON.md`, `tools/lift.py`, `tools/genall.py`, `tools/reloc2.py`, `runtime/cpu.h`, `runtime/dispatch.c`, `runtime/mem.c`, `runtime/gfx.h`, `runtime/metal.m`, and build/boot scripts.

- The proven architecture lifts x86 functions to C, compiles them as ARM64, and provides native implementations of Windows and graphics APIs.
- The lifter covers integer, x87 and SSE operations, instruction flags, function discovery and indirect dispatch.
- The runtime already addresses guest memory, files, heaps, Win32 threading, input, audio and native Mac windows.
- The renderer targets D3D9 and the NFSU2 shader pipeline. NFSV's Thrash/DX7 boundary needs its own integration.
- NFSU2's generator is restricted to one SPEED2.EXE hash. Its relocation extractor assumes an unnamed section, unlike the standard relocation directory in the NFSV ICD.
- Its CPU/dispatch and boot code contain NFSU2 addresses, fixed text ranges, entry points and game hooks. These must not be copied unchanged into a different game.
- The lifter primarily discovers `.text`; NFSV also has an executable `PACODE` section. Reachability and coverage must account for every executable section.

The local NFSU2 `LICENSE` permits personal local modification and restricts redistribution. Its imported nfsu2-web notice is MIT. Record the provenance of any reused file; a project-level notice is not proof that every file can be redistributed under the same terms.

## Existing native alternative

[OpenUnleashed](https://github.com/Second-Boot/Open-Unleashed) is a Rust engine reimplementation, rather than static recompilation. Inspected source snapshot: `b0ec06e90c9885fca0f6afb6a2caa5aa02c0169a`.

Source inspection found substantial implementations of vehicle physics, races, AI, traffic, police, front-end layouts, career, saves, replays and Factory Driver. The renderer selects wgpu's Metal backend on macOS; the documented `WGPU_BACKEND=metal` setting can require it explicitly. The project is GPL-3.0-or-later.

The [upstream build instructions](https://github.com/Second-Boot/Open-Unleashed/blob/main/docs/en/building.md) provide native builds, game-data paths, screenshots and automated driving. Its [game-data instructions](https://github.com/Second-Boot/Open-Unleashed/blob/main/docs/en/game-data.md) require `GameData` and `FEData`, with additional optional files. The original executable is not required to run the reconstructed engine.

This source has not been built or played during this investigation. Its support for the supplied 3.4 data, rendering fidelity, original save compatibility and all game modes remain unverified. Physics source explicitly documents differing confidence levels in reconstructed behavior. The career playthrough test advances the model with synthetic wins and validates asset availability; it is not proof of a complete playable career or matching handling.

An existing native engine could reach a useful result sooner, but adopting it changes the method from original-code recompilation to reconstructed behavior. That choice must be explicit.

## Other primary references

- [NFS5 Enhanced](https://github.com/iArtorias/nfs5_enhanced): an existing replacement Thrash renderer for Windows/D3D11, useful as an ABI reference. Its README identifies a v3.5 target executable by MD5 `316f33a59db48a7db2a75cc4b3bd03dc`. This patch has not been downloaded or applied here.
- [SilentPatchNFS90s](https://github.com/CookiePLMonster/SilentPatchNFS90s): compatibility research for the original game, including threading and timing issues.

## Verification performed

Parsed both ISO9660 and Joliet directory trees without mounting or running Windows programs. Inspected PE headers, imports, exports, relocation counts and section entropy using the sibling project's existing Python environment. Computed SHA-256 for both supplied image files. The native build targets ARM64 with Clang and Metal.

No game files were modified, no game executable was run, no port was built, and nothing was published. These findings establish inputs and architecture options, not gameplay readiness.

#!/usr/bin/env python3
"""Prepare the supplied BIN/CUE and patch archives for native recompilation.

Windows patch initialization runs only during preparation, under a bounded x86
build-time interpreter. The resulting game and patch functions are lifted to
ARM64; the native app never loads Windows plugins or an emulator.
"""
import argparse
import hashlib
import json
import shutil
import struct
import sys
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

import pefile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.disc import Disc
from tools.game_source import copy_game, verify_game

COMBINED_SHA = 'bb69d935b49dfe7ab71e22608102d01b985a4ca41c9e8559e765ed2d0149d5a2'
COMBINED_MIRROR_SHA = 'cc3087b5f8914dd47ab4e2b54da2e68c4caa03ab4871c11183a4720eba193d66'
SILENT_SHA = '6c3b181301f3b6e646f4f42ad8e89f74dd3fea95cc028d055c56ddab7e0fd1b8'
EXE_SHA = 'c318af393d4c2b7071a820ca3d69e956bbd94769b6e5c2e3e49f498ecbc94906'
DLL_SHA = 'f24b5c82404f403645e5bc3e52d47e4dd6d19bd92613c243ac31bea285fce758'
BASE, PATCH_BASE, IMPORT_RVA = 0x400000, 0x700000, 0x30a000
CONFIG = {'language': 'english', 'thrashdriver': 'dx7', 'windowedmode': '0',
          'singleprocaffinity': '0', 'cpulimit': '0', 'noerrorreporting': '0',
          'nomovies': '0', 'fog': '1', 'filtering': '1', 'carcontrol': '0'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verified_archive(path, expected):
    accepted = {expected} if isinstance(expected, str) else set(expected)
    if sha(Path(path).read_bytes()) not in accepted:
        raise ValueError(f'unsupported patch archive: {Path(path).name}')
    return ZipFile(path)


def align(value, boundary):
    return (value + boundary - 1) & -boundary


def link_patch(exe_data, dll_data):
    """Resolve Verok's code modifications before static translation."""
    if sha(exe_data) != EXE_SHA or sha(dll_data) != DLL_SHA:
        raise ValueError('unsupported Combined Patch executable or DLL')
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESP, UC_X86_REG_EIP

    exe, dll = pefile.PE(data=exe_data), pefile.PE(data=dll_data)
    dll.relocate_image(PATCH_BASE)
    images = [(exe, BASE), (dll, PATCH_BASE)]
    memory = bytearray(0x30a000)
    groups = []
    version_iat = None
    for pe, base in images:
        mapped = pe.get_memory_mapped_image()
        memory[base - BASE:base - BASE + len(mapped)] = mapped
        for module in pe.DIRECTORY_ENTRY_IMPORT:
            name = module.dll.decode('ascii')
            imports = [(s.address, s.name.decode('ascii') if s.name else s.ordinal) for s in module.imports]
            if name.lower() == 'nfs5.dll':
                version_iat = imports[0][0]
                continue
            groups.append((name, imports))
    if version_iat is None:
        raise ValueError('missing NFS5 version import')
    struct.pack_into('<I', memory, version_iat - BASE, PATCH_BASE + 0x35e0)
    # Dynamic imports requested by the verified DLL's process initialization.
    extra = [('KERNEL32.dll', 'SetProcessAffinityMask', 2),
             ('USER32.dll', 'MonitorFromWindow', 2),
             ('USER32.dll', 'GetMonitorInfoA', 2),
             ('KERNEL32.dll', 'SetThreadAffinityMask', 2),
             ('KERNEL32.dll', 'CreateActCtxA', 1),
             ('KERNEL32.dll', 'ReleaseActCtx', 1),
             ('KERNEL32.dll', 'ActivateActCtx', 2),
             ('KERNEL32.dll', 'DeactivateActCtx', 2)]
    payload = bytearray(20 * (len(groups) + len(extra) + 1))
    for module, name, _ in extra:
        iat = BASE + IMPORT_RVA + len(payload)
        payload.extend(bytes(8))
        groups.append((module, [(iat, name)]))
    imports = []
    for index, (module, symbols) in enumerate(groups):
        name_rva = IMPORT_RVA + len(payload)
        payload.extend(module.encode() + b'\0')
        if len(payload) & 1:
            payload.append(0)
        names = []
        for iat, name in symbols:
            if isinstance(name, int):
                names.append(0x80000000 | name)
            else:
                names.append(IMPORT_RVA + len(payload))
                payload.extend(b'\0\0' + name.encode() + b'\0')
                if len(payload) & 1:
                    payload.append(0)
            imports.append((module, name, iat))
        payload.extend(bytes(-len(payload) % 4))
        int_rva = IMPORT_RVA + len(payload)
        payload.extend(struct.pack('<' + 'I' * (len(names) + 1), *names, 0))
        struct.pack_into('<IIIII', payload, index * 20, int_rva, 0, 0, name_rva, symbols[0][0] - BASE)
    memory.extend(payload)
    uc = Uc(UC_ARCH_X86, UC_MODE_32)
    uc.mem_map(BASE, align(len(memory), 4096))
    uc.mem_write(BASE, bytes(memory))
    uc.mem_map(0x1000000, 0x20000)
    uc.mem_map(0xf0000000, 0x1000)
    uc.mem_map(0xff000000, 0x1000)
    lookup = {}
    for i, (module, name, iat) in enumerate(imports):
        uc.mem_write(iat, struct.pack('<I', 0xf0000000 + i))
        lookup.setdefault((module.lower(), name), 0xf0000000 + i)
    modules = {name.lower(): i + 1 for i, name in enumerate(sorted({m for m, _, _ in imports}))}
    module_names = {v: k for k, v in modules.items()}
    api_calls = set()

    def read32(address):
        return struct.unpack('<I', uc.mem_read(address, 4))[0]

    def string(address):
        if not address:
            return ''
        data = bytearray()
        for i in range(4096):
            ch = uc.mem_read(address + i, 1)[0]
            if not ch:
                return data.decode('cp1252')
            data.append(ch)
        raise ValueError('unterminated patch initializer string')

    def hook(uc, address, size, _):
        if not 0xf0000000 <= address < 0xf0000000 + len(imports):
            return
        _, name, _ = imports[address - 0xf0000000]
        api_calls.add(name)
        sp = uc.reg_read(UC_X86_REG_ESP)
        a = lambda i: read32(sp + 4 + i * 4)
        result, count = 0, 0
        if name == 'VirtualProtect':
            count = 4
            if not BASE <= a(0) < BASE + len(memory) or a(0) + a(1) > BASE + len(memory):
                raise ValueError('patch initializer tried to modify memory outside its images')
            uc.mem_write(a(3), struct.pack('<I', 0x40))
            result = 1
        elif name == 'GetModuleHandleA':
            count, result = 1, modules.get(string(a(0)).lower(), 0)
        elif name == 'GetProcAddress':
            count = 2
            result = lookup.get((module_names[a(0)], string(a(1))), 0)
            if not result:
                raise ValueError('unresolved patch initializer dynamic import: ' + string(a(1)))
        elif name == 'GetModuleFileNameA':
            count = 3
            data = b'C:\\NFSV\\nfs5.exe\0'
            if a(2) < len(data):
                raise ValueError('patch module filename buffer too small')
            uc.mem_write(a(1), data)
            result = len(data) - 1
        elif name == 'GetPrivateProfileIntA':
            count = 4
            result = int(CONFIG.get(string(a(1)).lower(), str(a(2))))
        elif name == 'GetPrivateProfileStringA':
            count = 6
            section, key = string(a(0)).lower(), string(a(1)).lower()
            values = CONFIG if section == 'nfs5' else {'file': 'dx7z.dll', 'type': 'd3d'} if section == 'thrash' else {}
            value = values.get(key, string(a(2)))
            data = value.encode('cp1252')[:max(0, a(4) - 1)]
            if a(4):
                uc.mem_write(a(3), data + b'\0')
            result = len(data)
        elif name == 'strrchr':
            data = string(a(0)).encode('cp1252')
            pos = (data + b'\0').rfind(bytes([a(1) & 255]))
            result = a(0) + pos if pos >= 0 else 0
        elif name == '_stricmp':
            left, right = string(a(0)).lower(), string(a(1)).lower()
            result = (left > right) - (left < right)
        elif name == 'CreateActCtxA':
            count, result = 1, 0xffffffff
        else:
            raise ValueError(f'unexpected patch initializer API: {name}')
        uc.reg_write(UC_X86_REG_EAX, result & 0xffffffff)
        uc.reg_write(UC_X86_REG_EIP, read32(sp))
        uc.reg_write(UC_X86_REG_ESP, sp + 4 + count * 4)

    uc.hook_add(UC_HOOK_CODE, hook)

    def run(address, args):
        stack = 0x101f000
        uc.mem_write(stack, struct.pack('<' + 'I' * (len(args) + 1), 0xff000000, *args))
        uc.reg_write(UC_X86_REG_ESP, stack)
        uc.emu_start(address, 0xff000000, timeout=5_000_000, count=1_000_000)
        if uc.reg_read(UC_X86_REG_EIP) != 0xff000000:
            raise ValueError('patch initializer did not finish within its execution limit')

    run(PATCH_BASE + dll.OPTIONAL_HEADER.AddressOfEntryPoint, [PATCH_BASE, 1, 0])
    run(PATCH_BASE + 0x22b0, [BASE])
    frozen = bytearray(uc.mem_read(BASE, len(memory)))
    changed = sum(a != b for a, b in zip(memory[:exe.OPTIONAL_HEADER.SizeOfImage], frozen))
    # Config changes must exist before lifting. Do not repeat self-modifying
    # initialization when the original WinMain hook executes in native code.
    frozen[PATCH_BASE - BASE + 0x2882:PATCH_BASE - BASE + 0x2887] = b'\x90' * 5
    # Keep the merged import table's original IAT entries; platform_init binds
    # these to the very same indexed native thunks used during initialization.
    sections = []
    for pe, base in images:
        for s in pe.sections:
            name = s.Name if base == BASE else b'.v' + s.Name[1:6]
            start = base - BASE + s.VirtualAddress
            size = max(s.Misc_VirtualSize, s.SizeOfRawData)
            sections.append((name, start, bytes(frozen[start:start + size]), s.Characteristics))
    sections.append((b'.imports', IMPORT_RVA, bytes(frozen[IMPORT_RVA:]), 0xc0000040))
    result = bytearray(exe_data[:4096])
    section_start = exe.sections[0].get_file_offset()
    result[section_start:] = bytes(4096 - section_start)
    struct.pack_into('<H', result, exe.FILE_HEADER.get_field_absolute_offset('NumberOfSections'), len(sections))
    struct.pack_into('<I', result, exe.OPTIONAL_HEADER.get_field_absolute_offset('SizeOfHeaders'), 4096)
    struct.pack_into('<I', result, exe.OPTIONAL_HEADER.get_field_absolute_offset('SizeOfImage'), align(len(frozen), 4096))
    struct.pack_into('<I', result, exe.OPTIONAL_HEADER.get_field_absolute_offset('CheckSum'), 0)
    for i, (name, rva, data, flags) in enumerate(sections):
        raw_size = align(len(data), 512)
        struct.pack_into('<8sIIIIIIHHI', result, section_start + i * 40, name, len(data), rva,
                         raw_size, len(result), 0, 0, 0, 0, flags)
        result.extend(data + bytes(raw_size - len(data)))
    for i in (0, 4, 5, 11, 12):  # exports, certificates, relocation, bound import, IAT
        struct.pack_into('<II', result, exe.OPTIONAL_HEADER.DATA_DIRECTORY[i].get_file_offset(), 0, 0)
    struct.pack_into('<II', result, exe.OPTIONAL_HEADER.DATA_DIRECTORY[1].get_file_offset(), IMPORT_RVA, 20 * (len(groups) + 1))
    return bytes(result), {'changed_bytes': changed, 'initializer_apis': sorted(api_calls), 'config': CONFIG,
                           'exe_sha256': EXE_SHA, 'dll_sha256': DLL_SHA, 'sha256': sha(result)}


def overlay_path(root, relative):
    """Use Windows path matching even on a case-sensitive build volume."""
    target = Path(root)
    for part in relative.parts:
        matches = [p for p in target.iterdir() if p.name.casefold() == part.casefold()] if target.is_dir() else []
        if len(matches) > 1:
            raise ValueError(f'ambiguous patch destination: {relative}')
        target = matches[0] if matches else target / part
    return target


def installed_entries(patch):
    """The Combined Patch archive members that preparation installs, with their game-relative paths."""
    for entry in patch.infolist():
        path = PurePosixPath(entry.filename)
        if entry.is_dir() or not path.parts or path.parts[0] != 'Copy':
            continue
        parts = path.parts[1:]
        if not parts or any(p in ('', '.', '..') or '\\' in p or ':' in p for p in parts):
            raise ValueError('unsafe patch path')
        # Native Metal and Cocoa replace the Windows wrappers/configurator.
        if parts[0] not in ('FEData', 'GameData', 'SaveData') and str(path) not in ('Copy/version.txt', 'Copy/Drivers/dx7/thrash.ini'):
            continue
        yield entry, PurePosixPath(*parts)


def prepare_game(disc, combined, silent, destination):
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise FileExistsError('game destination already exists')
    with verified_archive(combined, (COMBINED_SHA, COMBINED_MIRROR_SHA)) as patch, verified_archive(silent, SILENT_SHA):
        # Verify and link before extracting or writing any destination files.
        linked, report = link_patch(patch.read('Copy/nfs5.exe'), patch.read('Copy/nfs5.dll'))
        if Path(disc).is_dir():
            source = verify_game(disc)
            copy_game(source, destination)
            source_files = len(source.files)
        else:
            with Disc(disc) as source:
                source_files = len(source.extract(destination))
        try:
            applied = []
            for entry, relative in installed_entries(patch):
                target = overlay_path(destination, relative)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(patch.read(entry))
                applied.append(str(relative))
            (destination / 'Porsche.exe').write_bytes(linked)
            # Reference originals and all upstream notices stay local beside the assets.
            # Upstream documentation stays beside the privately prepared files;
            # the complete archives stay in the external download cache.
            notices = destination / 'PatchNotices'
            notices.mkdir()
            for entry in patch.infolist():
                if not entry.is_dir() and (entry.filename.startswith('Docs/') or entry.filename == 'Readme.txt'):
                    (notices / PurePosixPath(entry.filename).name).write_bytes(patch.read(entry))
            with ZipFile(silent) as upstream:
                (notices / 'SilentPatch-ReadMe.txt').write_bytes(upstream.read('ReadMe.txt'))
            report.update({'combined_sha256': sha(Path(combined).read_bytes()), 'silent_sha256': SILENT_SHA,
                           'source_files': source_files, 'applied': applied})
            (destination / 'patch-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
        except BaseException:
            shutil.rmtree(destination)
            raise
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('cue', type=Path)
    p.add_argument('patches', type=Path)
    p.add_argument('destination', type=Path)
    a = p.parse_args()
    report = prepare_game(a.cue, a.patches / 'NFS5-Combined-Patch-v1.1.zip',
                          a.patches / 'SilentPatchNFS90s.zip', a.destination)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

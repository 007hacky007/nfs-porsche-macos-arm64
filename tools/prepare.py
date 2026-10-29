#!/usr/bin/env python3
"""Validate the supported game image and generate native compilation inputs."""
import argparse
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools.inspect_pe import inspect_pe, require_supported
import pefile
import capstone


def pointer_seeds(pe):
    base = pe.OPTIONAL_HEADER.ImageBase
    ranges = [(base + s.VirtualAddress, base + s.VirtualAddress + s.Misc_VirtualSize)
              for s in pe.sections if s.Characteristics & 0x20000000]
    in_text = lambda value: any(lo <= value < hi for lo, hi in ranges)
    seeds = set()
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True
    md.skipdata = True
    mapped = pe.get_memory_mapped_image()
    for section in pe.sections:
        data = section.get_data()
        for offset in range(0, len(data) - 3, 4):
            value = struct.unpack_from('<I', data, offset)[0]
            if in_text(value):
                seeds.add(value)
        if section.Characteristics & 0x20000000:
            for instruction in md.disasm(data, base + section.VirtualAddress):
                if instruction.id and instruction.mnemonic == 'jmp' and instruction.operands[0].type == capstone.CS_OP_MEM:
                    operand = instruction.operands[0].mem
                    if not operand.base and operand.index and operand.scale == 4:
                        # Watcom/CRT jump tables need not be DWORD-aligned.
                        offset = operand.disp - base
                        for _ in range(4096):
                            if offset < 0 or offset + 4 > len(mapped):
                                break
                            target = struct.unpack_from('<I', mapped, offset)[0]
                            if not in_text(target):
                                break
                            seeds.add(target)
                            offset += 4
                if instruction.id and instruction.mnemonic in ('mov', 'push', 'lea'):
                    for op in instruction.operands:
                        if op.type == capstone.CS_OP_IMM and in_text(op.imm):
                            seeds.add(op.imm)
    return seeds


def prepare(path):
    info = inspect_pe(path)
    require_supported(info)
    pe = pefile.PE(str(path))
    output = ROOT / 'out'
    generated = ROOT / 'gen/all'
    output.mkdir(exist_ok=True)
    generated.mkdir(parents=True, exist_ok=True)
    (output / 'image.json').write_text(json.dumps(info, indent=2) + '\n')
    (output / 'relocs.txt').write_text(''.join(f'{a:08x}\n' for a in info['relocations']))
    seeds = {info['entry']}
    if 'native-linked' in require_supported(info):
        # The supplied patched EXE has its relocation table stripped. Recover
        # stored function pointers, including the patch's continuation targets.
        seeds.update(pointer_seeds(pe))
    if hasattr(pe, 'DIRECTORY_ENTRY_TLS'):
        addr = pe.DIRECTORY_ENTRY_TLS.struct.AddressOfCallBacks
        for index in range(128):
            value = struct.unpack('<I', pe.get_data(addr - info['base'] + index * 4, 4))[0]
            if not value:
                break
            seeds.add(value)
        else:
            raise ValueError('unterminated TLS callback array')
    (output / 'seeds.txt').write_text(''.join(f'{a:08x}\n' for a in sorted(seeds)))
    counts = json.loads((ROOT / 'tools/win32_args.json').read_text())
    counts.update({
        'CreateProcessA':10, 'SetEnvironmentVariableW':2, 'FormatMessageA':7,
        'GetCommProperties':2, 'WaitForMultipleObjectsEx':5, 'PulseEvent':1,
        'DisableThreadLibraryCalls':1, 'OpenSemaphoreA':3, 'OpenMutexA':3,
        'OpenFileMappingA':3, 'GetCommModemStatus':2, 'GetVolumeInformationA':8,
        'GetLogicalDriveStringsA':2, 'ReleaseDC':2, 'GetWindowDC':1, 'GetKeyState':1,
        'keybd_event':4, 'CharUpperA':1, 'GetKeyboardType':1, 'FindWindowA':2,
        'AdjustWindowRectEx':4, 'CallNextHookEx':4, 'SetWindowsHookExA':4,
        'SendNotifyMessageA':4, 'UnhookWindowsHookEx':1, 'RegisterClassA':1,
        'SystemParametersInfoA':4, 'DirectInputCreateA':4, 'DirectDrawEnumerateA':2,
        '__WSAFDIsSet':2, 'GetFileVersionInfoA':4, 'VerQueryValueA':4,
        'GetFileVersionInfoSizeA':2, '#6':5,
        '_CItan':0, '_CIatan2':0, 'strrchr':0, 'strchr':0, '_stricmp':0,
        'GetWindowPlacement':2, 'SetWindowPlacement':2, 'GetWindowRect':2,
        'MonitorFromWindow':2, 'GetMonitorInfoA':2, 'SetErrorMode':1,
        'CreateActCtxA':1, 'ReleaseActCtx':1, 'ActivateActCtx':2, 'DeactivateActCtx':2,
        'GetPrivateProfileIntA':4, 'GetPrivateProfileStringA':6,
    })
    imports = []
    for m in info['imports']:
        for s in m['symbols']:
            # The updater's exports are cdecl (plain ret in the supplied DLL).
            nargs = 0 if m['dll'].lower() == 'mrbupd.dll' else counts.get(s['name'])
            if nargs is None:
                raise ValueError(f"unknown calling convention: {m['dll']}!{s['name']}")
            imports.append((s['iat'], m['dll'], s['name'], nargs))
    sections = info['sections']
    executable = [s for s in sections if s['executable']]
    lo = min(s['address'] for s in executable)
    hi = max(s['address'] + s['virtual_size'] for s in executable)
    header = '''#ifndef NFSV_IMAGE_H
#define NFSV_IMAGE_H
#include <stdint.h>
typedef struct { uint32_t address, offset, size; } ImageSection;
typedef struct { uint32_t iat; const char *dll, *name; int nargs; } Import;
extern const ImageSection nfsv_sections[];
extern const uint32_t nfsv_section_count;
extern const Import nfsv_imports[];
extern const uint32_t nfsv_import_count;
'''
    for name, value in [('IMAGE_BASE',info['base']),('IMAGE_SIZE',info['image_size']),
                        ('IMAGE_ENTRY',info['entry']),('IMAGE_FILE_SIZE',info['bytes']),
                        ('DISPATCH_TEXT_BASE',lo),('DISPATCH_TEXT_SIZE',hi-lo)]:
        header += f'#define {name} 0x{value:x}u\n'
    header += f'#define IMAGE_SHA256 "{info["sha256"]}"\n#endif\n'
    mapped = pe.get_memory_mapped_image()
    keyboard = list(re.finditer(rb'\x68....\xe8....\x8b\x54\x24\x28\x8b\x44\x24\x20', mapped))
    if len(keyboard) != 1:
        raise ValueError('cannot identify the original keyboard buffer for focus-loss fix')
    key_buffer = struct.unpack_from('<I', mapped, keyboard[0].start() + 1)[0]
    header = header.replace('#endif\n', f'#define GAME_KEYBOARD_BUFFER 0x{key_buffer:x}u\n#endif\n')
    (generated / 'image.h').write_text(header)
    source = '#include "image.h"\n'
    source += f'const uint32_t nfsv_section_count = {len(sections)};\n'
    source += 'const ImageSection nfsv_sections[] = {\n'
    for s in sections:
        size = min(s['raw_size'], s['virtual_size'] or s['raw_size'])
        if s['raw_offset'] + size > info['bytes'] or s['address'] + size > info['base'] + info['image_size']:
            raise ValueError('section extends beyond the verified file or mapped image')
        source += f'{{0x{s["address"]:x}u,0x{s["raw_offset"]:x}u,{size}u}},\n'
    source += '};\n'
    source += f'const uint32_t nfsv_import_count = {len(imports)};\nconst Import nfsv_imports[] = {{\n'
    for iat, dll, name, nargs in imports:
        source += f'{{0x{iat:x}u,{json.dumps(dll)},{json.dumps(name)},{nargs}}},\n'
    source += '};\n'
    (generated / 'image.c').write_text(source)
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--metadata-only', action='store_true')
    args = parser.parse_args()
    image = args.image.resolve()
    os.chdir(ROOT)
    info = prepare(image)
    print(f"Verified {require_supported(info)}: entry 0x{info['entry']:x}, {len(info['relocations'])} fixups", flush=True)
    if not args.metadata_only:
        env = dict(os.environ, SEEDS='out/seeds.txt', X87PC='1', WATCH='1')
        subprocess.run([sys.executable, 'tools/genall.py', str(image), '64'], env=env, check=True)


if __name__ == '__main__':
    main()

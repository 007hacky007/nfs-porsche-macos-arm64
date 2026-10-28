#!/usr/bin/env python3
"""Validate the supported game image and generate native compilation inputs."""
import argparse
import json
import os
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools.inspect_pe import inspect_pe, require_supported
import pefile


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

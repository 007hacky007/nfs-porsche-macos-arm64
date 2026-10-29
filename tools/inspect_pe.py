#!/usr/bin/env python3
"""Inspect PE32 game inputs without executing them."""
import argparse
import hashlib
import json
from pathlib import Path

import pefile


# Populated only after a source and plaintext image have been verified.
SUPPORTED = {
    '13273410b8951e3785a5def780667d6101b1f72e8ac8fd9561f13b3cf724267b': 'NFSV Combined Patch v1.1 native-linked',
    '02437ddbf41af86dffe14251b28ed8889bd1c4c904fe77ff730d8912257ec90d': 'NFSV v3.5 USA',
}
PROTECTED = {
    '4b7bc7fc134f3e6145b9ad5dea1938085e9562344a088279d216f08a1543e9d8': 'SafeDisc disc loader',
    'd29edd10735246553b8d783e9a930d790b14c684b6c2b178266cb39af44eb7b6': 'SafeDisc encrypted ICD',
}


class UnsupportedImage(ValueError):
    pass


def require_supported(info):
    if info.get('protection'):
        raise UnsupportedImage('protected executable: ' + ', '.join(info['protection']))
    if info['machine'] != 0x14c:
        raise UnsupportedImage('expected a PE32 x86 executable')
    if info['sha256'] not in SUPPORTED:
        raise UnsupportedImage(f"unsupported executable SHA-256: {info['sha256']}")
    return SUPPORTED[info['sha256']]


def inspect_pe(path):
    data = Path(path).read_bytes()
    pe = pefile.PE(data=data)
    base = pe.OPTIONAL_HEADER.ImageBase
    sha = hashlib.sha256(data).hexdigest()
    sections = []
    for s in pe.sections:
        sections.append({'name': s.Name.rstrip(b'\0').decode('ascii', errors='replace'),
                         'address': base + s.VirtualAddress, 'virtual_size': s.Misc_VirtualSize,
                         'raw_offset': s.PointerToRawData, 'raw_size': s.SizeOfRawData,
                         'executable': bool(s.Characteristics & 0x20000000),
                         'entropy': round(s.get_entropy(), 4)})
    imports = []
    for module in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', []):
        imports.append({'dll': module.dll.decode('ascii'),
                        'symbols': [{'name': i.name.decode('ascii') if i.name else f'#{i.ordinal}',
                                     'iat': i.address} for i in module.imports]})
    relocs = [base + e.rva for block in getattr(pe, 'DIRECTORY_ENTRY_BASERELOC', [])
              for e in block.entries if e.type == 3]
    exports = [{'name': e.name.decode('ascii') if e.name else None, 'ordinal': e.ordinal,
                'address': base + e.address} for e in
               getattr(getattr(pe, 'DIRECTORY_ENTRY_EXPORT', None), 'symbols', [])]
    return {'bytes': len(data), 'sha256': sha, 'md5': hashlib.md5(data).hexdigest(),
            'machine': pe.FILE_HEADER.Machine, 'optional_magic': pe.OPTIONAL_HEADER.Magic,
            'base': base, 'entry': base + pe.OPTIONAL_HEADER.AddressOfEntryPoint,
            'image_size': pe.OPTIONAL_HEADER.SizeOfImage,
            'entry_bytes': pe.get_data(pe.OPTIONAL_HEADER.AddressOfEntryPoint, 32).hex(),
            'sections': sections, 'imports': imports, 'exports': exports,
            'relocations': relocs, 'protection': [PROTECTED[sha]] if sha in PROTECTED else [],
            'directories': {d.name: {'rva': d.VirtualAddress, 'size': d.Size}
                            for d in pe.OPTIONAL_HEADER.DATA_DIRECTORY if d.Size}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--supported', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    info = inspect_pe(args.image)
    if args.supported:
        require_supported(info)
    result = json.dumps(info, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result)
    else:
        print(result, end='')


if __name__ == '__main__':
    main()

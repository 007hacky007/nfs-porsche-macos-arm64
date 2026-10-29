#!/usr/bin/env python3
"""Compare lifted codec math with original x86 instructions, for this image only."""
import struct
import sys
from pathlib import Path
import pefile
from unicorn import Uc,UC_ARCH_X86,UC_MODE_32
from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_FPCW,UC_X86_REG_EIP

game=Path(sys.argv[1] if len(sys.argv)>1 else 'local/game-patched')
p=pefile.PE(str(game/'Porsche.exe'))
u=Uc(UC_ARCH_X86,UC_MODE_32)
u.mem_map(0x400000,(p.OPTIONAL_HEADER.SizeOfImage+4095)&~4095)
u.mem_write(0x400000,p.get_memory_mapped_image())
u.mem_map(0xc00000,0x20000)
u.mem_map(0x7f000000,0x10000)
u.mem_map(0x80000000,0x1000)
u.reg_write(UC_X86_REG_FPCW,0x37f)
def call(fn,args):
    sp=0x7f00f000
    u.mem_write(sp,struct.pack('<'+'I'*(len(args)+1),0x80000000,*args))
    u.reg_write(UC_X86_REG_ESP,sp)
    u.emu_start(fn,0x80000000,count=50000000)
    assert u.reg_read(UC_X86_REG_EIP)==0x80000000,hex(fn)+" did not return"

call(0x56ad70,[16])
expected=bytes(u.mem_read(0x6b62a0,0x2000))
actual=Path('out/codec-tables.bin').read_bytes()
differences=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
print('table byte differences:',len(differences))
for i in differences[:12]:print(hex(0x6b62a0+i),hex(actual[i]),hex(expected[i]))
for v in [0x80808080,0x10801080,0xeb80eb80,0x00800080,0xff80ff80]:
    u.mem_write(0xc02000,struct.pack('<I',v))
    call(0x592610,[0xc02000,0xc02020,1])
    print(f'{v:08x} -> {struct.unpack("<I",u.mem_read(0xc02020,4))[0]:08x}')
assert not differences,'native codec initialization differs from original x86'
u.mem_map(0x2000000,0x100000)
u.mem_write(0x2080000,(game/'FEData/movies/earts-av.mad').read_bytes())
movie=(game/'FEData/movies/earts-av.mad').read_bytes()
offset=decoded=0
while offset+24<len(movie) and decoded<12:
    tag=movie[offset:offset+4];length=struct.unpack_from('<I',movie,offset+4)[0]&0xffffff
    assert length>=8 and offset+length<=len(movie)
    if tag[:3]==b'MAD':
        packet=0x2080000+offset
        call(0x56ca50,[packet+24,int(tag[3:]!=b'k'),movie[offset+21]])
        for y in range(0,240,16):
            for x in range(0,320,16):
                at=(y*320+x)*2
                call(0x56cce0,[0x2010000+at,0x2050000+at,320])
        u.mem_write(0x2010000,bytes(u.mem_read(0x2050000,320*240*2)))
        decoded+=1
    offset+=length
reference=bytes(u.mem_read(0x2050000,320*240*2))
assert any(reference),'reference frame must contain actual image data'
Path('out/codec-frame-reference.bin').write_bytes(reference)
actual=Path('out/codec-frame.bin').read_bytes()
differences=[i for i,(a,b) in enumerate(zip(reference,actual)) if a!=b]
print('decoded frame byte differences:',len(differences))
for i in differences[:12]:print(hex(i),hex(actual[i]),hex(reference[i]))
assert not differences,'native decoder differs from original x86'
u.mem_map(0x2200000,0x100000)
u.mem_write(0x5de620,struct.pack('<12I',0x57494e44,640,480,0x01101078,1,0,0,640,200,1280,0,0x2200000))
call(0x56a920,[0,0,0x2050000,320,240,3])
reference=bytes(u.mem_read(0x2200000,640*480*2))
actual=Path('out/codec-blit.bin').read_bytes()
differences=[i for i,(a,b) in enumerate(zip(reference,actual)) if a!=b]
print('scaled blit byte differences:',len(differences))
for i in differences[:12]:print(hex(i),hex(actual[i]),hex(reference[i]))
assert not differences,'native video scaler differs from original x86'

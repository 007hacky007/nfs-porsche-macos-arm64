#!/usr/bin/env python3
"""Build and run native regression tests after build.py has compiled the runtime."""
from pathlib import Path
import os
import subprocess
ROOT=Path(__file__).resolve().parent.parent
os.chdir(ROOT)

def run(args):
    subprocess.run(args,check=True)

run(['clang','-Iruntime','tests/pixels.c','runtime/pixels.c','-o','out/pixels-test'])
run(['out/pixels-test'])
run(['clang','-Iruntime','tests/display.c','runtime/display.c','-o','out/display-test'])
run(['out/display-test'])
run(['clang','-DNFSV_NO_IMAGE','-Iruntime','tests/memory.c','runtime/memory.c','-o','out/memory-test'])
run(['out/memory-test'])
run(['clang','-O1','-DNFSV_NO_IMAGE','-Iruntime','tests/audio.c','runtime/audio.m','runtime/memory.c',
     '-framework','AudioUnit','-framework','AudioToolbox','-framework','CoreAudio','-o','out/audio-test'])
run(['out/audio-test'])
objects=sorted(str(p) for p in Path('out/obj').glob('runtime_*.o') if p.name not in ('runtime_main.m.o','runtime_host.m.o'))
run(['clang','-O1','-fobjc-arc','-Iruntime','-Igen/all','-include','gen/all/image.h','tests/platform.c','tests/platform_host.m','tests/io_faults.c',*objects,
     'out/obj/gen_all_image.c.o','-framework','Cocoa','-framework','Metal','-framework','QuartzCore',
     '-framework','AudioUnit','-framework','AudioToolbox','-framework','CoreAudio','-o','out/platform-test'])
run(['out/platform-test'])
run(['clang','-O1','-fobjc-arc','-Iruntime','-Igen/all','tests/metal.m','runtime/metal.m',
     '-framework','Cocoa','-framework','Metal','-framework','QuartzCore','-o','out/metal-test'])
run(['out/metal-test'])
run(['clang','-O1','-fobjc-arc','-Iruntime','tests/host.m','runtime/host.m','runtime/input.c','runtime/display.c',
     '-framework','Cocoa','-framework','Metal','-framework','QuartzCore','-o','out/host-test'])
run(['out/host-test'])

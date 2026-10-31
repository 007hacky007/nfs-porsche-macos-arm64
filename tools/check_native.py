#!/usr/bin/env python3
"""Build and run native regression tests after ./build.sh has compiled the runtime."""
from pathlib import Path
import os
import subprocess
import sys
ROOT=Path(__file__).resolve().parent.parent
os.chdir(ROOT)
PORTABLE='--portable' in sys.argv
if PORTABLE: os.makedirs('out',exist_ok=True)

def run(args):
    subprocess.run(args,check=True)

run(['clang','-Iruntime','tests/pixels.c','runtime/pixels.c','-o','out/pixels-test'])
run(['out/pixels-test'])
run(['clang','-Iruntime','tests/display.c','runtime/display.c','-o','out/display-test'])
run(['out/display-test'])
if not PORTABLE:
    run(['clang','-O1','-fobjc-arc','tests/launcher.m','launcher/settings.m','runtime/display.c',
         '-framework','Cocoa','-o','out/launcher-test'])
    run(['out/launcher-test'])
    run(['clang','-O1','-DNFSV_NO_IMAGE','-Iruntime','-include','gen/all/image.h',
         'tests/launch_settings.c','runtime/launch_settings.c','runtime/display.c','runtime/memory.c','-o','out/launch-settings-test'])
    run(['out/launch-settings-test'])
run(['clang','-O1','-DNFSV_NO_IMAGE','-Iruntime','tests/hud.c','runtime/hud.c','runtime/memory.c','-o','out/hud-test'])
run(['out/hud-test'])
run(['clang','-O1','-DNFSV_NO_IMAGE','-Iruntime','tests/frontend.c','runtime/frontend.c','runtime/memory.c','-o','out/frontend-test'])
run(['out/frontend-test'])
run(['clang','-DNFSV_NO_IMAGE','-Iruntime','tests/memory.c','runtime/memory.c','-o','out/memory-test'])
run(['out/memory-test'])
if not PORTABLE:
    run(['clang','-O1','-DNFSV_NO_IMAGE','-Iruntime','tests/audio.c','runtime/audio.m','runtime/memory.c',
         '-framework','AudioUnit','-framework','AudioToolbox','-framework','CoreAudio','-o','out/audio-test'])
    run(['out/audio-test'])
    objects=sorted(str(p) for p in Path('out/obj').glob('runtime_*.o') if p.name not in ('runtime_main.m.o','runtime_host.m.o'))
    run(['clang','-O1','-fobjc-arc','-Iruntime','-Igen/all','-include','gen/all/image.h','tests/platform.c','tests/platform_host.m','tests/io_faults.c',*objects,
         'out/obj/gen_all_image.c.o','-framework','Cocoa','-framework','Metal','-framework','QuartzCore',
         '-framework','AudioUnit','-framework','AudioToolbox','-framework','CoreAudio','-framework','GameController','-o','out/platform-test'])
    run(['out/platform-test'])
    run(['clang','-O1','-fobjc-arc','-Iruntime','-Igen/all','tests/metal.m','runtime/metal.m','runtime/hud.c','runtime/display.c',
         '-framework','Cocoa','-framework','Metal','-framework','QuartzCore','-o','out/metal-test'])
    run(['out/metal-test'])
    subprocess.run(['out/metal-test'],check=True,env={**os.environ,'NFSV_ENHANCED_GRAPHICS':'0'})
    run(['clang','-O1','-fobjc-arc','-Iruntime','tests/host.m','runtime/host.m','runtime/input.c','runtime/display.c',
         '-framework','Cocoa','-framework','Metal','-framework','QuartzCore','-o','out/host-test'])
    run(['out/host-test'])

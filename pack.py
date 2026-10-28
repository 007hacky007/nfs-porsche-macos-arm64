#!/usr/bin/env python3
"""Build a local native Mac app with external game assets."""
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent
os.chdir(ROOT)
app=ROOT/'out/NFSV.app'
if not Path('out/nfsv').is_file() or not Path('gen/all/image.h').is_file():
    raise SystemExit('Run tools/prepare.py and build.py first.')
contents=app/'Contents'
macos=contents/'MacOS'
macos.mkdir(parents=True,exist_ok=True)
subprocess.run(['clang','-O2','-fobjc-arc','-arch','arm64','-mmacosx-version-min=11.0',
                '-Igen/all','launcher/main.m','-framework','Cocoa','-o',str(macos/'NFSV')],check=True)
shutil.copy2('out/nfsv',macos/'NFSVEngine')
plist={
    'CFBundleIdentifier':'org.nfsv.local',
    'CFBundleName':'NFSV','CFBundleDisplayName':'NFSV','CFBundleExecutable':'NFSV',
    'CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1','CFBundleVersion':'1',
    'LSMinimumSystemVersion':'11.0','LSMultipleInstancesProhibited':True,
    'NSHighResolutionCapable':True,
}
with (contents/'Info.plist').open('wb') as f:plistlib.dump(plist,f)
subprocess.run(['codesign','--force','--sign','-',str(macos/'NFSVEngine')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('Built out/NFSV.app with external game assets')

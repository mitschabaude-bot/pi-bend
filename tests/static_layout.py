"""Compiler regression: converted literal fields must not enter STAT_IMG."""
import os
from pathlib import Path
from bend_toolchain import BEND
import shutil
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
source=ROOT/'tests/static-layout.bend'
output=BUILD/'test-static-layout'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=30)
bend=BEND
js=BUILD/'test-static-layout.js'
subprocess.run([bend,str(source),'-o',str(js)],cwd=ROOT,check=True)
bun=shutil.which('bun') or str(Path.home()/'.bun/bin/bun')
subprocess.run([bun,str(js)],cwd=ROOT,check=True,timeout=30)

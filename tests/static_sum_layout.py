"""Compiler regression: convert only the live arm of a static sum."""
import os,shutil,subprocess
from pathlib import Path
from bend_toolchain import BEND
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build';BUILD.mkdir(exist_ok=True)
source=ROOT/'tests/static-sum-layout.bend';output=BUILD/'test-static-sum-layout'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=30)
bend=BEND;js=BUILD/'test-static-sum-layout.js'
subprocess.run([bend,str(source),'-o',str(js)],cwd=ROOT,check=True)
subprocess.run([shutil.which('bun') or str(Path.home()/'.bun/bin/bun'),str(js)],cwd=ROOT,check=True,timeout=30)

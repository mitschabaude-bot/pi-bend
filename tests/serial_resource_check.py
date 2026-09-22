"""Affine retirement and async exclusion for reusable resource handles."""
import os
from pathlib import Path
from bend_toolchain import BEND
import subprocess

ROOT=Path(__file__).resolve().parents[1]
(ROOT/'build').mkdir(exist_ok=True)
negative=ROOT/'build/serial-resource-owner-duplicate.bend'
negative.write_text('import Base\nimport ../packages/runtime/src/serial-resource.bend as Serial\ndef duplicate(+owner: Serial.Owner<Unit>) -> Serial.Owner<Unit> & Serial.Owner<Unit>:\n  (owner, owner)\n')
result=subprocess.run([BEND,str(negative)],cwd=ROOT,capture_output=True,text=True,timeout=30)
diagnostic=result.stdout+result.stderr
assert result.returncode!=0 and 'expected : Data' in diagnostic and 'observed : Type' in diagnostic,diagnostic
print('PASS serial resource ownership cannot be duplicated',flush=True)
subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/serial-resource.bend','build/test-serial-resource'],cwd=ROOT,check=True)
for threads in ['1','4']:
    subprocess.run([str(ROOT/'build/test-serial-resource'),'--threads',threads],cwd=ROOT,check=True,timeout=30)

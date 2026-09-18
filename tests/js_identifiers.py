"""Compiler regression: module punctuation must form distinct valid JS names."""
import os
from pathlib import Path
import shutil
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/js-identifiers'
BUILD.mkdir(parents=True,exist_ok=True)
BEND=os.environ.get('BEND',str(Path.home()/'.bend/bin/bend'))
names=['a-b','a_b','a$2d$b','café']
lines=['import Base']
for index,name in enumerate(names):
    (BUILD/(name+'.bend')).write_text(f'import Base\ndef value() -> U32: {index+1}\n')
    lines.append(f'import ./{name}.bend as M{index}')
lines += ['def check(actual: U32, expected: U32) -> IO(Unit):','  Bool.pick(IO(Unit), U32.is_eq(actual, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "module symbol collision"))','def main() -> IO(Unit):','  do IO<Unit>:']
for index in range(len(names)): lines.append(f'    check(M{index}.value(), {index+1})')
lines.append('    IO.print("PASS hyphen, underscore, escape-marker and Unicode module identifiers")')
source=BUILD/'main.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'main.js'
subprocess.run([BEND,str(source),'-o',str(output)],cwd=ROOT,check=True)
bun=shutil.which('bun') or str(Path.home()/'.bun/bin/bun')
subprocess.run([bun,str(output)],check=True,timeout=30)

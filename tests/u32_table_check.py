"""Exact/predecessor lookup boundaries, absent values, empty and singleton tables."""
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
tables={'e':{},'z':{0:17},'m':{4294967295:19},'t':{2:20,5:50,100:1000,4294967295:99}}
arguments=[]
expected=[]
for kind,table in tables.items():
    for key in [*range(131),2147483647,2147483648,4294967294,4294967295]:
        candidates=[index for index in table if index<=key]
        floor=table[max(candidates)] if candidates else '-'
        arguments.append(f'{kind};{key}')
        expected.append(f'{table.get(key,"-")};{floor}')
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/u32-table.bend','build/u32-table'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/u32-table.bend','-o','build/u32-table.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/u32-table','--threads','1']),('native 4',['build/u32-table','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/u32-table.js'])]:
    result=subprocess.run([*command,*arguments],cwd=ROOT,text=True,capture_output=True,timeout=30)
    assert result.returncode==0,(label,result.stderr)
    assert result.stdout.splitlines()==expected,(label,result.stdout[:1000])
    print(f'{label}: {len(arguments)} exact/predecessor lookup pairs PASS',flush=True)

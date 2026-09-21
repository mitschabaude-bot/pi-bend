"""Runtime stack regression for wide immutable JSON containers."""
import os
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
if '--no-build' not in sys.argv:
    commands=[['sh','scripts/build-pure.sh','tests/json-finite-growth.bend','build/json-finite-growth'],[os.environ.get('BEND',str(Path.home()/'.bend/bin/bend')),'tests/json-finite-growth.bend','-o','build/json-finite-growth.js']]
    for index,command in enumerate(commands):
        subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib','4','--stats',f'build/json-finite-growth-rebuild-{index}.json','--',*command],cwd=ROOT,check=True)
for label,command in [('native 1',['build/json-finite-growth','--threads','1']),('native 4',['build/json-finite-growth','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/json-finite-growth.js'])]:
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=30)
    assert result.returncode==0 and result.stdout=='PASS finite array\nPASS finite object\n' and not result.stderr,(label,result)
    print(f'{label}: 65536-entry array and object PASS',flush=True)

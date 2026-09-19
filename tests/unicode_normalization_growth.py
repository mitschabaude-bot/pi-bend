"""Long combining runs: check normalized length and order checksum against ICU."""
import json
from pathlib import Path
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
rows = [(mode, count) for mode in ['gc', 'gd'] for count in [0, 1, 64, 1024, 4096, 16384, 32768]]
oracle = r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(([mode,count])=>{
 const text=('a'+'\u0315\u0300'.repeat(count)).normalize(mode==='gc'?'NFC':'NFD');
 let hash=2166136261,length=0;
 for(const c of text){hash=(Math.imul(hash,16777619)^c.codePointAt(0))>>>0;length++;}
 return length+';'+hash;
})));
'''
expected = json.loads(subprocess.check_output(['node','-e',oracle],input=json.dumps(rows),text=True))
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/unicode-normalization.bend','build/unicode-normalization'],cwd=ROOT,check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/unicode-normalization.bend','-o','build/unicode-normalization.js'],cwd=ROOT,check=True)
for label, command in [('native 1',['build/unicode-normalization','--threads','1']),('native 4',['build/unicode-normalization','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/unicode-normalization.js'])]:
    for (mode,count),want in zip(rows,expected,strict=True):
        result=subprocess.run([*command,f'{mode};{count}'],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,mode,count,result.stderr)
        assert result.stdout.strip()==want,(label,mode,count,result.stdout,want)
    print(f'{label}: {len(rows)} combining-run growth cases PASS',flush=True)

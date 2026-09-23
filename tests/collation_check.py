"""Exact String.prototype.localeCompare (Node 24, ICU 78.3, en-US) on every backend."""
import argparse,json,os,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
env={**os.environ,'LANG':'en_US.UTF-8','LC_ALL':'en_US.UTF-8'}
version=json.loads(subprocess.check_output(['node','-p','JSON.stringify({icu:process.versions.icu,unicode:process.versions.unicode,cldr:process.versions.cldr,locale:new Intl.Collator().resolvedOptions().locale})'],text=True,env=env))
assert version=={'icu':'78.3','unicode':'17.0','cldr':'48.0','locale':'en-US'},version
pairs=ROOT/'build/collation-pairs.tsv';strings=ROOT/'build/collation-sort.txt'
print(subprocess.check_output(['node','tests/collation_reference.mjs',str(pairs),str(strings)],cwd=ROOT,text=True,env=env,timeout=300).strip(),flush=True)
count=sum(1 for _ in pairs.open())
lines=strings.read_text().split('\n')[:-1]
order=[int(x) for x in (ROOT/'build/collation-sort.txt.order').read_text().split()]
expected='\n'.join(lines[i] for i in order)
for backend in a.backends:
 cmd=['bun','build/collation.js'] if backend=='bun' else ['build/collation','--threads',backend[-1],'--']
 start=time.monotonic();result=subprocess.run(cmd+['pairs',str(pairs)],cwd=ROOT,capture_output=True,text=True,timeout=900)
 assert result.returncode==0 and not result.stderr and result.stdout.strip()==str(count),(backend,result.returncode,result.stderr[-2000:],result.stdout[-2000:])
 sorted_=subprocess.run(cmd+['sort',str(strings)],cwd=ROOT,capture_output=True,text=True,timeout=300)
 assert sorted_.returncode==0 and sorted_.stdout.rstrip('\n')==expected,(backend,sorted_.returncode,sorted_.stderr[-2000:])
 print(f'{backend}: {count} localeCompare signs and a {len(lines)}-string sort match Node exactly ({time.monotonic()-start:.1f}s)',flush=True)

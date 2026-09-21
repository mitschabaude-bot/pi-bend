"""Inverse UTC calendar: independent host-date reference and range boundaries."""
import argparse,hashlib,json,random,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--prefix',type=Path,default=ROOT/'build/calendar-inverse');a=p.parse_args();prefix=a.prefix.resolve()
minimum=-62167219200000;maximum=253402300799999
rng=random.Random(719528)
values=[minimum,minimum-1,minimum+1,maximum,maximum+1,maximum-1,-1,0,1,-86400000,86400000,-(1<<63),(1<<63)-1]
values += [rng.randrange(minimum,maximum+1) for _ in range(4096)]
values += [rng.randrange(-(1<<63),1<<63) for _ in range(1024)]
boundary_script="""const years=[0,1,4,100,400,1600,1900,1970,2000,2024,2100,2400,9999];const result=[];for(const y of years)for(let m=0;m<=12;m++){const d=new Date(0);d.setUTCFullYear(y,m,1);for(const offset of [-1,0,1])result.push(String(d.getTime()+offset));}console.log(JSON.stringify(result));"""
values += list(map(int,json.loads(subprocess.check_output(['node','-e',boundary_script],text=True))))
script="""const fs=require('fs');const inputs=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(inputs.map(v=>{const n=BigInt(v);if(n< -62167219200000n||n>253402300799999n)return 'range';const d=new Date(Number(n));return [d.getUTCFullYear(),d.getUTCMonth()+1,d.getUTCDate(),d.getUTCHours(),d.getUTCMinutes(),d.getUTCSeconds(),d.getUTCMilliseconds()].join(':');})));"""
expected=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps(list(map(str,values))),text=True))
args=[f'{(v&((1<<64)-1))>>32};{v&0xffffffff}' for v in values]
runs=[]
for backend,command in [('native-1',[str(prefix),'--threads','1']),('native-4',[str(prefix),'--threads','4']),('bun',[str(Path.home()/'.bun/bin/bun'),str(prefix)+'.js'])]:
    for i in range(0,len(args),64):
        run=subprocess.run(command+args[i:i+64],cwd=ROOT,capture_output=True,text=True,check=True,timeout=15)
        assert run.stdout.splitlines()==expected[i:i+64],(backend,i,run.stdout,expected[i:i+64]);assert not run.stderr,run.stderr
    runs.append(dict(backend=backend,cases=len(values)));print(backend,len(values),'inverse calendar cases PASS',flush=True)
pending=[ROOT/'packages/runtime/test/calendar-inverse.bend'];seen={Path(__file__).resolve()}
while pending:
    path=pending.pop().resolve()
    if path in seen:continue
    seen.add(path);pending.extend(path.parent/n for n in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
record=dict(scope=__doc__,seed=719528,runs=runs,cases=[dict(epoch=str(v),expected=e) for v,e in zip(values,expected)],sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},program_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [prefix,Path(str(prefix)+'.c'),Path(str(prefix)+'.js')]})
Path(str(prefix)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')

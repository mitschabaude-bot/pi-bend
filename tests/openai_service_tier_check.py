"""Binary64 pricing differential against pinned pi's actual service-tier functions."""
import argparse,hashlib,json,math,random,re,struct,subprocess
from pathlib import Path
from channel_audit import instrument
ROOT=Path(__file__).resolve().parents[1]
compiler=ROOT/'build/bend-profiles/dns-transport-teles/bend2/main.ts'
parser=argparse.ArgumentParser()
parser.add_argument('--prefix',default='build/openai-service-tier')
parser.add_argument('--source',default='packages/ai/test/openai-responses-service-tier.bend')
config=parser.parse_args()
prefix=ROOT/config.prefix
source=config.source
words=lambda n:list(struct.unpack('!II',struct.pack('!d',n)))
models=['gpt-5.5','gpt-5.5-mini','gpt-5.5-2026-01-01','gpt-5.4','other']
tiers=[None,'auto','default','flex','scale','priority','future']
costs=[[1.,2.,3.,4.,999.],[-0.,0.,-0.,0.,-0.],[5e-324]*5,[1.7976931348623157e308]*5,[2.**53,1.,-2.**53,1.,0.],[math.inf,0.,0.,0.,0.],[math.inf,-math.inf,0.,0.,0.],[math.nan,1.,2.,3.,4.]]
rows=[dict(model=model,tier=tier,cost=[words(n) for n in cost]) for model in models for tier in tiers for cost in costs]
rng=random.Random(9412)
for _ in range(240):
    cost=[math.ldexp(rng.uniform(-1,1),rng.randrange(-1073,1024)) for _ in range(5)]
    rows.append(dict(model=rng.choice(models),tier=rng.choice(tiers),cost=[words(n) for n in cost]))
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert commit.startswith('46c9de402')
wanted=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/openai_service_tier_reference.mts'],cwd=ROOT,input=json.dumps(rows),text=True))
args=[','.join([r['model'],r['tier'] or '-']+[';'.join(map(str,n)) for n in r['cost']]) for r in rows]
for backend in ['c','js']:
    with Path(str(prefix)+'-'+backend+'.log').open('w') as log:
        subprocess.run([str(compiler),source,'-o',str(prefix)+'.'+backend],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
Path(str(prefix)+'-audit.c').write_text(Path(str(prefix)+'.c').read_text()+r'''
static void __attribute__((destructor)) tier_audit(void) { unsigned channels=0; for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live; fprintf(stderr,"AUDIT %u %u\n",channels,io_park.head!=NULL); }
''')
Path(str(prefix)+'-audit.js').write_text(instrument(Path(str(prefix)+'.js').read_text()))
runs=[]
for suffix in ['', '-audit']:
    subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',str(prefix)+suffix+'.c','-lpthread','-lm','-o',str(prefix)+suffix],check=True,timeout=180)
    for name,cmd in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[str(Path.home()/'.bun/bin/bun'),str(prefix)+suffix+'.js'])]:
        result=subprocess.run(cmd+args,cwd=ROOT,capture_output=True,text=True,timeout=40,check=True)
        actual=result.stdout.splitlines()
        expected_audit=('AUDIT 0 0 0\n' if name=='bun' else 'AUDIT 0 0\n') if suffix else ''
        assert result.stderr==expected_audit and actual==wanted,next(((name,row,a,b) for row,a,b in zip(rows,actual,wanted) if a!=b),(name,len(actual),len(wanted),result.stderr))
        runs.append(dict(backend=name,audited=bool(suffix),cases=len(rows),passed=True));print(name,suffix or 'plain',len(rows),'service-tier cases PASS',flush=True)
pending=[ROOT/source];seen=set()
while pending:
    p=pending.pop().resolve()
    if p in seen:continue
    seen.add(p);pending.extend(p.parent/n for n in re.findall(r'^import (\.[^\s]+)',p.read_text(),re.M))
seen.update([ROOT/'tests/channel_audit.py',Path(__file__).resolve(),ROOT/'tests/openai_service_tier_reference.mts',ROOT.parent/'pi-mono/packages/ai/src/api/openai-responses.ts'])
record=dict(compiler_sha256={n:hashlib.sha256((compiler.parent/n).read_bytes()).hexdigest() for n in ['main.ts','bend.ts','comp.ts','base.bend']},scope='Actual pinned service-tier policy, exact binary64 component and left-associated total results. NaNs compared by classification; signed zeros, subnormals, overflow, cancellation and stale unchanged totals included. Generic counter-preservation laws are separate. Every vector uses the reusable pricing callback factory and disposes it. Audited native channels/parked IO and Bun channels/live/waiting IO end at zero.',reference_commit=commit,runs=runs,sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},programs={str(prefix)+s:hashlib.sha256(Path(str(prefix)+s).read_bytes()).hexdigest() for s in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']})
Path(str(prefix)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')

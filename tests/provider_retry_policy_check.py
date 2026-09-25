"""Native numeric-prefix/retry decisions versus actual pinned pi helpers.

Date parsing and cancellable waiting are explicitly outside this pure policy.
"""
import itertools,json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
texts=['',' ','0','-0','+0','+','-','.','-.','1.','1.e2','1e','1e+','1e-','1e2tail','1e+2tail','1.2.3','0x10','-0x10','0b11','1_000','1n','Infinity','Infinitytail','+Infinity','-Infinity','infinity','NaN','1\0tail','\ud8001','1\ud800','١','１']
spaces=[*range(9,14),32,160,5760,*range(8192,8203),8232,8233,8239,8287,12288,65279,0,8,14,133,6158,8203,8288]
for cp in spaces:texts += [chr(cp)+'-12.5e2tail','1'+chr(cp)+'2']
for t in ['2.4703282292062327e-324','2.4703282292062328e-324','4.9406564584124654e-324','2.2250738585072014e-308','1.7976931348623157e308','1.7976931348623159e308','9007199254740993','1.00000000000000011102230246251565404236316680908203125','1e'+'9'*100,'1e-'+'9'*100]:texts += [t,t+'tail','-'+t+'!']
rng=random.Random(4419)
for _ in range(300):
    digits=''.join(str(rng.randrange(10)) for _ in range(rng.randrange(1,80)));pos=rng.randrange(len(digits)+1)
    texts.append(rng.choice(['','+','-'])+digits[:pos]+'.'+digits[pos:]+rng.choice(['e','E'])+str(rng.randrange(-450,450))+rng.choice(['','x','e+','🙂']))
cases=[dict(mode='p',text=t) for t in texts]
for status,should in itertools.product([None,'0','200','400','408','409','429','499','500','503','999','NaN','Infinity'],[None,'','true','false','TRUE',' true ']):
    cases.append(dict(mode='r',status=status,should=should,ms=None,seconds=None,max=None,index=0,random='0.5'))
for ms,seconds,maximum in itertools.product([None,'','1000','0','-2','12.5ms','invalid','Infinity','1e','0x10'],[None,'','2','-1','invalid','Wed, 21 Oct 2015 07:28:00 GMT','2seconds'],[None,'0','-1','1000','60000','NaN']):
    cases.append(dict(mode='r',status='429',should=None,ms=ms,seconds=seconds,max=maximum,index=2,random='0.25'))
for index,rnd,maximum in itertools.product([0,1,2,3,4,5,50],[0,0.125,0.5,0.9999999999999999],[None,'1']):
    cases.append(dict(mode='r',status=None,should=None,ms=None,seconds=None,max=maximum,index=index,random=str(rnd)))
for epoch,now,maximum in itertools.product(['0','1','1000','60001','1e15','NaN'],['0','1000','1e15'],[None,'0','1000']):cases.append(dict(mode='d',epoch=epoch,now=now,max=maximum))
expected=json.loads(subprocess.check_output(['node','tests/provider_retry_policy_reference.mts'],input=json.dumps(cases),cwd=ROOT,text=True))
def text(value):return '-' if value is None else ','.join(str(ord(c)) for c in value)
def number(value):return '-' if value is None else value
def encode(c,e):
    if c['mode']=='p':return ';'.join(['p',text(c['text']),e])
    if c['mode']=='d':return ';'.join(['d',c['epoch'],c['now'],number(c['max']),e])
    return ';'.join(['r',number(c['status']),text(c['should']),text(c['ms']),text(c['seconds']),number(c['max']),str(c['index']),c['random'],e])
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', sys.executable,'scripts/run-rss-guarded.py','--stats','build/provider-retry-policy-build.json','--','sh','scripts/build-pure.sh','packages/ai/test/provider-retry-policy.bend','build/provider-retry-policy'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(cases),32):
        args=[encode(c,e) for c,e in zip(cases[start:start+32],expected[start:start+32])]
        result=subprocess.run([str(ROOT/'build/provider-retry-policy'),'--threads',threads,*args],cwd=ROOT,capture_output=True,text=True,timeout=120)
        assert result.returncode==0,(threads,start,cases[start:start+32],result.stdout,result.stderr)
    print(f'PASS {len(cases)} numeric-prefix/retry-policy comparisons on {threads} threads')
print('Numeric-prefix cases:',len(texts))

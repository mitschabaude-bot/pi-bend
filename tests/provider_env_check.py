"""Native scoped/process environment resolution versus actual pi helpers."""
import itertools,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=list(itertools.product([None,'','short','long','LONG',' '],[None,'','short','long','none',' ','long '],[None,'none','short','long']))
expected=json.loads(subprocess.check_output(['node','tests/provider_env_reference.mts'],input=json.dumps(cases),cwd=ROOT,text=True))
if '--no-build' not in sys.argv:
    subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats','build/provider-env-build.json','--','sh','scripts/build-pure.sh','packages/ai/test/provider-env.bend','build/provider-env'],cwd=ROOT,check=True)
def codes(value):return '-' if value is None else ','.join(str(ord(c)) for c in value)
for threads in ['1','4']:
    for (ambient,override,explicit),(value,retention) in zip(cases,expected,strict=True):
        env=dict(os.environ)
        env.pop('PI_CACHE_RETENTION',None)
        if ambient is not None:env['PI_CACHE_RETENTION']=ambient
        result=subprocess.run([str(ROOT/'build/provider-env'),'--threads',threads,codes(override),explicit or '-',codes(value)+'|'+retention],env=env,cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert result.returncode==0,(threads,ambient,override,explicit,result.stdout,result.stderr)
    print(f'PASS {len(cases)} actual-pi environment/cache comparisons on {threads} threads')

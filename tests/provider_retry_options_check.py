"""Boundary/reference checks for the pure retry-options adapter."""
from pathlib import Path
import hashlib,json,math,re,struct,subprocess
ROOT=Path(__file__).resolve().parents[1]
BUN=str(Path.home()/'.bun/bin/bun')
MAX=(1<<48)-1
words=lambda x:struct.unpack('!II',struct.pack('!d',x))
values=[None,-math.inf,math.nan,-1.5,-1.0,-.5,-0.0,0.0,.5,1.0,2.0,65535.0,float(2**32),float(MAX),float(MAX+1),60000.0,1e300,math.inf]
argument=lambda x:'none' if x is None else ';'.join(map(str,words(x)))
bits=lambda x:':'.join(map(str,words(x)))
rows=[];wanted=[]
for retries in values:
    for limit in values:
        rows.append(argument(retries)+','+argument(limit))
        if retries is not None and not (math.isfinite(retries) and 0<=retries<=MAX and retries.is_integer()):want='count:'+bits(retries)
        elif limit is not None and not (math.isfinite(limit) and limit>=0):want='limit:'+bits(limit)
        else:want='ok:'+('none' if retries is None else str(int(retries)))+':'+('none' if limit is None else bits(limit))
        wanted.append(want)
programs=[ROOT/'build/provider-retry-options',ROOT/'build/provider-retry-options.js'];samples=[]
for backend,command in [('native-1',[str(programs[0]),'--threads','1']),('native-4',[str(programs[0]),'--threads','4']),('bun',[BUN,str(programs[1])])]:
    run=subprocess.run([*command,*rows],cwd=ROOT,capture_output=True,text=True,timeout=15)
    assert run.returncode==0 and not run.stderr,(backend,run.returncode,run.stderr)
    actual=run.stdout.splitlines()
    assert actual==wanted,next(((backend,row,a,b) for row,a,b in zip(rows,actual,wanted) if a!=b),(backend,len(actual),len(wanted)))
    samples.append(dict(backend=backend,cases=len(rows),passed=True));print(backend,len(rows),'retry-option cases PASS',flush=True)
pending=[ROOT/'packages/ai/test/provider-retry-options.bend'];seen=set()
while pending:
    p=pending.pop().resolve()
    if p in seen:continue
    seen.add(p);pending.extend(p.parent/name for name in re.findall(r'^import (\.[^\s]+)',p.read_text(),re.M))
seen.add(Path(__file__).resolve())
record=dict(scope='All pairs of absent, finite, fractional, negative, signed-zero, range-boundary and nonfinite retry-count/delay-limit inputs. Checks error precedence, cause bits and exact accepted fields. Generic signal-independence laws are separate.',sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},programs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in programs},samples=samples)
(ROOT/'build/provider-retry-options-result.json').write_text(json.dumps(record,indent=2)+'\n')

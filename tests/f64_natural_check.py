"""Differential IEEE-754 to native Nat conversion and error-bit preservation."""
from pathlib import Path
import hashlib,json,math,random,re,struct,subprocess
ROOT=Path(__file__).resolve().parents[1]
BUN=str(Path.home()/'.bun/bin/bun')
MAX=(1<<48)-1
bits=lambda n:struct.unpack('!Q',struct.pack('!d',float(n)))[0]
values={0,1,1<<63,0x7ff0000000000000,0xfff0000000000000,0x7ff8000000000001,0xfff123456789abcd}
for n in [0,1,2,2**16-1,2**16,2**32-1,2**32,MAX-1,MAX,MAX+1,2**53]:
    for x in [float(n),math.nextafter(float(n),-math.inf),math.nextafter(float(n),math.inf)]:
        values.update([bits(x),bits(-x)])
for exponent in range(2048):
    for mantissa in [0,(1<<52)-1]:values.add((exponent<<52)|mantissa)
rng=random.Random(4832)
values.update(rng.getrandbits(64) for _ in range(512))
values.update(bits(rng.randrange(MAX+1)) for _ in range(512))
rows=sorted(values)
wanted=[]
for word in rows:
    value=struct.unpack('!d',struct.pack('!Q',word))[0]
    valid=math.isfinite(value) and 0<=value<=MAX and value.is_integer()
    wanted.append(str(int(value)) if valid else f'invalid:{word>>32}:{word&0xffffffff}')
results=[]
programs=[ROOT/'build/f64-natural',ROOT/'build/f64-natural.js']
for backend,command in [('native-1',[str(programs[0]),'--threads','1']),('native-4',[str(programs[0]),'--threads','4']),('bun',[BUN,str(programs[1])])]:
    actual=[]
    for start in range(0,len(rows),256):
        batch=rows[start:start+256]
        run=subprocess.run([*command,*[f'{word>>32};{word&0xffffffff}' for word in batch]],cwd=ROOT,capture_output=True,text=True,timeout=15)
        assert run.returncode==0 and not run.stderr,(backend,run.returncode,run.stderr)
        actual.extend(run.stdout.splitlines())
    assert actual==wanted,next(((backend,hex(word),a,b) for word,a,b in zip(rows,actual,wanted) if a!=b),(backend,len(actual),len(wanted)))
    results.append(dict(backend=backend,cases=len(rows),passed=True))
    print(backend,len(rows),'native Nat conversions PASS',flush=True)
pending=[ROOT/'packages/runtime/test/f64-natural.bend'];seen=set()
while pending:
    path=pending.pop().resolve()
    if path in seen:continue
    seen.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
seen.add(Path(__file__).resolve())
record=dict(scope='Native Nat 48-bit exact conversion: boundaries, every binary64 exponent with zero/maximal mantissa, deterministic random bits and representable integers. Python numeric reference, not a proof of all inputs. Error words must be retained exactly.',maximum=MAX,sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},programs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in programs},samples=results)
(ROOT/'build/f64-natural-result.json').write_text(json.dumps(record,indent=2)+'\n')

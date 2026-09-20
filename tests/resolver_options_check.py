"""Typed resolver options: documented settings vs libc and strict diagnostics.

No DNS queries. Libc observes the host file before RES_OPTIONS; differential
cases seed Bend with the observed supported host flags and reset all numeric
values, avoiding assumptions about the host's configuration. Invalid-token
policy is not selected here: the native report retains diagnostics separately.
"""
import hashlib
import json
from pathlib import Path
import platform
import random
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2/main.ts'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-options-{suffix}-build.json','--',str(bun),str(compiler),'tests/resolver-options.bend','-o',f'build/resolver-options.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-options.c','-lpthread','-lm','-o','build/resolver-options'],cwd=ROOT,check=True)
subprocess.run(['cc','-std=c11','-O2','tests/resolver-options-oracle.c','-lresolv','-o','build/resolver-options-oracle'],cwd=ROOT,check=True)
features=['rotate','edns0','single-request-reopen','single-request','no-tld-query','no-reload','use-vc','trust-ad','no-aaaa']
limits={'ndots':15,'timeout':30,'attempts':5}

def oracle(text):return subprocess.check_output(['build/resolver-options-oracle',text],cwd=ROOT,text=True).strip()
reset='ndots:1 timeout:5 attempts:2'
baseline=oracle(reset);bits=list(map(int,baseline.split(',')[3:]));assert len(bits)==9
seed=reset+' '+ ' '.join(feature for feature,on in zip(features,bits) if on)

def model(text):
    values={'ndots':1,'timeout':5,'attempts':2};enabled=set();errors=[]
    for token in filter(None,re.split('[ \t]+',text)):
        found=re.fullmatch(r'(ndots|timeout|attempts):([0-9]+)',token)
        if found:
            key,digits=found.groups();digits=digits.lstrip('0') or '0'
            value=limits[key] if len(digits)>2 else min(int(digits),limits[key])
            values[key]=value
        elif any(token.startswith(key+':') for key in limits):errors.append('malformed:'+token)
        elif token in features:enabled.add(token)
        elif token=='no_tld_query':enabled.add('no-tld-query')
        else:errors.append('unknown:'+token)
    return [','.join(map(str,[values['ndots'],values['timeout'],values['attempts'],*[int(name in enabled) for name in features]])),*errors,'END']

valid=['',*features,'no_tld_query',' '.join(features)*1,'rotate rotate rotate']
for key,limit in limits.items():
    valid.extend(f'{key}:{n}' for n in [0,1,2,limit-1,limit,limit+1,99,1000,2147483647])
    valid.extend([f'{key}:00001',f'{key}:{limit} {key}:0 {key}:2'])
rng=random.Random(593)
tokens=[*features,'no_tld_query',*[f'{key}:{value}' for key in limits for value in [0,1,2,5,15,30,99]]]
valid += [' '.join(rng.choices(tokens,k=rng.randrange(1,80))) for _ in range(180)]
differential=[seed+' '+text for text in valid]
expected=[]
for text in differential:
    line=oracle(text);assert model(text)==[line,'END'],(text,line,model(text))
    expected.extend([line,'END'])
assert oracle(reset)==baseline,'host configuration changed during oracle runs'
strict=['','ndots:-1','timeout:7junk','attempts:','rotate-junk','-rotate','ndots:+1','timeout:１',
        'Ndots:3','ndots:3:4','attempts:2.0','edns0-extra','debug','unknown',
        'timeout:3 timeout:bad timeout:4','ndots:-1 ndots:2 rotate-junk rotate',
        *[key+':'+('9'*5000) for key in limits],*[key+':'+('0'*5000)+'1' for key in limits],
        ' '.join(['rotate','ndots:2','timeout:9','attempts:3']*2000)]
rows=[]
for label,command in [('native 1',['build/resolver-options','--threads','1']),('native 4',['build/resolver-options','--threads','4']),('Bun',[str(bun),'build/resolver-options.js'])]:
    for category,inputs in [('libc',differential),('strict reports',strict)]:
        for start in range(0,len(inputs),32):
            batch=inputs[start:start+32]
            want=[line for text in batch for line in model(text)]
            run=subprocess.run([*command,*batch],cwd=ROOT,capture_output=True,text=True,timeout=30)
            assert run.returncode==0 and not run.stderr,(label,category,run)
            assert run.stdout.splitlines()==want,(label,category,start,run.stdout[:1000],want[:30])
        rows.append(dict(backend=label,category=category,cases=len(inputs)))
    print(f'{label}: {len(differential)} libc sequences and {len(strict)} strict reports PASS',flush=True)
paths=['packages/runtime/src/resolver-options.bend','tests/resolver-options.bend','tests/resolver-options-oracle.c','tests/resolver_options_check.py','build/resolver-options','build/resolver-options.js']
record=dict(scope=__doc__,cases=rows,libc_version=list(platform.libc_ver()),supported_host_flags=bits,
            libc_quirks={text:oracle(reset+' '+text) for text in ['timeout:7junk','ndots:-1','attempts:','rotate-junk','timeout:4294967296']},
            sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},
            builds={suffix:json.loads((ROOT/f'build/resolver-options-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-options-result.json').write_text(json.dumps(record,indent=2)+'\n')

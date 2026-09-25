"""Execute DNS search through an asynchronous injected native request function.

Covers all classified policy traces, immediate typed halts, invalid candidates,
exact returned values, serial request counts and caller-owned source disposal.
"""
import ctypes
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path(BEND)
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-search-run-{suffix}-build.json','--',str(bun),str(compiler),'tests/dns-search-run.bend','-o',f'build/dns-search-run.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-search-run.c','-lpthread','-lm','-o','build/dns-search-run'],cwd=ROOT,check=True)
# Disposable exit-only instrumentation; production source/effects are unchanged.
audit='''\nstatic void __attribute__((destructor)) search_run_audit(void) {
  unsigned live=0;
  for(u32 i=0;i<chan_len;i++) live+=chan_rows[i].live;
  fprintf(stderr,"SEARCH_CHANNELS %u\\n",live);
}\n'''
(ROOT/'build/dns-search-run-audit.c').write_text((ROOT/'build/dns-search-run.c').read_text()+audit)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-search-run-audit.c','-lpthread','-lm','-o','build/dns-search-run-audit'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);pton=libc.ns_name_pton;pton.argtypes=[ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t];pton.restype=ctypes.c_int

def wire(text):
    b=ctypes.create_string_buffer(256)
    if pton(text.encode(),b,256)<0:return None
    raw=b.raw;end=0
    while raw[end]:end+=raw[end]+1
    return raw[:end+1]

def model(case):
    text,dots,absolute,ndots,default,search,notld,suffixes,script=case
    dots,absolute,ndots,default,search,notld=map(int,[dots,absolute,ndots,default,search,notld])
    domains=suffixes.split('|') if suffixes else [];tokens=script.split(',');lines=[];calls=0
    initial=None;nodata=False;servfail=False;last=1;direct=False;root=False;searched=False
    codes={'n':1,'d':4,'s':2,'t':2,'f':3,'r':2}
    base=wire(text)
    def query(origin,value):
        nonlocal calls
        if value is None or len(value)>255:return 'f'
        lines.append(origin+':'+''.join(str(x)+',' for x in value))
        token=tokens[calls] if calls<len(tokens) else 'n';calls+=1
        return token
    def terminal(token):
        if token=='a':return 'ok:exact answer payload'
        if token.startswith('h'):return 'halt:'+token[1:]
        return None
    def finish(value):return lines+[value,'calls:'+str(calls)]
    if absolute or dots>=ndots:
        direct=True;token=query('initial',base)
        end=terminal(token)
        if end:return finish(end)
        initial=last=codes[token]
        if absolute:return finish('error:'+str(initial))
    if (default if dots==0 else search):
        if not search:domains=domains[:1]
        for index,domain in enumerate(domains):
            suffix=wire(domain);searched=True;root |= suffix==b'\0'
            value=None if base is None or suffix is None else base[:-1]+suffix
            token=query('suffix:'+str(index),value);end=terminal(token)
            if end:return finish(end)
            if token=='r':return finish('error:2')
            last=codes[token];nodata |= token=='d';servfail |= token=='s'
            if token in ['t','f']:break
    if not direct and not root and (dots or not searched or not notld):
        token=query('final',base);end=terminal(token)
        if end:return finish(end)
        last=codes[token]
    result=initial if initial is not None else (4 if nodata else (2 if servfail else last))
    return finish('error:'+str(result))

contexts=[('a',2,1,1,0,'x|y'),('a.b',1,1,1,0,'x|y'),('a',2,1,1,1,'x|.'),('a.',2,1,1,0,'x|y'),('a',2,1,0,0,'x|y'),('a',2,0,0,1,'x|y'),('a',2,1,1,0,'.|x')]
def case_for(context,script):
    text,ndots,default,search,notld,domains=context
    return (text,str(text.count('.')),str(int(text.endswith('.'))),str(ndots),str(default),str(search),str(notld),domains,','.join(script))
cases=[case_for(context,script) for context in contexts for script in itertools.product('ndstfra',repeat=3)]
for context in contexts:
    for prefix in [[],['n'],['d'],['s'],['d','n']]:
        for failure in ['cancelled','entropy:11','cleanup:closed','', '理由']:
            cases.append(case_for(context,[*prefix,'h'+failure,'a']))
for text,suffix in [('bad..name','x|y'),('a','bad..suffix|y'),('a'*63,'.'.join(['b'*63]*3)+'|y'),('.'.join(['a'*63]*3+['b'*61]),'x|y')]:
    for script in [['a'],['n'],['hcancelled']]:cases.append(case_for((text,15,1,1,0,suffix),script))
rows=[]
commands=[('native 1',['build/dns-search-run','--threads','1'],False),('native 4',['build/dns-search-run','--threads','4'],False),('Bun',[str(bun),'build/dns-search-run.js'],False),('native 1 audit',['build/dns-search-run-audit','--threads','1'],True),('native 4 audit',['build/dns-search-run-audit','--threads','4'],True)]
for label,command,audited in commands:
    inputs=cases if not audited else cases[2401:]
    for start in range(0,len(inputs),64):
        batch=inputs[start:start+64];want=[line for case in batch for line in model(case)]
        run=subprocess.run([*command,*[';'.join(case) for case in batch]],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and run.stderr==('SEARCH_CHANNELS 0\n' if audited else ''),(label,start,run.returncode,run.stderr)
        assert run.stdout.splitlines()==want,(label,start,run.stdout[:1000],want[:30])
    rows.append(dict(backend=label,cases=len(inputs),live_channels_at_exit=0 if audited else None));print(f'{label}: {len(inputs)} async search cases PASS',flush=True)
paths=['packages/runtime/src/dns-message.bend','packages/runtime/src/dns-message.bend','packages/runtime/src/dns-message.bend','tests/dns-search-run.bend','tests/dns_search_run_check.py','build/dns-search-run','build/dns-search-run.js']
(ROOT/'build/dns-search-run-result.json').write_text(json.dumps(dict(scope=__doc__,cases=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/dns-search-run-{suffix}-build.json').read_text()) for suffix in ['c','js']}),indent=2)+'\n')

"""Strict option selection connects loaded settings to DNS search without partial application."""
import ctypes
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=Path(BEND)
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-search-{suffix}-build.json','--',str(bun),str(compiler),'tests/resolver-search.bend','-o',f'build/resolver-search.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-search.c','-lpthread','-lm','-o','build/resolver-search'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);pton=libc.ns_name_pton;pton.argtypes=[ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t];pton.restype=ctypes.c_int

def wire(text):
    buf=ctypes.create_string_buffer(256)
    if pton(text.encode(),buf,256)<0:return None
    data=buf.raw;at=0
    while data[at]:at+=data[at]+1
    return data[:at+1]
def csv(value):return 'invalid' if value is None else ''.join(f'{b},' for b in value)

def trace(base,domains,ndots,notld,stop_invalid):
    dots=base.count('.');absolute=base.endswith('.');initial=absolute or dots>=ndots
    steps=[];root=False;searched=False
    if initial:steps.append(('initial',wire(base)))
    if not absolute:
        for index,domain in enumerate(domains):
            suffix=domain[1:] if domain.startswith('.') else domain
            searched=True;root |= not suffix
            value=wire(base+'.'+suffix)
            steps.append((f'suffix:{index}',value))
            if value is None and stop_invalid:break
    if not initial and not root and (dots or not searched or not notld):steps.append(('final',wire(base)))
    return steps

# Hand-selected expected values exercise precedence, caps, retained non-search
# flags and rejection of every diagnostic, including repeated unknown tokens.
options=[
 ('','',(1,5,2,set()),None),
 ('ndots:0','',(0,5,2,set()),None),
 ('ndots:15','ndots:2',(2,5,2,set()),None),
 ('ndots:2 no-tld-query','ndots:0',(0,5,2,{4}),None),
 ('timeout:9 attempts:4 rotate','timeout:30 attempts:0',(1,30,0,{0}),None),
 ('edns0 single-request single-request-reopen no-reload use-vc trust-ad no-aaaa','',(1,5,2,{1,2,3,5,6,7,8}),None),
 ('no_tld_query no-tld-query','',(1,5,2,{4}),None),
 ('ndots:999 timeout:999 attempts:999','',(15,30,5,set()),None),
 ('ndots:0 ndots:x','unknown',None,['malformed:ndots:x','unknown:unknown']),
 ('','rotating ndots:-1 ndots:2',None,['unknown:rotating','malformed:ndots:-1']),
 ('unknown','ndots:0',None,['unknown:unknown']),
 ('','unknown unknown',None,['unknown:unknown','unknown:unknown']),
]
searches=[('', ['example']),('search x y',['x','y']),('search .',['.']),('search .. y',['..','y']),('search x .. y',['x','..','y']),('search \n',['example']),('domain .x',['.x'])]
cases=[]
for base,(directive,domains),(file_options,env_options,selected,errors) in itertools.product(['a','a.b','a.b.'],searches,options):
    config=directive+'\noptions '+file_options+'\nunknown-file-line'
    args=[base,str(base.count('.')),str(int(base.endswith('.'))),config,env_options]
    if errors:want=['rejected',*errors,'END']
    else:
        ndots,timeout,attempts,flags=selected
        policy=','.join(map(str,[ndots,timeout,attempts,*[int(i in flags) for i in range(9)]]))
        all_steps=trace(base,domains,ndots,4 in flags,False)
        actual=trace(base,domains,ndots,4 in flags,True)
        status=1 if base.endswith('.') or base.count('.')>=ndots or not actual or actual[-1][1] is not None else 3
        want=[policy,'END',*[origin+':'+csv(value) for origin,value in all_steps],'END',*['query:'+origin+':'+csv(value) for origin,value in actual if value is not None],f'error:{status}']
    cases.append((args,want))
checks=[]
for backend,command in [('native 1',['build/resolver-search','--threads','1']),('native 4',['build/resolver-search','--threads','4']),('Bun',[str(bun),'build/resolver-search.js'])]:
    for index,(args,want) in enumerate(cases):
        run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=20)
        assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,index,args,run,want)
    checks.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} settings/options/search cases PASS',flush=True)
paths=['packages/runtime/src/resolver-config.bend','tests/resolver-search.bend','tests/resolver_search_check.py']
result=dict(scope=__doc__,checks=checks,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-search-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-search-result.json').write_text(json.dumps(result,indent=2)+'\n')

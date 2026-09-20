"""DNS search failure policy: exhaustive classified traces and libc loopback.

Live comparisons use NXDOMAIN, empty NOERROR and positive A replies. Other
classified failures are checked against the independent source-derived model;
packet/transport classification is a separate, unfinished adapter.
"""
import ctypes
from concurrent.futures import ThreadPoolExecutor
import hashlib
import itertools
import json
from pathlib import Path
import socket
import struct
import subprocess
import threading

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2/main.ts'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-search-response-{suffix}-build.json','--',str(bun),str(compiler),'tests/dns-search-response.bend','-o',f'build/dns-search-response.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-search-response.c','-lpthread','-lm','-o','build/dns-search-response'],cwd=ROOT,check=True)
subprocess.run(['cc','-std=c11','-O2','tests/dns-search-oracle.c','-lresolv','-o','build/dns-search-oracle'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);pton=libc.ns_name_pton;pton.argtypes=[ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t];pton.restype=ctypes.c_int

def wire(text):
    b=ctypes.create_string_buffer(256);assert pton(text.encode(),b,256)>=0
    raw=b.raw;end=0
    while raw[end]:end+=raw[end]+1
    return raw[:end+1]

def model(case):
    text,dots,absolute,ndots,default,search,notld,suffixes,script=case
    dots,absolute,ndots,default,search,notld=map(int,[dots,absolute,ndots,default,search,notld])
    domains=suffixes.split('|') if suffixes else [];tokens=script.split(',');lines=[];queries=[]
    initial=None;nodata=False;servfail=False;last=1;direct=False;root=False;searched=False
    codes={'n':1,'d':4,'s':2,'t':2,'f':3,'r':2}
    def query(origin,name):
        value=wire(name);lines.append(origin+':'+''.join(str(x)+',' for x in value));queries.append(value)
        return tokens[len(queries)-1] if len(queries)<=len(tokens) else 'n'
    def finish(value):return lines+[value],queries,value
    if absolute or dots>=ndots:
        direct=True;token=query('initial',text)
        if token=='a':return finish('ok')
        initial=last=codes[token]
        if absolute:return finish('error:'+str(initial))
    if (default if dots==0 else search):
        if not search:domains=domains[:1]
        for index,domain in enumerate(domains):
            searched=True;root |= domain in ['', '.']
            token=query('suffix:'+str(index),text.rstrip('.')+('.'+domain if domain not in ['', '.'] else '.'))
            if token=='a':return finish('ok')
            if token=='r':return finish('error:2')
            last=codes[token]
            nodata |= token=='d';servfail |= token=='s'
            if token in ['t','f']:break
    if not direct and not root and (dots or not searched or not notld):
        token=query('final',text)
        if token=='a':return finish('ok')
        last=codes[token]
    result=initial if initial is not None else (4 if nodata else (2 if servfail else last))
    return finish('error:'+str(result))

contexts=[('a',2,1,1,0,'x|y'),('a.b',1,1,1,0,'x|y'),('a',2,1,1,1,'x|.'),
          ('a.',2,1,1,0,'x|y'),('a',2,1,0,0,'x|y'),('a',2,0,0,1,'x|y'),('a',2,1,1,0,'.|x')]

def case_for(context,script):
    text,ndots,default,search,notld,domains=context
    return (text,str(text.count('.')),str(int(text.endswith('.'))),str(ndots),str(default),str(search),str(notld),domains,','.join(script))

cases=[case_for(context,script) for context in contexts for script in itertools.product('nds tfra'.replace(' ',''),repeat=3)]
rows=[]
for label,command in [('native 1',['build/dns-search-response','--threads','1']),('native 4',['build/dns-search-response','--threads','4']),('Bun',[str(bun),'build/dns-search-response.js'])]:
    for start in range(0,len(cases),32):
        batch=cases[start:start+32];wanted=[line for case in batch for line in model(case)[0]]
        run=subprocess.run([*command,*[';'.join(case) for case in batch]],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(label,start,run.returncode,run.stderr)
        assert run.stdout.splitlines()==wanted,(label,start,run.stdout[:1000],wanted[:30])
    rows.append(dict(backend=label,cases=len(cases)));print(f'{label}: {len(cases)} response-policy traces PASS',flush=True)

network=[case_for(context,script) for context in contexts[:4] for script in itertools.product('nda',repeat=3)]
observations=[]
for case in network:
    text,dots,absolute,ndots,default,search,notld,domains,script=case
    _,expected,result=model(case);tokens=script.split(',');seen=[];done=threading.Event()
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as server,ThreadPoolExecutor(max_workers=1) as pool:
        server.bind(('127.0.0.1',0));server.settimeout(.05)
        def serve():
            while not done.is_set():
                try:packet,peer=server.recvfrom(4096)
                except socket.timeout:continue
                head=struct.unpack('!6H',packet[:12]);assert head[2]==1
                at=12
                while packet[at]:at+=packet[at]+1
                at+=1;assert packet[at:at+4]==struct.pack('!HH',1,1)
                token=tokens[len(seen)] if len(seen)<len(tokens) else 'n'
                seen.append(packet[12:at]);question=packet[12:at+4]
                answer=(b'\xc0\x0c'+struct.pack('!HHIH',1,1,60,4)+b'\x7f\0\0\x02') if token=='a' else b''
                server.sendto(struct.pack('!6H',head[0],0x8183 if token=='n' else 0x8180,1,int(token=='a'),0,0)+question+answer,peer)
        future=pool.submit(serve)
        try:run=subprocess.run(['build/dns-search-oracle',str(server.getsockname()[1]),text,ndots,default,search,notld,domains],cwd=ROOT,capture_output=True,text=True,timeout=4)
        finally:done.set()
        future.result(timeout=2)
    assert run.returncode==0 and not run.stderr,(case,run)
    returned,herror=map(int,run.stdout.strip().split(','));actual='ok' if returned>0 else 'error:'+str(herror)
    assert actual==result and seen==expected,(case,actual,result,seen,expected)
    observations.append(dict(input=list(case),queries=[list(q) for q in seen],result=actual))
print(f'libc: {len(network)} mixed-response loopback sequences PASS',flush=True)
paths=['packages/runtime/src/dns-search-response.bend','packages/runtime/src/dns-search.bend','tests/dns-search-response.bend','tests/dns_search_response_check.py','tests/dns-search-oracle.c','build/dns-search-response','build/dns-search-response.js']
(ROOT/'build/dns-search-response-result.json').write_text(json.dumps(dict(scope=__doc__,cases=rows,libc_sequences=observations,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/dns-search-response-{suffix}-build.json').read_text()) for suffix in ['c','js']}),indent=2)+'\n')

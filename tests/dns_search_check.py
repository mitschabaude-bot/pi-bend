"""Immutable DNS search cursors, plus libc query-order checks on loopback only.

The cursor enumerates candidates; response classification/retry is not part of
this module. Libc cases receive NXDOMAIN so its whole candidate path is observed.
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
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-search-{suffix}-build.json','--',str(bun),str(compiler),'tests/dns-search.bend','-o',f'build/dns-search.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-search.c','-lpthread','-lm','-o','build/dns-search'],cwd=ROOT,check=True)
subprocess.run(['cc','-std=c11','-O2','tests/dns-search-oracle.c','-lresolv','-o','build/dns-search-oracle'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);pton=libc.ns_name_pton;pton.argtypes=[ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t];pton.restype=ctypes.c_int

def wire(text):
    buffer=ctypes.create_string_buffer(256)
    if pton(text.encode(),buffer,256)<0:return None
    data=buffer.raw;end=0
    while data[end]:end+=data[end]+1
    return data[:end+1]

def csv(data):return 'invalid' if data is None else ''.join(str(b)+',' for b in data)

def model(case):
    text,dots,absolute,ndots,defnames,search,notld,domaintext,stop=case
    dots,absolute,ndots,defnames,search,notld,stop=map(int,[dots,absolute,ndots,defnames,search,notld,stop])
    base=wire(text);domains=domaintext.split('|') if domaintext else []
    trace=[];actual=[];direct=False;root=False;searched=False
    def emit(origin,value):
        trace.append(origin+':'+csv(value));actual.append(value)
        return len(actual)-1==stop
    if absolute or dots>=ndots:
        direct=True
        if emit('initial',base):domains=[]
    if absolute:domains=[]
    elif not (defnames if dots==0 else search):domains=[]
    elif not search:domains=domains[:1]
    for index,domain in enumerate(domains):
        suffix=wire(domain);searched=True;root |= suffix==b'\0'
        value=None if base is None or suffix is None else base[:-1]+suffix
        if value is not None and len(value)>255:value=None
        if emit('suffix:'+str(index),value):break
    if not direct and not root and (dots or not searched or not notld):emit('final',base)
    return trace+['END'],actual

cases=[]
for text,ndots,defnames,search,notld,domains in itertools.product(['a','a.b','a.b.','.'],[0,1,2,15],[0,1],[0,1],[0,1],['','x|y','.|x','x|.','x|x']):
    cases.append((text,str(text.count('.')),str(int(text.endswith('.'))),str(ndots),str(defnames),str(search),str(notld),domains,'4294967295'))
for stop in range(4):
    for domains in ['x|.|y','x|y|.','.|x|y','x|x|y']:
        for notld in [0,1]:cases.append(('a','0','0','1','1','1',str(notld),domains,str(stop)))
for text,domains in [('a'*63,'.'.join(['b'*63]*3)),('.'.join(['a'*63]*3+['b'*61]),'x|.'),('a','bad..name|x'),('a','|x'),('a', '|'.join(['x']*1000)),(r'a\.b', 'x|y')]:
    cases.append((text,str(text.count('.')),'0','2','1','1','0',domains,'4294967295'))
rows=[]
for label,command in [('native 1',['build/dns-search','--threads','1']),('native 4',['build/dns-search','--threads','4']),('Bun',[str(bun),'build/dns-search.js'])]:
    for start in range(0,len(cases),32):
        batch=cases[start:start+32];want=[line for case in batch for line in model(case)[0]]
        run=subprocess.run([*command,*[';'.join(case) for case in batch]],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(label,start,run.returncode,run.stderr)
        assert run.stdout.splitlines()==want,(label,start,run.stdout[:1000],want[:30])
    rows.append(dict(backend=label,cases=len(cases)));print(f'{label}: {len(cases)} search cursor cases PASS',flush=True)

# Check actual libc res_nsearch order for ordinary and escaped interior names.
network_cases=[]
for text,ndots,defnames,search,notld,domains in itertools.product(['a','a.b','a.b.',r'a\.b'],[0,2],[0,1],[0,1],[0,1],['','x|y','x|.']):
    network_cases.append((text,str(text.count('.')),str(int(text.endswith('.'))),str(ndots),str(defnames),str(search),str(notld),domains,'4294967295'))
observations=[]
for case in network_cases:
    text,dots,absolute,ndots,defnames,search,notld,domains,stop=case
    _,expected=model(case);seen=[];done=threading.Event()
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as server,ThreadPoolExecutor(max_workers=1) as pool:
        server.bind(('127.0.0.1',0));server.settimeout(.05)
        def serve():
            while not done.is_set():
                try:packet,peer=server.recvfrom(4096)
                except socket.timeout:continue
                header=struct.unpack('!6H',packet[:12]);assert header[2]==1
                at=12
                while packet[at]:at+=packet[at]+1
                at+=1
                assert packet[at:at+4]==struct.pack('!HH',1,1)
                seen.append(packet[12:at]);question=packet[12:at+4]
                server.sendto(struct.pack('!6H',header[0],0x8183,1,0,0,0)+question,peer)
        future=pool.submit(serve)
        try:
            run=subprocess.run(['build/dns-search-oracle',str(server.getsockname()[1]),text,ndots,defnames,search,notld,domains],cwd=ROOT,capture_output=True,text=True,timeout=4)
        finally:done.set()
        future.result(timeout=2)
    assert run.returncode==0 and not run.stderr and run.stdout=='-1,1\n',(case,run)
    assert seen==expected,(case,seen,expected)
    observations.append(dict(input=list(case),queries=[list(value) for value in seen]))
print(f'libc: {len(network_cases)} loopback NXDOMAIN sequences PASS',flush=True)
paths=['packages/runtime/src/dns-search.bend','tests/dns-search.bend','tests/dns-search-oracle.c','tests/dns_search_check.py','build/dns-search','build/dns-search.js']
(ROOT/'build/dns-search-result.json').write_text(json.dumps(dict(scope=__doc__,cases=rows,libc_sequences=observations,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/dns-search-{suffix}-build.json').read_text()) for suffix in ['c','js']}),indent=2)+'\n')

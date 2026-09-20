"""Single-server DNS search over real loopback TCP exchanges.

Checks DNS RCODE classification, selected-empty replies, search precedence,
alias follow-ups, refusal, EOF/reset/partial framing, shared deadline and
terminal source/validation/abort errors.
Each scenario runs through both the default wrapper and explicit request options.
This is not a server retry, OS configuration or full resolver test.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import select
import socket
import struct
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('candidate',type=Path)
p.add_argument('--no-build',action='store_true')
p.add_argument('--configured',action='store_true',help='Parse resolver settings and use the configured search entry point')
p.add_argument('--build-limit-gib',type=float,default=16)
a=p.parse_args();candidate=a.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
fixture='dns-configured-search' if a.configured else 'dns-address-search'
if not a.no_build:
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib',str(a.build_limit_gib),'--stats',f'build/{fixture}-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),f'tests/{fixture}.bend','-o',f'build/{fixture}.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',f'build/{fixture}.c','-lpthread','-lm','-o',f'build/{fixture}'],cwd=ROOT,check=True)

def wire(text):
    return b''.join(bytes([len(label)])+label.encode() for label in text.rstrip('.').split('.'))+b'\0'

def exact(peer,size):
    data=b''
    while len(data)<size:
        part=peer.recv(size-len(data));assert part,'early EOF';data+=part
    return data

def reply(identifier,owner,kind,value):
    extension=value if isinstance(value,dict) else None
    code=extension['code'] if extension else value if isinstance(value,int) else 0
    flags=0x8180|(code & 15);rr=b'';count=0
    if value=='address' or extension:
        data=bytes(range(1,5 if kind==1 else 17));count=1
        rr=wire(owner)+struct.pack('!HHIH',kind,1,60,len(data))+data
    if value=='alias':
        data=wire('target');count=1
        rr=wire(owner)+struct.pack('!HHIH',5,1,60,len(data))+data
    if value=='truncated':flags |= 512
    extra=b''
    if extension:
        data=bytes(extension.get('data',[]))
        extra=b'\0'+struct.pack('!HHIH',41,1232,(code>>4)<<24,len(data))+data
    packet=struct.pack('!6H',identifier,flags,1,count,0,bool(extension))+wire(owner)+struct.pack('!HH',kind,1)+rr+extra
    return struct.pack('!H',len(packet))+packet

def selected(owner,kind):
    return 'ok:'+''.join(str(x)+',' for x in wire(owner))+':'+('4,16909060,60;' if kind==1 else '6,16909060,84281096,151653132,219025168,60;')

# Explicit plans and outcomes, independent of the Bend cursor/classifier.
cases=[]
for code in range(16):
    cases.append(dict(label='rcode-'+str(code),name='a.',ndots=2,plan=[('a',code)],dns={0:4,2:2,3:1}.get(code,3)))
cases += [
    dict(label='suffix-answer',plan=[('a.x',3),('a.y','address')],answer='a.y'),
    dict(label='no-data-precedence',plan=[('a.x',0),('a.y',2),('a',3)],dns=4),
    dict(label='server-failure-precedence',plan=[('a.x',2),('a.y',3),('a',3)],dns=2),
    dict(label='refused-final-answer',plan=[('a.x',5),('a','address')],answer='a'),
    dict(label='format-error-final-answer',plan=[('a.x',1),('a','address')],answer='a'),
    dict(label='initial-precedence',name='a.b',ndots=1,plan=[('a.b',3),('a.b.x',0),('a.b.y',2)],dns=1),
    dict(label='alias-answer',plan=[('a.x','alias'),('target','address')],answer='target'),
    dict(label='alias-missing-next-suffix',plan=[('a.x','alias'),('target',3),('a.y','address')],answer='a.y'),
    dict(label='root-suppresses-final',domains='x|.',plan=[('a.x',3),('a',3)],dns=1),
    dict(label='deadline',mode='deadline',plan=[('a.x',3),('a.y','stall')],halt='read:expiry',reason='expiry'),
    dict(label='source-second',mode='error-second',plan=[('a.x',3)],halt='entropy:38:test source unavailable',draws=2),
    dict(label='source-first',mode='error-first',plan=[],halt='entropy:11:test source unavailable',draws=1),
    dict(label='pre-abort',mode='pre',plan=[],halt='connect:parent',reason='parent'),
    dict(label='invalid-size',mode='zero',plan=[],halt='zero'),
    dict(label='invalid-type',mode='type',plan=[],halt='type'),
    dict(label='truncated',plan=[('a.x','truncated')],halt='truncated'),
    dict(label='refused-suffix',mode='refused',plan=[],dns=2,draws=1),
    dict(label='refused-initial',mode='refused',ndots=0,plan=[],dns=2,draws=2),
    dict(label='refused-absolute',mode='refused',name='a.',plan=[],dns=2,draws=1),
    dict(label='eof-final-answer',plan=[('a.x','eof'),('a','address')],answer='a'),
    dict(label='partial-frame-final-answer',plan=[('a.x','partial'),('a','address')],answer='a'),
    dict(label='reset-final-answer',plan=[('a.x','reset'),('a.x','reset'),('a','address')],ids=[0,0,65535],draws=2,answer='a'),
    dict(label='reset-recovery-answer',plan=[('a.x','reset'),('a.x','address')],ids=[0,0],draws=1,answer='a.x'),
    dict(label='initial-eof-precedence',name='a.b',ndots=1,plan=[('a.b','eof'),('a.b.x',0),('a.b.y',3)],dns=2),
]
# Deliberately unsolicited OPT metadata checks that address extraction cannot
# accept an extended error, even on the current plain-query transport path.
for code in [16,18,19,4095]:
    cases.append(dict(label='extended-'+str(code),plan=[('a.x',dict(code=code)),('a','address')],answer='a'))
cases.append(dict(label='extended-success',plan=[('a.x',dict(code=0))],answer='a.x'))
cases.append(dict(label='malformed-opt',plan=[('a.x',dict(code=0,data=[0,1,0,1]))],halt='extension'))
if a.configured:
    cases += [
        dict(label='no-tld-suppresses-final',extra='no-tld-query',plan=[('a.x',3),('a.y',3)],dns=1),
        dict(label='no-tld-keeps-absolute',extra='no-tld-query',name='a.',plan=[('a','address')],answer='a'),
    ]
cases=[dict(case,edns=edns) for case in cases for edns in [False,True]]
rows=[]
for backend,command in [('native 1',[f'build/{fixture}','--threads','1']),('native 4',[f'build/{fixture}','--threads','4']),('Bun',[str(bun),f'build/{fixture}.js'])]:
    for number,family,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for kind in [1,28]:
            for case in cases:
                mode=case.get('mode','direct');plan=case['plan'];name=case.get('name','a')
                with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                    listener.bind((host,0))
                    if mode!='refused':listener.listen(4)
                    listener.settimeout(4)
                    def serve():
                        for index,(owner,value) in enumerate(plan):
                            with listener.accept()[0] as peer:
                                peer.settimeout(4)
                                query=exact(peer,struct.unpack('!H',exact(peer,2))[0]);identifier=case.get('ids',[0,65535,4660])[min(index,2)]
                                extension=(b'\0'+(struct.pack('!HHIH',41,1200,0,0) if a.configured else struct.pack('!HHIH',41,1232,32768,10)+bytes.fromhex('fde9000200fffde90000'))) if case['edns'] else b''
                                expected=struct.pack('!6H',identifier,288 if case['edns'] else 256,1,0,0,int(case['edns']))+wire(owner)+struct.pack('!HH',kind,1)+extension
                                assert query==expected,(case,query,expected)
                                if value=='eof':continue
                                if value=='partial':
                                    peer.sendall(b'\0');continue
                                if value=='reset':
                                    peer.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0));continue
                                if mode=='deadline' and index==0:time.sleep(.7)
                                if value=='stall':
                                    assert select.select([peer],[],[],.6)[0],'search restarted deadline'
                                else:
                                    peer.sendall(reply(identifier,owner,kind,value))
                                assert peer.recv(1)==b'','exchange not closed'
                    future=pool.submit(serve) if plan else None
                    run=subprocess.run([*command,'edns' if case['edns'] else 'plain',mode,str(number),str(listener.getsockname()[1]),str(15 if mode=='type' else kind),name,str(name.count('.')),str(int(name.endswith('.'))),str(case.get('ndots',2)),case.get('domains','x|y'),*([case.get('extra','')] if a.configured else [])],cwd=ROOT,capture_output=True,text=True,timeout=7)
                    if future:future.result(timeout=5)
                    if mode!='refused':assert not select.select([listener],[],[],0)[0],('unexpected candidate',case,run)
                if 'dns' in case:want=['dns:'+str(case['dns'])]
                elif 'answer' in case:want=[selected(case['answer'],kind),'none']
                else:want=[case['halt'],'none']
                want += [case.get('reason','none'),'draws:'+str(case.get('draws',len(plan)))]
                assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,number,kind,case,run,want)
                rows.append(dict(backend=backend,family=number,kind=kind,case=case,output=want))
    print(f'{backend}: {len(cases)*4} live search cases PASS',flush=True)
paths=['packages/runtime/src/dns-edns-response.bend','packages/runtime/src/dns-address-answer.bend','packages/runtime/src/dns-address-search.bend','packages/runtime/src/dns-address-lookup.bend','packages/runtime/src/dns-search-run.bend','packages/runtime/src/dns-search-response.bend',f'tests/{fixture}.bend','tests/dns-lookup-options.bend','packages/runtime/src/resolver-search.bend','packages/runtime/src/resolver-request.bend','tests/dns_address_search_check.py',f'build/{fixture}',f'build/{fixture}.js']
r=dict(scope=__doc__,configured=a.configured,cases=rows,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/{fixture}-{suffix}-build.json').read_text()) for suffix in ['c','js']},compiler_sha256={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/f'build/{fixture}-result.json').write_text(json.dumps(r,indent=2)+'\n')

"""Files-first hosts dispatch into live native DNS, preserving owner/search behavior."""
import argparse
import hashlib
import json
import re
import select
import socket
import struct
import subprocess
import time
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
p.add_argument('--native-built',action='store_true')
a=p.parse_args();candidate=a.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
for suffix in ['c','js']:
    if suffix=='c' and a.native_built:continue
    with (ROOT/f'build/dns-hosts-resolver-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-hosts-resolver-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-hosts-resolver.bend','-o',f'build/dns-hosts-resolver.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
source=(ROOT/'build/dns-hosts-resolver.c').read_text()+'''
static void __attribute__((destructor)) configured_audit(void) {
 unsigned r=0,w=0,t=0,c=0,s=0,k=0;
 for(u32 i=0;i<udp_read_len;i++)r+=udp_read_rows[i].live;
 for(u32 i=0;i<udp_write_len;i++)w+=udp_write_rows[i].live;
 for(u32 i=0;i<timer_len;i++)t+=timer_rows[i].live;
 for(u32 i=0;i<chan_len;i++)c+=chan_rows[i].live;
 for(u32 i=0;i<connect_len;i++)k+=connect_rows[i].live;
 for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)s++;}
 fprintf(stderr,"AUDIT %u %u %u %u %u %u %u\\n",r,w,t,c,s,k,io_park.head!=NULL);
}
'''
(ROOT/'build/dns-hosts-resolver-audit.c').write_text(source)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-hosts-resolver-audit.c','-lpthread','-lm','-o','build/dns-hosts-resolver'],cwd=ROOT,check=True)
(ROOT/'build/dns-hosts-resolver-audit.js').write_text('process.on("exit",()=>console.error(`AUDIT ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'+(ROOT/'build/dns-hosts-resolver.js').read_text())

def exact(peer,n):
    data=b''
    while len(data)<n:
        part=peer.recv(n-len(data));assert part,'early EOF';data+=part
    return data

def namewire(name):return b''.join(bytes([len(x)])+x.encode() for x in name.split('.'))+b'\0'
def selected(name,kind):return 'ok:'+''.join(f'{x},' for x in namewire(name))+':'+('4,16909060,60;' if kind==1 else '6,0,0,0,1,60;')
# Plans specify actual wire visits, including retries within a candidate.
cases=[
 ('repeat',[('udp',0,'a.x',3),('udp',1,'a.y','address'),('udp',0,'a.x',3),('udp',1,'a.y','address')],'a.y'),
 ('suffix',[('udp',0,'a.x',3),('udp',0,'a.y','address')],'a.y'),
 ('alias',[('udp',0,'a.x',3),('udp',0,'a.y','alias:b'),('udp',0,'b','address')],'b'),
 ('servfail',[('udp',0,'a.x',2),('udp',1,'a.x',2),('udp',0,'a.y','address')],'a.y'),
 ('refused-code',[('udp',0,'a.x',5),('udp',1,'a.x',5),('udp',0,'a','address')],'a'),
 ('not-implemented',[('udp',0,'a.x',4),('udp',1,'a.x',4),('udp',0,'a','address')],'a'),
 ('empty-rejected',[('udp',0,'a.x','empty-rejected'),('udp',1,'a.x','empty-rejected'),('udp',0,'a','address')],'a'),
 ('no-data',[('udp',0,'a.x',0),('udp',0,'a.y',3),('udp',0,'a',3)],'dns:4'),
 ('timeout',[('udp',0,'a.x','stall'),('udp',1,'a.x','stall'),('udp',0,'a','address')],'a'),
 ('rotate',[('udp',0,'a.x',3),('udp',1,'a.y','address')],'a.y'),
 ('fallback',[('udp',0,'a.x','tc'),('tcp',0,'a.x',3),('udp',0,'a.y','address')],'a.y'),
 ('forced',[('tcp',0,'a.x',3),('tcp',0,'a.y','address')],'a.y'),
 ('forced-eof',[('tcp',0,'a.x','eof'),('tcp',1,'a.x','eof'),('tcp',0,'a','address')],'a'),
 ('edns',[('udp',0,'a.x',3),('udp',0,'a.y','address')],'a.y'),
 ('malformed-edns',[('udp',0,'a.x','bad-opt')],'transport'),
 ('deadline',[('udp',0,'a.x','stall'),('udp',1,'a.x','stall')],'transport'),
 ('connection-refused',[],'dns:2'),
 ('pre',[],'abort:parent'),('error-first',[],'entropy:11'),
 ('error-second',[('udp',0,'a.x',3)],'entropy:38'),
 ('size',[],'zero'),('zero-attempts',[],'transport'),
 ('local',[],'local'),('local-invalid-name',[],'local'),
 ('source-error',[],'source:2'),('invalid-name',[],'invalid-name'),
 ('wrong-family',[('udp',0,'a.x',3),('udp',0,'a.y','address')],'a.y'),
 ('absolute',[('udp',0,'a','address')],'a'),
 ('dotted',[('udp',0,'a.z','address')],'a.z'),
]
rows=[]
for backend,command in [('native 1',['build/dns-hosts-resolver','--threads','1']),('native 4',['build/dns-hosts-resolver','--threads','4']),('Bun',[str(bun),'build/dns-hosts-resolver-audit.js'])]:
 for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
  for kind in [1,28]:
   for mode,plan,answer in cases:
    udp=[];tcp=[];held=[];process=None
    try:
     for _ in range(2):
      listener=socket.socket(af,socket.SOCK_STREAM);listener.bind((host,0));listener.listen()
      datagram=socket.socket(af,socket.SOCK_DGRAM);datagram.bind((host,listener.getsockname()[1]))
      tcp.append(listener);udp.append(datagram)
     ports=[x.getsockname()[1] for x in udp];trace=[];owners=[];started=time.monotonic()
     if mode=='connection-refused':
      for peer in udp:peer.close()
      udp=[]
     process=subprocess.Popen([*command,mode,str(family),*map(str,ports),str(15 if mode=='unsupported' else kind)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
     while process.poll() is None:
      assert time.monotonic()-started<9,(backend,mode,'hung',trace)
      ready,_,_=select.select(udp+tcp,[],[],.01)
      for peer in ready:
       stream=peer in tcp;index=(tcp if stream else udp).index(peer)
       if stream:
        client,_=peer.accept();client.settimeout(2);held.append(client);wire=exact(client,struct.unpack('!H',exact(client,2))[0])
       else:wire,client=peer.recvfrom(65536)
       ident,flags,qd,an,ns,ar=struct.unpack('!6H',wire[:12]);pos=12;labels=[]
       while wire[pos]:size=wire[pos];labels.append(wire[pos+1:pos+1+size].decode());pos+=1+size
       pos+=1;owner='.'.join(labels);question=wire[12:pos+4]
       assert question==namewire(owner)+struct.pack('!HH',kind,1)
       visit=('tcp' if stream else 'udp',index,owner)
       assert len(trace)<len(plan) and visit==plan[len(trace)][:3],(backend,family,kind,mode,trace,visit,plan)
       action=plan[len(trace)][3];trace.append(visit)
       if not owners or owners[-1]!=owner:owners.append(owner)
       assert ident==([0,65535,4660][min(len(owners)-1,2)]) and flags==256 and (qd,an,ns,ar)==(1,0,0,int(mode=='edns'))
       opt=b'\0'+struct.pack('!HHIH',41,1200,0,0)
       assert wire[pos+4:]==(opt if mode=='edns' else b'')
       if action=='stall':continue
       if action=='eof':client.close();held.remove(client);continue
       response_flags=0x8380 if action=='tc' else 0x8000 if action=='empty-rejected' else 0x8180|(action if isinstance(action,int) else 0)
       records=b'';count=0
       if action=='address' or str(action).startswith('alias:'):
        alias=str(action).startswith('alias:');data=namewire(action[6:]) if alias else bytes([1,2,3,4]) if kind==1 else bytes(15)+b'\1'
        records=b'\xc0\x0c'+struct.pack('!HHIH',5 if alias else kind,1,60,len(data))+data;count=1
       additional=2 if action=='bad-opt' else int(mode=='edns')
       response=struct.pack('!6H',ident,response_flags,1,count,0,additional)+question+records+opt*additional
       if stream:client.sendall(struct.pack('!H',len(response))+response)
       else:peer.sendto(response,client)
     out,err=process.communicate(timeout=1)
     assert trace==[x[:3] for x in plan],(mode,trace,plan,out,err)
     draws=0 if mode in ['pre','size','local','local-invalid-name','source-error','invalid-name'] else 1 if mode in ['error-first','zero-attempts','connection-refused'] else len(owners)+int(mode=='error-second')
     expected=answer if answer.startswith(('dns:','entropy:','abort:')) or answer in ['transport','zero','type','local','invalid-name'] or answer.startswith('source:') else selected(answer,kind)
     if answer=='local':
      token='a..x' if mode=='local-invalid-name' else 'a'
      address='4:2130706441' if kind==1 else '6:0,0,0,9'
      expected='local:'+address+'/'+','.join(str(ord(c)) for c in token)+'/;'
     elif answer.startswith('source:') or answer=='invalid-name':expected=answer
     reason='expiry' if mode=='deadline' else 'parent' if mode=='pre' else 'none'
     lines=([expected,reason]* (2 if mode=='repeat' else 1))+[f'next:{ports[0]}',f'draws:{draws}']
     assert process.returncode==0 and out.splitlines()==lines,(backend,family,kind,mode,out,err,lines)
     assert err==('AUDIT 0 0\n' if backend=='Bun' else 'AUDIT 0 0 0 0 0 0 0\n'),(mode,err)
     assert not select.select(udp+tcp,[],[],0)[0],(mode,'extra traffic')
     rows.append(dict(backend=backend,family=family,kind=kind,mode=mode,trace=trace,result=lines,seconds=time.monotonic()-started,audit=err.strip()))
    finally:
     if process is not None and process.poll() is None:process.kill();process.wait()
     for peer in udp+tcp+held:peer.close()
 print(f'{backend}: {4*len(cases)} configured searches PASS',flush=True)
sources=set()
def imports(path):
 path=path.resolve()
 if path in sources:return
 sources.add(path)
 for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-hosts-resolver.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_hosts_resolver_check.py']
record=dict(scope=__doc__,runs=rows,candidate=str(candidate),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-hosts-resolver-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-hosts-resolver-result.json').write_text(json.dumps(record,indent=2)+'\n')

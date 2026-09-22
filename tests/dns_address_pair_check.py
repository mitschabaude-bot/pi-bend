"""Live paired native DNS: shared ID reservation/order/deadline and complete child retirement."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import select
import socket
import struct
import subprocess
import time
from channel_audit import instrument

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN);candidate=p.parse_args().candidate.resolve()
bun=Path.home()/'.bun/bin/bun'
for suffix in ['c','js']:
 with (ROOT/f'build/dns-address-pair-{suffix}.log').open('w') as log:
  subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-address-pair-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-address-pair.bend','-o',f'build/dns-address-pair.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
audit='''
static void __attribute__((destructor)) pair_audit(void) {
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
(ROOT/'build/dns-address-pair-audit.c').write_text((ROOT/'build/dns-address-pair.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-address-pair-audit.c','-lpthread','-lm','-o','build/dns-address-pair'],cwd=ROOT,check=True)
(ROOT/'build/dns-address-pair-audit.js').write_text(instrument((ROOT/'build/dns-address-pair.js').read_text()))

def exact(peer,n):
 data=b''
 while len(data)<n:
  part=peer.recv(n-len(data));assert part,'early EOF';data+=part
 return data

def namewire(name):return b''.join(bytes([len(x)])+x.encode() for x in name.split('.'))+b'\0'
def answer(name,kind,empty=False):return 'ok:'+''.join(str(x)+',' for x in namewire(name))+':'+('' if empty else '4,16909060,60;' if kind==1 else '6,0,0,0,1,60;')
setup={'pre':('abort:parent:retained cancellation',0),'abort-first':('abort:parent:retained cancellation',1),'abort-second':('abort:parent:retained cancellation',2),
       'error-first':('entropy:4:11',1),'error-second':('entropy:6:12',2),
       'invalid-first':('encoding:4',2),'invalid-second':('encoding:6',2),'bad-name':('encoding:4',2),'bad-flags':('encoding:4',2),
       'zero':('zero',0),'no-servers':('servers',0)}
modes=['normal','reverse','same-ids','fixed','alias4','alias6','aliases','fallback4','forced','edns','refused4','empty4','deadline','wrong-class',*setup]
rows=[]
for backend,cmd in [('native 1',['build/dns-address-pair','--threads','1']),('native 4',['build/dns-address-pair','--threads','4']),('Bun',[str(bun),'build/dns-address-pair-audit.js'])]:
 for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
  for mode in modes:
   udp=[];tcp=[];clients=[];process=None;pending=[];trace=[];started=time.monotonic()
   try:
    for _ in range(2):
     listener=socket.socket(af,socket.SOCK_STREAM);listener.bind((host,0));listener.listen()
     datagram=socket.socket(af,socket.SOCK_DGRAM);datagram.bind((host,listener.getsockname()[1]))
     tcp.append(listener);udp.append(datagram)
    ports=[peer.getsockname()[1] for peer in udp]
    expected=[] if mode in setup or mode=='wrong-class' else [('tcp' if mode=='forced' else 'udp',0,kind,'a') for kind in [1,28]]
    if mode in ['alias4','aliases']:expected.append(('udp',0,1,'b'))
    if mode in ['alias6','aliases']:expected.append(('udp',0,28,'c'))
    if mode=='fallback4':expected.append(('tcp',0,1,'a'))
    if mode=='refused4':expected.append(('udp',1,1,'a'))
    process=subprocess.Popen([*cmd,mode,str(family),*map(str,ports)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    initial=set();released=False
    def respond(item):
     peer,client,stream,ident,question,kind,owner,index=item
     if mode=='deadline' and kind==28:return
     code=5 if mode=='refused4' and kind==1 and index==0 else 0
     tc=mode=='fallback4' and kind==1 and not stream
     alias=('b' if kind==1 else 'c') if owner=='a' and ((kind==1 and mode in ['alias4','aliases']) or (kind==28 and mode in ['alias6','aliases'])) else None
     empty=mode=='empty4' and kind==1
     data=namewire(alias) if alias else bytes([1,2,3,4]) if kind==1 else bytes(15)+b'\1'
     records=b'' if code or tc or empty else b'\xc0\x0c'+struct.pack('!HHIH',5 if alias else kind,1,60,len(data))+data
     flags=0x8380 if tc else 0x8180|code
     opt=b'\0'+struct.pack('!HHIH',41,1200,0,0) if mode=='edns' else b''
     response=struct.pack('!6H',ident,flags,1,int(bool(records)),0,int(bool(opt)))+question+records+opt
     if stream:client.sendall(struct.pack('!H',len(response))+response)
     else:peer.sendto(response,client)
    while process.poll() is None:
     assert time.monotonic()-started<8,(backend,family,mode,'hung',trace)
     ready,_,_=select.select(udp+tcp,[],[],.005)
     for peer in ready:
      stream=peer in tcp;index=(tcp if stream else udp).index(peer)
      if stream:
       client,_=peer.accept();client.settimeout(1);clients.append(client);wire=exact(client,struct.unpack('!H',exact(client,2))[0])
      else:wire,client=peer.recvfrom(65536)
      ident,flags,qd,an,ns,ar=struct.unpack('!6H',wire[:12]);pos=12;labels=[]
      while wire[pos]:size=wire[pos];labels.append(wire[pos+1:pos+1+size].decode());pos+=size+1
      pos+=1;kind,cls=struct.unpack('!HH',wire[pos:pos+4]);owner='.'.join(labels);question=wire[12:pos+4]
      visit=('tcp' if stream else 'udp',index,kind,owner);trace.append(visit)
      assert Counter(trace)<=Counter(expected),(backend,family,mode,trace,expected)
      expected_id=42 if mode=='same-ids' else 4660 if owner!='a' else 0 if kind==1 else 65535
      assert ident==expected_id and flags==256 and (qd,an,ns,ar,cls)==(1,0,0,int(mode=='edns'),1),(mode,wire)
      opt=b'\0'+struct.pack('!HHIH',41,1200,0,0) if mode=='edns' else b''
      assert wire[pos+4:]==opt,(mode,wire)
      item=(peer,client,stream,ident,question,kind,owner,index)
      if not released:
       pending.append(item);initial.add(kind)
       # Both questions must arrive before either gets an answer. This also
       # checks forced TCP concurrency without timing sleeps.
       if initial=={1,28}:
        released=True
        pending.sort(key=lambda item:item[5],reverse=mode=='reverse')
        for item in pending:respond(item)
        pending=[]
      else:respond(item)
    out,err=process.communicate(timeout=1)
    assert Counter(trace)==Counter(expected),(mode,trace,expected,out,err)
    if mode in setup:
     text,draws=setup[mode];lines=['setup:'+text];next_port=0 if mode=='no-servers' else ports[0]
    elif mode=='wrong-class':lines=['class'];draws=0;next_port=ports[0]
    else:
     lines=['4:'+answer('b' if mode in ['alias4','aliases'] else 'a',1,mode=='empty4'), '6:'+('transport' if mode=='deadline' else answer('c' if mode in ['alias6','aliases'] else 'a',28))]
     draws=4 if mode=='aliases' else 3 if mode in ['alias4','alias6'] else 2
     next_port=ports[0] if mode=='fixed' else ports[1]
    reason='expiry' if mode=='deadline' else 'parent:retained cancellation' if mode in ['pre','abort-first','abort-second'] else 'none'
    lines += ['deadline:'+reason,'draws:'+str(draws),'next:'+str(next_port)]
    assert process.returncode==0 and out.splitlines()==lines,(backend,family,mode,out,err,lines)
    assert err==('AUDIT 0 0 0\n' if backend=='Bun' else 'AUDIT 0 0 0 0 0 0 0\n'),(mode,err)
    assert not select.select(udp+tcp,[],[],0)[0],(mode,'extra traffic')
    rows.append(dict(backend=backend,family=family,mode=mode,trace=trace,result=lines,seconds=time.monotonic()-started,audit=err.strip()))
   finally:
    if process is not None and process.poll() is None:process.kill();process.wait()
    for peer in udp+tcp+clients:peer.close()
 print(f'{backend}: {2*len(modes)} paired exchanges PASS',flush=True)
sources=set()
def imports(path):
 path=path.resolve()
 if path in sources:return
 sources.add(path)
 for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-address-pair.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_address_pair_check.py','tests/channel_audit.py']
record=dict(scope=__doc__,runs=rows,candidate=str(candidate),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-address-pair-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-address-pair-result.json').write_text(json.dumps(record,indent=2)+'\n')

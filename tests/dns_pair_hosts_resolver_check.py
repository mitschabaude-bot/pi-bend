"""Live paired hosts/resolver adapter: canonical settings, local short circuit and persistent rotation."""
import argparse
import errno
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
 with (ROOT/f'build/dns-pair-hosts-resolver-{suffix}.log').open('w') as log:
  subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-pair-hosts-resolver-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-pair-hosts-resolver.bend','-o',f'build/dns-pair-hosts-resolver.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
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
(ROOT/'build/dns-pair-hosts-resolver-audit.c').write_text((ROOT/'build/dns-pair-hosts-resolver.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-pair-hosts-resolver-audit.c','-lpthread','-lm','-o','build/dns-pair-hosts-resolver'],cwd=ROOT,check=True)
(ROOT/'build/dns-pair-hosts-resolver-audit.js').write_text(instrument((ROOT/'build/dns-pair-hosts-resolver.js').read_text()))

def exact(peer,n):
 data=b''
 while len(data)<n:
  part=peer.recv(n-len(data));assert part,'early EOF';data+=part
 return data

def namewire(name):return b''.join(bytes([len(x)])+x.encode() for x in name.split('.'))+b'\0'
def answer(name,kind,empty=False):return 'ok:'+''.join(str(x)+',' for x in namewire(name))+':'+('' if empty else '4,16909060,60;' if kind==1 else '6,0,0,0,1,60;')
modes=['suffix','partial4','partial6','aliases','forced','edns','priority','exhausted','terminal','deadline','error-second-candidate','absolute','zero','local','local-invalid-name','local-v4','local-v6','source-error','invalid-name','repeat']
local={'local':'local:4:2130706441/97/;6:0,0,0,9/97/;4:2130706441/97/;', 'local-invalid-name':'local:6:0,0,0,9/97,46,46,120/;', 'local-v4':'local:4:2130706441/97/;', 'local-v6':'local:6:0,0,0,9/97/;', 'source-error':'source:2','invalid-name':'invalid-name'}
rows=[]
for backend,cmd in [('native 1',['build/dns-pair-hosts-resolver','--threads','1']),('native 4',['build/dns-pair-hosts-resolver','--threads','4']),('Bun',[str(bun),'build/dns-pair-hosts-resolver-audit.js'])]:
 for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
  for priority in [4,6]:
   for mode in modes:
    udp=[];tcp=[];clients=[];process=None;trace=[];pending={};started=time.monotonic()
    try:
     for _ in range(2):
      for attempt in range(128):
       listener=socket.socket(af,socket.SOCK_STREAM);datagram=socket.socket(af,socket.SOCK_DGRAM)
       try:
        listener.bind((host,0));listener.listen();datagram.bind((host,listener.getsockname()[1]))
       except OSError as error:
        listener.close();datagram.close()
        if error.errno!=errno.EADDRINUSE:raise
       else:
        tcp.append(listener);udp.append(datagram);break
      else:raise AssertionError('could not reserve a shared TCP/UDP fixture port')
     ports=[peer.getsockname()[1] for peer in udp]
     names=[] if mode=='zero' or mode in local else ['a.x','a.x'] if mode=='repeat' else ['a'] if mode=='absolute' else ['a.x'] if mode in ['partial4','partial6','terminal','error-second-candidate'] else ['a.x','a.y','a'] if mode=='exhausted' else ['a.x','a'] if mode=='priority' and priority==4 else ['a.x','a.y']
     transport='tcp' if mode in ['forced','priority'] else 'udp'
     expected=[(transport,i%2,k,n) for i,n in enumerate(names) for k in [1,28]]
     if mode=='aliases':expected += [('udp',1,1,'b'),('udp',1,28,'c')]
     process=subprocess.Popen([*cmd,mode,str(priority),str(family),*map(str,ports)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
     def respond(item):
      peer,client,stream,ident,question,kind,owner,index=item
      if mode=='deadline' and owner=='a.y' and kind==28:return
      code=3 if (owner=='a.x' and mode!='repeat') or mode=='exhausted' else 0
      if mode in ['partial4','partial6','terminal']:
       code=3 if mode=='partial4' and kind==28 or mode=='partial6' and kind==1 else 0
      if mode=='priority' and owner=='a.x':code=5 if kind==1 else 3
      alias=('b' if kind==1 else 'c') if mode=='aliases' and owner=='a.y' else None
      data=namewire(alias) if alias else bytes([1,2,3,4]) if kind==1 else bytes(15)+b'\1'
      # An invalid A payload is a terminal selection error, even if AAAA succeeds.
      if mode=='terminal' and kind==1:data=b'\1\2\3'
      records=b'' if code else b'\xc0\x0c'+struct.pack('!HHIH',5 if alias else kind,1,60,len(data))+data
      opt=b'\0'+struct.pack('!HHIH',41,1200,0,0) if mode=='edns' else b''
      response=struct.pack('!6H',ident,0x8180|code,1,int(bool(records)),0,int(bool(opt)))+question+records+opt
      if stream:client.sendall(struct.pack('!H',len(response))+response)
      else:peer.sendto(response,client)
     while process.poll() is None:
      assert time.monotonic()-started<8,(backend,family,priority,mode,'hung',trace)
      ready,_,_=select.select(udp+tcp,[],[],.005)
      for peer in ready:
       stream=peer in tcp;index=(tcp if stream else udp).index(peer)
       if stream:
        client,_=peer.accept();client.settimeout(1);clients.append(client);wire=exact(client,struct.unpack('!H',exact(client,2))[0])
       else:wire,client=peer.recvfrom(65536)
       ident,flags,qd,an,ns,ar=struct.unpack('!6H',wire[:12]);pos=12;labels=[]
       while wire[pos]:size=wire[pos];labels.append(wire[pos+1:pos+1+size].decode());pos+=size+1
       pos+=1;kind,cls=struct.unpack('!HH',wire[pos:pos+4]);owner='.'.join(labels);question=wire[12:pos+4]
       trace.append(('tcp' if stream else 'udp',index,kind,owner))
       assert Counter(trace)<=Counter(expected),(backend,family,priority,mode,trace,expected)
       assert flags==256 and (qd,an,ns,ar,cls)==(1,0,0,int(mode=='edns'),1),(mode,wire)
       if owner in names:assert ident==2*((len(trace)-1)//2 if mode=='repeat' else names.index(owner))+(kind==28),(mode,owner,ident)
       else:assert ident in [4,5],(mode,owner,ident)
       opt=b'\0'+struct.pack('!HHIH',41,1200,0,0) if mode=='edns' else b''
       assert wire[pos+4:]==opt,(mode,wire)
       item=(peer,client,stream,ident,question,kind,owner,index)
       if owner in names:
        batch=pending.setdefault(owner,[]);batch.append(item)
        if len(batch)==2:
         # No candidate gets a reply until both family queries have arrived.
         for response in sorted(batch,key=lambda x:x[5],reverse=priority==6):respond(response)
         pending[owner]=[]
       else:respond(item)
     out,err=process.communicate(timeout=1)
     assert Counter(trace)==Counter(expected),(mode,trace,expected,out,err)
     draws=2*len(names);rotations=len(names)
     if mode in local:lines=[local[mode]]
     elif mode=='zero':lines=['setup:zero']
     elif mode=='no-servers':lines=['setup:servers']
     elif mode=='error-second-candidate':lines=['setup:entropy:4:11'];draws=3
     elif mode=='exhausted':lines=['dns:1']
     else:
      name=names[-1]
      left='record' if mode=='terminal' else 'rcode:3' if mode=='partial6' else answer('b' if mode=='aliases' else name,1)
      right='transport' if mode=='deadline' else 'rcode:3' if mode=='partial4' else answer('c' if mode=='aliases' else name,28)
      lines=['halt' if mode in ['terminal','deadline'] else 'answer','4:'+left,'6:'+right]
      if mode=='aliases':draws+=2
     if mode not in local:lines+=['deadline:'+('expiry' if mode=='deadline' else 'none')]
     if mode=='repeat':lines=lines*2
     lines+=['draws:'+str(draws),'next:'+str(ports[rotations%2])]
     assert process.returncode==0 and out.splitlines()==lines,(backend,family,priority,mode,out,err,lines)
     assert err==('AUDIT 0 0 0\n' if backend=='Bun' else 'AUDIT 0 0 0 0 0 0 0\n'),(mode,err)
     assert not select.select(udp+tcp,[],[],0)[0],(mode,'extra traffic')
     rows.append(dict(backend=backend,family=family,priority=priority,mode=mode,trace=trace,result=lines,seconds=time.monotonic()-started,audit=err.strip()))
    finally:
     if process is not None and process.poll() is None:process.kill();process.wait()
     for peer in udp+tcp+clients:peer.close()
 print(f'{backend}: {4*len(modes)} paired searches PASS',flush=True)
sources=set()
def imports(path):
 path=path.resolve()
 if path in sources:return
 sources.add(path)
 for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-pair-hosts-resolver.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_pair_hosts_resolver_check.py','tests/channel_audit.py']
record=dict(scope=__doc__,runs=rows,candidate=str(candidate),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-pair-hosts-resolver-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-pair-hosts-resolver-result.json').write_text(json.dumps(record,indent=2)+'\n')

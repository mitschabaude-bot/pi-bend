"""Configured UDP/TCP address lookup shares alias, ID, cancellation and rotation machinery."""
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
    with (ROOT/f'build/dns-configured-lookup-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-configured-lookup-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-configured-lookup.bend','-o',f'build/dns-configured-lookup.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
source=(ROOT/'build/dns-configured-lookup.c').read_text()+'''
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
(ROOT/'build/dns-configured-lookup-audit.c').write_text(source)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-configured-lookup-audit.c','-lpthread','-lm','-o','build/dns-configured-lookup'],cwd=ROOT,check=True)
(ROOT/'build/dns-configured-lookup-audit.js').write_text('process.on("exit",()=>console.error(`AUDIT ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'+(ROOT/'build/dns-configured-lookup.js').read_text())

def exact(peer,n):
    data=b''
    while len(data)<n:
        part=peer.recv(n-len(data));assert part,'early EOF';data+=part
    return data

modes=['answer','alias','alias-loop','retry','rotate','rotate-alias','fallback','forced','forced-alias','edns','empty','nxdomain','deadline','pre','abort-source','abort-child','error-first','error-second','size','unsupported','zero-attempts']
rows=[]
for backend,command in [('native 1',['build/dns-configured-lookup','--threads','1']),('native 4',['build/dns-configured-lookup','--threads','4']),('Bun',[str(bun),'build/dns-configured-lookup-audit.js'])]:
    for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for kind in [1,28]:
            for mode in modes:
                udp=[];tcp=[];held=[];process=None
                try:
                    for _ in range(2):
                        listener=socket.socket(af,socket.SOCK_STREAM);listener.bind((host,0));listener.listen()
                        datagram=socket.socket(af,socket.SOCK_DGRAM);datagram.bind((host,listener.getsockname()[1]))
                        tcp.append(listener);udp.append(datagram)
                    ports=[peer.getsockname()[1] for peer in udp]
                    started=time.monotonic()
                    process=subprocess.Popen([*command,mode,str(family),*map(str,ports),str(15 if mode=='unsupported' else kind)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                    trace=[]
                    while process.poll() is None:
                        assert time.monotonic()-started<7,(backend,family,kind,mode,'hung',trace)
                        ready,_,_=select.select(udp+tcp,[],[],.01)
                        for peer in ready:
                            stream=peer in tcp;index=(tcp if stream else udp).index(peer)
                            if stream:
                                client,_=peer.accept();client.settimeout(2);held.append(client)
                                wire=exact(client,struct.unpack('!H',exact(client,2))[0])
                            else:wire,client=peer.recvfrom(65536)
                            ident,flags,qd,an,ns,ar=struct.unpack('!6H',wire[:12])
                            qname=wire[13:14];question=wire[12:19]
                            assert qname in [b'a',b'b'] and question==b'\x01'+qname+b'\0'+struct.pack('!HH',kind,1)
                            assert ident==(0 if qname==b'a' else 65535) and flags==256 and (qd,an,ns,ar)==(1,0,0,int(mode=='edns')),(mode,wire.hex())
                            opt=b'\0'+struct.pack('!HHIH',41,1200,0,0)
                            assert wire[19:]==(opt if mode=='edns' else b''),(mode,'request options')
                            trace.append(('tcp' if stream else 'udp',index,qname.decode(),ident))
                            if mode in ['deadline','abort-source']:continue
                            response_flags=0x8180;records=b'';count=0
                            if mode=='fallback' and not stream:response_flags=0x8380
                            elif mode in ['retry','rotate'] and index==0:response_flags=0x8182
                            elif mode=='nxdomain':response_flags=0x8183
                            elif mode=='empty':pass
                            else:
                                alias=mode in ['alias','alias-loop','rotate-alias','forced-alias','error-second'] and (qname==b'a' or mode=='alias-loop')
                                target=b'b' if qname==b'a' else b'a'
                                data=b'\1'+target+b'\0' if alias else bytes([1,2,3,4]) if kind==1 else bytes(15)+b'\1'
                                records=b'\xc0\x0c'+struct.pack('!HHIH',5 if alias else kind,1,60,len(data))+data;count=1
                            response=struct.pack('!6H',ident,response_flags,1,count,0,int(mode=='edns'))+question+records+(opt if mode=='edns' else b'')
                            if stream:client.sendall(struct.pack('!H',len(response))+response)
                            else:peer.sendto(response,client)
                    out,err=process.communicate(timeout=1)
                    protocol='tcp' if mode in ['forced','forced-alias'] else 'udp'
                    expected_trace=[(protocol,0,'a',0)]
                    if mode in ['alias','alias-loop','forced-alias']:expected_trace.append((protocol,0,'b',65535))
                    elif mode=='rotate-alias':expected_trace.append(('udp',1,'b',65535))
                    elif mode in ['retry','rotate','deadline']:expected_trace.append(('udp',1,'a',0))
                    elif mode=='fallback':expected_trace.append(('tcp',0,'a',0))
                    elif mode in ['pre','abort-source','abort-child','error-first','size','unsupported','zero-attempts']:expected_trace=[]
                    if mode=='abort-source':
                        assert trace in [[], [('udp',0,'a',0)]], trace
                    else:assert trace==expected_trace,(backend,family,kind,mode,trace)
                    canonical=98 if mode in ['alias','rotate-alias','forced-alias'] else 97
                    address='4,16909060,60;' if kind==1 else '6,0,0,0,1,60;'
                    expected=f'ok:1,{canonical},0,:{address}'
                    expected={'alias-loop':'loop','empty':'ok:1,97,0,:','nxdomain':'rcode:3','deadline':'transport','pre':'abort:parent','abort-source':'abort:parent','abort-child':'abort:parent','error-first':'entropy:11','error-second':'entropy:38','size':'zero','unsupported':'type','zero-attempts':'transport'}.get(mode,expected)
                    draws=0 if mode in ['pre','size','unsupported'] else 2 if mode in ['alias','alias-loop','rotate-alias','forced-alias','error-second'] else 1
                    reason='expiry' if mode=='deadline' else 'parent' if mode in ['pre','abort-source','abort-child'] else 'none'
                    next_port=ports[1] if mode=='rotate' else ports[0]
                    if mode=='abort-source':
                        actual=out.splitlines()
                        assert len(actual)==4 and actual[0] in ['abort:parent','transport'],(mode,out,err)
                        assert actual[2] in [f'next:{value}' for value in ports]
                        if trace:assert actual[2]==f'next:{ports[1]}'
                        expected=actual[0];next_port=int(actual[2].split(':')[1])
                    lines=[expected,reason,f'next:{next_port}',f'draws:{draws}']
                    assert process.returncode==0 and out.splitlines()==lines,(backend,family,kind,mode,out,err,lines)
                    assert err==('AUDIT 0 0\n' if backend=='Bun' else 'AUDIT 0 0 0 0 0 0 0\n'),(mode,err)
                    assert not select.select(udp+tcp,[],[],0)[0],(mode,'extra traffic')
                    rows.append(dict(backend=backend,family=family,kind=kind,mode=mode,trace=trace,result=lines,seconds=time.monotonic()-started,audit=err.strip()))
                finally:
                    if process is not None and process.poll() is None:process.kill();process.wait()
                    for peer in udp+tcp+held:peer.close()
    print(f'{backend}: {4*len(modes)} configured address lookups PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-configured-lookup.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_configured_lookup_check.py']
record=dict(scope=__doc__,runs=rows,candidate=str(candidate),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-configured-lookup-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-configured-lookup-result.json').write_text(json.dumps(record,indent=2)+'\n')

"""Disposable syscall-boundary checks of endpoint decoding and error paths.

Native ABI is Linux. JS additionally simulates Darwin sockaddr bytes; that is
not a real Darwin FFI/platform test. Production effects remain unchanged.
"""
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1];candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve();bun=Path.home()/'.bun/bin/bun'
c_helper=r'''
static int endpoint_probe(int fd, struct sockaddr* address, socklen_t* length, int side) {
  int test=atoi(getenv("ENDPOINT_CASE"));
  if(test==6){errno=EBADF;return -1;}
  if(test==3){address->sa_family=AF_UNIX;*length=sizeof(struct sockaddr);return 0;}
  if(test==0||test==4||test==7){
    struct sockaddr_in at={0};at.sin_family=AF_INET;
    at.sin_addr.s_addr=htonl(test==7?0xffffffff:0x12345678);
    at.sin_port=htons(test==7?0:54321);
    memcpy(address,&at,sizeof(at));*length=test==4?15:sizeof(at);return 0;
  }
  struct sockaddr_in6 at={0};at.sin6_family=AF_INET6;
  uint32_t words[4]={htonl(0x01020304),htonl(0x89abcdef),htonl(0xfedcba98),htonl(0xffffffff)};
  if(test!=2)memcpy(&at.sin6_addr,words,sizeof(words));
  at.sin6_port=htons(test==2?0:65535);at.sin6_scope_id=test==2?0:0xdeadbeef;
  memcpy(address,&at,sizeof(at));*length=test==5?27:sizeof(at);return 0;
}
'''
js_mock=r'''
  const sys = {...io_sys(), mac: process.env.ENDPOINT_MAC==='1', ptr:x=>x, errno:()=>9};
  const probe=(fd,address,length)=>{
    const test=Number(process.env.ENDPOINT_CASE);
    if(test===6)return -1;
    const view=new DataView(address.buffer);
    const little=new Uint8Array(new Uint16Array([1]).buffer)[0]===1;
    const family=test===3?1:([0,4,7].includes(test)?2:(sys.mac?30:10));
    if(sys.mac){address[0]=family===2?16:28;address[1]=family;}
    else view.setUint16(0,family,little);
    length[0]=test===4?15:(test===5?27:(family===2?16:28));
    if(family===2){view.setUint32(4,test===7?0xffffffff:0x12345678,false);view.setUint16(2,test===7?0:54321,false);}
    else if(test!==2){
      [0x01020304,0x89abcdef,0xfedcba98,0xffffffff].forEach((x,i)=>view.setUint32(8+i*4,x,false));
      view.setUint16(2,65535,false);view.setUint32(24,0xdeadbeef,little);
    }
    return 0;
  };
  globalThis.BEND_SOCKET_ENDPOINT={symbols:{getsockname:probe,getpeername:probe}};
'''
rows=[]
with tempfile.TemporaryDirectory(prefix='socket-endpoint-layout-',dir=ROOT/'build') as directory:
    folder=Path(directory)
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',str(folder/f'{suffix}-build.json'),'--',str(bun),str(candidate/'main.ts'),'tests/socket-endpoint-probe.bend','-o',str(folder/f'probe.{suffix}')],cwd=ROOT,check=True)
    p=folder/'probe.c';text=p.read_text();original=(candidate/'effs/socket_endpoint.c').read_text();assert original in text
    changed=c_helper+original.replace('getsockname(fd, (struct sockaddr*)&address, &length)','endpoint_probe(fd, (struct sockaddr*)&address, &length, 0)').replace('getpeername(fd, (struct sockaddr*)&address, &length)','endpoint_probe(fd, (struct sockaddr*)&address, &length, 1)')
    p.write_text(text.replace(original,changed));subprocess.run(['clang','-fbracket-depth=2048','-std=c11','-O1',str(p),'-lpthread','-lm','-o',str(folder/'probe')],check=True,timeout=60)
    p=folder/'probe.js';text=p.read_text();original=(candidate/'effs/socket_endpoint.js').read_text();assert original in text
    assert original.count('  const sys = io_sys();')==1;p.write_text(text.replace(original,original.replace('  const sys = io_sys();',js_mock)))
    commands=[('native 1',[str(folder/'probe'),'--threads','1'],False),('native 4',[str(folder/'probe'),'--threads','4'],False),('Bun Linux layout',[str(bun),str(p)],False),('Bun simulated Darwin layout',[str(bun),str(p)],True)]
    for label,command,mac in commands:
        for test in range(8):
            for side in [0,1,2]:
                if side==2:expected='error:22'
                elif test==6:expected='error:9'
                elif test in [3,4,5]:expected='error:'+str(47 if mac else 97)
                elif test==0:expected='4,305419896,0,0,0,54321,0'
                elif test==7:expected='4,4294967295,0,0,0,0,0'
                elif test==2:expected='6,0,0,0,0,0,0'
                else:expected='6,16909060,2309737967,4275878552,4294967295,65535,3735928559'
                run=subprocess.run([*command,str(side)],cwd=ROOT,env=dict(os.environ,ENDPOINT_CASE=str(test),ENDPOINT_MAC='1' if mac else '0'),capture_output=True,text=True,timeout=10)
                assert run.returncode==0 and run.stdout==expected+'\n' and not run.stderr,(label,test,side,run,expected)
                rows.append(dict(backend=label,test=test,side=side,result=expected))
        print(label+': endpoint sockaddr boundary PASS',flush=True)
report={'scope':__doc__,'cases':rows,'sha256':{name:hashlib.sha256((candidate/'effs'/name).read_bytes()).hexdigest() for name in ['socket_endpoint.c','socket_endpoint.js']}}
(ROOT/'build/socket-endpoint-layout-result.json').write_text(json.dumps(report,indent=2)+'\n')

"""Configuration address tokens against Linux libc IPv4 and inet_pton IPv6.

IPv6 zone text is preserved, not interpreted as an OS interface here.
"""
import ctypes
import hashlib
import ipaddress
import json
from pathlib import Path
import random
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2/main.ts'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-address-{suffix}-build.json','--',str(bun),str(compiler),'tests/resolver-address.bend','-o',f'build/resolver-address.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-address.c','-lpthread','-lm','-o','build/resolver-address'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);aton=libc.__inet_aton_exact;aton.argtypes=[ctypes.c_char_p,ctypes.c_void_p];aton.restype=ctypes.c_int

def oracle(text):
    word=ctypes.create_string_buffer(4)
    if aton(text.encode(),word):return '4:'+str(int.from_bytes(word.raw,'big'))
    host,sep,zone=text.partition('%')
    try:raw=socket.inet_pton(socket.AF_INET6,host)
    except OSError:return 'invalid'
    return '6:'+','.join(str(int.from_bytes(raw[i:i+4],'big')) for i in range(0,16,4))+':'+('some:'+zone if sep else 'none')

values=['','0','1','127.1','0x7f.1','0177.1','127.0.0.1','255.255.255.255','4294967295',
        '4294967296','1.16777215','1.16777216','1.2.65535','1.2.65536','0x','0X','1.0x',
        '1.0X.2','1.2.3.','1.2.3.4.','1..2','+1','-1','1.2.3.256','1.2.3.4.5','09','08',
        '::','::1','::ffff:192.0.2.1','[::1]','::ffff:192.000.2.1','fe80::1%eth0','fe80::1%1',
        'fe80::1%','fe80::1%0','fe80::1%4294967295','fe80::1%4294967296','fe80::1%a%b',
        '2001:db8::1%arbitrary','127.0.0.1%lo','localhost','example.com','0b101','０','١','1\r',
        '1\n',' 1','1 ','1\t','1#comment','::1 ','::1\r','0'*10000,'1.'*10000,'f:'*10000]
rng=random.Random(128481)
for _ in range(384):
    n=rng.getrandbits(32);b=n.to_bytes(4,'big')
    values.extend(['.'.join(map(str,b)),hex(n),oct(n)[1:],str(n),f'{b[0]}.{n&0xffffff}',f'{b[0]}.{b[1]}.{n&65535}',
                   f'{b[0]}.{b[1]}.{b[2]}.{b[3]}.',f'{b[0]}.0x'])
for _ in range(384):
    address=ipaddress.IPv6Address(rng.getrandbits(128))
    values.extend([address.compressed,address.exploded,address.exploded.upper(),str(address)+'%lo',str(address)+'%12',str(address)+':'])
values=list(dict.fromkeys(values));expected=[oracle(v) for v in values];rows=[]
for label,command in [('native 1',['build/resolver-address','--threads','1']),('native 4',['build/resolver-address','--threads','4']),('Bun',[str(bun),'build/resolver-address.js'])]:
    for start in range(0,len(values),128):
        batch=values[start:start+128];want=expected[start:start+128]
        run=subprocess.run([*command,*batch],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(label,run)
        got=run.stdout.splitlines()
        assert len(got)==len(want),(label,start,len(got),len(want))
        for token,actual,result in zip(batch,got,want):assert actual==result,(label,repr(token),actual,result)
    rows.append(dict(backend=label,cases=len(values)));print(f'{label}: {len(values)} resolver address tokens PASS',flush=True)
paths=['packages/runtime/src/resolver-address.bend','tests/resolver-address.bend','tests/resolver_address_check.py','build/resolver-address','build/resolver-address.js']
(ROOT/'build/resolver-address-result.json').write_text(json.dumps(dict(scope=__doc__,cases=rows,libc_version=list(__import__('platform').libc_ver()),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}),indent=2)+'\n')

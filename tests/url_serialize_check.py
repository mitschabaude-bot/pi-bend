"""Normalized URL record serialization, including hostless path ambiguity."""
import ipaddress
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def record(scheme='https', user='', password='', host=('d','example.com'), port=None,
           path=None, opaque=False, query=None, fragment=None):
    return dict(scheme=scheme,user=user,password=password,host=host,port=port,
                path=([''] if path is None else path),opaque=opaque,query=query,fragment=fragment)

def host_text(host):
    kind, value = host
    if kind == '4': return str(ipaddress.IPv4Address(value))
    if kind == '6': return '[::1]'
    return value

def serialize(value, exclude=False):
    v=value
    out=v['scheme']+':'
    if v['host'][0]!='n':
        out+='//'
        if v['user'] or v['password']:
            out+=v['user']+(':'+v['password'] if v['password'] else '')+'@'
        out+=host_text(v['host'])
        if v['port'] is not None: out+=':'+str(v['port'])
    elif not v['opaque'] and len(v['path'])>1 and v['path'][0]=='':
        out+='/.'
    out+=v['path'] if v['opaque'] else ''.join('/'+part for part in v['path'])
    if v['query'] is not None: out+='?'+v['query']
    if not exclude and v['fragment'] is not None: out+='#'+v['fragment']
    return out

records=[]
for scheme in ['ftp','http','https','ws','wss']:
    for host in [('d','example.com'),('d','xn--bcher-kva.example'),('4',2130706433),('4',4294967295),('6','')]:
        for user,password in [('', ''),('user',''),('','password'),('u%40x','p%3Ass'),('%25','%F0%9F%99%82')]:
            for port in [None,0,65535]:
                for query,fragment in [(None,None),('',None),(None,''),('',''),('x+y=%20','f#tail')]:
                    records.append(record(scheme,user,password,host,port,query=query,fragment=fragment))
for host in [('e',''),('d','server'),('4',2130706433),('6','')]:
    for path in [[''],['C:',''],['C:','folder','file.txt'],['','a',''],['usr','local']]:
        records.append(record('file',host=host,path=path,query='',fragment=''))
for host in [('n',''),('e',''),('o','Example.COM'),('o','%C3%A9'),('6','')]:
    for path in [[],[''],['a'],['',''],['','not-a-host',''],['a','','b'],['a%2Fb','%252e']]:
        for query,fragment in [(None,None),('',None),(None,''),('',''),('q','f')]:
            records.append(record('custom',host=host,path=path,query=query,fragment=fragment))
for scheme in ['mailto','data','urn','custom']:
    for path in ['', 'user@example.com', 'text/plain,hello%20world', 'a b c', '%00%25', 'x:y/z']:
        for query,fragment in [(None,None),('',None),(None,''),('',''),('q','f#tail')]:
            records.append(record(scheme,host=('n',''),path=path,opaque=True,query=query,fragment=fragment))
rng=random.Random(20260924)
for _ in range(1000):
    scheme=rng.choice(['http','https','custom'])
    records.append(record(scheme,user=rng.choice(['','u','u%3Av','%C3%A9']),password=rng.choice(['','p','p%40x']),
        host=('d','example.com') if scheme!='custom' else ('o','Example.COM'),
        port=rng.choice([None,0,1234,65535]),path=rng.choices(['','x','y%2Fz','%252e','%C3%A9','%F0%9F%99%82','a%20b'],k=rng.randrange(1,12)),
        query=rng.choice([None,'','x+y=%25','%C3%A9']),fragment=rng.choice([None,'','f?x#y','%F0%9F%99%82'])))
for size in [1024,8192]:
    records += [record(user='u'*size),record(password='p'*size),record(path=['x']*size),
                record(path=['x'*size]),record(query='q'*size),record(fragment='f'*size),
                record('custom',host=('n',''),path=['','x'*size]),
                record('data',host=('n',''),path='x'*size,opaque=True)]
expected=[(serialize(v),serialize(v,True)) for v in records]
# Every input here is a normalized, already encoded record; the serializer is
# deliberately not responsible for normalizing raw credentials, paths or ports.
script=r'''
const inputs=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(inputs.map(text=>{const u=new URL(text);return [u.href,u.href.split('#')[0]]})));
'''
actual=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps([v[0] for v in expected]),text=True))
for index,(got,want) in enumerate(zip(actual,expected,strict=True)):
    assert tuple(got)==want,(index,records[index],got,want)
print(f'Node serializer cross-check: {len(records)} records PASS',flush=True)
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/url-serialize.bend','build/url-serialize'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/url-serialize.bend','-o','build/url-serialize.js'],cwd=ROOT,check=True)
def codes(text):return ','.join(map(str,map(ord,text)))
def optional(value):return '-' if value is None else codes(value)
def wire(v):
    kind,host=v['host']
    return ';'.join([v['scheme'],codes(v['user']),codes(v['password']),kind,str(host) if kind=='4' else codes(host),
                     '-' if v['port'] is None else str(v['port']), 'o' if v['opaque'] else 'h',
                     codes(v['path']) if v['opaque'] else ':'.join(map(codes,v['path'])) if v['path'] else '-',
                     optional(v['query']),optional(v['fragment'])])
arguments=list(map(wire,records))
reference=[';'.join(map(codes,pair)) for pair in expected]
for label,command in [('native 1',['build/url-serialize','--threads','1']),('native 4',['build/url-serialize','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-serialize.js'])]:
    start=0
    while start<len(arguments):
        end,size=start,0
        while end<len(arguments) and end-start<64 and size+len(arguments[end])<262144:
            size+=len(arguments[end]);end+=1
        assert end>start
        result=subprocess.run([*command,*arguments[start:end]],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),reference[start:end],strict=True)):
            assert got==want,(label,start+offset,records[start+offset],got[:500],want[:500])
        start=end
    print(f'{label}: {len(records)} URL records, with/without fragment PASS',flush=True)

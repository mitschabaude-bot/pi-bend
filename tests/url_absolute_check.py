"""Absolute URL parser composition against actual Node URL construction.

The nine known IDNA policy differences are tested under explicit strict options
and reported separately, not counted as Node compatibility.
"""
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
if '--js-only' in sys.argv and '--native-only' in sys.argv:
    raise SystemExit('Choose at most one backend restriction')
texts=['','relative','//example.com','/a','?q','#f','1abc:x','http:','https:?q','ftp:#f',
       'http:example.com','https:/example.com','http:\\example.com','http:////example.com',
       'http://user:pass@example.com:80/a/../b?q#f','https://bücher.example:443/é?x=🙂#f',
       'http://①.②.③.④/','http://[::1]:80/','https://[::ffff:192.0.2.1]:65535/a',
       'https://a:65536/','https://a:123x/','https://:80/','https://@/','http://a%2fb/',
       'http://%EF%BB%BFexample.com/','http://%5B::1%5D/','http://%ED%A0%80/',
       'custom:','custom:a b?x#f','custom:a  ?q','custom:/','custom://','custom:///',
       'custom://:','custom://@','custom://u:p@Host:80/a','custom://é/a','custom://%gg/a',
       'custom:/..//not-a-host/','custom:/a/..//not-a-host/','custom:\\host\\path',
       'data:text/plain,hello%20world','mailto:user@example.com','urn:example:a/b/../c',
       'file:','file:?q','file:#f','file:a','file:/a','file://','file:///','file:////a',
       'file:C|/a/../b','file:/C:/../../b','file://C:/a','file://C|/a','file://%43:/a',
       'file://localhost/a','file://LOCALHOST/a','file://loc%61lhost/a','file://user@host/a',
       'file://host:80/a','file://host:/a','file://[::1]/a','file://127.1/a',
       'file:\\C:\\a','file:\\\\host\\a','file:/\\host/a','file:\\/host/a']
for scheme in ['http','https','ftp','ws','wss','custom','file']:
    for slashes in ['', '/', '//', '///', '\\', '\\\\', '/\\', '\\/']:
        for tail in ['', 'example.com', 'user:pass@example.com:443/a', 'C|/a', '?q#f', '#f']:
            texts.append(scheme+':'+slashes+tail)
for scheme in ['http','https','custom','file']:
    for host in ['example.com','EXAMPLE.com','bücher.example','127.1','0x7f.1','[::1]','', '.', 'a..b','xn--abc-','a%20b','a%2eb','%gg']:
        for port in ['', ':', ':0', ':80', ':443', ':65535', ':65536', ':x']:
            texts.append(scheme+'://'+host+port+'/a/../b?x+y=%20#z')
for code in range(128):
    texts += [chr(code)+'HTTP://example.com/a'+chr(code), 'http://a'+chr(code)+'b/', 'data:a'+chr(code)+'b?q#f']
rng=random.Random(20260928)
for _ in range(1000):
    scheme=rng.choice(['http','https','custom','file'])
    user=rng.choice(['','u@','u:p@','u@@','u:p@x@',':p@']) if scheme!='file' else ''
    host=rng.choice(['example.com','bücher.example','127.1','[::1]','localhost',''])
    port=rng.choice(['',':80',':443',':00021',':65535',':x']) if scheme!='file' else ''
    path='/'.join(rng.choices(['a','','.','..','%2e','%2E%2e','é🙂','C|','%2f','a b'],k=rng.randrange(1,12)))
    texts.append(scheme+'://'+user+host+port+'/'+path+rng.choice(['','?','#','?q=x+y#f','#f?q']))
for size in [1024,8192]:
    texts += ['https://example.com/'+'a/'*size+'../end','data:'+'x'*size+'  ?q#f',
              'file:///C:/'+'../'*size+'x','custom:/..//'+'x'*size]
script=r'''
const texts=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(texts.map(text=>{try{return new URL(text).href}catch{return null}})));
'''
actual=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps(texts),text=True))
def codes(text):return ','.join(map(str,map(ord,text)))
expected=['invalid' if value is None else '+'+codes(value) for value in actual]
parity_count=len(texts)
review=json.loads((ROOT/'docs/idna-context-review.json').read_text())
for row in review['cases']:
    texts.append('http://'+row['input']+'/');expected.append('invalid')
print(f'{parity_count} Node absolute-URL cases; {len(review["cases"])} explicit strict-policy cases',flush=True)
if '--prepare-only' in sys.argv:raise SystemExit(0)
if '--no-build' not in sys.argv and '--js-only' not in sys.argv:
    subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib','32','--stats','build/url-absolute-check-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/url-absolute.bend','build/url-absolute'],cwd=ROOT,check=True)
if '--native-only' not in sys.argv and '--no-js-build' not in sys.argv:
    subprocess.run([str(Path(BEND)),'packages/runtime/test/url-absolute.bend','-o','build/url-absolute.js'],cwd=ROOT,check=True)
arguments=list(map(codes,texts))
backends=[('native 1',['build/url-absolute','--threads','1']),('native 4',['build/url-absolute','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-absolute.js'])]
if '--js-only' in sys.argv:backends=backends[2:]
if '--native-only' in sys.argv:backends=backends[:2]
for label,command in backends:
    for start in range(0,len(arguments),16):
        result=subprocess.run([*command,*arguments[start:start+16]],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+16],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got[:500],want[:500])
    print(f'{label}: {len(texts)} absolute URL cases PASS ({len(review["cases"])} explicit strict-policy cases are not Node parity)',flush=True)

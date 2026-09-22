"""Host-stage rules with actual Node URL oracles where input boundaries match."""
import ipaddress
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
rng=random.Random(20260919)
rows=[]
for text in ['', 'example.com','example.com.','a..b','localhost','xn--bcher-kva','0','0x','0xffffffff','127.1','0177.1','1.2.65535','1.2.65536','09','a.42','a.0xg','a.0xf','1.2.3.4.5','4294967296','-','ab--c']:
    rows.append(['d',text])
for _ in range(700):
    text='.'.join(''.join(rng.choice('abcxyz0123456789-_') for _ in range(rng.randrange(10))) for _ in range(rng.randrange(1,6)))
    rows.append(['d',text])
for text in ['', 'EXAMPLE.com','127.1','0x7f.1','é','例え','🙂','a%20b','%','%gg','%ff','%2520','%00','a_b','a`b','a{b','a}b','a"b']:
    rows.append(['o',text])
for code in [*range(256),0x3002,0xfeff,0xfffd,0x1f642,0x10ffff]:
    for mode in ['d','o']:
        rows.append([mode,'a'+chr(code)+'b'])
for _ in range(400):
    rows.append(['o',''.join(rng.choice('abcXYZ012.%!-_é🙂\x01\x7f') for _ in range(rng.randrange(40)))])
for text in ['::1]','::]','2001:DB8::1]','::ffff:192.0.2.1]','::ffff:192.00.2.1]','::1','::1]:80','::1]/]','::1%25lo]','[::1]]',']','1:2:3:4:5:6:7:8]','1:2:3]']:
    rows.extend([['6',text],['o','['+text]])
for _ in range(200):
    address=ipaddress.IPv6Address(rng.getrandbits(128))
    rows.extend([['6',address.exploded+']'],['o','['+address.compressed+']']])
for text in ['a'*8192,'a'*8192+'%gg','0'*8192+'1','['+'0'*8192+']']:
    rows.extend([['d',text],['o',text]])
# Special-domain classification is called AFTER domain processing. Apply its
# ASCII case normalization in the test adapter before comparing both backends.
rows=[(mode,''.join(chr(ord(c)+32) if 'A'<=c<='Z' else c for c in text) if mode=='d' else text) for mode,text in rows]
oracle=r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
const forbidden=new Set([0,9,10,13,32,35,47,58,60,62,63,64,91,92,93,94,124]);
const codes=text=>Array.from(text,c=>c.codePointAt(0)).join(',');
let nodeComparisons=0;
const values=rows.map(([mode,text])=>{
 let host=text;
 if(mode==='6')host='['+text;
 // IPv6 dispatch occurs before opaque-host character rejection.
 if(mode==='6'||mode==='o'&&host.startsWith('[')){
  if(!/^\[[0-9A-Fa-f:.]+\]$/.test(host))return 'invalid';
  nodeComparisons++;
  try{return 'ipv6;'+codes(new URL('custom://'+host+'/').hostname)}catch{return 'invalid'}
 }
 const points=Array.from(host,c=>c.codePointAt(0));
 // Raw host parsing receives text AFTER the URL parser handles delimiters and
 // strips tabs/newlines. Guard those boundaries independently of full URL parsing.
 if(mode==='d'){
  if(!host||points.some(c=>c>127||c<32||c===37||c===127||forbidden.has(c)))return 'invalid';
  nodeComparisons++;
  try{
   const value=new URL('http://'+host+'/').hostname;
   return (/^\d+\.\d+\.\d+\.\d+$/.test(value)?'ipv4':'domain')+';'+codes(value);
  }catch{return 'invalid'}
 }
 if(points.some(c=>forbidden.has(c)))return 'invalid';
 nodeComparisons++;
 try{const value=new URL('custom://'+host+'/').hostname;return (value?'opaque':'empty')+';'+codes(value)}catch{return 'invalid'}
});
console.log(JSON.stringify({values,nodeComparisons}));
'''
reference=json.loads(subprocess.check_output(['node','-e',oracle],input=json.dumps(rows),text=True))
arguments=[mode+';'+','.join(map(str,map(ord,text))) for mode,text in rows]
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/url-host.bend','build/url-host'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/url-host.bend','-o','build/url-host.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/url-host','--threads','1']),('native 4',['build/url-host','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-host.js'])]:
    for start in range(0,len(arguments),64):
        result=subprocess.run([*command,*arguments[start:start+64]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),reference['values'][start:start+64],strict=True)):
            assert got==want,(label,start+offset,rows[start+offset],got,want)
    print(f'{label}: {len(rows)} host-stage cases PASS ({reference["nodeComparisons"]} actual Node comparisons)',flush=True)

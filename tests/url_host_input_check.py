"""Raw special-host preparation, before domain validity or normalization."""
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys
from urllib.parse import unquote_to_bytes
ROOT=Path(__file__).resolve().parents[1]
texts=['','example.com','EXAMPLE.com','+','%2b','a+b','a%20b','%2520','%25EF%25BB%25BF','\ufeffa','%EF%BB%BFa','%ef%bb%bfa','%EF%BB%BF%EF%BB%BFa','%E2%82','%ED%A0%80','%F4%90%80%80','%C0%80','%','%2','%gg🙂%00','%5B::1%5D','[::1]','[2001:DB8::1]','[::ffff:192.0.2.1]','[::ffff:192.00.2.1]','[::1','[::1%25lo]','[::1%5D','[::1]/]','[::1]:80']
texts += [f'a%{code:02X}b' for code in range(256)]
texts += ['%'+format(a,'02X')+'%'+format(b,'02X') for a in [0,37,127,128,194,224,237,239,240,244,255] for b in range(256)]
rng=random.Random(20260920)
texts += [''.join(rng.choice(['a','+','%','%gg','%20','%E2','%82','%AC','%00','%EF%BB%BF','é','🙂']) for _ in range(rng.randrange(40))) for _ in range(500)]
# Full output comparisons retain incomplete UTF-8 at the end of long strings.
for size in [1024,8192,16384]:
    texts += ['a'*size+suffix for suffix in ['%F0','%E2%82','%EF%BB%BF','%25']]
def codes(text): return ','.join(map(str,map(ord,text)))
expected=[]
for text in texts:
    if not text: expected.append('invalid')
    elif text.startswith('['): expected.append(None)
    else: expected.append('domain;'+codes(unquote_to_bytes(text).decode('utf-8','replace')))
# Independent JS byte walk and TextDecoder cross-check the Python oracle.
oracle=r'''
const inputs=JSON.parse(require('fs').readFileSync(0,'utf8'));
const hex=c=>c>=48&&c<=57?c-48:c>=65&&c<=70?c-55:c>=97&&c<=102?c-87:-1;
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
console.log(JSON.stringify(inputs.map(text=>{
 if(!text)return 'invalid';
 if(text.startsWith('[')){
  if(!/^\[[0-9A-Fa-f:.]+\]$/.test(text))return 'invalid';
  try{return 'literal;'+codes(new URL('http://'+text+'/').hostname)}catch{return 'invalid'}
 }
 const bytes=new TextEncoder().encode(text),out=[];
 for(let i=0;i<bytes.length;i++){
  if(bytes[i]===37&&i+2<bytes.length&&hex(bytes[i+1])>=0&&hex(bytes[i+2])>=0){out.push(16*hex(bytes[i+1])+hex(bytes[i+2]));i+=2}else out.push(bytes[i]);
 }
 return 'domain;'+codes(new TextDecoder('utf-8',{ignoreBOM:true}).decode(Uint8Array.from(out)));
})));
'''
reference=json.loads(subprocess.check_output(['node','-e',oracle],input=json.dumps(texts),text=True))
for index,(want,actual) in enumerate(zip(expected,reference,strict=True)):
    if want is not None: assert want==actual,(index,texts[index],want,actual)
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/url-host-input.bend','build/url-host-input'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/url-host-input.bend','-o','build/url-host-input.js'],cwd=ROOT,check=True)
arguments=list(map(codes,texts))
for label,command in [('native 1',['build/url-host-input','--threads','1']),('native 4',['build/url-host-input','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-host-input.js'])]:
    for start in range(0,len(arguments),64):
        result=subprocess.run([*command,*arguments[start:start+64]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),reference[start:start+64],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got,want)
    print(f'{label}: {len(texts)} special-host preparation cases PASS',flush=True)

"""Strict ACE label decoding; excludes subsequent IDNA validity/policy checks."""
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
texts=['','example','xn','xn-','xn--','xn---','xn--abc-','xn--abc','XN--bcher-kva','xn--bcher-kva','xn--BCHER-KVA','xn--é','xn--é-','xn--🙂','xn--a_b','xn--'+'9'*1024]
values=['bücher','faß','ß','ẞ','βόλος','日本語','🙂','a.b','xn--é','\u0301a','e\u0301','\u200c','\u200d','\x00','ABC','\U0010ffff']
values += [chr(code) for code in range(256)]
rng=random.Random(4613492)
for _ in range(400):
    values.append(''.join(rng.choice('abXYZéßẞ日本🙂\u0301\u200c\u200d') for _ in range(rng.randrange(30))))
texts += ['xn--'+value.encode('punycode').decode('ascii') for value in values]
texts += ['xn--'+''.join(rng.choice('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_!') for _ in range(rng.randrange(50))) for _ in range(800)]
texts += ['a'*8192,'xn--'+'a'*8192,'xn--'+('é'*1024).encode('punycode').decode('ascii')]
oracle=r'''
const pc=require('punycode');
const inputs=JSON.parse(require('fs').readFileSync(0,'utf8'));
const from=String.fromCodePoint;
String.fromCodePoint=(...points)=>{if(points.some(p=>p>=0xd800&&p<=0xdfff))throw Error('non-scalar');return from(...points)};
const codes=text=>Array.from(text,c=>c.codePointAt(0)).join(',');
console.log(JSON.stringify(inputs.map(text=>{
 if(!text.startsWith('xn--'))return 'plain;'+codes(text);
 if(/[^\x00-\x7f]/.test(text))return 'non-ascii';
 try{const value=pc.decode(text.slice(4));return /[^\x00-\x7f]/.test(value)?'decoded;'+codes(value):'ascii-only'}
 catch(error){return /overflow/i.test(error.message)?'overflow':'invalid'}
})));
'''
expected=json.loads(subprocess.check_output(['node','--no-warnings','-e',oracle],input=json.dumps(texts),text=True))
arguments=[','.join(str(ord(char)) for char in text) for text in texts]
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/idna-ace.bend','build/idna-ace'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/idna-ace.bend','-o','build/idna-ace.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-ace','--threads','1']),('native 4',['build/idna-ace','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-ace.js'])]:
    for start in range(0,len(arguments),64):
        result=subprocess.run([*command,*arguments[start:start+64]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+64],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got,want)
    print(f'{label}: {len(texts)} ACE decoding cases PASS',flush=True)

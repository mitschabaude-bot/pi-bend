"""Strict form/query parsing and actual OpenAI SDK Responses URL preparation."""
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess
import sys
from urllib.parse import unquote_to_bytes, quote

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
rows = []
def codes(text): return ','.join(str(ord(c)) for c in text)
def parsed(text):
    tuples = []
    for index, field in enumerate(text.split('&')):
        if not field: continue
        name, _, value = field.partition('=')
        pair = []
        for label, part in [('name', name), ('value', value)]:
            if re.search(r'%(?![0-9a-fA-F]{2})', part): return f'{label}:{index}', None
            try: pair.append(unquote_to_bytes(part.replace('+', ' ')).decode('utf-8', 'strict'))
            except UnicodeDecodeError: return f'{label}:{index}', None
        tuples.append(pair)
    return None, tuples

def form_expected(text):
    error, tuples = parsed(text)
    return error if error else '+'+''.join(codes(k)+':'+codes(v)+'/' for k,v in tuples)

forms=['','?','??','&','&&','=','==','a','a=b=c','a=1&a=2&=x','%26=%3D','x=a+b%2Bc','x=%2520','x=%','x=%2','x=%GG','%FF=x','x=%FF','&&x=%C0%AF','x=é🙂','x=%EF%BB%BF','x=\ufeff','x=%FFé🙂','x=%C3é','x=%C3%A9','x=\x00\r\n','a=ok&%FF=%FF','a=ok&b=%FF&%FF=x']
forms += ['x='+''.join('%'+f'{b:02X}' for b in data) for data in [[n] for n in range(256)] + [[n,128] for n in range(192,256)] + [[226,130],[240,159,153],[226,65,161]]]
rng=random.Random(921)
forms += [''.join(rng.choice('abc&=+%12AFgé🙂\ufeff') for _ in range(rng.randrange(45))) for _ in range(150)]
for value in forms:
    rows.append(dict(kind='f',text=value,expected=form_expected(value)))
    rows.append(dict(kind='q',text=value,expected=form_expected(value[1:] if value.startswith('?') else value)))
for value in ['', ''.join(chr(n) for n in range(128)), "!'()*~-._ +&=", 'é🙂\ufeff', '\x00', 'x'*1023+'🙂x', 'x'*1024+'🙂x']:
    rows.append(dict(kind='e',text=value,expected=codes(quote(value,safe='-._~'))))

encoder_inputs=[row['text'] for row in rows if row['kind']=='e']
encoder_script="""
import {encode} from 'SDK/internal/qs/utils.mjs';
const input=JSON.parse(await new Response(process.stdin).text());
console.log(JSON.stringify(input.map(value=>encode(value,undefined,'utf-8','value','RFC3986'))));
""".replace('SDK',str(SDK))
encoder_sdk=json.loads(subprocess.check_output(['node','--input-type=module','-e',encoder_script],input=json.dumps(encoder_inputs),text=True))
encoder_observations=[dict(input=text,sdk=actual,rfc3986=quote(text,safe='-._~')) for text,actual in zip(encoder_inputs,encoder_sdk,strict=True)]
for item in encoder_observations:
    if item['sdk'] != item['rfc3986']:
        assert item['input']=='x'*1023+'🙂x', item

bases=['https://api.openai.com/v1','https://api.openai.com/v1/','http://127.0.0.1:8080/v1','http://[::1]:8080/v1/', 'https://EXAMPLE.test:443/a/../v1/', 'https://例え.テスト/v1','https://example.test/v1#fragment','https://example.test/v1?','https://example.test/v1?&&','https://example.test/v1?x=one+two','https://example.test/v1?x=1&x=2','https://example.test/v1?2=a&1=b&x=c','https://example.test/v1?__proto__=x&constructor=y','https://example.test/v1?a=%FF','https://example.test/v1?%GG=x','https://example.test/v1?a=%EF%BB%BF','https://example.test/v1?a=!*()~','https://example.test/v1?a=é🙂','', '/v1', 'http://', 'https://example.test:70000/v1']
for form in forms[:28]+forms[-50:]:
    bases.append('https://example.test/v1?'+form)
NODE=r'''
import OpenAI from 'SDK/index.mjs';
const rows=JSON.parse(await new Response(process.stdin).text());
const out=rows.map(base=>{
 const address=base+(base.endsWith('/')?'responses':'/responses');
 try {
  const before=new URL(address);
  const client=new OpenAI({apiKey:'test-only',baseURL:base});
  return {query:before.search.slice(1), original:before.toString(), sdk:client.buildURL('/responses',undefined)};
 } catch(error) {return {error:String(error)}}
});
console.log(JSON.stringify(out));
'''.replace('SDK',str(SDK))
observations=json.loads(subprocess.check_output(['node','--input-type=module','-e',NODE],input=json.dumps(bases),text=True))
adaptations=[]
for base, observed in zip(bases,observations,strict=True):
    if 'error' in observed:
        expected='invalid-url'
    else:
        error, tuples=parsed(observed['query'])
        if error:
            expected=error
            adaptations.append(dict(base=base,reason='strict malformed query rejection',sdk=observed['sdk'],expected=expected))
        else:
            fields=dict(tuples)
            # SDK numeric property enumeration is intentionally not a native
            # dictionary ordering requirement. Keep insertion order explicitly.
            if fields:
                prefix, marker, fragment=observed['original'].partition('#')
                prefix=prefix.split('?',1)[0]
                native=prefix+'?'+'&'.join(quote(k,safe='-._~')+'='+quote(v,safe='-._~') for k,v in fields.items())+(marker+fragment if marker else '')
            else: native=observed['original']
            expected='+'+codes(native)
            if native!=observed['sdk']:
                assert any(k.isascii() and k.isdigit() for k in fields), (base,native,observed)
                adaptations.append(dict(base=base,reason='native insertion order for numeric-looking names',sdk=observed['sdk'],native=native))
    rows.append(dict(kind='u',text=base,expected=expected))
if '--no-build' not in sys.argv:
    subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib','16','--stats','build/openai-responses-url-rebuild-c.json','--','sh','scripts/build-pure.sh','packages/ai/test/openai-responses-url.bend','build/openai-responses-url'],cwd=ROOT,check=True)
    subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib','10','--stats','build/openai-responses-url-rebuild-js.json','--',os.environ.get('BEND',str(Path.home()/'.bend/bin/bend')),'packages/ai/test/openai-responses-url.bend','-o','build/openai-responses-url.js'],cwd=ROOT,check=True)
args=[row['kind']+codes(row['text']) for row in rows]
for label,command in [('native 1',['build/openai-responses-url','--threads','1']),('native 4',['build/openai-responses-url','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/openai-responses-url.js'])]:
    for start in range(0,len(rows),16):
        run=subprocess.run([*command,*args[start:start+16]],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0,(label,start,run.stderr)
        for offset,(got,row) in enumerate(zip(run.stdout.splitlines(),rows[start:start+16],strict=True)):
            assert got==row['expected'],(label,start+offset,row,got)
    print(f'{label}: {len(rows)} strict form/query/SDK URL cases PASS',flush=True)

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
pending=[ROOT/'packages/ai/test/openai-responses-url.bend'];seen=set()
while pending:
    path=pending.pop().resolve()
    if path in seen:continue
    seen.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
report=dict(encoder_observations=encoder_observations, cases=len(rows),comparisons=3*len(rows),source_sha256={str(p.relative_to(ROOT)):digest(p) for p in sorted(seen)},checker_sha256=digest(Path(__file__)),sdk_version=json.loads((SDK/'package.json').read_text())['version'],sdk_sha256={str(p.relative_to(SDK)):digest(p) for p in [SDK/'client.mjs',SDK/'internal/qs/stringify.mjs',SDK/'internal/qs/utils.mjs']},adaptations=adaptations,url_observations=observations,rows=rows,artifact_sha256={p:digest(ROOT/p) for p in ['build/openai-responses-url','build/openai-responses-url.c','build/openai-responses-url.js']})
(ROOT/'build/openai-responses-url-results.json').write_text(json.dumps(report,ensure_ascii=True,indent=2)+'\n')

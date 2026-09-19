"""Opaque path state, including the final-space-before-delimiter rule."""
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
def encode(text,extra=''):
    return ''.join(f'%{byte:02X}' if byte<32 or byte>126 or chr(byte) in extra else chr(byte) for byte in text.encode('utf-8'))
def reference(text):
    path_query,hashmark,fragment=text.partition('#')
    path,question,query=path_query.partition('?')
    value=encode(path[:-1])+'%20' if path.endswith(' ') and (question or hashmark) else encode(path)
    return [value,encode(query,' "#<>') if question else None,encode(fragment,' "<>`') if hashmark else None]
texts=['','hello world','user@example.com','text/plain,hello%20world','a/b/../c','./../%2e',
       '/a//b','C|/../x','a\\b','a?','a#','a?#','a?x#y#z','a#x?y','a ?','a  ?','a   #',
       'a %20 ?','a%20?','a %2?','a + ?','a b c','a b c?','a b c#','a\t ?q',
       'a \n?x','a\0?x','a ?\'"<>#\'"<>`','  ','a  ','\ufeffé🙂?é+🙂#é🙂']
for code in range(256):
    texts += ['a'+chr(code)+'b?x#y','a'+chr(code)+'?x','a?b'+chr(code)+'c#d','a#b'+chr(code)+'c']
for spaces in range(33):
    for suffix in ['', '?', '#', '?q#f', '#f?q']:
        texts.append('x'+' '*spaces+suffix)
rng=random.Random(20260926)
alphabet='abc%20 /\\.:?|# +<>`\'\"é🙂\0\t\n\r'
texts += [''.join(rng.choices(alphabet,k=rng.randrange(100))) for _ in range(1500)]
for size in [1024,8192]:
    texts += ['a'*size+'  ?x#y','a'+' '*size+'#f','a/'*size+'..',
              'a?'+ 'é'*size,'a#'+'🙂'*size]
expected=list(map(reference,texts))
# Constructor preprocessing and choosing opaque versus hierarchical path happen
# outside this component. Compare only inputs that reach this state unchanged.
eligible=[(i,text) for i,text in enumerate(texts) if not text.startswith('/') and not any(c in text for c in '\t\n\r') and not (text and ord(text[-1])<=32)]
script=r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(([i,text])=>{
 const u=new URL('data:'+text);
 return [i,[u.pathname,u.href.split('#')[0].includes('?')?u.search.slice(1):null,u.href.includes('#')?u.hash.slice(1):null]];
})));
'''
actual=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps(eligible),text=True))
for index,got in actual:
    assert got==expected[index],(index,texts[index],got,expected[index])
print(f'Node opaque path cross-check: {len(actual)} cases PASS',flush=True)
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/url-opaque-path.bend','build/url-opaque-path'],cwd=ROOT,check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/url-opaque-path.bend','-o','build/url-opaque-path.js'],cwd=ROOT,check=True)
def codes(text):return ','.join(map(str,map(ord,text)))
def wire(values):
    value,query,fragment=values
    return ';'.join([codes(value),'absent' if query is None else 'present',codes(query or ''),'absent' if fragment is None else 'present',codes(fragment or '')])
arguments=list(map(codes,texts))
expected=list(map(wire,expected))
for label,command in [('native 1',['build/url-opaque-path','--threads','1']),('native 4',['build/url-opaque-path','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-opaque-path.js'])]:
    start=0
    while start<len(arguments):
        end,size=start,0
        while end<len(arguments) and end-start<64 and size+len(arguments[end])<262144:
            size+=len(arguments[end]);end+=1
        assert end>start
        result=subprocess.run([*command,*arguments[start:end]],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:end],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got[:500],want[:500])
        start=end
    print(f'{label}: {len(texts)} opaque path cases PASS',flush=True)

"""Constructor input preprocessing and lossless scheme/relative separation."""
import json
from pathlib import Path
import random
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
EDGE=''.join(chr(code) for code in range(33))
def stripped(text): return re.sub('[\t\n\r]', '', text)
def prepared(text): return stripped(text.strip(EDGE))
def prefix(text):
    found=re.match(r'^([A-Za-z][A-Za-z0-9+.-]*):',text)
    return ('absolute',found[1].lower(),text[found.end():]) if found else ('relative','',text)
def codes(text):return ','.join(map(str,map(ord,text)))
texts=['',' ',':','HTTP:','HtTpS://EXAMPLE.com/a?b#c','http//example.com','HTTP/path:rest',
       '1x:y','+x:y','x+y.z-1:rest:tail','a:','é:x','🙂:x','C:\\folder','/a:b','../a:b',
       '//example.com/x','?x:y','#x:y','a%3Ab','h\tt\nt\rp://example.com/',
       '\u00a0http://example.com/\u00a0','\ufeffhttp://example.com/\ufeff',
       'http://example.com/a b','http://example.com/\vinside\f','http://example.com/\0middle']
for before in range(33):
    for after in range(33):
        for text in ['HTTP://example.com/a?b#c','../MixedCase:rest','custom:hello world','']:
            texts.append(chr(before)+text+chr(after))
for code in range(256):
    texts += [chr(code)+'a:b','a'+chr(code)+':b','http://example.com/a'+chr(code)+'b']
for char in ['\u00a0','\u1680','\u2000','\u200b','\u2028','\u2029','\u202f','\u3000','\ufeff','🙂']:
    texts += [char+'http://example.com/'+char,'a'+char+':b','x:'+char]
rng=random.Random(20260925)
alphabet='abcABC019:+-./?#% \t\n\r\v\0é🙂'
texts += [''.join(rng.choices(alphabet,k=rng.randrange(80))) for _ in range(1000)]
for size in [1024,8192,16384]:
    texts += ['\0'*size+'HTTP://example.com/'+'\x1f'*size,
              'A'*size+':MixedCase/path','A'*size+'/MixedCase:relative',
              'x:'+'a\tb\nc\r'*size,'\t'*size,'\ufeff'+' '*size]
reference=[]
for text in texts:
    clean=prepared(text)
    kind,scheme,remainder=prefix(clean)
    reference.append(';'.join([codes(clean),codes(stripped(text)),kind,codes(scheme),codes(remainder)]))
# Cross-check preprocessing through actual constructors, both absolute and
# relative, without mistaking a missing base for a preprocessing failure.
script=r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
const parse=(s,b)=>{try{const u=b===null?new URL(s):new URL(s,b);return [u.href,u.protocol.slice(0,-1)]}catch{return null}};
console.log(JSON.stringify(rows.map(([raw,clean])=>[null,'https://base.example/dir/file?old#old'].map(base=>[parse(raw,base),parse(clean,base)]))));
'''
actual=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps([(text,prepared(text)) for text in texts]),text=True))
valid=0
for index,results in enumerate(actual):
    for raw,clean in results:
        assert raw==clean,(index,texts[index],raw,clean)
        kind,scheme,_=prefix(prepared(texts[index]))
        if raw is not None:
            valid+=1
            if kind=='absolute':assert raw[1]==scheme,(index,texts[index],raw,scheme)
print(f'Node preprocessing: {len(texts)*2} constructor comparisons ({valid} successful parses) PASS',flush=True)
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/url-input.bend','build/url-input'],cwd=ROOT,check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/url-input.bend','-o','build/url-input.js'],cwd=ROOT,check=True)
arguments=[]
for text in texts:
    encoded=codes(text)
    if len(encoded)>=120000:
        block='a\tb\nc\r'
        assert text.startswith('x:') and text[2:]==block*(len(text[2:])//len(block))
        encoded=codes('x:')+';'+str(len(text[2:])//len(block))+';'+codes(block)
    arguments.append(encoded)
for label,command in [('native 1',['build/url-input','--threads','1']),('native 4',['build/url-input','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-input.js'])]:
    start=0
    while start<len(arguments):
        end,size=start,0
        while end<len(arguments) and end-start<64 and size+len(arguments[end])<262144:
            size+=len(arguments[end]);end+=1
        assert end>start
        result=subprocess.run([*command,*arguments[start:end]],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),reference[start:end],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got[:300],want[:300])
        start=end
    print(f'{label}: {len(texts)} input/prefix cases PASS',flush=True)

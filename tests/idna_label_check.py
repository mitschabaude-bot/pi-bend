"""Strict prepared-label processing with full Unicode tables and policy flags."""
from bisect import bisect_right
from itertools import product
import importlib.util
import json
from pathlib import Path
import random
import re
import subprocess
import sys
from idna_unicode_reference import ROOT, context

for generator in ['generate-idna-mapping.py','generate-unicode-normalization.py']:
    subprocess.run([sys.executable,'scripts/'+generator,'--check'],cwd=ROOT,check=True)

spec=importlib.util.spec_from_file_location('mapping_generator',ROOT/'scripts/generate-idna-mapping.py')
data=importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
ranges=[]
for line in data.source('IdnaMappingTable.txt').splitlines():
    fields=[part.strip() for part in line.split('#')[0].split(';')]
    if len(fields)>1:
        ends=[int(part,16) for part in fields[0].split('..')]
        ranges.append((ends[0],ends[-1],fields[1]))
starts=[row[0] for row in ranges]
def status(code):
    first,last,value=ranges[bisect_right(starts,code)-1]
    assert first<=code<=last
    return value

def unescape(text):
    if text=='""': return ''
    text=re.sub(r'\\u([0-9A-Fa-f]{4})|\\x\{([0-9A-Fa-f]+)\}',lambda match:chr(int(match[1] or match[2],16)),text)
    return text.encode('utf-16-le','surrogatepass').decode('utf-16-le','replace')

texts=['','a','123','-','-a','a-','ab--c','a.b','a_b','A','é','e\u0301','\u0301a','\u0903a','ß','ẞ','\u00ad','\ufeff','\u0378','\x00','\x7f','\x80','אב','אב1','אב١','אב1١','aאב','ب\u200cب','ب\u200c\u200cب','ب-\u200cب','क्\u200dष','क्\u200dאב','a\u200db','xn--','xn---','xn--a','xn--abc-','xn--é','xn--bcher-kva','xn--'+('9'*128)]
texts += ['xn--'+text.encode('punycode').decode('ascii') for text in texts]
rng=random.Random(4617)
texts += [''.join(rng.choice('abéßẞ-_.אבب١1\u200c\u200d\u094d\u0301\u00ad') for _ in range(rng.randrange(20))) for _ in range(200)]
texts += ['a'*8192,'a'*8192+'-','é'*1024,'xn--'+('é'*1024).encode('punycode').decode('ascii')]
rows=[(text,mode,hyphens,std3,joiners) for mode,hyphens,std3,joiners in product('nt',[False,True],[False,True],[False,True]) for text in texts]
# Official test inputs and Unicode result labels supply varied valid and invalid
# text. We test label-stage assertions, not the corpus's whole-domain outcomes.
official=set()
for line in data.source('IdnaTestV2.txt').splitlines():
    fields=[part.strip(' \t') for part in line.split('#')[0].split(';')]
    if len(fields)<2: continue
    for field in [fields[0],fields[1] or fields[0]]:
        official.update(unescape(field).split('.'))
rows += [(text,'n',False,False,True) for text in sorted(official)]
unique=list(dict.fromkeys(row[0] for row in rows))
oracle=r'''
const pc=require('punycode');
if(process.versions.unicode!=='17.0')throw Error('Unicode version mismatch');
const from=String.fromCodePoint;
String.fromCodePoint=(...points)=>{if(points.some(p=>p>=0xd800&&p<=0xdfff))throw Error('non-scalar');return from(...points)};
const inputs=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(inputs.map(input=>{
 let text=input,encoded=input.startsWith('xn--');
 if(encoded){
  if(/[^\x00-\x7f]/.test(input))return {error:'non-ascii'};
  try{text=pc.decode(input.slice(4))}catch(e){return {error:/overflow/i.test(e.message)?'overflow':'invalid'}}
  if(!/[^\x00-\x7f]/.test(text))return {error:'ascii-only'};
 }
 return {text,encoded,nfc:text.normalize('NFC')===text};
})));
'''
values=json.loads(subprocess.check_output(['node','--no-warnings','-e',oracle],input=json.dumps(unique),text=True))
decoded=dict(zip(unique,values,strict=True))
def codes(text): return ','.join(map(str,map(ord,text)))
def expected(row):
    source,mode,hyphens,std3,joiners=row
    value=decoded[source]
    if 'error' in value: return value['error']
    text=value['text']
    if not value['nfc']: return 'nfc'
    if hyphens:
        if text[2:4]=='--': return 'hyphen-positions'
        if text.startswith('-') or text.endswith('-'): return 'hyphen-edge'
    elif text.startswith('xn--'): return 'reserved'
    for char in text:
        if char=='.': return 'dot'
        if std3 and ord(char)<128 and not (char=='-' or 'a'<=char<='z' or '0'<=char<='9'): return 'ascii;'+str(ord(char))
    allowed={'valid','deviation'} if mode=='n' or value['encoded'] else {'valid'}
    for char in text:
        if status(ord(char)) not in allowed: return 'status;'+str(ord(char))
    mark,rtl,bidi,valid_joiners=context(text)
    if mark=='1': return 'mark'
    if joiners and valid_joiners=='0': return 'joiners'
    return 'ok;'+str(int(not text))+rtl+bidi+';'+codes(text)
arguments=[f'{mode};{int(hyphens)};{int(std3)};{int(joiners)};'+codes(text) for text,mode,hyphens,std3,joiners in rows]
results=[expected(row) for row in rows]
if '--prepare-only' in sys.argv:
    print(f'{len(rows)} label cases prepared; {len(official)} distinct official label inputs')
    raise SystemExit(0)
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/idna-label.bend','build/idna-label'],cwd=ROOT,check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/idna-label.bend','-o','build/idna-label.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-label','--threads','1']),('native 4',['build/idna-label','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-label.js'])]:
    for start in range(0,len(arguments),64):
        result=subprocess.run([*command,*arguments[start:start+64]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),results[start:start+64],strict=True)):
            assert got==want,(label,start+offset,rows[start+offset],got,want)
    print(f'{label}: {len(rows)} complete label processing comparisons PASS',flush=True)

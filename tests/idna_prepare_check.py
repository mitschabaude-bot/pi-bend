"""Mapping+NFC composition on UTS #46 inputs; not full IDNA validity claims."""
from bisect import bisect_right
import importlib.util
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('idna_data',ROOT/'scripts/generate-idna-mapping.py')
data=importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
raw=[]
for line in data.source('IdnaMappingTable.txt').splitlines():
    fields=[part.strip() for part in line.split('#')[0].split(';')]
    if len(fields)<2:
        continue
    bounds=[int(value,16) for value in fields[0].split('..')]
    replacement=''.join(chr(int(value,16)) for value in fields[2].split()) if len(fields)>2 else ''
    raw.append((bounds[0],bounds[-1],fields[1],replacement))
starts=[row[0] for row in raw]

def unescape(text):
    if text=='""':
        return ''
    text=re.sub(r'\\u([0-9A-Fa-f]{4})|\\x\{([0-9A-Fa-f]+)\}',lambda match:chr(int(match[1] or match[2],16)),text)
    # URL string inputs are USVStrings. Do not construct invalid Bend Char values.
    return text.encode('utf-16-le','surrogatepass').decode('utf-16-le','replace')

texts=[]
for line in data.source('IdnaTestV2.txt').splitlines():
    body=line.split('#')[0].strip(' \t')
    if body:
        texts.append(unescape(body.split(';')[0].strip(' \t')))
examples=['BÜCHER.example','faß.example','βόλος.example','İ.example','例え。テスト','ＡＢＣ．ＥＸＡＭＰＬＥ','e\u0301.example','a\u00adb.example','\ufeffExample.COM','ﬃ.example']
texts+=examples
mapped=[]
for text in texts:
    output=[]
    for char in text:
        code=ord(char)
        first,last,status,replacement=raw[bisect_right(starts,code)-1]
        assert first<=code<=last
        if status=='disallowed':
            mapped.append({'error':code})
            break
        if status=='mapped':
            output.append(replacement)
        elif status!='ignored':
            output.append(char)
    else:
        mapped.append(''.join(output))
oracle=r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
if(process.versions.unicode!=='17.0')throw Error('Unicode version mismatch');
console.log(JSON.stringify(rows.map(value=>typeof value==='string'?value.normalize('NFC'):value)));
'''
expected_values=json.loads(subprocess.check_output(['node','-e',oracle],input=json.dumps(mapped),text=True))
# These deliberately valid complete-domain examples also agree with Node's
# public domainToUnicode API. Arbitrary preparation results are not valid hosts.
public_oracle=r'''
const {domainToUnicode}=require('url');
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(domainToUnicode)));
'''
public=json.loads(subprocess.check_output(['node','-e',public_oracle],input=json.dumps(examples),text=True))
assert public==expected_values[-len(examples):],(public,expected_values[-len(examples):])
def codes(text):
    return ','.join(str(ord(char)) for char in text)
arguments=list(map(codes,texts))
expected=['+'+codes(value) if isinstance(value,str) else 'invalid;'+str(value['error']) for value in expected_values]
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/idna-prepare.bend','build/idna-prepare'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/idna-prepare.bend','-o','build/idna-prepare.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-prepare','--threads','1']),('native 4',['build/idna-prepare','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-prepare.js'])]:
    for start in range(0,len(arguments),128):
        result=subprocess.run([*command,*arguments[start:start+128]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+128],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got,want)
    print(f'{label}: {len(texts)} mapping+NFC inputs PASS; full label validity remains separate',flush=True)

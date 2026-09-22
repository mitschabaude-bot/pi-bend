"""Base64 wire compatibility and canonical padding against Python's codec."""
from pathlib import Path
import base64
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(4648)
cases = []

def csv(data):
    return ','.join(map(str,data))

for data in [b'',b'f',b'fo',b'foo',b'foob',b'fooba',b'foobar'] + [bytes([i]) for i in range(256)] + [rng.randbytes(n) for n in list(range(193))+[255,256,257,1024,8192]]:
    text = base64.b64encode(data).decode('ascii')
    cases += [('e:'+csv(data),text),('d:'+text,csv(data))]

alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
# Every possible trailing sextet combination: accept exactly the canonical
# encodings, even though Python validate=True accepts nonzero discarded bits.
for a in alphabet:
    for b in alphabet:
        for text in [a+b+'==','R'+a+b+'=']:
            raw = base64.b64decode(text,validate=True)
            expected = csv(raw) if base64.b64encode(raw).decode('ascii') == text else 'error'
            cases.append(('d:'+text,expected))
for text in ['A','AA','AAA','A===','====','AA=A','AA==A','AAAA=','AAAA====','AA==\n','AA ==','-AAA','_AAA','éAAA']:
    cases.append(('d:'+text,'error'))
for code in range(1,128):
    char = chr(code)
    if char not in alphabet+'=':
        cases.append(('d:'+'AAA'+char,'error'))
for data in [[256],[0,1,4294967295],[0,1,2,256]]:
    cases.append(('e:'+csv(data),'error'))

for name,command in [('native-1',['build/base64','--threads','1']),
                     ('native-4',['build/base64','--threads','4']),
                     ('bun',['bun','build/base64.js'])]:
    for start in range(0,len(cases),128):
        group=cases[start:start+128]
        run=subprocess.run(command+[arg for arg,_ in group],cwd=ROOT,capture_output=True,text=True,timeout=90)
        assert run.returncode==0,(name,run.stderr[-2000:])
        actual=run.stdout.splitlines()
        assert len(actual)==len(group),(name,start,len(actual),len(group))
        for index,(value,(arg,expected)) in enumerate(zip(actual,group)):
            assert value==expected,(name,start+index,arg[:100],value[:100],expected[:100])
    print(f'{name}: {len(cases)} Base64 checks PASS',flush=True)

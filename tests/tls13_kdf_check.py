"""TLS 1.3 derivation against RFC 8448 and independent HKDF reference."""
import hashlib
import hmac
import json
from pathlib import Path
import random
import subprocess
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDFExpand

ROOT = Path(__file__).resolve().parents[1]
fixture = json.loads((ROOT/'tests/fixtures/tls/rfc8448-simple.json').read_text())
encode = lambda data: ','.join(map(str,data))
unhex = bytes.fromhex

def label_info(label, context, length):
    label = b'tls13 '+label.encode('ascii')
    return length.to_bytes(2,'big')+bytes([len(label)])+label+bytes([len(context)])+context

def expand(key,label,context,length):
    return HKDFExpand(hashes.SHA256(),length,label_info(label,context,length)).derive(key)

cases = []
for v in fixture['expansions']:
    key, context = unhex(v['key']),unhex(v['context'])
    assert label_info(v['label'],context,v['length']).hex() == v['info']
    assert expand(key,v['label'],context,v['length']).hex() == v['output']
    cases.extend([
        (':'.join(['e',v['label'],encode(context),str(v['length'])]),v['info']),
        (':'.join(['x',encode(key),v['label'],encode(context),str(v['length'])]),v['output']),
    ])
messages = {k:unhex(v) for k,v in fixture['messages'].items()}
hello = messages['ClientHello']+messages['ServerHello']
before_finished = hello+messages['EncryptedExtensions']+messages['Certificate']+messages['CertificateVerify']
server_finished = before_finished+messages['Finished']
for v in fixture['expansions']:
    if v['label']=='derived': transcript=b''
    elif v['label'] in ['c hs traffic','s hs traffic']: transcript=hello
    elif v['label'] in ['c ap traffic','s ap traffic','exp master']: transcript=server_finished
    else: continue
    assert hashlib.sha256(transcript).hexdigest()==v['context']
    cases.append((':'.join(['d',encode(unhex(v['key'])),v['label'],encode(transcript)]),v['output']))
early=unhex('33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a')
shared=unhex('8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d')
handshake=unhex('1dc826e93606aa6fdc0aadc12f741b01046aa6b99f691ed221a9f0ca043fbeac')
master=unhex(next(v['key'] for v in fixture['expansions'] if v['label']=='exp master'))
for key,input,expected in [(early,shared,handshake),(handshake,bytes(32),master)]:
    assert hmac.digest(expand(key,'derived',hashlib.sha256(b'').digest(),32),input,'sha256')==expected
    cases.append((':'.join(['a',encode(key),encode(input)]),expected.hex()))
finished_outputs = ['9b9b141d906337fbd2cbdce71df4deda4ab42c309572cb7fffee5454b78f0718', 'a8ec436d677634ae525ac1fcebe11a039ec17694fac6e98527b642f2edd5ce61']
finished_vectors=[v for v in fixture['expansions'] if v['label']=='finished']
assert len(finished_vectors)==2
for v,transcript,expected in zip(finished_vectors,[before_finished,server_finished],finished_outputs):
    assert hmac.digest(unhex(v['output']),hashlib.sha256(transcript).digest(),'sha256').hex()==expected
    cases.append((':'.join(['f',encode(unhex(v['key'])),encode(transcript)]),expected))
rng=random.Random(8446)
for n in [1,2,12,248,249]:
    for c in [0,1,32,254,255]:
        label='x'*n; context=rng.randbytes(c); key=rng.randbytes(32); length=rng.choice([0,1,12,16,32,33,256])
        cases.append((':'.join(['e',label,encode(context),str(length)]),label_info(label,context,length).hex()))
        cases.append((':'.join(['x',encode(key),label,encode(context),str(length)]),expand(key,label,context,length).hex()))
key=encode(bytes(32))
cases.extend([
    ('e:::32','label'), ('e:'+('x'*250)+'::32','label'), ('e:é::32','label'),
    ('e:key:'+encode(bytes(256))+':32','context'), ('e:key::65536','length:65536'),
    ('e:key:256:32','byte:256'), ('x:'+key+':key::8161','length:8161'),
    ('x:1:key::32','key'), ('x:'+key+',256:key::32','byte:256'),
    ('e:key::65535',label_info('key',b'',65535).hex()),
])
records={}
for backend, command in [('native-1',['build/tls13-kdf','--threads','1']), ('native-4',['build/tls13-kdf','--threads','4']), ('bun',['bun','build/tls13-kdf.js'])]:
    outputs=[]
    for i in range(0,len(cases),16):
        batch=cases[i:i+16]
        run=subprocess.run(command+[text for text,_ in batch],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert run.returncode==0 and not run.stderr,(backend,i,run.returncode,run.stderr[-2000:])
        lines=run.stdout.splitlines(); assert len(lines)==len(batch),(backend,i,len(lines))
        for line,(_,expected) in zip(lines,batch):
            actual=bytes(map(int,filter(None,line[3:].split(',')))).hex() if line.startswith('ok:') else line
            assert actual==expected,(backend,i,actual[:100],expected[:100])
            outputs.append(actual)
    records[backend]={'cases':len(outputs),'outputs_sha256':hashlib.sha256('\n'.join(outputs).encode()).hexdigest()}
    print(backend,len(outputs),'TLS 1.3 KDF cases PASS',flush=True)
paths=['packages/runtime/src/tls13-kdf.bend','packages/runtime/src/hkdf-sha256.bend','packages/runtime/src/hmac-sha256.bend','packages/runtime/src/sha256.bend','tests/tls13-kdf.bend','tests/tls13_kdf_check.py','tests/fixtures/tls/rfc8448-simple.json']
record={'runs':records,'sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}}
(ROOT/'build/tls13-kdf-results.json').write_text(json.dumps(record,indent=2)+'\n')

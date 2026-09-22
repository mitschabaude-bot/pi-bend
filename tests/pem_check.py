"""PEM framing, canonical Base64 and real system certificates."""
from pathlib import Path
import base64
import random
import subprocess
from cryptography import x509
from cryptography.hazmat.primitives import serialization

ROOT=Path(__file__).resolve().parents[1]
rng=random.Random(7468)
cases=[]
def csv(raw): return ','.join(map(str,raw))
def wrap(label,raw,newline='\n',width=64):
    text=base64.b64encode(raw).decode('ascii')
    return newline.join(['-----BEGIN '+label+'-----']+[text[i:i+width] for i in range(0,len(text),width)]+['-----END '+label+'-----'])

for length in list(range(130))+[255,256,257,1024,8192]:
    data=rng.randbytes(length)
    label=rng.choice(['CERTIFICATE','PUBLIC KEY','X509 CRL','A-B C',''])
    for newline in ['\n','\r\n','\r']:
        wire=wrap(label,data,newline,rng.randrange(1,80))
        cases.append((wire,label+':'+csv(data)))
        padded=newline.join(' \t'+line+'\t ' for line in wire.split(newline))
        cases.append(('explanatory text'+newline+padded+newline+'trailing text',label+':'+csv(data)))
for space in [' ','\t','\v','\f']:
    cases.append(('-----BEGIN X-----\nZ'+space+'m'+space+'9'+space+'v\n-----END X-----','X:102,111,111'))
for text in ['', 'outside text', '# comments\nmore text']:
    cases.append((text,''))
for label in [' A','A ','A  B','A--B','A -B','-A','A-','A\tB','é']:
    cases.append((wrap(label,b'foo'),'error'))
for text in ['-----BEGIN X-----','-----END X-----',
             '-----BEGIN X-----\nZm9v\n-----END Y-----',
             '-----BEGIN X-----\n-----BEGIN Y-----\n-----END Y-----\n-----END X-----',
             '-----BEGINX-----\nZm9v\n-----END X-----',
             '-----BEGIN X----\nZm9v\n-----END X-----',
             '-----BEGIN X------\nZm9v\n-----END X-----',
             '-----BEGIN X-----\nProc-Type: 4,ENCRYPTED\nZm9v\n-----END X-----']:
    cases.append((text,'error'))
for payload in ['Zg','Zg=','Zh==','Zm9=','Zm9v!','Zm9v_','Zm9v-','Zg==YQ==']:
    cases.append(('-----BEGIN X-----\n'+payload+'\n-----END X-----','error'))

# Decode installed roots independently and test concatenated bundle order.
certificates=[]
for path in sorted(Path('/etc/ssl/certs').glob('*.pem')):
    text=path.read_text()
    if '-----BEGIN CERTIFICATE-----' not in text:continue
    cert=x509.load_pem_x509_certificate(text.encode())
    expected='CERTIFICATE:'+csv(cert.public_bytes(serialization.Encoding.DER))
    cases.append((text,expected))
    certificates.append((text,expected))
for i in range(0,len(certificates),10):
    group=certificates[i:i+10]
    cases.append(('\n'.join(text for text,_ in group),'|'.join(expected for _,expected in group)))
cases.append((wrap('A',b'one')+'\n'+wrap('B',b'two')+'\n'+wrap('A',b'three'),'A:111,110,101|B:116,119,111|A:116,104,114,101,101'))

for name,command in [('native-1',['build/pem','--threads','1']),('native-4',['build/pem','--threads','4']),('bun',['bun','build/pem.js'])]:
    for start in range(0,len(cases),24):
        group=cases[start:start+24]
        run=subprocess.run(command+[arg for arg,_ in group],cwd=ROOT,capture_output=True,text=True,timeout=90)
        assert run.returncode==0,(name,run.stderr[-2000:])
        lines=run.stdout.splitlines()
        assert len(lines)==len(group),(name,start,len(lines),len(group))
        for i,(actual,(arg,expected)) in enumerate(zip(lines,group)):
            assert actual==expected,(name,start+i,arg[:80],actual[:100],expected[:100])
    print(f'{name}: {len(cases)} PEM checks PASS, including {len(certificates)} system certificates',flush=True)

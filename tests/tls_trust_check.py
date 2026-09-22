"""Explicit trust-bundle parsing and bounded native file reads."""
from pathlib import Path
import hashlib
import re
import subprocess
import tempfile
from cryptography import x509

ROOT=Path(__file__).resolve().parents[1]
CERTIFICATE=re.compile(br'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',re.S)

def summary(data):
    certs=[x509.load_pem_x509_certificate(text) for text in CERTIFICATE.findall(data)]
    digest=hashlib.sha256(b''.join(c.tbs_certificate_bytes for c in certs)).digest()
    return str(len(certs))+'|'+','.join(map(str,digest))

sample=Path('/etc/ssl/certs/GTS_Root_R4.pem').read_bytes()
second=Path('/etc/ssl/certs/ISRG_Root_X1.pem').read_bytes()
cases=[]
for data in [sample,second,sample+second,second+sample,sample+sample]:
    cases.append((data.decode(),summary(data)))
for text,expected in [('', 'empty'),('only comments\n', 'empty'),
                      ('-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----','certificate'),
                      ('-----BEGIN CERTIFICATE-----\nAB==\n-----END CERTIFICATE-----','pem'),
                      ('-----BEGIN CERTIFICATE-----','pem'),
                      ('-----BEGIN PUBLIC KEY-----\nAA==\n-----END PUBLIC KEY-----','label:PUBLIC KEY'),
                      ('-----BEGIN TRUSTED CERTIFICATE-----\nAA==\n-----END TRUSTED CERTIFICATE-----','label:TRUSTED CERTIFICATE')]:
    cases.append((text,expected))
    if expected not in ['empty']:
        cases.append((sample.decode()+text,expected))
        cases.append((text+'\n'+sample.decode(),expected))

with tempfile.TemporaryDirectory(prefix='pi-bend-trust-') as temp:
    folder=Path(temp)
    def file_case(name,data,limit,expected):
        path=folder/name
        path.write_bytes(data)
        cases.append(('file:'+str(limit)+':'+str(path),expected))
    for prefix in [b'',b'\xef\xbb\xbf',b'# '+b'x'*4090+b'\xe2\x82\xac\n',b'# '+b'x'*8192+b'\n']:
        data=prefix+sample+second
        file_case('bundle-'+str(len(prefix)),data,len(data),summary(data))
        file_case('short-'+str(len(prefix)),data,len(data)-1,'size')
    file_case('zero',sample,0,'size')
    file_case('empty',b'',0,'empty')
    file_case('invalid-utf8',b'\xff'+sample,100000,'utf8')
    file_case('truncated-utf8',sample+b'\xe2\x82',100000,'utf8')
    file_case('bad-second',sample+b'-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n',100000,'certificate')
    cases.append(('file:100000:'+str(folder/'missing'),'read'))
    bundle=Path('/etc/ssl/certs/ca-certificates.crt')
    data=bundle.read_bytes()
    cases.append(('file:'+str(len(data))+':'+str(bundle),summary(data)))
    # Repeated failure/success reads exercise descriptor retirement in one process.
    cases += [('file:1:'+str(bundle),'size'),('file:'+str(len(sample))+':'+str(folder/'bundle-0'),'size')]*20
    cases += [('file:'+str(len(data))+':'+str(bundle),summary(data))]
    for name,command in [('native-1',['build/tls-trust','--threads','1']),
                         ('native-4',['build/tls-trust','--threads','4']),
                         ('bun',['bun','build/tls-trust.js'])]:
        run=subprocess.run(command+[arg for arg,_ in cases],cwd=ROOT,capture_output=True,text=True,timeout=120)
        assert run.returncode==0,(name,run.stderr[-2000:])
        lines=run.stdout.splitlines()
        assert len(lines)==len(cases),(name,len(lines),len(cases))
        for i,(actual,(arg,expected)) in enumerate(zip(lines,cases)):
            assert actual==expected,(name,i,arg[:100],actual,expected)
        print(f'{name}: {len(cases)} trust-file checks PASS',flush=True)

"""RFC 5869 vectors and differential tests against cryptography's HKDF."""
import hashlib
import hmac
import json
from pathlib import Path
import random
import subprocess
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF, HKDFExpand

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(5869)
encode = lambda data: ','.join(map(str, data))
vectors = [
    (b'\x0b'*22, bytes(range(13)), bytes(range(240,250)), 42,
     '077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5',
     '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865'),
    (bytes(range(80)), bytes(range(96,176)), bytes(range(176,256)), 82,
     '06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244',
     'b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87'),
    (b'\x0b'*22, b'', b'', 42,
     '19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04',
     '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8'),
]
cases = []
for ikm, salt, info, length, prk, okm in vectors:
    assert hmac.digest(salt, ikm, 'sha256').hex() == prk
    assert HKDF(hashes.SHA256(), length, salt, info).derive(ikm).hex() == okm
    cases.extend([
        (encode(salt)+':'+encode(ikm), prk),
        (':'.join([encode(salt), encode(ikm), encode(info), str(length)]), okm),
        (':'.join([encode(bytes.fromhex(prk)), encode(info), str(length)]), okm),
    ])
for length in list(range(66)) + [95,96,97,127,128,129,255,256,257,1024,8159,8160]:
    salt = rng.randbytes(rng.choice([0,1,32,64,65,131]))
    ikm, info = rng.randbytes(rng.randrange(130)), rng.randbytes(rng.choice([0,1,32,64,65,129]))
    expected = HKDF(hashes.SHA256(), length, salt, info).derive(ikm).hex()
    cases.append((':'.join([encode(salt),encode(ikm),encode(info),str(length)]), expected))
    key = rng.randbytes(rng.choice([32,33,63,64,65,131]))
    expected = HKDFExpand(hashes.SHA256(), length, info).derive(key).hex()
    cases.append((':'.join([encode(key),encode(info),str(length)]), expected))
key = encode(bytes(range(32)))
cases.extend([(key+'::8161','length:8161'), (key+'::4294967295','length:4294967295')])
for n in [0,1,31]:
    cases.extend([(encode(bytes(n))+'::0','key'), (encode(bytes(n))+'::32','key')])
cases.extend([
    (key+':256:0','byte:256'), (key+':256:32','byte:256'),
    (key+',256::0','byte:256'), ('256:1','byte:256'), ('1:4294967295','byte:4294967295'),
    ('1:256::32','byte:256'), ('1:2:256:32','byte:256'),
])
records = {}
for backend, command in [('native-1',['build/hkdf-sha256','--threads','1']), ('native-4',['build/hkdf-sha256','--threads','4']), ('bun',['bun','build/hkdf-sha256.js'])]:
    outputs = []
    for i in range(0,len(cases),16):
        batch = cases[i:i+16]
        run = subprocess.run(command+[text for text,_ in batch], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert run.returncode == 0 and not run.stderr, (backend,i,run.returncode,run.stderr[-2000:])
        lines = run.stdout.splitlines()
        assert len(lines) == len(batch), (backend,i,len(lines))
        for line,(_,expected) in zip(lines,batch):
            actual = bytes(map(int,filter(None,line[3:].split(',')))).hex() if line.startswith('ok:') else line
            assert actual == expected, (backend,i,actual[:100],expected[:100])
            outputs.append(actual)
    records[backend] = {'cases':len(outputs),'outputs_sha256':hashlib.sha256('\n'.join(outputs).encode()).hexdigest()}
    print(backend,len(outputs),'HKDF-SHA-256 cases PASS',flush=True)
paths = ['packages/runtime/src/hkdf-sha256.bend','packages/runtime/src/hmac-sha256.bend','packages/runtime/src/sha256.bend','tests/hkdf-sha256.bend','tests/hkdf_sha256_check.py']
record = {'runs':records,'sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}}
(ROOT/'build/hkdf-sha256-results.json').write_text(json.dumps(record,indent=2)+'\n')

"""HMAC-SHA-256 reference vectors and differential streaming checks."""
import hashlib
import hmac
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(4231)
encode = lambda data: ','.join(map(str, data))
cases = []
# RFC 4231 full-output vectors (cases 1–4, 6–7).
vectors = [
    (b'\xaa'*131, b'Test Using Larger Than Block-Size Key - Hash Key First', '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54'),
    (b'\xaa'*131, b'This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.', '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2'),
    (b'\x0b'*20, b'Hi There', 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7'),
    (b'Jefe', b'what do ya want for nothing?', '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843'),
    (b'\xaa'*20, b'\xdd'*50, '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe'),
    (bytes(range(1,26)), b'\xcd'*50, '82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b'),
]
for key, data, expected in vectors:
    assert hmac.digest(key, data, 'sha256').hex() == expected
    cases.append((encode(key)+':'+encode(data), expected))
for k in [0, 1, 20, 32, 63, 64, 65, 127, 128, 131, 1024]:
    for n in [0, 1, 31, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024, 8192]:
        key, data = rng.randbytes(k), rng.randbytes(n)
        expected = hmac.digest(key, data, 'sha256').hex()
        cases.append((encode(key)+':'+encode(data), expected))
        chunks, at = [''], 0
        while at < n:
            end = min(n, at + rng.randrange(1, 80))
            chunks.extend([encode(data[at:end]), ''])
            at = end
        cases.append((encode(key)+':'+ '|'.join(chunks), expected))
for k in [0, 63, 64, 65, 128]:
    cases.append((encode([0]*k+[256])+':1', 'byte:256'))
cases.extend([('4294967295:1', 'byte:4294967295'), ('1:2|256|3', 'byte:256')])
records = {}
for backend, command in [('native-1', ['build/hmac-sha256','--threads','1']), ('native-4', ['build/hmac-sha256','--threads','4']), ('bun', ['bun','build/hmac-sha256.js'])]:
    outputs = []
    for i in range(0, len(cases), 16):
        batch = cases[i:i+16]
        run = subprocess.run(command+[text for text,_ in batch], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert run.returncode == 0 and not run.stderr, (backend, i, run.returncode, run.stderr[-2000:])
        lines = run.stdout.splitlines()
        assert len(lines) == len(batch), (backend, i, len(lines))
        for line, (_, expected) in zip(lines, batch):
            actual = line if line.startswith('byte:') else bytes(map(int, line.split(','))).hex()
            assert actual == expected, (backend, i, actual, expected)
            outputs.append(actual)
    records[backend] = {'cases':len(outputs), 'outputs_sha256':hashlib.sha256('\n'.join(outputs).encode()).hexdigest()}
    print(backend, len(outputs), 'HMAC-SHA-256 cases PASS', flush=True)
paths = ['packages/runtime/src/hmac-sha256.bend', 'packages/runtime/src/sha256.bend', 'tests/hmac-sha256.bend', 'tests/hmac_sha256_check.py']
record = {'runs': records, 'sources': {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}}
(ROOT/'build/hmac-sha256-results.json').write_text(json.dumps(record, indent=2)+'\n')

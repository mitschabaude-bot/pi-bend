"""Byte-oriented SHA-256 vectors and streaming comparison with hashlib."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--backends', nargs='+', default=['native-1', 'native-4', 'bun'])
args = p.parse_args()
rng = random.Random(1804)
known = [
    (b'', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    (b'abc', 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
    (b'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq', '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'),
]
cases = []
encode = lambda chunks: '|'.join(','.join(map(str, chunk)) for chunk in chunks)
for data, expected in known:
    assert hashlib.sha256(data).hexdigest() == expected
    cases.append((encode([data]), expected))
for n in list(range(130)) + [191, 192, 193, 255, 256, 257, 511, 512, 513, 1024, 4096, 8192]:
    data = rng.randbytes(n)
    expected = hashlib.sha256(data).hexdigest()
    cases.append((encode([data]), expected))
    chunks = [b'']
    at = 0
    while at < n:
        end = min(n, at + rng.randrange(1, 70))
        chunks.extend([data[at:end], b''])
        at = end
    cases.append((encode(chunks), expected))
for split in range(65):
    data = bytes(range(64))
    cases.append((encode([data[:split], data[split:]]), hashlib.sha256(data).hexdigest()))
cases.append(('m', 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0'))
cases.extend([('256', 'byte:256'), ('1,2|4294967295|3', 'byte:4294967295')])
records = {}
for backend, command in [('native-1', [str(ROOT/'build/sha256'), '--threads', '1']), ('native-4', [str(ROOT/'build/sha256'), '--threads', '4']), ('bun', ['bun', str(ROOT/'build/sha256.js')])]:
    if backend not in args.backends: continue
    outputs = []
    for i in range(0, len(cases), 24):
        group = cases[i:i+24]
        run = subprocess.run(command + [text for text, _ in group], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert run.returncode == 0, (backend, i, run.returncode, run.stderr[-2000:])
        assert not run.stderr, (backend, run.stderr)
        lines = run.stdout.splitlines()
        assert len(lines) == len(group), (backend, len(lines), len(group))
        for line, (text, expected) in zip(lines, group):
            actual = line if line.startswith('byte:') else bytes(map(int, line.split(','))).hex()
            assert actual == expected, (backend, text, actual, expected)
            outputs.append(actual)
    records[backend] = {'cases': len(outputs), 'outputs_sha256': hashlib.sha256('\n'.join(outputs).encode()).hexdigest()}
    print(backend, len(outputs), 'SHA-256 cases PASS', flush=True)
paths = ['packages/runtime/src/sha256.bend', 'laws/sha256.bend', 'proofs/sha256.bend', 'tests/sha256.bend', 'tests/sha256_check.py']
record = {'scope': 'NIST standard vectors, padding boundaries, random byte strings and streaming partitions, invalid-byte rejection; no TLS integration or formal SHA-256 equivalence claim.', 'runs': records, 'sources': {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}, 'programs': {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in ['build/sha256', 'build/sha256.c', 'build/sha256.js']}}
(ROOT/'build/sha256-results.json').write_text(json.dumps(record, indent=2)+'\n')

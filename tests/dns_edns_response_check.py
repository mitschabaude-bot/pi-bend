"""EDNS response metadata and opaque TLVs against independent wire construction."""
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUN = Path.home() / '.bun/bin/bun'
COMPILER = Path(BEND)
if '--no-build' not in sys.argv:
    for suffix in ['c', 'js']:
        subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', f'build/dns-edns-response-{suffix}-build.json', '--', str(BUN), str(COMPILER), 'tests/dns-edns-response.bend', '-o', f'build/dns-edns-response.{suffix}'], cwd=ROOT, check=True)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1', 'build/dns-edns-response.c', '-lpthread', '-lm', '-o', 'build/dns-edns-response'], cwd=ROOT, check=True)

def rr(kind=41, payload=1232, upper=0, version=0, flags=0, data=b'', owner=b'\0'):
    return owner + struct.pack('!HHIH', kind, payload, upper << 24 | version << 16 | flags, len(data)) + data

def packet(additional=(), answers=(), authorities=(), low=0, question=b''):
    return struct.pack('!6H', 42, 0x8180 | low, bool(question), len(answers), len(authorities), len(additional)) + question + b''.join(answers + authorities + additional)

def tlvs(options):
    return b''.join(struct.pack('!HH', code, len(data)) + data for code, data in options)

def expected(payload, upper, version, flags, low, options):
    return [f'{payload}:{upper}:{version}:{flags}:{upper * 16 + low}:{"do" if flags & 32768 else "no"}', *[f'{code}:{data.hex()}' for code, data in options]]

cases = []
def add(wire, want):
    cases.append(([wire.hex()], want))

for upper, version, flags, low in itertools.product([0, 1, 255], [0, 1, 255], [0, 1, 32768, 65535], [0, 3, 15]):
    options = [(65001, b'\0\xff'), (0, b''), (65001, b'abc'), (65535, b'')]
    add(packet((rr(upper=upper, version=version, flags=flags, data=tlvs(options)),), low=low), expected(1232, upper, version, flags, low, options))
for payload in [0, 1, 511, 512, 4096, 65535]:
    add(packet((rr(payload=payload),)), expected(payload, 0, 0, 0, 0, []))
for low in range(16):
    add(packet(low=low), [f'none:{low}'])
    add(packet((rr(kind=65000, owner=b'\x01x\0', data=b'\xff'),), low=low), [f'none:{low}'])
other = rr(kind=1, owner=b'\x01a\0', data=b'\x7f\0\0\1')
for position in range(4):
    additional = [other] * 3
    additional.insert(position, rr())
    add(packet(tuple(additional), (other,), (other,)), expected(1232, 0, 0, 0, 0, []))
for section in ['answer', 'authority']:
    add(packet(answers=(rr(),) if section == 'answer' else (), authorities=(rr(),) if section == 'authority' else ()), ['misplaced'])
for additional in [(rr(), rr()), (rr(), other, rr())]:
    add(packet(additional), ['duplicate'])
add(packet((rr(owner=b'\x01a\0'),)), ['owner'])
# Compressed root is represented as the root name by the shared name parser.
question = b'\0\0\1\0\1'
add(packet((rr(owner=b'\xc0\x0c'),), question=question), expected(1232, 0, 0, 0, 0, []))
for data in [b'\0', b'\0\1', b'\0\1\0', b'\0\1\0\1', b'\0\1\xff\xff', b'\0\1\0\2x', tlvs([(9, b'ok')]) + b'\xff']:
    # The following RR has bytes available, but they must never satisfy this RDLENGTH.
    add(packet((rr(data=data), other)), ['option'])
for length in [0, 1, 255, 256, 4096, 65508]:
    options = [(65000, bytes(i % 256 for i in range(length)))]
    add(packet((rr(data=tlvs(options)),)), expected(1232, 0, 0, 0, 0, options))
for count in [1, 127, 4096, 16378]:
    options = [(i % 65536, b'') for i in range(count)]
    add(packet((rr(data=tlvs(options)),)), expected(1232, 0, 0, 0, 0, options))
for wire in [b'', b'\0' * 11, packet((rr(),))[:-1], packet((rr(),)) + b'\0']:
    add(wire, ['message'])
# Public record decoder: hostile spans must not wrap or borrow adjacent bytes.
for start, length, kind, payload in [(0, 0, 41, 1232), (4, 0, 41, 1232), (5, 0, 41, 1232), (0, 4, 41, 1232), (1, 4, 41, 1232), (0, 3, 41, 1232), (0, 65536, 41, 1232), (4294967295, 2, 41, 1232), (2, 4294967295, 41, 1232), (0, 0, 1, 1232), (0, 0, 41, 65536)]:
    want = ['field']
    if kind == 41 and payload <= 65535 and start <= 4 and length <= 4 - start:
        want = expected(payload, 0, 0, 0, 0, [(0, b'')] if length == 4 else []) if length in [0, 4] else ['option']
    cases.append((['00000000', str(start), str(length), str(kind), str(payload)], want))

checks = []
for backend, command in [('native 1', ['build/dns-edns-response', '--threads', '1']), ('native 4', ['build/dns-edns-response', '--threads', '4']), ('Bun', [str(BUN), 'build/dns-edns-response.js'])]:
    for index, (args, want) in enumerate(cases):
        run = subprocess.run([*command, *args], cwd=ROOT, capture_output=True, text=True, timeout=45)
        assert run.returncode == 0 and not run.stderr and run.stdout.splitlines() == want, (backend, index, run.returncode, run.stderr, run.stdout[:200], want[:2])
    checks.append(dict(backend=backend, cases=len(cases)))
    print(f'{backend}: {len(cases)} EDNS response cases PASS', flush=True)
paths = ['packages/runtime/src/dns-message.bend', 'tests/dns-edns-response.bend', 'tests/dns_edns_response_check.py']
result = dict(scope=__doc__, reference='https://datatracker.ietf.org/doc/html/rfc6891', checks=checks, sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}, builds={s: json.loads((ROOT / f'build/dns-edns-response-{s}-build.json').read_text()) for s in ['c', 'js']})
(ROOT / 'build/dns-edns-response-result.json').write_text(json.dumps(result, indent=2) + '\n')

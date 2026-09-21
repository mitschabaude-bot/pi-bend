"""TLS 1.3 record protection against an independent AESGCM oracle (RFC 8446 §5).

Build tests/tls13-record.bend to build/tls13-record and build/tls13-record.js.
"""
from pathlib import Path
import random
import subprocess
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(8446)
key, iv = rng.randbytes(16), rng.randbytes(12)
cases = []


def encode(data):
    return ','.join(map(str, data))


def request(seq, command, *parts):
    fields = [encode(key), encode(iv), str(seq >> 32), str(seq & 0xffffffff), command]
    return ':'.join(fields + [encode(p) if isinstance(p, (bytes, bytearray, list)) else str(p) for p in parts])


def successor(seq):
    return 'exhausted' if seq == (1 << 64) - 1 else f'{(seq + 1) >> 32},{(seq + 1) & 0xffffffff}'


def record(seq, inner, version=b'\x03\x03'):
    nonce = (int.from_bytes(iv, 'big') ^ seq).to_bytes(12, 'big')
    header = b'\x17' + version + (len(inner) + 16).to_bytes(2, 'big')
    return header + AESGCM(key).encrypt(nonce, inner, header)


def check(seq, kind, content, padding):
    wire = record(seq, content + bytes([kind]) + bytes(padding))
    cases.append((request(seq, 's', kind, padding, content), successor(seq) + '|' + encode(wire)))
    trailing = rng.randbytes(7)
    cases.append((request(seq, 'o', wire + trailing), successor(seq) + '|' + str(kind) + '|' + encode(content) + '|' + encode(trailing)))
    changed = bytearray(wire)
    changed[-1] ^= 1
    cases.append((request(seq, 'o', changed), 'mac'))
    cases.append((request(seq ^ 1, 'o', wire), 'mac'))


for seq in [0, 1, 255, 256, 0xffffffff, 0x100000000, (1 << 63), (1 << 64) - 2, (1 << 64) - 1]:
    for kind, content in [(23, b''), (23, b'a\x00\x00'), (22, b'\x01\x00\x00\x00'), (21, b'\x01\x00')]:
        for padding in [0, 1, 15, 16, 17]:
            check(seq, kind, content, padding)

# Bounds include padding, not just content. Alert records contain exactly one
# two-byte alert. Empty handshake records and unsupported inner types fail.
for size, padding in [(16384, 0), (16383, 1), (0, 16384), (255, 257)]:
    check(2, 23, rng.randbytes(size), padding)
for kind, data, padding, error in [
    (23, bytes(16385), 0, 'overflow'), (23, b'', 16385, 'overflow'),
    (23, b'', 0xffffffff, 'overflow'), (23, bytes(16384), 1, 'overflow'),
    (22, b'', 0, 'unexpected'), (21, b'', 0, 'unexpected'),
    (21, b'a', 0, 'unexpected'), (21, b'abcd', 0, 'unexpected'),
    (23, [256], 0, 'byte'),
]:
    cases.append((request(0, 's', kind, padding, data), error))
for inner, expected in [
    (b'', 'unexpected'), (bytes(31), 'unexpected'), (b'\x14', 'unexpected'),
    (b'data\x19\x00', 'unexpected'), (b'\x16\x00', 'unexpected'),
    (b'\x15', 'unexpected'), (b'a\x15', 'unexpected'), (b'abcd\x15', 'unexpected'),
    (bytes(16385) + b'\x17', 'overflow'),
]:
    cases.append((request(0, 'o', record(0, inner)), expected))

wire = record(0, b'hello\x17')
for n in range(len(wire)):
    cases.append((request(0, 'o', wire[:n]), 'truncated'))
for length, expected in [(0, 'mac'), (15, 'mac'), (16641, 'overflow'), (65535, 'overflow')]:
    cases.append((request(0, 'o', b'\x17\x03\x03' + length.to_bytes(2, 'big')), expected))
for byte in [0, 20, 21, 22, 24, 255]:
    cases.append((request(0, 'o', bytes([byte]) + wire[1:]), 'unexpected'))
for position in [0, 1, 2, 3, 4, 5, len(wire) - 1]:
    changed = list(wire)
    changed[position] = 256
    cases.append((request(0, 'o', changed), 'byte'))
# The legacy version is ignored semantically but its exact bytes are authenticated.
for version in [b'\x03\x01', b'\x00\xff']:
    cases.append((request(0, 'o', record(0, b'hello\x17', version)), '0,1|23|' + encode(b'hello') + '|'))
    changed = bytearray(wire)
    changed[1:3] = version
    cases.append((request(0, 'o', changed), 'mac'))
# Use the actual returned affine state for a second write, including exhaustion.
for seq in [0, 0xffffffff, (1 << 64) - 2, (1 << 64) - 1]:
    first = record(seq, b'hello\x17')
    after = 'exhausted' if seq == (1 << 64) - 1 else successor(seq + 1) + '|' + encode(record(seq + 1, b'hello\x17'))
    cases.append((request(seq, 'c', b'hello'), encode(first) + '|' + after))

for seq in [0, 0xffffffff, (1 << 64) - 2, (1 << 64) - 1]:
    combined = record(seq, b'first\x17') + record((seq + 1) % (1 << 64), b'second\x17')
    expected = 'exhausted' if seq == (1 << 64) - 1 else successor(seq + 1) + '|23|' + encode(b'second') + '|'
    cases.append((request(seq, 'r', combined), expected))
    altered = bytearray(combined)
    altered[-1] ^= 1
    cases.append((request(seq, 'r', altered), 'exhausted' if seq == (1 << 64) - 1 else 'mac'))

# RFC 8448 section 3, client Finished: published wire bytes, not oracle-generated.
# https://www.rfc-editor.org/rfc/rfc8448#section-3
rfc_key = bytes.fromhex('dbfaa693d1762c5b666af5d950258d01')
rfc_iv = bytes.fromhex('5bd3c71b836e0b76bb73265f')
rfc_plain = bytes.fromhex('14000020a8ec436d677634ae525ac1fcebe11a039ec17694fac6e98527b642f2edd5ce61')
rfc_wire = bytes.fromhex('170303003575ec4dc238cce60b298044a71e219c56cc77b0517fe9b93c7a4bfc44d87f38f80338ac98fc46deb384bd1caeacab6867d726c40546')
rfc_prefix = encode(rfc_key) + ':' + encode(rfc_iv) + ':0:0:'
cases.extend([
    (rfc_prefix + 's:22:0:' + encode(rfc_plain), '0,1|' + encode(rfc_wire)),
    (rfc_prefix + 'o:' + encode(rfc_wire), '0,1|22|' + encode(rfc_plain) + '|'),
])

for name, command in [('native-1', ['build/tls13-record', '--threads', '1']),
                      ('native-4', ['build/tls13-record', '--threads', '4']),
                      ('bun', ['bun', 'build/tls13-record.js'])]:
    for start in range(0, len(cases), 16):
        batch = cases[start:start + 16]
        result = subprocess.run(command + [text for text, _ in batch], cwd=ROOT,
                                capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, (name, start, result.stderr[-2000:])
        actual = result.stdout.splitlines()
        assert len(actual) == len(batch), (name, start, len(actual))
        for offset, (line, (_, expected)) in enumerate(zip(actual, batch)):
            assert line == expected, (name, start + offset, line[:180], expected[:180])
    print(f'{name}: {len(cases)} TLS record checks PASS', flush=True)

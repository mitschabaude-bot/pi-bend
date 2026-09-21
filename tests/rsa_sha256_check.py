"""Native RSA public operations and PSS/PKCS1-v1.5 SHA256 vs independent references.

Build tests/rsa-sha256.bend to build/rsa-sha256 and .js first.
Private keys are ephemeral oracle inputs and never enter the Bend verifier.
"""
from pathlib import Path
import random
import subprocess
import time
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(8017)


def encode(values):
    return ','.join(map(str, values))


def integer(value, size=None):
    return value.to_bytes(size or max(1, (value.bit_length() + 7) // 8), 'big')


cases = []
# The primitive is generic public modular arithmetic, including multi-byte e.
for _ in range(120):
    n = rng.randrange(7, 1 << rng.randrange(4, 129)) | 1
    e = rng.randrange(3, n, 2)
    s = rng.randrange(n)
    size = len(integer(n))
    cases.append(('r:' + ':'.join(map(encode, [integer(n), integer(e), integer(s, size)])), encode(integer(pow(s, e, n), size))))
for n, e in [(b'', b'\x03'), (b'\x00\x0f', b'\x03'), (b'\x10', b'\x03'),
             (b'\x0f', b'\x00\x03'), (b'\x0f', b'\x01'), (b'\x0f', b'\x02'),
             (b'\x0f', b'\x0f'), (b'\x0f', b'\x11'), ([256], [3])]:
    cases.append(('r:' + encode(n) + ':' + encode(e) + ':1', 'key'))
for signature in [[], [15], [16], [256], [0, 1]]:
    cases.append(('r:15:3:' + encode(signature), 'signature'))

for bits, e in [(1024, 3), (1025, 65537), (2048, 65537), (3072, 65537)]:
    private = rsa.generate_private_key(public_exponent=e, key_size=bits)
    public = private.public_key().public_numbers()
    nbytes, ebytes = integer(public.n), integer(public.e)
    key = encode(nbytes) + ':' + encode(ebytes)
    message = rng.randbytes(73)
    for salt_length in [0, 32, (public.n.bit_length() + 6) // 8 - 34]:
        signature = private.sign(message, padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=salt_length), hashes.SHA256())
        arg = 'p:' + key + ':' + encode(message) + ':' + encode(signature) + ':' + str(salt_length)
        cases.append((arg, 'ok'))
        cases.append(('p:' + key + ':' + encode(message + b'x') + ':' + encode(signature) + ':' + str(salt_length), 'signature'))
        cases.append(('p:' + key + ':' + encode(message) + ':' + encode(signature) + ':' + str(salt_length + 1), 'signature'))
    if bits == 1024:
        encoded = integer(pow(int.from_bytes(signature, 'big'), e, public.n), len(nbytes))
        for index in [0, len(encoded)-33, len(encoded)-1]:
            bad = bytearray(encoded)
            bad[index] ^= 128 if index == 0 else 1
            value = int.from_bytes(bad, 'big')
            if value < public.n:
                malformed = integer(pow(value, private.private_numbers().d, public.n), len(nbytes))
                cases.append(('p:' + key + ':' + encode(message) + ':' + encode(malformed) + ':' + str(salt_length), 'signature'))
    signature = private.sign(message, padding.PKCS1v15(), hashes.SHA256())
    cases.append(('v:' + key + ':' + encode(message) + ':' + encode(signature), 'ok'))
    cases.append(('v:' + key + ':' + encode(message + b'x') + ':' + encode(signature), 'signature'))
    # Use only this ephemeral test key to encode malformed padding blocks.
    encoded = integer(pow(int.from_bytes(signature, 'big'), e, public.n), len(nbytes))
    for index, replacement in [(0, 1), (1, 2), (5, 0), (len(encoded)-1, encoded[-1] ^ 1)]:
        bad = bytearray(encoded)
        bad[index] = replacement
        value = int.from_bytes(bad, 'big')
        if value < public.n:
            malformed = integer(pow(value, private.private_numbers().d, public.n), len(nbytes))
            cases.append(('v:' + key + ':' + encode(message) + ':' + encode(malformed), 'signature'))
    for signature in [bytes(len(nbytes)), nbytes, b'\x00' + signature, signature[:-1]]:
        cases.append(('p:' + key + ':' + encode(message) + ':' + encode(signature) + ':32', 'signature'))

for name, command in [('native-1', ['build/rsa-sha256', '--threads', '1']),
                      ('native-4', ['build/rsa-sha256', '--threads', '4']),
                      ('bun', ['bun', 'build/rsa-sha256.js'])]:
    start = time.monotonic()
    run = subprocess.run(command + [arg for arg, _ in cases], cwd=ROOT, capture_output=True, text=True, timeout=300)
    assert run.returncode == 0, (name, run.stderr[-3000:])
    lines = run.stdout.splitlines()
    assert len(lines) == len(cases), (name, len(lines), len(cases))
    for index, (actual, (_, expected)) in enumerate(zip(lines, cases)):
        assert actual == expected, (name, index, actual[:100], expected[:100])
    print(f'{name}: {len(cases)} RSA SHA256 checks PASS in {time.monotonic() - start:.2f}s', flush=True)

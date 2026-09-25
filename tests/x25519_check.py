"""Native X25519: field arithmetic, RFC 7748 vectors and independent key exchange.

Build tests/x25519.bend to build/x25519 and build/x25519.js first.
Python integers and cryptography are test oracles only.
"""
from pathlib import Path
import random
import subprocess
import time
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

ROOT = Path(__file__).resolve().parents[1]
P = 2**255 - 19
rng = random.Random(7748)


def encode(data):
    return ','.join(map(str, data))


def integer(n):
    return n.to_bytes(32, 'little')


def request(operation, *parts):
    return ':'.join([operation, *(encode(p) for p in parts)])


def public(secret):
    return X25519PrivateKey.from_private_bytes(secret).public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)


def shared(secret, point):
    try:
        return X25519PrivateKey.from_private_bytes(secret).exchange(X25519PublicKey.from_public_bytes(point))
    except ValueError:
        return None


field_cases = []
values = [0, 1, 18, 19, 255, 256, 257, 2**128 - 1, 2**128, P - 2, P - 1]
pairs = [(a, b) for a in values for b in values]
pairs += [(rng.randrange(P), rng.randrange(P)) for _ in range(128)]
for a, b in pairs:
    for operation, expected in [('a', (a + b) % P), ('d', (a - b) % P), ('m', (a * b) % P)]:
        field_cases.append((request(operation, integer(a), integer(b)), encode(integer(expected))))
for a in values:
    field_cases.append((request('i', integer(a), b''), encode(integer(pow(a, P - 2, P)))))
# The field holds any value below 2^256 between operations, so noncanonical
# inputs up to 2^256 - 1 exercise every carry fold and both final subtractions.
# (The earlier byte-limb field's coefficient-normalization cases tested an
# internal representation that no longer exists.)
wide = [P, P + 18, 2**255, 2**256 - 38, 2**256 - 1]
for a in wide:
    for b in values + wide:
        for x, y in [(a, b), (b, a)]:
            for operation, expected in [('a', (x + y) % P), ('d', (x - y) % P), ('m', (x * y) % P)]:
                field_cases.append((request(operation, integer(x), integer(y)), encode(integer(expected))))
    field_cases.append((request('i', integer(a), b''), encode(integer(pow(a, P - 2, P)))))

curve_cases = []
# https://www.rfc-editor.org/rfc/rfc7748#section-5.2
for scalar, point, expected in [
    ('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4',
     'e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c',
     'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552'),
    ('4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d',
     'e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493',
     '95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957'),
]:
    secret, point, expected = map(bytes.fromhex, (scalar, point, expected))
    assert shared(secret, point) == expected
    curve_cases.append((request('x', secret, point), encode(expected)))
# RFC 7748 section 5.2, iterated: k and u start at 9; each step sets
# k, u = X25519(k, u), k.
nine = integer(9)
for count, expected in [(1, '422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079'),
                        (1000, '684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51')]:
    curve_cases.append((f'r:{count}:' + encode(nine), encode(bytes.fromhex(expected))))
# RFC 7748 section 6.1: both parties' public keys and shared secret.
alice = bytes.fromhex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a')
bob = bytes.fromhex('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb')
ap = bytes.fromhex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a')
bp = bytes.fromhex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f')
expected = bytes.fromhex('4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742')
assert public(alice) == ap and public(bob) == bp and shared(alice, bp) == expected
curve_cases += [(request('p', alice), encode(ap)), (request('p', bob), encode(bp)),
                (request('s', alice, bp), encode(expected)), (request('s', bob, ap), encode(expected))]

for _ in range(12):
    a, b = rng.randbytes(32), rng.randbytes(32)
    pa, pb = public(a), public(b)
    expected = shared(a, pb)
    assert expected == shared(b, pa)
    curve_cases += [(request('p', a), encode(pa)), (request('p', b), encode(pb)),
                    (request('s', a, pb), encode(expected)), (request('s', b, pa), encode(expected))]
for _ in range(16):
    secret, point = rng.randbytes(32), rng.randbytes(32)
    expected = shared(secret, point)
    assert expected is not None
    curve_cases.append((request('x', secret, point), encode(expected)))
    changed = bytearray(secret)
    changed[0] ^= 7
    changed[-1] ^= 192
    point = bytearray(point)
    point[-1] ^= 128
    curve_cases.append((request('s', changed, point), encode(expected)))

# Noncanonical coordinates and the mandatory top-bit mask are part of X25519,
# not permissive parsing. The TLS entry point rejects all-zero shared secrets.
for point in [0, 1, P - 1] + list(range(P, P + 19)):
    for top in [0, 2**255]:
        point_bytes = integer(point + top)
        value = shared(alice, point_bytes)
        curve_cases.append((request('x', alice, point_bytes), encode(value or bytes(32))))
        curve_cases.append((request('s', alice, point_bytes), encode(value) if value else 'low-order'))
for length in [0, 1, 31, 33, 64]:
    curve_cases += [(request('x', bytes(length), bp), 'length'), (request('s', alice, bytes(length)), 'length')]
for position in [0, 15, 31]:
    for value in [256, 0xffffffff]:
        malformed = list(alice)
        malformed[position] = value
        curve_cases += [(request('x', malformed, bp), 'byte'), (request('s', alice, malformed), 'byte')]

for name, command in [('native-1', ['build/x25519', '--threads', '1']),
                      ('native-4', ['build/x25519', '--threads', '4']),
                      ('bun', ['bun', 'build/x25519.js'])]:
    for group, cases in [('field', field_cases), ('curve', curve_cases)]:
        started = time.monotonic()
        for start in range(0, len(cases), 8):
            batch = cases[start:start + 8]
            result = subprocess.run(command + [text for text, _ in batch], cwd=ROOT,
                                    capture_output=True, text=True, timeout=90)
            assert result.returncode == 0, (name, group, start, result.stderr[-2000:])
            actual = result.stdout.splitlines()
            assert len(actual) == len(batch), (name, group, start, len(actual))
            for offset, (line, (_, expected)) in enumerate(zip(actual, batch)):
                assert line == expected, (name, group, start + offset, line, expected)
        print(f'{name}: {len(cases)} {group} checks PASS ({time.monotonic() - started:.2f}s)', flush=True)

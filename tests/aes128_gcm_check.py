"""AES-GCM known answers and differential checks; no production Python dependency.

Build with:
  sh scripts/build-pure.sh tests/aes128-gcm.bend build/aes128-gcm
  build/bend-native-toolchain/bend2/main.ts tests/aes128-gcm.bend -o build/aes128-gcm.js
"""
from pathlib import Path
import random
import subprocess

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]


def encode(data):
    return ",".join(map(str, data))


def request(operation, *parts):
    return ":".join([operation, *(encode(part) for part in parts)])


cases = []


def vector(key, nonce, aad, plaintext, expected=None):
    encrypted = AESGCM(key).encrypt(nonce, plaintext, aad)
    if expected is not None:
        assert encrypted.hex() == expected
    ciphertext, tag = encrypted[:-16], encrypted[-16:]
    cases.append((request("s", key, nonce, aad, plaintext), encode(ciphertext) + ":" + encode(tag)))
    cases.append((request("o", key, nonce, aad, ciphertext, tag), "ok:" + encode(plaintext)))
    return ciphertext, tag


# Published GCM zero-key known answers, checked against the independent oracle.
vector(bytes(16), bytes(12), b"", b"", "58e2fccefa7e3061367f1d57a4e7455a")
vector(bytes(16), bytes(12), b"", bytes(16),
       "0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf")
# The multi-block, partial-last-block example exercises nonempty AAD padding.
vector(bytes.fromhex("feffe9928665731c6d6a8f9467308308"),
       bytes.fromhex("cafebabefacedbaddecaf888"),
       bytes.fromhex("feedfacedeadbeeffeedfacedeadbeefabaddad2"),
       bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                     "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"),
       "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
       "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc3221a5db94fae95ae7121a47")

rng = random.Random(8446)
for size in [0, 1, 2, 15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 256, 257, 16384, 16385]:
    for aad_size in [0, 5, 15, 16, 17, 33]:
        key, nonce = rng.randbytes(16), rng.randbytes(12)
        aad, plaintext = rng.randbytes(aad_size), rng.randbytes(size)
        ciphertext, tag = vector(key, nonce, aad, plaintext)
        # Each authenticated input contributes independently to the tag.
        for index in range(5):
            fields = [key, nonce, aad, ciphertext, tag]
            changed = bytearray(fields[index])
            if not changed:
                changed.append(1)
            else:
                changed[len(changed) // 2] ^= 1
            fields[index] = bytes(changed)
            cases.append((request("o", *fields), "authentication"))

key, nonce, aad = rng.randbytes(16), rng.randbytes(12), b"headers"
ciphertext, tag = vector(key, nonce, aad, b"authenticated plaintext")
for bit in range(128):
    changed = bytearray(tag)
    changed[bit // 8] ^= 1 << (bit % 8)
    cases.append((request("o", key, nonce, aad, ciphertext, changed), "authentication"))
for bad in [256, 4294967295]:
    cases.extend([
        (request("s", key, nonce, [bad], b""), "byte"),
        (request("s", key, nonce, b"", [bad]), "byte"),
        (request("o", key, nonce, [bad], ciphertext, tag), "byte"),
        (request("o", key, nonce, aad, [bad], tag), "byte"),
    ])
for length in [0, 1, 11, 13, 16]:
    cases.append((request("s", key, bytes(length), b"", b""), "invalid"))
for length in [0, 15, 17]:
    cases.append((request("o", key, nonce, aad, ciphertext, bytes(length)), "invalid"))

for name, command in [
    ("native-1", ["build/aes128-gcm", "--threads", "1"]),
    ("native-4", ["build/aes128-gcm", "--threads", "4"]),
    ("bun", ["bun", "build/aes128-gcm.js"]),
]:
    for start in range(0, len(cases), 16):
        batch = cases[start:start + 16]
        result = subprocess.run(command + [text for text, _ in batch], cwd=ROOT,
                                capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, (name, start, result.stderr[-2000:])
        actual = result.stdout.splitlines()
        assert len(actual) == len(batch), (name, start, len(actual), result.stderr[-2000:])
        for offset, (line, (_, expected)) in enumerate(zip(actual, batch)):
            assert line == expected, (name, start + offset, line[:200], expected[:200])
    print(f"{name}: {len(cases)} AES-GCM checks PASS", flush=True)

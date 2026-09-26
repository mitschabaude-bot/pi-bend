#!/usr/bin/env python3
"""Native RS256 signing (packages/runtime/src/rsa-sign.bend) vs pyca/cryptography.

Keys of several sizes and public exponents are generated per run and written
as PKCS#8 and PKCS#1 PEM; RSASSA-PKCS1-v1_5 SHA-256 is deterministic, so each
native signature must equal the reference byte for byte. Unsupported and
malformed keys report their error kind.

Usage: python3 tests/rsa_sign_check.py [--backend bun|native|all]
"""
import argparse
import os
import pathlib
import random
import subprocess
import tempfile
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tests/rsa-sign.bend"
rng = random.Random(8017)


def pem(key, fmt):
    return key.private_bytes(serialization.Encoding.PEM, fmt, serialization.NoEncryption())


def probable_prime(bits):
    while True:
        candidate = rng.getrandbits(bits) | (1 << (bits - 1)) | 1
        if all(pow(a, candidate - 1, candidate) == 1 for a in (2, 3, 5, 7, 11, 13)):
            return candidate


def der_integer(value):
    body = value.to_bytes(max(1, (value.bit_length() + 8) // 8), "big")
    return der(0x02, body)


def der(tag, body):
    size = len(body)
    length = bytes([size]) if size < 128 else bytes([0x80 | ((size.bit_length() + 7) // 8)]) + size.to_bytes((size.bit_length() + 7) // 8, "big")
    return bytes([tag]) + length + body


def small_key_pem():
    """A 488-bit PKCS#1 key, below cryptography's generation minimum."""
    import base64, math
    while True:
        p, q = probable_prime(244), probable_prime(244)
        n, e = p * q, 65537
        phi = (p - 1) * (q - 1)
        if math.gcd(e, phi) == 1 and n.bit_length() == 488:
            break
    d = pow(e, -1, phi)
    body = b"".join(der_integer(v) for v in (0, n, e, d, p, q, d % (p - 1), d % (q - 1), pow(q, -1, p)))
    text = base64.b64encode(der(0x30, body)).decode()
    return "-----BEGIN RSA PRIVATE KEY-----\n" + "\n".join(text[i:i + 64] for i in range(0, len(text), 64)) + "\n-----END RSA PRIVATE KEY-----\n"


def cases(directory):
    items = []
    for index, (bits, e) in enumerate([(1024, 3), (1025, 65537), (2048, 65537), (2048, 3), (3072, 65537), (512, 65537)]):
        key = rsa.generate_private_key(public_exponent=e, key_size=bits)
        for fmt, name in [(serialization.PrivateFormat.PKCS8, "pkcs8"), (serialization.PrivateFormat.TraditionalOpenSSL, "pkcs1")]:
            path = pathlib.Path(directory) / f"{index}-{name}.pem"
            path.write_bytes(pem(key, fmt))
            for size in (0, 1, 55, 64, 1000):
                message = rng.randbytes(size)
                want = key.sign(message, padding.PKCS1v15(), hashes.SHA256()).hex() 
                items.append((f"{bits}-bit e={e} {name} {size}-byte message", str(path), message.hex(), want))
    path = pathlib.Path(directory) / "small.pem"
    path.write_text(small_key_pem())
    items.append(("a 488-bit key is too small for the SHA-256 DigestInfo", str(path), "00", "error:small"))
    path = pathlib.Path(directory) / "ec.pem"
    path.write_bytes(pem(ec.generate_private_key(ec.SECP256R1()), serialization.PrivateFormat.PKCS8))
    items.append(("an EC key is unsupported", str(path), "00", "error:unsupported"))
    path = pathlib.Path(directory) / "garbage.pem"
    path.write_text("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n")
    items.append(("a malformed DER body is rejected", str(path), "00", "error:der"))
    path = pathlib.Path(directory) / "none.pem"
    path.write_text("not a pem")
    items.append(("text without a PEM block is rejected", str(path), "00", "error:unsupported"))
    return items


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rsa-sign-") as directory:
        items = cases(directory)
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "rsa-sign.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "rsa-sign"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        for backend, command in commands:
            argv = [value for _, path, message, _ in items for value in (path, message)]
            result = subprocess.run(command + argv, capture_output=True, text=True, timeout=1800)
            assert result.returncode == 0, result.stderr[-2000:]
            lines = result.stdout.splitlines()
            assert len(lines) == len(items), (len(lines), len(items))
            for (name, _, _, want), got in zip(items, lines):
                assert want is None or got == want, (backend, name, got[:80], want[:80] if want else want)
                print(f"PASS {backend}: {name}")


if __name__ == "__main__":
    main()

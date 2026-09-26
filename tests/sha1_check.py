#!/usr/bin/env python3
"""SHA-1 (packages/runtime/src/sha1.bend) vs Python's hashlib.

Messages cover every padding boundary around one and two 64-byte blocks, the
FIPS 180 examples and seeded random lengths up to several blocks.

Usage: python3 tests/sha1_check.py [--backend bun|native|all]
"""
import argparse
import hashlib
import os
import pathlib
import random
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tests/sha1.bend"
rng = random.Random(1790)
MESSAGES = [b"", b"abc", b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", b"https://example.awsapps.com/start", b"corp"]
MESSAGES += [bytes(rng.getrandbits(8) for _ in range(n)) for n in (*range(52, 70), *range(116, 132), 1, 7, 200, 511, 1000)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    expected = [hashlib.sha1(m).hexdigest() for m in MESSAGES]
    with tempfile.TemporaryDirectory(prefix="sha1-") as directory:
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "sha1.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "sha1"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        for backend, command in commands:
            result = subprocess.run([*command, *(m.hex() for m in MESSAGES)], capture_output=True, text=True, timeout=300, check=True)
            actual = result.stdout.split()
            for message, want, got in zip(MESSAGES, expected, actual):
                assert want == got, (backend, len(message), want, got)
            assert len(actual) == len(expected), (backend, len(actual))
            print(f"PASS {backend}: sha1 matches hashlib for {len(MESSAGES)} messages (lengths 0-1000)")


if __name__ == "__main__":
    main()

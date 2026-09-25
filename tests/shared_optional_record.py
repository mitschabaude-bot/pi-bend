"""Positive native ownership regression: sharing Some<String> preserves Some<Record>."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", type=Path, help="compiler entry point; defaults to BEND or the normal toolchain")
    parser.add_argument("--prefix", type=Path, default=Path("build/shared-optional-record"))
    parser.add_argument("--backends", nargs="+", choices=["bun", "native-1", "native-4"], default=["bun", "native-1", "native-4"])
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()
    local = ROOT / "build/bend-native-toolchain/bend2/main.ts"
    compiler = args.bend or Path(os.environ.get("BEND", str(local if local.exists() else Path.home() / ".bend/bin/bend")))
    compiler = compiler.resolve()
    prefix = (ROOT / args.prefix).resolve()
    javascript = Path(str(prefix) + ".js")
    source = "tests/shared-optional-record.bend"
    if not args.no_build:
        prefix.parent.mkdir(parents=True, exist_ok=True)
        if "bun" in args.backends:
            subprocess.run([str(compiler), source, "-o", str(javascript)], cwd=ROOT, check=True)
        if any(backend.startswith("native") for backend in args.backends):
            env = dict(os.environ, BEND=str(compiler))
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', "sh", "scripts/build-pure.sh", source, str(prefix)], cwd=ROOT, env=env, check=True)
    for backend in args.backends:
        command = ["bun", str(javascript)] if backend == "bun" else [str(prefix), "--threads", backend.rsplit("-", 1)[1]]
        count = 0
        for length in [0, 1, 3, 16, 17, 64, 1024]:
            # Empty input selects [0..11]. Otherwise [n+1..n+12]. Sharing
            # the optional string contributes its length twice. U32 wraps.
            expected = (66 if length == 0 else 14 * length + 78) & 0xFFFFFFFF
            for order in ["before", "after"]:
                result = subprocess.run([*command, order, "x" * length], cwd=ROOT, capture_output=True, text=True, timeout=30)
                assert result.returncode == 0 and result.stdout.strip() == str(expected), (
                    backend, order, length, expected, result.returncode, result.stdout, result.stderr)
                count += 1
        print(f"PASS {backend}: {count} shared optional-record checks", flush=True)


if __name__ == "__main__":
    main()

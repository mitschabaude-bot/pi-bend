"""Compare fresh native certificate validation with a test-only OpenSSL oracle.

Input is JSON containing the existing x509 runner's `limited:...` argument.
No network, credentials, or system trust store are used. Body measurements omit
DER parsing in both implementations and include policy/key preparation. Bend's
timer includes writing one `ok` line to a pipe (a conservative small overhead).
Process measurements include startup, file/argument handling and DER parsing;
their ratio is not the arithmetic acceptance ratio.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def execute(command):
    start = time.perf_counter_ns()
    result = subprocess.run(command, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(f"{command[0]} exited {result.returncode}: {result.stderr.strip()}")
    return result.stdout.splitlines(), time.perf_counter_ns() - start


def summary(values):
    return {"median_ms": statistics.median(values) / 1e6,
            "min_ms": min(values) / 1e6, "max_ms": max(values) / 1e6,
            "samples_ns": values}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--bend", type=Path, default=Path("build/certificate-benchmark"))
    parser.add_argument("--openssl", type=Path, default=Path("build/certificate-benchmark-openssl"))
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--oracle-samples", type=int, default=101)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--cpu", type=int, help="pin both implementations to one logical CPU (Linux)")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    assert args.samples > 0 and args.oracle_samples > 0
    if args.cpu is not None:
        assert args.threads == 1, "single-CPU comparison requires --threads 1"
        os.sched_setaffinity(0, {args.cpu})
    argument = json.loads(args.fixture.read_text())["argument"]
    mode, steps, high, low, leaf, peers, anchors = argument.split(":")
    assert mode == "limited"
    peer_values = [value for value in peers.split("|") if value]
    anchor_values = [value for value in anchors.split("|") if value]
    assert peer_values and len(anchor_values) == 1, "benchmark expects an intermediate and one explicit anchor"
    milliseconds = (int(high) << 32) | int(low)
    if milliseconds >= 1 << 63:
        milliseconds -= 1 << 64
    result = {"fixture_sha256": hashlib.sha256(argument.encode()).hexdigest(),
              "bend_binary_sha256": hashlib.sha256(args.bend.read_bytes()).hexdigest(),
              "openssl_binary_sha256": hashlib.sha256(args.openssl.read_bytes()).hexdigest(),
              "epoch_milliseconds": milliseconds, "threads": args.threads,
              "cpu_affinity": sorted(os.sched_getaffinity(0)),
              "policy": "explicit anchor; SSL server purpose; no hostname; fresh certificate objects",
              "openssl_version": subprocess.check_output(["openssl", "version"], text=True).strip(),
              "workloads": {}}
    with tempfile.TemporaryDirectory(prefix="bend-certificate-benchmark-") as folder:
        root = Path(folder)
        def write(name, value):
            path = root / name
            path.write_bytes(bytes(map(int, value.split(","))))
            return str(path)
        leaf_path = write("leaf.der", leaf)
        anchor_path = write("anchor.der", anchor_values[0])
        peer_paths = [write(f"peer-{i}.der", value) for i, value in enumerate(peer_values)]
        workloads = {
            "chain": (argument, ["chain", str(args.oracle_samples), str(milliseconds // 1000), leaf_path, anchor_path, *peer_paths]),
            "leaf_signature": (f"v:{peer_values[0]}:{leaf}", ["signature", str(args.oracle_samples), peer_paths[0], leaf_path]),
            "intermediate_signature": (f"v:{anchor_values[0]}:{peer_values[0]}", ["signature", str(args.oracle_samples), anchor_path, peer_paths[0]]),
        }
        for name, (bend_argument, oracle_arguments) in workloads.items():
            # One untimed warm-up establishes CPU/library state; fresh certs are
            # still parsed in every measured oracle iteration and Bend process.
            execute([str(args.openssl.resolve()), oracle_arguments[0], "1", *oracle_arguments[2:]])
            oracle_body = []
            body, processes, oracle_processes = [], [], []
            for _ in range(args.samples):
                oracle_lines, _ = execute([str(args.openssl.resolve()), *oracle_arguments])
                oracle_body.extend(map(int, oracle_lines))
                lines, duration = execute([str(args.bend.resolve()), "--threads", str(args.threads), bend_argument])
                assert len(lines) == 2 and lines[0] == "ok", lines
                h, l = map(int, lines[1].split(":"))
                body.append((h << 32) | l)
                processes.append(duration)
                _, oracle_duration = execute([str(args.openssl.resolve()), oracle_arguments[0], "1", *oracle_arguments[2:]])
                oracle_processes.append(oracle_duration)
            measurement = {"bend_body": summary(body), "openssl_body": summary(oracle_body),
                           "bend_process": summary(processes), "openssl_process": summary(oracle_processes),
                           "body_ratio": statistics.median(body) / statistics.median(oracle_body)}
            result["workloads"][name] = measurement
            print(f"{name}: Bend {statistics.median(body)/1e6:.3f} ms; OpenSSL {statistics.median(oracle_body)/1e6:.3f} ms; {measurement['body_ratio']:.1f}x", flush=True)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()

"""Measure the uninstrumented timer fixture; includes fixed race-test overhead."""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
source = root / 'tests/timer-races.bend'
records = []
with tempfile.TemporaryDirectory(prefix='timer-cohorts-') as directory:
    metrics = Path(directory) / 'time.txt'
    for threads in (1, 4):
        for repetition in range(3):
            sizes = [0, 128, 1024, 4096]
            if repetition % 2:
                sizes.reverse()
            for size in sizes:
                start = time.monotonic()
                result = subprocess.run([
                    '/usr/bin/time', '-f', '%U %S %M', '-o', str(metrics),
                    str(binary), '--threads', str(threads), '10', str(size),
                ], cwd=root, capture_output=True, text=True, check=True, timeout=60)
                wall = time.monotonic() - start
                assert result.stdout == 'PASS timer races and batches\n', result.stdout
                assert not result.stderr, result.stderr
                user, system, rss = metrics.read_text().split()
                records.append(dict(threads=threads, repetition=repetition, size=size,
                                    rounds=10, wall_seconds=wall, user_seconds=float(user),
                                    system_seconds=float(system), peak_rss_kib=int(rss)))
        for size in (0, 128, 1024, 4096):
            group = [r for r in records if r['threads'] == threads and r['size'] == size]
            print(threads, size, 'median wall', statistics.median(r['wall_seconds'] for r in group),
                  'median KiB', statistics.median(r['peak_rss_kib'] for r in group), flush=True)
output.write_text(json.dumps(dict(
    scope='Uninstrumented full lifecycle cohorts, reverse-order cancellation, 10 rounds. Includes fixed 272-race overhead; not isolated cancellation latency or an old-path regression comparison.',
    source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
    binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
    generated_c_sha256=hashlib.sha256(binary.with_suffix('.c').read_bytes()).hexdigest(),
    samples=records,
), indent=2) + '\n')

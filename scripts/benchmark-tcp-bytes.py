"""Compare isolated raw-TCP additions with the installed compiler.

Usage: python3 scripts/benchmark-tcp-bytes.py CANDIDATE_BEND2 OUTPUT_JSON
Measures loading/checking/C emission, not Clang, networking or runtime throughput.
"""
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
baseline = Path.home() / '.bend/current/bend2'
candidate = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2])
bun = Path.home() / '.bun/bin/bun'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


for name in ['main.ts', 'bend.ts', 'comp.ts']:
    assert digest(baseline / name) == digest(candidate / name), name
for path in (baseline / 'effs').iterdir():
    if path.is_file():
        assert digest(path) == digest(candidate / 'effs' / path.name), path.name
result = {
    'scope': __doc__, 'kernel': platform.release(), 'shared_host': True,
    'bun': subprocess.check_output([str(bun), '--version'], text=True).strip(),
    'compiler_sha256': {name: digest(baseline / name) for name in ['main.ts', 'bend.ts', 'comp.ts']},
    'base_sha256': {'baseline': digest(baseline / 'base.bend'), 'candidate': digest(candidate / 'base.bend')},
    'candidate_effect_sha256': {name: digest(candidate / 'effs' / name) for name in
        ['tcp_send_bytes.c', 'tcp_recv_bytes.c', 'tcp_send_bytes.js', 'tcp_recv_bytes.js']},
    'method': 'Two warmups; 20 alternating-order rounds per fixture. Fresh Bun process per sample. Wall clock includes GNU time wrapper. Individual GNU time peak RSS in KiB. C bytes must match for every sample.',
    'fixtures': {},
}
with tempfile.TemporaryDirectory(prefix='tcp-perf-', dir=ROOT / 'build') as directory:
    folder = Path(directory)
    for source in ['tests/tcp-text-baseline.bend', 'packages/runtime/test/utf8-runner.bend']:
        samples = {'baseline': [], 'candidate': []}
        expected = None
        for round_index in range(-2, 20):
            order = ['candidate', 'baseline'] if round_index % 2 else ['baseline', 'candidate']
            for variant in order:
                compiler = baseline if variant == 'baseline' else candidate
                generated = folder / (variant + '.c')
                usage = folder / 'usage.txt'
                started = time.perf_counter()
                subprocess.run(['/usr/bin/time', '-f', '%U %S %M', '-o', str(usage),
                                str(bun), str(compiler / 'main.ts'), source, '-o', str(generated)],
                               cwd=ROOT, check=True, capture_output=True, timeout=60)
                wall = time.perf_counter() - started
                cpu_user, cpu_system, rss = usage.read_text().split()
                code = generated.read_bytes()
                if expected is None:
                    expected = code
                assert code == expected, (source, variant, 'generated C changed')
                if round_index >= 0:
                    samples[variant].append({'wall_seconds': wall, 'cpu_user_seconds': float(cpu_user),
                                             'cpu_system_seconds': float(cpu_system), 'peak_rss_kib': int(rss)})
        medians = {variant: {key: statistics.median(row[key] for row in rows)
                            for key in ['wall_seconds', 'peak_rss_kib']} for variant, rows in samples.items()}
        result['fixtures'][source] = {'source_sha256': digest(ROOT / source),
            'generated_c_bytes': len(expected), 'generated_c_sha256': hashlib.sha256(expected).hexdigest(),
            'samples': samples, 'medians': medians,
            'wall_ratio': medians['candidate']['wall_seconds'] / medians['baseline']['wall_seconds']}
        print(source, result['fixtures'][source]['wall_ratio'], medians, flush=True)
destination.write_text(json.dumps(result, indent=2) + '\n')

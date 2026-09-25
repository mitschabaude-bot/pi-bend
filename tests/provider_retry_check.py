"""Compare retry-loop effect traces to upstream with only sleep replaced."""
from upstream_pin import check_sibling
check_sibling()
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
if '--no-build' not in sys.argv:
    subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--stats',
                    'build/provider-retry-build.json', '--', 'sh', 'scripts/build-pure.sh',
                    'packages/ai/test/provider-retry.bend', 'build/provider-retry'], cwd=root, check=True)
expected = json.loads(subprocess.check_output(
    ['node', '--disable-warning=ExperimentalWarning', 'tests/provider_retry_reference.mts'], cwd=root, text=True))
for threads in (1, 4):
    for mode, trace in enumerate(expected):
        result = subprocess.run([str(root/'build/provider-retry'), '--threads', str(threads), str(mode)],
                                cwd=root, capture_output=True, text=True, check=True, timeout=20)
        assert result.stdout == trace, (threads, mode, result.stdout, trace)
        assert not result.stderr, result.stderr
    print(f'{threads} threads: {len(expected)} retry-loop traces PASS')

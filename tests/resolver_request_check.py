"""Resolver request policy vs an independent model of documented glibc flags.

No network and no libc state manipulation. Every supported feature subset is
checked, including preservation of settings consumed by other resolver layers.
"""
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess

ROOT = Path(__file__).resolve().parents[1]
bun = Path.home() / '.bun/bin/bun'
compiler = TOOLCHAIN
for suffix in ('c', 'js'):
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8',
                    '--stats', f'build/resolver-request-{suffix}-build.json', '--',
                    str(bun), str(compiler / 'main.ts'), 'tests/resolver-request.bend',
                    '-o', f'build/resolver-request.{suffix}'], cwd=ROOT, check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                'build/resolver-request.c', '-lpthread', '-lm', '-o',
                'build/resolver-request'], cwd=ROOT, check=True)
features = ['rotate', 'edns0', 'single-request-reopen', 'single-request',
            'no-tld-query', 'no-reload', 'use-vc', 'trust-ad', 'no-aaaa']
cases = []
for bits in itertools.product((0, 1), repeat=len(features)):
    enabled = [name for name, bit in zip(features, bits) if bit]
    for numbers in [(1, 5, 2), (15, 30, 5)]:
        tokens = ' '.join([f'{k}:{v}' for k, v in zip(['ndots', 'timeout', 'attempts'], numbers)] + enabled + enabled)
        want = [','.join(map(str, (*numbers, *bits))),
                str(288 if bits[7] else 256) + (':1200,0:empty' if bits[1] else ':none')]
        cases.append((tokens, want))
for text, diagnostics in [
    ('edns0 timeout:7junk trust-ad', ['malformed:timeout:7junk']),
    ('trust-ad ndots:-1 edns0', ['malformed:ndots:-1']),
    ('attempts: rotate-junk', ['malformed:attempts:', 'unknown:rotate-junk']),
    ('unknown edns0-extra', ['unknown:unknown', 'unknown:edns0-extra']),
]:
    cases.append((text, ['FAIL', *diagnostics, 'END']))
results = []
for label, command in [('native 1', ['build/resolver-request', '--threads', '1']),
                       ('native 4', ['build/resolver-request', '--threads', '4']),
                       ('Bun', [str(bun), 'build/resolver-request.js'])]:
    for start in range(0, len(cases), 64):
        batch = cases[start:start + 64]
        run = subprocess.run([*command, *(text for text, _ in batch)], cwd=ROOT,
                             capture_output=True, text=True, timeout=30, check=True)
        assert not run.stderr, run.stderr
        expected = [line for _, lines in batch for line in lines]
        assert run.stdout.splitlines() == expected, (label, start, run.stdout, expected)
    results.append({'backend': label, 'cases': len(cases)})
    print(f'PASS resolver request: {len(cases)} cases on {label}', flush=True)
paths = ['packages/runtime/src/resolver-config.bend', 'packages/runtime/src/resolver-config.bend',
         'tests/resolver-request.bend', 'tests/resolver_request_check.py', 'tests/resolver-options.bend',
         'build/resolver-request', 'build/resolver-request.js']
record = {'scope': __doc__, 'results': results,
          'sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in paths},
          'builds': {suffix: json.loads((ROOT / f'build/resolver-request-{suffix}-build.json').read_text()) for suffix in ('c', 'js')}}
(ROOT / 'build/resolver-request-result.json').write_text(json.dumps(record, indent=2) + '\n')

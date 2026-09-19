"""Portable reset errno classification and unchanged unrelated code emission."""
import errno
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
candidate, baseline = [Path(value).resolve() for value in sys.argv[1:3]]
bun = str(Path.home() / '.bun/bin/bun')
launcher = ROOT / 'build/socket-reset-compiler'
launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(bun) + ' ' + shlex.quote(str(candidate / 'main.ts')) + ' "$@"\n')
launcher.chmod(0o755)
binary = ROOT / 'build/socket-reset-classifier'
subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/socket-reset-classifier.bend', str(binary)], cwd=ROOT, env=dict(os.environ, BEND=str(launcher)), check=True)
javascript = binary.with_suffix('.js')
subprocess.run([str(launcher), 'tests/socket-reset-classifier.bend', '-o', str(javascript)], cwd=ROOT, check=True)
codes = [*range(512), 65535, 4294967295]
expected = [f'{code}:' + ('reset' if code == errno.ECONNRESET else 'other') for code in codes]
for label, command in [('native 1', [str(binary), '--threads', '1']), ('native 4', [str(binary), '--threads', '4']), ('Bun', [bun, str(javascript)])]:
    result = subprocess.run([*command, 'c' + ','.join(map(str, codes))], cwd=ROOT, text=True, capture_output=True, timeout=15)
    assert result.returncode == 0 and result.stdout.splitlines() == expected, (label, result.stdout, result.stderr)
    print(label + ': 514 errno classifications PASS', flush=True)
for extension in ['c', 'js']:
    outputs = []
    for name, compiler in [('baseline', baseline), ('candidate', candidate)]:
        output = ROOT / f'build/reset-{name}.{extension}'
        subprocess.run([bun, str(compiler / 'main.ts'), 'tests/tcp-bytes-probe.bend', '-o', str(output)], cwd=ROOT, check=True)
        outputs.append(output.read_bytes())
    assert outputs[0] == outputs[1], extension
    print('Unrelated TCP fixture: identical ' + extension.upper() + ' emission PASS', flush=True)

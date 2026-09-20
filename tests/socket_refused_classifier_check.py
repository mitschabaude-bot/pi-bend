"""Portable refused errno classification and unchanged unrelated code emission."""
import errno
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
candidate, baseline = [Path(value).resolve() for value in sys.argv[1:3]]
bun = str(Path.home() / '.bun/bin/bun')
launcher = ROOT / 'build/socket-refused-compiler'
launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(bun) + ' ' + shlex.quote(str(candidate / 'main.ts')) + ' "$@"\n')
launcher.chmod(0o755)
binary = ROOT / 'build/socket-refused-classifier'
subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/socket-refused-classifier.bend', str(binary)], cwd=ROOT, env=dict(os.environ, BEND=str(launcher)), check=True)
javascript = binary.with_suffix('.js')
subprocess.run([str(launcher), 'tests/socket-refused-classifier.bend', '-o', str(javascript)], cwd=ROOT, check=True)
codes = [*range(512), 65535, 4294967295]
expected = [f'{code}:' + ('refused' if code == errno.ECONNREFUSED else 'other') for code in codes]
for label, command in [('native 1', [str(binary), '--threads', '1']), ('native 4', [str(binary), '--threads', '4']), ('Bun', [bun, str(javascript)])]:
    result = subprocess.run([*command, 'c' + ','.join(map(str, codes))], cwd=ROOT, text=True, capture_output=True, timeout=15)
    assert result.returncode == 0 and result.stdout.splitlines() == expected, (label, result.stdout, result.stderr)
    print(label + ': 514 errno classifications PASS', flush=True)
for extension in ['c', 'js']:
    outputs = []
    for name, compiler in [('baseline', baseline), ('candidate', candidate)]:
        output = ROOT / f'build/refused-{name}.{extension}'
        subprocess.run([bun, str(compiler / 'main.ts'), 'tests/tcp-bytes-probe.bend', '-o', str(output)], cwd=ROOT, check=True)
        outputs.append(output.read_bytes())
    assert outputs[0] == outputs[1], extension
    print('Unrelated TCP fixture: identical ' + extension.upper() + ' emission PASS', flush=True)

import hashlib,json
paths=['tests/socket-refused-classifier.bend','tests/socket_refused_classifier_check.py','patches/experimental/socket-refused/base.bend','patches/experimental/socket-refused/socket_is_connection_refused.c','patches/experimental/socket-refused/socket_is_connection_refused.js']
(ROOT/'build/socket-refused-result.json').write_text(json.dumps(dict(codes=codes,backends=['native 1','native 4','Bun'],expected=expected,unchanged_emission=['C','JS'],sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}),indent=2)+'\n')

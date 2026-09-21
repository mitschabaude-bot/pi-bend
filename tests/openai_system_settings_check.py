"""Real provider system-file loading, strict decoding, ordering and descriptor closure."""
import argparse
import ast
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'build/openai-system-settings'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--backends', nargs='+', choices=['native-1', 'native-4', 'bun'], default=['native-1', 'native-4', 'bun'])
p.add_argument('--prepare-audit', action='store_true')
a = p.parse_args()
if a.prepare_audit:
    tree = ast.parse((ROOT / 'tests/resolver_file_check.py').read_text())
    audit = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'audit' for t in n.targets))
    if Path(str(BASE) + '.c').exists():
        Path(str(BASE) + '-audit.c').write_text(Path(str(BASE) + '.c').read_text() + audit)
    js_audit = """import {readdirSync as auditList,readlinkSync as auditLink} from 'node:fs';
process.on('exit',()=>{let live=0;const root=process.env.PI_BEND_FILE_TEST_ROOT;
for(const fd of auditList('/proc/self/fd')) {try {const target=auditLink('/proc/self/fd/'+fd);if(target===root||target.startsWith(root+'/'))live++;}catch{}}
console.error('FILES '+live);});
"""
    Path(str(BASE) + '-audit.js').write_text(js_audit + Path(str(BASE) + '.js').read_text())
    raise SystemExit(0)

commands = {'native-1': [str(BASE) + '-audit', '--threads', '1'], 'native-4': [str(BASE) + '-audit', '--threads', '4'], 'bun': [str(Path.home() / '.bun/bin/bun'), str(BASE) + '-audit.js']}
runs = []
with tempfile.TemporaryDirectory(prefix='pi-bend-system-settings-') as temp:
    root = Path(temp)
    files = {
        'resolver': b'nameserver 127.0.0.1\nsearch fixture.invalid\noptions ndots:2 timeout:1 attempts:1\n',
        'hosts': b'127.0.0.1 unit alias\n',
        'empty': b'',
        'bad-hosts': b'not-an-address unit\n',
        'bad-utf8': b'\xff',
        'bad-options': b'nameserver 127.0.0.1\noptions ndots:bad\n',
        'large-hosts': b'127.0.0.1 unit\n' * 20,
    }
    for name, data in files.items():
        (root / name).write_bytes(data)
    # Opening this path would block. Resolver failures must return before the
    # hosts loader is invoked, giving a concrete sensitivity check for ordering.
    os.mkfifo(root / 'unopened-hosts')
    normal = ['source:available', 'settings:2:1:1:1:4321:4096']
    cases = [
        ('valid', 'resolver', 'hosts', 4096, normal + ['hosts:rows:1'], ''),
        ('empty-hosts', 'resolver', 'empty', 4096, normal + ['hosts:rows:0'], ''),
        ('missing-hosts', 'resolver', 'missing', 4096, normal + [f'hosts:open:{errno.ENOENT}'], ''),
        ('bad-hosts', 'resolver', 'bad-hosts', 4096, normal + ['hosts:parse'], ''),
        ('bad-hosts-utf8', 'resolver', 'bad-utf8', 4096, normal + ['hosts:decode'], ''),
        ('bad-resolver-utf8', 'bad-utf8', 'unopened-hosts', 4096, ['resolver:decode'], ''),
        ('bad-options', 'bad-options', 'unopened-hosts', 4096, ['resolver:options'], ''),
        ('resolver-limit', 'resolver', 'unopened-hosts', len(files['resolver']) - 1, ['resolver:large'], ''),
        ('exact-resolver-limit', 'resolver', 'hosts', len(files['resolver']), normal + ['hosts:rows:1'], ''),
        ('hosts-limit', 'resolver', 'large-hosts', len(files['large-hosts']) - 1, normal + ['hosts:large'], ''),
        ('exact-hosts-limit', 'resolver', 'large-hosts', len(files['large-hosts']), normal + ['hosts:rows:20'], ''),
        ('environment-options', 'resolver', 'hosts', 4096, ['source:available', 'settings:4:1:2:1:4321:4096', 'hosts:rows:1'], 'ndots:4 attempts:2'),
        ('missing-resolver-default', 'missing', 'hosts', 4096, ['source:unavailable', 'settings:1:5:2:1:4321:4096', 'hosts:rows:1'], ''),
    ]
    for backend in a.backends:
        for chunk in [1, 7, 4096]:
            for name, resolver, hosts, limit, expected, options in cases:
                env = dict(os.environ, LOCALDOMAIN='', RES_OPTIONS=options, PI_BEND_FILE_TEST_ROOT=str(root))
                result = subprocess.run(commands[backend] + [str(root / resolver), str(root / hosts), str(chunk), str(limit)], cwd=ROOT, env=env, capture_output=True, text=True, timeout=12)
                assert result.returncode == 0 and result.stdout.splitlines() == expected and result.stderr == 'FILES 0\n', (backend, name, chunk, result, expected)
                runs.append({'backend': backend, 'case': name, 'chunk': chunk, 'trace': expected, 'files_live': 0})
        print(backend, len(cases) * 3, 'system-loading cases PASS', flush=True)

pending = [ROOT / 'tests/openai-system-settings.bend']
seen = {Path(__file__).resolve(), ROOT / 'tests/resolver_file_check.py'}
while pending:
    path = pending.pop().resolve()
    if path in seen:
        continue
    seen.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
programs = [Path(str(BASE) + suffix) for suffix in ['-audit', '-audit.c', '-audit.js', '.c', '.js']]
record = {'scope': __doc__, 'runs': runs, 'fixture_bytes': {name: data.hex() for name, data in files.items()}, 'sources': {str(path): digest(path) for path in sorted(seen)}, 'program_sha256': {str(path): digest(path) for path in programs if path.exists()}}
Path(str(BASE) + '-' + ','.join(a.backends) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')

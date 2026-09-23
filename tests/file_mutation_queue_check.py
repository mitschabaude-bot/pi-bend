"""Pi file-mutation queue contracts, using channel gates instead of sleeps.

The edit/write integration cases remain pending until those tools are ported.
"""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/file-mutation-queue'

vectors = [(base, path) for base in ['/', '/a/b', '/a//b/../c']
           for path in ['', '.', '..', '../../..', 'x/../y/', '/x//z/..',
                        'é/漢/😀', './a//b/../../c', '/../../../']]
reference = subprocess.check_output(
    ['node', '-e', 'const p=require("node:path").posix; '
     'console.log(JSON.stringify(JSON.parse(process.argv[1]).map(([b,v])=>p.resolve(b,v))))',
     json.dumps(vectors)], text=True)

for backend, command in [('bun', ['bun', str(PREFIX) + '.js']),
                         ('native-1', [str(PREFIX), '--threads', '1']),
                         ('native-4', [str(PREFIX), '--threads', '4'])]:
    with tempfile.TemporaryDirectory(prefix='bend-mutation-') as directory:
        root = Path(directory)
        (root / 'target').write_text('unchanged')
        (root / 'alias').symlink_to('target')
        (root / 'loop').symlink_to('loop')

        def run(*args):
            result = subprocess.run(command + list(map(str, args)), cwd=root,
                                    capture_output=True, text=True, timeout=20)
            assert result.returncode == 0 and not result.stderr, (backend, args, result)
            return result.stdout.strip()

        cases = [
            ('serializes operations for the same file', 'serial', 'target', 'target'),
            ('allows different files to proceed in parallel', 'parallel', 'target', 'other'),
            ('uses the same queue for symlink aliases', 'serial', 'target', 'alias'),
            ('normalizes relative aliases', 'serial', './target', root / 'target'),
            ('serializes missing paths', 'serial', 'missing/child', './missing/child'),
            ('falls back on ENOTDIR', 'serial', 'target/child', './target/child'),
        ]
        for name, mode, first, second in cases:
            for _ in range(4):
                assert run('pair', mode, first, second) == 'ok', name
            print(f'{backend}: {name} PASS', flush=True)
        assert run('recovery', 'loop', 'target') == 'ok'
        assert (root / 'target').read_text() == 'unchanged'
        for (base, path), expected in zip(vectors, json.loads(reference)):
            assert run('path', base, path) == expected, (base, path, expected)
        assert run('path', 'relative', 'child') == 'invalid base'
        assert run('path', 'relative', '/absolute') == '/absolute'
        print(f'{backend}: registration recovery, operation failure, reuse and POSIX paths PASS', flush=True)

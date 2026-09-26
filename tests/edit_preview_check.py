"""Read-only edit preflight matches pinned pi's diff and error contracts."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
from upstream_pin import UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--runner', default='build/edit-preview.js')
p.add_argument('--threads', default='1')
args = p.parse_args()
runner = (ROOT / args.runner).resolve()
command = ['bun', str(runner)] if runner.suffix == '.js' else [str(runner), '--threads', args.threads, '--']
large = [f'line {i}' for i in range(1000)]
edits = [( '\n'.join(large[n-1:n+2]), '\n'.join([large[n-1], large[n] + ' changed', large[n+1]])) for n in range(50, 1000, 100)]
cases = [
    ('large preview', ('\n'.join(large) + '\n').encode(), edits),
    ('CRLF', b'one\r\ntwo\r\n', [('two', 'TWO')]),
    ('BOM', b'\xef\xbb\xbfone\r\ntwo\r\n', [('two', 'TWO')]),
    ('immutable snapshot', b'foo\nbar\n', [('foo\n', 'foo bar\n'), ('bar\n', 'BAR\n')]),
    ('not found', b'hello', [('missing', 'replacement')]),
    ('duplicate', b'foo foo', [('foo', 'bar')]),
    ('overlap', b'one\ntwo\nthree\n', [('one\ntwo', 'a'), ('two\nthree', 'b')]),
    ('no change', b'hello', [('hello', 'hello')]),
    ('empty needle', b'hello', [('', 'replacement')]),
    ('missing file', None, [('old', 'new')]),
]
with tempfile.TemporaryDirectory(prefix='pi-edit-preview-') as place:
    work = Path(place)
    driver = work / 'reference.ts'
    driver.write_text('import { computeEditsDiff } from ' + json.dumps(str(UPSTREAM / 'packages/coding-agent/src/core/tools/edit-diff.ts')) + ';\nconst [path, cwd, ...pairs] = process.argv.slice(2);\nconst edits=[]; for(let i=0;i<pairs.length;i+=2) edits.push({oldText:pairs[i],newText:pairs[i+1]});\nconsole.log(JSON.stringify(await computeEditsDiff(path,edits,cwd)));\n')
    for name, content, replacements in cases:
        file = work / 'input.txt'
        if file.exists():
            file.unlink()
        if content is not None:
            file.write_bytes(content)
        pairs = [value for edit in replacements for value in edit]
        expected = json.loads(subprocess.check_output(['bun', str(driver), 'input.txt', place, *pairs], text=True))
        actual = json.loads(subprocess.check_output(command + [place, place, 'input.txt', *pairs], text=True, timeout=60))
        # Upstream omits an absent firstChangedLine; Bend represents it explicitly.
        if 'diff' in expected:
            expected.setdefault('firstChangedLine', None)
        assert actual == expected, (name, expected, actual)
        assert file.exists() == (content is not None), name
        if content is not None:
            assert file.read_bytes() == content, name
        print(f'{name}: matching read-only preflight')
    file.write_bytes(b'\xff')
    rejected = json.loads(subprocess.check_output(command + [place, place, str(file), 'old', 'new'], text=True, timeout=60))
    assert rejected == {'error': 'File contains invalid UTF-8'}, rejected
    assert file.read_bytes() == b'\xff'
    print('invalid UTF-8: rejected without modifying the file')

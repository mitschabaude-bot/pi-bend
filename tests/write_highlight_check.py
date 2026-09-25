"""Streamed write previews (incremental highlight cache) against upstream renderCall."""
import os, random, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
command = sys.argv[1:] or ['bun', 'build/write-highlight.js']
env = dict(os.environ); env.pop('NO_COLOR', None); env.update(FORCE_COLOR='1', TERM='xterm-256color')
r = random.Random(3417)
TS = ['const a = 1;', 'let s = "text";', '/* block', 'comment inside', 'end */ const b = 2;', 'function f(x: number) {', '  return x * 2;', '}', '`template ${a}', 'more template`', '// line comment', 'interface P { x: number }', '\tindented\twith tabs', '']
PY = ['def f(x):', '    return x', '"""doc', 'still doc', '"""', 'x = [1, 2]', '# comment', "s = 'q'", 'class A:', '    pass', '']
def stream(content):
    steps, i = [], 0
    while i < len(content):
        i = min(len(content), i + r.choice([1, 3, 17, 40, 200]))
        steps += ['partial', content[:i]]
    return steps + ['complete', content]
cases = []
for path, pool in [('src/a.ts', TS), ('tool.py', PY), ('notes.txt', TS)]:
    for n in [5, 49, 50, 51, 70, 120]:
        lines = [r.choice(pool) for _ in range(n)]
        cases.append((path, stream('\r\n'.join(lines) if n == 51 else '\n'.join(lines))))
# Rewritten (non-prefix) content and a changed path rebuild the cache.
cases.append(('src/b.ts', ['partial', 'const a = 1;\n/* x', 'partial', 'let other = 2;\n', 'complete', 'let other = 2;\nconst z = 3;']))
count = 0
for path, steps in cases:
    want = subprocess.run(['bun', 'tests/write_highlight_reference.ts', path, *steps], cwd=ROOT, env=env, capture_output=True, text=True, check=True).stdout
    got = subprocess.run(command + [path, *steps], cwd=ROOT, env=env, capture_output=True, text=True, check=True).stdout
    for i, (g, w) in enumerate(zip(got.split('\x1e\n'), want.split('\x1e\n'))):
        assert g == w, (path, i, steps[2 * i: 2 * i + 2], g, w)
    assert got.count('\x1e') == want.count('\x1e') == len(steps) // 2
    count += len(steps) // 2
print(f'{len(cases)} streamed writes, {count} previews match upstream')

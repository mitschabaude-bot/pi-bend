"""Compare tool-output truncation with the pinned Pi implementation.

TypeScript is a test oracle only. The Bend implementation owns all production
behavior. Whole-character grep cuts intentionally avoid isolated surrogates.
"""
from upstream_pin import UPSTREAM
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = UPSTREAM / 'packages/coding-agent/src/core/tools/truncate.ts'
PREFIX = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/tool-truncate').resolve()
cases = []
texts = ['', '\n', '\n\n', 'a', 'a\n', 'a\nb', 'a\nb\n', '\r\n',
         'é漢😀\nsecond\n', '\ufeffprefix\n\ufefftail', 'abc\x00def',
         '\nlong last line', '😀😀😀']
for text in texts:
    for lines in [0, 1, 2, 8, None]:
        for size in [0, 1, 3, 4, 10, None]:
            for mode in ['h', 't']:
                cases.append([mode, text, lines, size])
rng = random.Random(9471)
for _ in range(160):
    text = ''.join(rng.choice('abc\n\r\té漢😀\ufeff') for _ in range(rng.randrange(90)))
    for mode in ['h', 't']:
        cases.append([mode, text, rng.randrange(12), rng.randrange(100)])
for text in ['abc', '', 'é漢😀x', '😀😀', 'a' * 501]:
    for count in [0, 1, 2, 3, 4, 5, 500, None]:
        cases.append(['l', text, count])
for size in [0, 1, 1023, 1024, 1075, 1536, 1048575, 1048576]:
    cases.append(['s', size])
for mode in ['h', 't']:
    cases.extend([[mode, 'a\n' * 2001, None, None],
                  [mode, '\x00' * 51201, None, None]])

oracle = r'''
const T = await import(process.argv[1]);
const cases = JSON.parse(await Bun.stdin.text());
const scalars = s => [...s].map(c => c.codePointAt(0)).join(',');
const out = cases.map(([mode,text,lines,bytes]) => {
  if (mode === 's') return T.formatSize(text);
  if (mode === 'l') {
    const r = T.truncateLine(text, lines ?? undefined);
    // Accepted native string policy: retain complete characters. The byte and
    // line truncators are compared without any expected-output adaptation.
    if (r.wasTruncated) r.text = r.text.replace(/[\uD800-\uDBFF](?=\.\.\. \[truncated\]$)/, '');
    return scalars(r.text) + '|' + Number(r.wasTruncated);
  }
  const r = (mode === 'h' ? T.truncateHead : T.truncateTail)(text,
    {maxLines:lines ?? undefined,maxBytes:bytes ?? undefined});
  return [scalars(r.content),Number(r.truncated),r.truncatedBy ?? 'none',
    r.totalLines,r.totalBytes,r.outputLines,r.outputBytes,
    Number(r.lastLinePartial),Number(r.firstLineExceedsLimit),r.maxLines,r.maxBytes].join('|');
});
console.log(JSON.stringify(out));
'''
expected = json.loads(subprocess.check_output(
    ['bun', '--eval', oracle, str(UPSTREAM)], input=json.dumps(cases), text=True))

def encoded(case):
    mode, text, *options = case
    if mode == 's':
        return f's:{text}'
    numbers = ','.join(str(ord(c)) for c in text)
    limits = ':'.join('' if x is None else str(x) for x in options)
    return f'{mode}:{limits}:{numbers}'

for name, command in [('bun', ['bun', str(PREFIX) + '.js']),
                      ('native-1', [str(PREFIX), '--threads', '1']),
                      ('native-4', [str(PREFIX), '--threads', '4'])]:
    actual = []
    batch = []
    size = 0
    for arg in [encoded(c) for c in cases] + [None]:
        if batch and (arg is None or size + len(arg) > 90000):
            run = subprocess.run(command + batch, capture_output=True, text=True, timeout=120)
            assert run.returncode == 0, (name, run.returncode, run.stderr, len(actual), len(run.stdout.splitlines()))
            assert not run.stderr, (name, run.stderr)
            actual.extend(run.stdout.splitlines())
            batch, size = [], 0
        if arg is not None:
            batch.append(arg)
            size += len(arg)
    assert len(actual) == len(expected), (name, len(actual), len(expected))
    for index, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, (name, index, cases[index], got, want)
    print(f'{name}: {len(cases)} tool truncation comparisons PASS', flush=True)

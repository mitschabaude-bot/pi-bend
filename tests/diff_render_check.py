"""Pinned numbered-line parsing, grouping, whitespace and word-level ANSI rendering."""
from pathlib import Path
import itertools
import random
import subprocess
ROOT = Path(__file__).resolve().parents[1]
cases = ['', '--- file', '+++ file', 'not a diff', '-bad', '+bad', '-123bad', '- 1', '- ', '+ ', ' ', '     ...', ' 12 text', '\t12 text', '-\t12\ttext', ' 12 text\r', ' 12 text\u2028end', ' 12 text\u2029end']
for removed, added in itertools.product(range(4), repeat=2):
    cases.append('\n'.join(['  1 before'] + [f'- {i+2} old {i}\tvalue' for i in range(removed)] + [f'+ {i+2} new {i}\tvalue' for i in range(added)] + [' 99 after']))
# A single modified token has identical styling, with line numbers outside it.
cases += ['- 1 old\n+ 42 new', '- 1 same old end\n+ 2 same new end', '- 1 old\n+ 1 new\n- 2 old\n+ 2 new']
spaces = [' ', '\t', '\u00a0', '\u2002', '\u2028', '\u2029']
for prefix, gap in itertools.product(['-', '+', ' ', '\t', 'X'], spaces):
    cases += [prefix + gap + '12' + gap + 'text', prefix + gap + 'text', prefix + gap]
rng = random.Random(2531)
old_choices = ["same text", "é 日本", "x\ty"]
for _ in range(160):
    removed, added = rng.randrange(5), rng.randrange(5)
    cases.append('\n'.join([f'- {i} {rng.choice(old_choices)}' for i in range(removed)] + [f'+ {i} {rng.choice(["new text", "😀", "a b"])}' for i in range(added)]))
# Multiple separated edits, punctuation, indentation and whitespace-only edits.
pairs = [
    ('const a = 1; const b = 2;', 'const a = 3; const b = 4;'),
    ('lines.push(chalk.gray("  No user messages found"));', 'lines.push(theme.fg("muted", "  No user messages found"));'),
    ('a  b c', 'a b  d'), ('same same left same', 'same right same same'),
    ('foo bar baz', 'foo baz'), ('foo\nbar baz', 'foo baz'),
    ('foo baz', 'foo\nbar baz'), ('foo   bar baz', 'foo  baz'),
]
for gap in ['\u00a0', '\u1680', '\u2002', '\u202f', '\u205f', '\u3000', '\ufeff']:
    pairs += [(f'alpha{gap}beta{gap}gamma', f'alpha{gap}gamma'),
              (f'alpha{gap}beta', 'alpha gamma'), (gap + 'alpha', gap + 'beta')]
pairs += list(itertools.product(['', ' ', '  ', 'alpha', 'alpha beta', 'beta alpha', 'alpha(beta)', 'é', '日本語', '😀'], repeat=2))
parts = ['alpha', 'beta', '_x', '(', ')', '.', ';', '=', ' ', '  ', '\t', 'é', '日本', '😀']
for _ in range(300):
    pairs.append((''.join(rng.choices(parts, k=rng.randrange(12))), ''.join(rng.choices(parts, k=rng.randrange(12)))))
# Embedded line terminators are tested as standalone parser inputs above.
cases += ['- 12 ' + old + '\n+ 42 ' + newer for old,newer in pairs if '\n' not in old + newer]
args = [','.join(str(ord(char)) for char in text) for text in cases]
for start in range(0, len(args), 40):
    batch = args[start:start+40]
    expected = subprocess.check_output(['bun', 'tests/diff_render_reference.ts', *batch], cwd=ROOT, text=True).splitlines()
    for threads in ['1','4']:
        got = subprocess.check_output(['build/diff-render', '--threads', threads, '--', *batch], cwd=ROOT, text=True).splitlines()
        assert len(got) == len(expected)
        assert got == expected, [(start+i, cases[start+i], want, actual) for i,(want,actual) in enumerate(zip(expected,got)) if want != actual][:2]
print(f'native one/four: {len(cases)} numbered/grouped diff renders match pi')

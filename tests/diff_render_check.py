"""Pinned numbered-line parsing and edit-block grouping; word styling is partial."""
from pathlib import Path
import itertools
import random
import subprocess
ROOT = Path(__file__).resolve().parents[1]
cases = ['', '--- file', '+++ file', 'not a diff', '-bad', '+bad', '-123bad', '- 1', '- ', '+ ', ' ', '     ...', ' 12 text', '\t12 text', '-\t12\ttext', ' 12 text\r', ' 12 text\u2028end', ' 12 text\u2029end']
for removed, added in itertools.product(range(4), repeat=2):
    if removed == added == 1: continue  # Multiple changed spans/policy remain pending.
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
    if removed == added == 1: added = 2
    cases.append('\n'.join([f'- {i} {rng.choice(old_choices)}' for i in range(removed)] + [f'+ {i} {rng.choice(["new text", "😀", "a b"])}' for i in range(added)]))
args = [','.join(str(ord(char)) for char in text) for text in cases]
for start in range(0, len(args), 40):
    batch = args[start:start+40]
    expected = subprocess.check_output(['bun', 'tests/diff_render_reference.ts', *batch], cwd=ROOT, text=True).splitlines()
    for threads in ['1','4']:
        got = subprocess.check_output(['build/diff-render', '--threads', threads, '--', *batch], cwd=ROOT, text=True).splitlines()
        assert len(got) == len(expected)
        assert got == expected, [(start+i, cases[start+i], want, actual) for i,(want,actual) in enumerate(zip(expected,got)) if want != actual][:2]
print(f'native one/four: {len(cases)} numbered/grouped diff renders match pi')

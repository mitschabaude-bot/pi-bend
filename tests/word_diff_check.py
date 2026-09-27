"""Default jsdiff word-token matching, independently of rendered whitespace."""
from pathlib import Path
import itertools
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
encode = lambda text: ','.join(str(ord(char)) for char in text)
pairs = list(itertools.product(['', ' ', '\t\n', 'alpha', 'alpha beta', 'alpha  beta', 'beta alpha', 'alpha(beta)', '日本語', 'e\u0301', 'é'], repeat=2))
# Exercise every edge of jsdiff's extended Latin ranges and whitespace set.
boundaries = [0, 8, 9, 13, 14, 32, 48, 57, 65, 90, 95, 97, 122, 160, 173,
              191, 192, 214, 215, 216, 246, 247, 248, 710, 711, 712, 727, 728,
              733, 734, 767, 768, 5760, 7680, 7935, 7936, 8192, 8202, 8203,
              8232, 8233, 8239, 8287, 12288, 65279, 128512]
for code in boundaries:
    char = chr(code)
    pairs.extend([(f'a{char}b', 'a b'), (f'a{char}b', f'b{char}a'), (char, '')])
pairs += [
    ('const a = 1; const b = 2;', 'const a = 3; const b = 4;'),
    ('lines.push(chalk.gray("  No user messages found"));', 'lines.push(theme.fg("muted", "  No user messages found"));'),
    ('a  b c', 'a b  d'), ('same same left same', 'same right same same'),
]
rng = random.Random(932)
parts = ['alpha', 'beta', 'one', 'two', '_x', '(', ')', '.', ';', '=', ' ', '  ', '\t', '\n', 'é', '日本', '😀']
for _ in range(600):
    pairs.append((''.join(rng.choices(parts, k=rng.randrange(12))), ''.join(rng.choices(parts, k=rng.randrange(12)))))
args = [encode(old) + '/' + encode(newer) for old, newer in pairs]
word_count = len(pairs)
line_pairs = list(itertools.product(['', '\n', 'a', 'a\n', 'a\r\n', 'a\nb\n', 'b\na\n', 'a\na\n'], repeat=2))
for _ in range(200):
    line_pairs.append((''.join(rng.choices(['a\n', 'b\n', '\n', 'c\r\n'], k=rng.randrange(12))), ''.join(rng.choices(['a\n', 'b\n', '\n', 'c\r\n'], k=rng.randrange(12)))))
pairs.extend(line_pairs)
args.extend('line/' + encode(old) + '/' + encode(newer) for old, newer in line_pairs)
for start in range(0, len(args), 50):
    batch = args[start:start + 50]
    expected = subprocess.check_output(['bun', 'tests/word_diff_reference.ts', *batch], cwd=ROOT, text=True).splitlines()
    for threads in ['1', '4']:
        actual = subprocess.check_output(['build/word-diff', '--threads', threads, '--', *batch], cwd=ROOT, text=True).splitlines()
        assert len(actual) == len(expected), (threads, start, len(actual), len(expected))
        assert actual == expected, [(start+i, pairs[start+i], want, got) for i, (want, got) in enumerate(zip(expected, actual)) if want != got][:3]
print(f'native one/four: {word_count} word-token and {len(line_pairs)} line-token edit scripts match jsdiff')

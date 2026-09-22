"""Independent dynamic-programming oracle for the native-agent glob feature."""
import argparse
import itertools
import random
import subprocess


def compile_reference(pattern):
    tokens = []
    pos = 0
    def character():
        nonlocal pos
        if pos == len(pattern):
            raise ValueError('unfinished pattern')
        value = pattern[pos]
        pos += 1
        if value == '\\':
            if pos == len(pattern):
                raise ValueError('dangling escape')
            value = pattern[pos]
            pos += 1
        return value
    while pos < len(pattern):
        value = pattern[pos]
        pos += 1
        if value == '\\':
            if pos == len(pattern):
                raise ValueError('dangling escape')
            tokens.append(('literal', pattern[pos]))
            pos += 1
        elif value in '*?':
            tokens.append((value, None))
        elif value == '[':
            negative = pos < len(pattern) and pattern[pos] == '!'
            pos += negative
            ranges = []
            while pos < len(pattern) and pattern[pos] != ']':
                first = character()
                last = first
                if pos < len(pattern) and pattern[pos] == '-' and pos + 1 < len(pattern) and pattern[pos + 1] != ']':
                    pos += 1
                    last = character()
                    if ord(first) > ord(last):
                        raise ValueError('reversed range')
                ranges.append((first, last))
            if pos == len(pattern) or not ranges:
                raise ValueError('unfinished or empty set')
            pos += 1
            tokens.append(('set', (negative, ranges)))
        else:
            tokens.append(('literal', value))
    return tokens


def reference(pattern, text):
    try:
        tokens = compile_reference(pattern)
    except ValueError:
        return 'error'
    row = [True]
    for kind, value in tokens:
        row.append(kind == '*' and row[-1])
    for char in text:
        next_row = [False]
        for i, (kind, value) in enumerate(tokens, 1):
            if kind == '*':
                matched = next_row[-1] or row[i]
            else:
                accepts = kind == '?' or (kind == 'literal' and value == char)
                if kind == 'set':
                    negative, ranges = value
                    accepts = any(first <= char <= last for first, last in ranges) != negative
                matched = row[i - 1] and accepts
            next_row.append(matched)
        row = next_row
    return str(row[-1]).lower()


def cases():
    atoms = ['a', 'b', '*', '?', '[ab]', '[!a]', '[a-c]', '\\*', 'é', '🐍']
    texts = [''] + [''.join(x) for n in range(1, 4) for x in itertools.product('ab*', repeat=n)]
    for count in range(3):
        for pieces in itertools.product(atoms, repeat=count):
            for text in texts:
                yield ''.join(pieces), text
    invalid = ['\\', '[', '[]', '[!]', '[a', '[a\\', '[z-a]', '[a--c]', '[!z-a]']
    for pattern in invalid:
        for text in ['', 'a', 'z', '🐍']:
            yield pattern, text
    rng = random.Random(5208)
    for _ in range(3000):
        pattern = ''.join(rng.choices(atoms + ['/', '.', '[\\]a]', '[-a]', '[a-]', '[!é-ê]'], k=rng.randrange(9)))
        text = ''.join(rng.choices('abc*?éê🐍/.]-', k=rng.randrange(18)))
        yield pattern, text
    yield '*a' * 64 + 'b', 'a' * 512
    yield '*a' * 64 + 'b', 'a' * 512 + 'b'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('runner')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    vectors = list(cases())
    command = ['bun', args.runner, '--', '--'] if args.runner.endswith('.js') else [args.runner, '--threads', args.threads, '--']
    for offset in range(0, len(vectors), 100):
        group = vectors[offset:offset + 100]
        result = subprocess.run(command + [x for pair in group for x in pair], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr[:1000])
        expected = [reference(*pair) for pair in group]
        actual = result.stdout.splitlines()
        assert actual == expected, [(pair, want, got) for pair, want, got in zip(group, expected, actual) if want != got][:5]
    # Long inputs exercise stack safety without making the DP oracle quadratic.
    # These expectations follow directly from literal/set/star semantics.
    long_cases = [
        ('a' * 12000, 'a' * 12000, 'true'),
        ('a' * 12000, 'a' * 11999 + 'b', 'false'),
        ('*', 'a' * 30000, 'true'),
        ('[' + 'a' * 12000 + ']', 'a', 'true'),
        ('[' + 'a' * 12000 + ']', 'b', 'false'),
    ]
    for pattern, text, expected in long_cases:
        result = subprocess.run(command + [pattern, text], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and not result.stderr, ('long input', len(pattern), len(text), result.returncode, result.stderr[:1000])
        assert result.stdout.splitlines() == [expected], ('long input', len(pattern), len(text), result.stdout[:200])
    print(f'{len(vectors)} independent glob comparisons and {len(long_cases)} long-input checks passed')

if __name__ == '__main__':
    main()

"""Differential scalar-regex checks; byte-required rejection is reported separately."""
import argparse
import base64
import itertools
import json
from pathlib import Path
import random
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def corpus():
    patterns = [
        '', 'a', 'a*', 'a+', 'a?', 'a{2,4}', '(a|b)*c', '((a?)*)*b', '^a$',
        'a|', '(a|b)c', '[a-z]', '[^a]', '[a&&b]', '[a-z&&[^b]]', '[a-z--b]',
        '[a-z~~b-z]', '[[:alpha:]]', '[]a]', '[--a]', '[a--]', '[a&&]', '[a-b-c]',
        '[a-]', '[-a]', r'[a\x62]', r'\d+', r'\s', r'\w', r'\bword\b',
        '(?i)[^a]', '(?i)[a-z]', '(?i)a', '(?i:a)b', r'(?-u)\w', '(?i-u)[a-z]',
        '(?m)^a$', '(?mR)^a$', '(?s).', '(?x) a #comment\n b', '(?x)[ a ]',
        r'\p{Greek}', r'\p{gc:Lu}', r'\p{Alphabetic}', r'\P{ASCII}', r'\x{1F600}',
        r'\u0041', r'\U00000041', 'a**', 'a++', 'a?+', '(?P<abc>a)', '(?<abc>a)',
        r'(?i-u)[\x61-\x7a]', r'(?-u)\pL', r'\p{lc}', r'\p{Bidi_Mirrored}',
        '(?P<a>a)(?P<a>b)', '(?<😀>a)', '(?i-)a', '(?-)a', r'[a-\d]',
        r'\UFFFFFFFF', r'\x{110000}', '(?x)[ ^a ]', '(?x) a { 2 , 3 }',
        r'\p{gc!=Lu}', r'\p{scx=Greek}', r'\p{Age=6.0}', r'\p{WB=ALetter}',
        r'\p{gcb=Extend}', r'\p{sb=Lower}', r'\b{start}a', r'\b{end}a',
        r'\b{start-half}a', r'\b{end-half}a', r'\<a', r'a\>', r'\B',
        r'\x{000000000000041}', r'(?x)\x{ 4 1 }', r'(?x)\u 0 0 4 1',
        r'(?-u)[^\x00-\x7F&&[:ascii:]]', r'\a', r'\f', r'\v', r'\0',
        r'\1', r'\q', '(', '[', '{2}', 'a{3,1}', '(?=a)', '(?<=a)',
        '(?<1bad>a)', '(?q)a', '(?i-i)a', '[z-a]', 'a{,3}', 'a{1,2,3}',
        r'\p{Not_A_Property}', r'\p{^Lu}', r'\b{unknown}', '\\', '--help', '--pre=x',
    ]
    # Selective Rust verbose-mode token boundaries: escapes and repetitions
    # accept ignored text internally, but escaped text and group flags do not.
    patterns += [
        '(?x)'+p for p in [
            r'\x { 4 1 }', '\\x#prefix\n{4#digit\n1}',
            '\\x4#digit\n1', '\\u0#digit\n0 4 1',
            '\\U0000#digit\n0041', '\\x{#empty\n}', '\\x4#EOF',
            '\\x{4#EOF}', '\\x{4#CR\r1}', '\\x{4#CRLF\r\n1}',
            '\\x{4#unicode line separator\u20281}', r'\x{0000000000041}',
            '\\p#prefix\n{G r e e k}', '\\p{G#part\nreek}',
            '\\p{ g c ! #operator\n = L u }', '\\P #prefix\n L',
            '\\p{#empty\n}', '\\p{Greek#EOF}',
            '\\b{s#part\ntart}a', '\\b{start-#part\nhalf}a',
            '\\b{#prefix\nend}', '\\b #gap\n{start}',
            '\\b{ #prefix\n2 }a', r'\b{2}a', r'\b{0,2}a',
            'a{#prefix\n2}', 'a{1#part\n2}', 'a{2#comma\n,#upper\n3}',
            'a{2,#unbounded\n}', 'a{#empty\n}', 'a{2#EOF}',
            'a{2,#EOF}', 'a{2,3#end\n}#lazy\n?', 'a*#lazy\n?',
            'a+#lazy\n?b', 'a?#lazy\n?', r'\#', r'\ ',
            r'[\#\ ]', '[\\x4#digit\n1-\\x4#digit\n3]',
            '[\\p{G#part\nreek}]', '(?-x:a#b)', '(?-x:a{ 2 })',
            '(?-x:\\x4#digit\n1)', '(? #invalid flags\ni:a)',
            '( #group prefix\n?:a)', '( #group prefix\n?i:a)',
            '(?P<na me>a)', '(?P<na#comment\nme>a)',
        ]
    ]
    for gap in [' \t', '#comment\n', '\r\n', '\u0085', '\u00a0', '\u1680',
                '\u2007', '\u2028', '\u2029', '\u202f', '\u205f', '\u3000']:
        patterns += ['(?x)\\x'+gap+'{4'+gap+'1}',
                     '(?x)\\p{G'+gap+'reek}',
                     '(?x)a{'+gap+'2'+gap+','+gap+'3'+gap+'}']
    patterns += ['(?x-u)\\xC#digit\n3\\xA#digit\n9', '(?x-u)\\x #prefix\n{E9}', '(?x-u)[\\x4#digit\n1]', '(?x-u)\\b{start-#suffix\nhalf}a']
    patterns += [r'\b{2}a', r'\b{0,2}a', 'a{ 2 }', 'a{2 , 3}',
                 'a{2, }', 'a{ 2 3}', 'a{2 ,}', 'a{2, 3 }',
                 r'\x {41}', r'\p {Greek}', 'a{2} ?']
    texts = ['', 'a', 'b', 'ab', 'abc', 'aaaa', 'aaaab', 'a\na', 'a\r\nb', '\n',
             '\r', ' ', '\t', '-', ']', 'c', 'xword y', 'word', 'words', 'é', 'É',
             'α', '😀', 'ſ', 'K', 'A', 'Z', '_', '2', '\0', '\u00a0', '#', 'a#b', 'a'*12]
    random.seed(81270)
    atoms = ['a', 'b', '.', r'\w', r'\d', r'\s', '[a-c]', '[^a]', '[a-c--b]',
             r'\p{Greek}', r'\b', '^', '$', '']

    def expression(depth):
        if not depth or random.randrange(4) == 0:
            return random.choice(atoms)
        choice = random.randrange(5)
        if choice == 0:
            return '(' + expression(depth-1) + '|' + expression(depth-1) + ')'
        if choice == 1:
            return '(?:' + expression(depth-1) + ')' + random.choice(['*', '+', '?', '{1,3}', '{2}', '{0,}'])
        if choice == 2:
            return '(' + expression(depth-1) + expression(depth-1) + ')'
        if choice == 3:
            return '(?' + random.choice(['i', 'm', 's', 'R', 'im', '-u', 'i-u']) + ':' + expression(depth-1) + ')'
        return expression(depth-1) + random.choice(atoms)

    patterns += sorted({expression(3) for _ in range(350)})
    return [(mode, pattern, text) for pattern, text, mode in itertools.product(patterns, texts, ['', 'i'])]


def encoded(value):
    return base64.b64encode((value if isinstance(value, bytes) else value.encode())).decode()


def command(backend, prefix):
    return ['bun', str(prefix) + '.js', '--', '--'] if backend == 'bun' else [str(prefix), '--threads', backend[-1], '--']


def run(backend, prefix, cases, timeout=60):
    argv = [item for mode, pattern, text in cases for item in [mode, encoded(pattern), encoded(text)]]
    result = subprocess.run(command(backend, prefix) + argv, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (backend, result.returncode, result.stderr[-1200:])
    lines = result.stdout.splitlines()
    assert len(lines) == len(cases), (backend, len(lines), len(cases), result.stdout[:200])
    return lines


def reference(cases, executable):
    result = subprocess.run([str(executable)], input=''.join(json.dumps(case) + '\n' for case in cases), capture_output=True, text=True, check=True)
    return result.stdout.splitlines()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
    parser.add_argument('--prefix', type=Path, default=ROOT / 'build/regex')
    parser.add_argument('--reference', type=Path, default=ROOT / 'build/regex-reference/target/release/regex-reference')
    args = parser.parse_args()
    cases = corpus()
    expected = reference(cases, args.reference)
    required_bytes = [('', r'(?-u).', 'é'), ('', r'(?-u)..', 'é'), ('', r'(?-u)\xC3', 'é'), ('', r'(?-u)[^a]', 'b'), ('', r'(?-u)\W', 'é')]
    long_cases = [
        ('', 'a'*12000, 'a'*12000),
        ('', 'a'*11999+'b', 'a'*24000),
        ('', '['+'a'*12000+']', 'b'),
        ('', '|'.join(['a']*12000), 'b'),
        ('', 'a{20000}', 'a'*20000),
        ('', '((){65536}){65536}', 'b'),
        ('', '(a|aa)*b', 'a'*20000),
        ('', '(a?)*b', 'a'*20000+'b'),
    ]
    long_expected = reference(long_cases, args.reference)
    # Unicode 17 additions, independently identified in the pinned official
    # UnicodeData/Scripts files. The Rust oracle embeds Unicode 16.
    unicode17 = [
        ('', r'\p{Sidetic}', '\U00010940'),
        ('', r'\p{Sidetic}', 'a'),
        ('', r'\p{Tolong_Siki}', '\U00011DB0'),
        ('', r'\p{Tai_Yo}', '\U0001E6C0'),
        ('', r'\p{Beria_Erfe}', '\U00016EA0'),
        ('', r'\p{Lu}', '\uA7CE'),
        ('i', '\uA7CE', '\uA7CF'),
        ('', r'\w', '\U0001E6C0'),
    ]
    unicode_expected = ['true', 'false', 'true', 'true', 'true', 'true', 'true', 'true']
    stream_sources = [
        ('', 'abc', 'xabcx'), ('', 'aaab', 'aaaaab'), ('', 'abc', 'abx'),
        ('', '(?i)ſKé', 'xSkÉ'), ('', '^abc$', 'abc'), ('', '^abc$', 'abcx'),
        ('', 'abc$', 'abc\n'), ('', '(?m)^abc$', 'x\nabc\ny'),
        ('', '(?mR)^abc$', 'x\r\nabc\r\ny'), ('', '(?mR)^$', '\r\n'),
        ('', '(?mR)abc$', 'abc\rX'), ('', r'\bélan\b', 'élan!'),
        ('', r'\bélan\b', 'élans'), ('', r'\Bélan', 'xélan'),
        ('', r'\A(?:a|é)+\z', 'aéa'), ('', r'\p{Greek}+', 'xαβ'),
        ('', '😀é', 'x😀é'), ('', '', ''), ('', '$', ''), ('', '$a', 'a'),
        ('', '(a?)*b', 'aaaaab'), ('', 'a[^b]c', 'aéc'),
    ]
    stream_expected = reference(stream_sources, args.reference)
    streams = [(('s' + 'x'*split, pattern, text), wanted)
               for (_, pattern, text), wanted in zip(stream_sources, stream_expected)
               for split in range(len(text)+1)]
    literals = [(mode, pattern, text) for mode in ['l', 'li']
                for pattern in ['', '[a-z]+', '--pre=x', 'é😀', 'ſK', '\0']
                for text in ['', 'x[a-z]+y', '--pre=x', 'É😀', 'é😀', 'sk', '\0']]
    # Use the Rust engine with every scalar escaped as a literal, so the oracle
    # does not share the native fast-path implementation or its parser.
    literal_reference = [('i' if mode == 'li' else '', ''.join(r'\x{' + format(ord(c), 'x') + '}' for c in pattern), text)
                         for mode, pattern, text in literals]
    literal_expected = reference(literal_reference, args.reference)
    literal_streams = [(('L' + 'x'*split, pattern, text), wanted)
                       for (mode, pattern, text), wanted in zip(literals, literal_expected) if mode == 'l'
                       for split in range(len(text)+1)]
    byte_cases = [('bi' if mode == 'i' else 'b', pattern, text.encode()) for mode, pattern, text in cases]
    byte_expected = expected
    byte_patterns = [r'(?-u).', r'(?-u)..', r'(?s-u).*', r'(?-u)\xFF', r'(?-u)[^a]',
                     r'(?-u)\xC3(?u:.)', r'(?-u)\xC3\xA9', r'(?-u)\x{E9}', r'(?-u)\u00E9',
                     r'(?-u)[é]', r'(?-u)[\xE9]', r'(?-u)[\u00E9]', r'(?-u)\xFF\babc\b',
                     r'(?-u)\xFF(?u:\w+)', r'\B', r'\b', r'\b{start-half}', r'\b{end-half}',
                     r'(?-u)\B', r'(?-u)\b', r'\pL', r'(?i)é', r'(?i-u)é', r'(?i-u)[a-z]',
                     r'(?mR)^a$', r'\A(?-u:.)(?u:é)\z', 'a', 'ab', 'aaab', 'éx', '', '^$', r'(?s).', '😀']
    raw_values = [b'', b'a', b'abc', b'\xffabc\xff', b'\xc3\xa9', b'\xc3a', b'\xa9',
                  b'\xe0\x80\x80', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\xf0\x9f\x98\x80',
                  b'\xf0\x9f', b'\r\na\r\n', b'\xff\xc3\xa9', b'\0', b'\xff', b'\xc3\xa9a',
                  b'\xc3\xc3\xa9', b'\xffa', b'a\xff', b'\xc3\xff\xa9', b'\xc3\xa9\xff',
                  b'a\xffb', b'aa\xc3aab', b'\xc3\xa9\xffx', b'\xff\xc3\xa9x']
    raw_cases = [('b', pattern, value) for pattern in byte_patterns for value in raw_values]
    raw_expected = reference([(mode, pattern, value.hex()) for mode, pattern, value in raw_cases], args.reference)
    raw_streams = [(('B' + 'x'*split, pattern, value), wanted)
                   for (_, pattern, value), wanted in zip(raw_cases, raw_expected)
                   for split in range(len(value)+1)]
    for backend in args.backends:
        compared = rejected = 0
        for start in range(0, len(cases), 150):
            chunk = cases[start:start+150]
            actual = run(backend, args.prefix, chunk)
            for case, wanted, got in zip(chunk, expected[start:start+150], actual):
                if got == 'byte-input-required':
                    assert '-u' in case[1], case
                    rejected += 1
                else:
                    got = 'error' if got.startswith('error:') else got
                    assert got == wanted, (backend, case, wanted, got)
                    compared += 1
        for start in range(0, len(byte_cases), 150):
            actual_bytes = run(backend, args.prefix, byte_cases[start:start+150])
            for case, wanted, got in zip(byte_cases[start:start+150], byte_expected[start:start+150], actual_bytes):
                assert ('error' if got.startswith('error:') else got) == wanted, (backend, case, wanted, got)
        for start in range(0, len(raw_streams), 150):
            chunk = raw_streams[start:start+150]
            actual_bytes = run(backend, args.prefix, [case for case, _ in chunk])
            for (case, wanted), got in zip(chunk, actual_bytes):
                assert ('error' if got.startswith('error:') else got) == wanted, (backend, case, wanted, got)
        assert run(backend, args.prefix, required_bytes) == ['byte-input-required'] * len(required_bytes)
        assert run(backend, args.prefix, unicode17) == unicode_expected
        assert run(backend, args.prefix, literals) == literal_expected
        for chunk_start in range(0, len(streams + literal_streams), 150):
            chunk = (streams + literal_streams)[chunk_start:chunk_start+150]
            actual_stream = run(backend, args.prefix, [case for case, _ in chunk])
            assert actual_stream == [wanted for _, wanted in chunk], (backend, chunk, actual_stream)
        started = time.monotonic()
        actual = run(backend, args.prefix, long_cases)
        assert actual == long_expected, (backend, actual, long_expected)
        assert run(backend, args.prefix, [('b', pattern, text.encode()) for _, pattern, text in long_cases]) == long_expected
        duration = time.monotonic() - started
        tables = subprocess.run(command(backend, args.prefix) + ['tables'], capture_output=True, text=True, timeout=60)
        assert tables.returncode == 0 and tables.stdout.strip() == 'true', (backend, tables.stdout, tables.stderr[-1000:])
        print(f'{backend}: {compared} scalar and {len(byte_cases)+len(raw_streams)} byte Rust comparisons, {rejected + len(required_bytes)} explicit byte-input rejections, {len(unicode17)} Unicode 17, {len(streams)+len(literal_streams)} chunk-boundary and {len(literals)} literal API checks, {len(long_cases)} long/adversarial checks ({duration:.3f}s) and 131,101 indexed-table checks passed', flush=True)


if __name__ == '__main__':
    main()

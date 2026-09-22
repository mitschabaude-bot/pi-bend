"""Quantized native timer conversion against independent binary64 arithmetic."""
import hashlib, json, math, random, struct, subprocess, sys
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
root = Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()
bun = Path.home() / '.bun/bin/bun'
rng = random.Random(8173)
values = [0., -0., 1., -1., .5, math.inf, -math.inf, math.nan, 5e-324, -5e-324]
for edge in [1., 2147483647., 2147483648., 4294967295., 4294967296.]:
    values += [math.nextafter(edge, -math.inf), edge, math.nextafter(edge, math.inf)]
values += [float(rng.randrange(2**32)) for _ in range(600)]
values += [struct.unpack('>d', rng.randbytes(8))[0] for _ in range(600)]
cases = [';'.join(map(str, struct.unpack('>II', struct.pack('>d', value)))) for value in values]
expected = [str(math.floor(value)) if math.isfinite(value) and 0 <= value < 2**32 else 'invalid:'+':'.join(map(str, struct.unpack('>II', struct.pack('>d', value)))) for value in values]
fixture = root/'packages/runtime/test/timer-delay.bend'
for suffix in ['c', 'js']:
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', f'build/timer-delay-{suffix}-build.json', '--', str(bun), str(candidate/'main.ts'), str(fixture), '-o', f'build/timer-delay.{suffix}'], cwd=root, check=True)
subprocess.run(['clang', '-std=c11', '-O1', '-fbracket-depth=2048', 'build/timer-delay.c', '-lpthread', '-lm', '-o', 'build/timer-delay'], cwd=root, check=True)
results = []
for backend, command in [('native-1', [str(root/'build/timer-delay'), '--threads', '1']), ('native-4', [str(root/'build/timer-delay'), '--threads', '4']), ('bun', [str(bun), str(root/'build/timer-delay.js')])]:
    for start in range(0, len(cases), 32):
        result = subprocess.run([*command, *cases[start:start+32]], capture_output=True, text=True, check=True, timeout=10)
        assert result.stdout.splitlines() == expected[start:start+32], (backend, start, result.stdout, expected[start:start+32])
        assert not result.stderr, result.stderr
    results.append(dict(backend=backend, cases=len(cases)))
    print(backend, len(cases), 'PASS', flush=True)
sources = [fixture, root/'packages/runtime/src/timer-delay.bend', root/'packages/runtime/src/timer-milliseconds.bend', root/'packages/runtime/test/utf8-runner.bend', root/'packages/runtime/src/f64.bend', root/'packages/runtime/src/u64.bend', Path(__file__).resolve()]
(root/'build/timer-delay-result.json').write_text(json.dumps(dict(scope='Independent Python binary64 range/floor oracle; 1,225 inputs per backend, not a universal arithmetic proof.', sources={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, results=results, vectors=[dict(bits=c, expected=e) for c,e in zip(cases,expected)]), indent=2)+'\n')

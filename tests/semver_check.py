"""packages/runtime/src/semver.bend against node-semver 7.8.5 valid/compare.

Usage: python3 tests/semver_check.py [build/semver.js] [build/semver]
"""
import itertools, json, os, pathlib, random, subprocess, sys

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/semver.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/semver'
versions = ['0.70.6', '0.70.5', '0.70.4', '5.0.0-beta.20', '5.0.0-beta.9', '1.2.3', 'v1.2.3', '=1.2.3', ' 1.2.3 ', '01.2.3', '1.02.3', '1.2', '1.2.3.4',
            '1.2.3-0', '1.2.3-00', '1.2.3-01', '1.2.3-alpha', '1.2.3-alpha.1', '1.2.3-alpha.beta', '1.2.3-alpha.10', '1.2.3-alpha.2', '1.2.3-0a', '1.2.3--',
            '1.2.3-', '1.2.3+', '1.2.3+build', '1.2.3+build.01', '1.2.3-rc.1+sha.5', '1.2.3+b..c', '1.2.3-a..b', 'V1.2.3', 'vv1.2.3', '', ' ', 'latest',
            '9007199254740991.0.0', '9007199254740992.0.0', '1.2.3-9007199254740991', '1.2.3-99999999999999999999', '1.2.3-99999999999999999998',
            '0.0.0', '10.0.0', '2.0.0', '1.10.0', '1.9.99', '1.2.3-x.7.z.92', '1.2.3-X', '1.2.3-a-b', '1.0.0-alpha.beta.1', '1.0.0-rc.1',
            '1.2.3\t', ' 1.2.3', '1.2.3-é', '１.2.3', '1.2.3 ', '1.2.3-alpha.01', '1.2.3-alpha.0', '1.2.3-99999999999999999999.b', '1.2.3-99999999999999999998.a', '1.2.3-9007199254740993', '1.2.3-9007199254740992', '1.2.3-a.99999999999999999999', '1' + '0' * 300 + '.0.0']
rng = random.Random(3)
pairs = [[a, b] for a in versions[:30] for b in versions[:30]] + [[rng.choice(versions), rng.choice(versions)] for _ in range(300)] + [[v, v] for v in versions] + [[a, b] for a in versions if '999999' in a or '900719' in a for b in versions if '999999' in b or '900719' in b]
expected = subprocess.run(['bun', 'tests/semver_reference.ts'], cwd=root, input=json.dumps(pairs), capture_output=True, text=True, check=True).stdout.splitlines()
encoded = [';'.join(','.join(str(ord(c)) for c in text) for text in pair) for pair in pairs]
lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/semver.bend first'
for name, command in lanes:
    actual = []
    for chunk in range(0, len(encoded), 200):
        run = subprocess.run(command + encoded[chunk:chunk + 200], cwd=root, capture_output=True, text=True, timeout=300)
        assert run.returncode == 0, (name, run.stderr)
        actual += run.stdout.splitlines()
    bad = [(pairs[i], expected[i], actual[i] if i < len(actual) else None) for i in range(len(pairs)) if i >= len(actual) or actual[i] != expected[i]]
    for case in bad[:15]:
        print('MISMATCH', case)
    assert not bad, (name, len(bad))
    print(f'{name}: {len(pairs)} valid/compare pairs match node-semver 7.8.5')

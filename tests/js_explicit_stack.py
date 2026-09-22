"""BEND-019 regression: non-tail self-recursion in Base and user defs must not
overflow the JS backend's stack. Runs the two reproducers on Bun and checks
the native build of the small one prints the same result."""
import pathlib, subprocess, os
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = os.environ.get('BEND', str(ROOT / 'build/bend-native-toolchain/bend2/main.ts'))

def js(source, target):
    subprocess.run(['bun', BEND, source, '-o', target], check=True, cwd=ROOT, capture_output=True)
    result = subprocess.run(['bun', target], capture_output=True, text=True, timeout=120, cwd=ROOT)
    assert result.returncode == 0 and not result.stderr, (source, result.returncode, result.stderr[-400:])
    return result.stdout.strip()

assert js('tests/compiler-js-list-append.bend', 'build/js-list-append.js') == 'constructed'
print('PASS List.append doubles a 256-element list eight times on Bun', flush=True)
assert js('tests/compiler-js-list-length.bend', 'build/js-list-length.js') == '200000 50001 40001'
print('PASS List.length, String.split and String.join over 200,000/50,000/20,000 elements on Bun', flush=True)
subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/compiler-js-list-append.bend', 'build/js-list-append'], check=True, cwd=ROOT, capture_output=True)
native = subprocess.run([str(ROOT / 'build/js-list-append'), '--threads', '1'], capture_output=True, text=True, timeout=120)
assert native.returncode == 0 and native.stdout.strip() == 'constructed', native
print('PASS the native build agrees', flush=True)
print('js_explicit_stack: PASS')

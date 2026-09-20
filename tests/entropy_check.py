"""Linux OS entropy and disposable syscall fault injection on native/Bun backends.

Checks byte preservation, bounds, error propagation and exact syscall counts.
Randomness strength is an OS contract, not inferred from sample uniqueness.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate', type=Path)
args = parser.parse_args()
candidate = args.candidate.resolve()
bun = Path.home() / '.bun/bin/bun'
folder = ROOT / 'build/entropy-check'
folder.mkdir(exist_ok=True)
for suffix in ['c', 'js']:
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8',
                    '--stats', str(folder / f'{suffix}-build.json'), '--', str(bun),
                    str(candidate / 'main.ts'), 'tests/entropy.bend', '-o',
                    str(folder / f'live.{suffix}')], cwd=ROOT, check=True)

def compile_c(source, binary):
    subprocess.run(['clang', '-std=c11', '-O1', str(source), '-lpthread', '-lm',
                    '-o', str(binary)], check=True)

compile_c(folder / 'live.c', folder / 'live')
c_helper = r'''
#include <sys/random.h>
static unsigned entropy_calls;
static void __attribute__((destructor)) entropy_audit(void) {
  fprintf(stderr, "calls:%u\n", entropy_calls);
}
static ssize_t entropy_probe(void* buffer, size_t count, unsigned flags) {
  entropy_calls++;
  if (count == 0 || count > 256 || flags != GRND_NONBLOCK) abort();
  int mode = atoi(getenv("ENTROPY_MODE"));
  if (mode > 0) { errno = mode; return -1; }
  for (size_t i = 0; i < count; i++) ((uint8_t*)buffer)[i] = i;
  return mode == -1 ? count - 1 : (mode == -2 ? 0 : count);
}
'''
original = (candidate / 'effs/entropy_bytes.c').read_text()
text = (folder / 'live.c').read_text()
assert text.count(original) == 1
changed = c_helper + original.replace('getrandom(buffer, count, GRND_NONBLOCK)',
                                      'entropy_probe(buffer, count, GRND_NONBLOCK)')
(folder / 'probe.c').write_text(text.replace(original, changed))
compile_c(folder / 'probe.c', folder / 'probe')
js_mock = r'''
  const sys = {...io_sys(), ptr: x => x, errno: () => Number(process.env.ENTROPY_MODE)};
  if (globalThis.ENTROPY_CALLS === undefined) {
    globalThis.ENTROPY_CALLS = 0;
    process.on('exit', () => process.stderr.write(`calls:${globalThis.ENTROPY_CALLS}\n`));
  }
  globalThis.BEND_ENTROPY = {symbols: {getrandom: (buffer, count, flags) => {
    globalThis.ENTROPY_CALLS++;
    if (count === 0 || count > 256 || flags !== 1) throw Error('invalid syscall');
    const mode = Number(process.env.ENTROPY_MODE);
    if (mode > 0) return -1;
    for (let i = 0; i < count; i++) buffer[i] = i;
    return mode === -1 ? count - 1 : (mode === -2 ? 0 : count);
  }}};
'''
original = (candidate / 'effs/entropy_bytes.js').read_text()
text = (folder / 'live.js').read_text()
assert text.count(original) == 1
assert original.count('  const sys = io_sys();') == 1
(folder / 'probe.js').write_text(text.replace(original, original.replace('  const sys = io_sys();', js_mock)))
counts = [*range(257), 257, 65536, 4294967295, 0, 2, 256]
rows = []
for backend, command, probe in [
    ('native 1', [str(folder/'live'), '--threads', '1'], [str(folder/'probe'), '--threads', '1']),
    ('native 4', [str(folder/'live'), '--threads', '4'], [str(folder/'probe'), '--threads', '4']),
    ('Bun', [str(bun), str(folder/'live.js')], [str(bun), str(folder/'probe.js')]),
]:
    for mode in [None, 0, 11, 38, 4, -1, -2]:
        call = command if mode is None else probe
        result = subprocess.run([*call, *map(str, counts)], cwd=ROOT, capture_output=True,
                                text=True, timeout=30,
                                env=dict(os.environ, ENTROPY_MODE=str(mode or 0)))
        expected_calls = sum(0 < n <= 256 for n in counts)
        stderr = '' if mode is None else f'calls:{expected_calls}\n'
        assert result.returncode == 0 and result.stderr == stderr, (backend, mode, result)
        lines = result.stdout.splitlines()
        assert len(lines) == len(counts), (backend, mode, lines)
        for n, line in zip(counts, lines):
            if n > 256:
                assert line == 'error:22', (backend, mode, n, line)
            elif n == 0:
                assert line == 'ok:', (backend, mode, n, line)
            elif mode not in [None, 0]:
                assert line == f'error:{mode if mode > 0 else 5}', (backend, mode, n, line)
            else:
                assert line.startswith('ok:') and line.endswith(','), (backend, mode, n, line)
                values = list(map(int, line[3:-1].split(',')))
                assert len(values) == n and all(0 <= value <= 255 for value in values)
                if mode == 0:
                    assert values == list(range(n)), (backend, n, values)
        rows.append(dict(backend=backend, mode='live' if mode is None else mode,
                         requests=len(counts), syscall_count=None if mode is None else expected_calls))
    print(f'{backend}: live entropy and six injected outcomes PASS', flush=True)
paths = [ROOT/'tests/entropy.bend', ROOT/'tests/entropy_check.py',
         candidate/'comp.ts', candidate/'base.bend', candidate/'effs/entropy_bytes.c',
         candidate/'effs/entropy_bytes.js', folder/'live', folder/'live.js']
(folder/'result.json').write_text(json.dumps(dict(scope=__doc__, cases=rows,
    builds={suffix:json.loads((folder/f'{suffix}-build.json').read_text()) for suffix in ['c','js']},
    sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}), indent=2)+'\n')

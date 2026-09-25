"""Shared provider thinking budgets compared with actual pinned Pi helpers."""
import json
import random
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
levels = ['minimal', 'low', 'medium', 'high', 'xhigh', 'max']
defaults = [1024, 2048, 8192, 16384, 16384, 16384]
cases = []
for level, budget in zip(levels, defaults, strict=True):
    for model in [0, 512, 1024, 1025, budget - 1, budget, budget + 1, 32768]:
        for base in [None, 0, 1000, 32768]:
            cases.append(dict(level=level, model=model, base=base, custom=None))
    for custom in [{}, {'high': 777}, {'minimal': 0, 'low': .5, 'medium': 1024, 'high': 32768}]:
        for base in [None, 1, 8192]:
            cases.append(dict(level=level, model=16384, base=base, custom=custom))
# Out-of-range numeric inputs remain observable; no new validation is inserted.
for special in [-1, -1024, -.5, 'nan', 'infinity', '-infinity', 1e300, 5e-324]:
    for field in ['model', 'base', 'custom']:
        c = dict(level='high', model=32768, base=8192, custom=None)
        c[field] = {'high': special} if field == 'custom' else special
        cases.append(c)
rng = random.Random(7423)
for _ in range(80):
    cases.append(dict(level=rng.choice(levels), model=rng.randrange(65536), base=rng.choice([None, rng.randrange(65536)]), custom={k:rng.randrange(65536) for k in levels[:4] if rng.randrange(2)}))
expected = json.loads(subprocess.check_output(['node', 'tests/thinking_options_reference.mts'], input=json.dumps(cases), text=True, cwd=ROOT))

def number(value):
    if value == 'nan': return 'F.nan()'
    if value == 'infinity': return 'F.infinity(False{})'
    if value == '-infinity': return 'F.infinity(True{})'
    high, low = struct.unpack('>II', struct.pack('>d', value))
    return f'F.fromBits({high}, {low})'

def optional(value):
    return 'None{}' if value is None else 'Some{' + number(value) + '}'

def budgets(custom):
    if custom is None: return 'None{}'
    return 'Some{Ai.ThinkingBudgets{' + ', '.join(optional(custom.get(k)) for k in levels[:4]) + '}}'

constructors = ['Minimal', 'Low', 'Medium', 'High', 'XHigh', 'Max']
lines = ['import Base', 'import ../packages/ai/test/api/thinking-options.bend as T', 'import ../packages/ai/src/types.bend as Ai', 'import ../packages/runtime/src/f64.bend as F']
for i, (case, result) in enumerate(zip(cases, expected, strict=True)):
    args = [optional(case['base']), number(case['model']), 'Ai.' + constructors[levels.index(case['level'])] + '{}', budgets(case['custom']), json.dumps(result['level'])]
    args += [number(result[key]) for key in ['budget', 'room', 'maxTokens', 'thinkingBudget']]
    args += [f'"thinking options {i}"']
    lines += [f'def case{i}() -> IO(Unit):', '  T.check(' + ', '.join(args) + ')']
groups = []
for start in range(0, len(cases), 40):
    name = f'group{start}'; groups.append(name)
    lines += [f'def {name}() -> IO(Unit):', '  do IO<Unit>:'] + [f'    case{i}()' for i in range(start, min(start + 40, len(cases)))]
lines += ['def main() -> IO(Unit):', '  do IO<Unit>:', '    T.absence()'] + [f'    {name}()' for name in groups] + [f'    IO.print("PASS {len(cases)} thinking-budget source comparisons and absent reasoning")']
src = BUILD / 'thinking-options-check.bend'
out = BUILD / 'thinking-options-check'
src.write_text('\n'.join(lines) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(src), str(out)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    subprocess.run([str(out), '--threads', threads], cwd=ROOT, check=True, timeout=120)

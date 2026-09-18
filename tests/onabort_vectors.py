"""Compare typed onabort property replacement, identity and ordering with Node."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/onabort_reference.mjs'], cwd=ROOT, text=True))
lines = ['import Base', 'import ../packages/runtime/test/onabort.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    actions = []
    for action in case['actions']:
        op = action[0]
        if op == 'abort': actions.append('T.Abort{}')
        elif op == 'fire': actions.append('T.Fire{}')
        elif op == 'set': actions.append('T.SetHandler{' + ('None{}' if action[1] is None else f'Some{{{action[1]}}}') + '}')
        else: actions.append('T.' + {'add':'Add','remove':'Remove'}[op] + '{' + str(action[1]) + '}')
    values = ' <> '.join([*actions, 'Nil{}'])
    errors = " <> ".join([*(json.dumps(error) for error in case["errors"]), "Nil{}"] )
    lines.append(f'    T.run({case["mode"]}, {values}, ' + json.dumps('|'.join(case['trace'])) + ', ' + errors + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} onabort ordering and getter traces")')
source = BUILD / 'onabort-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-onabort-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1','4'):
    subprocess.run([str(output),'--threads',threads], check=True, timeout=30)
print(f'PASS onabort reference {reference["node"]}; dynamic non-callable values and listener-count hooks remain pending')

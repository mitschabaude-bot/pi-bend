"""Compare pure Bend listener traversal with real Node EventTarget traces."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/listener_reference.mjs'], cwd=ROOT, text=True))


def string(value):
    return json.dumps(value, ensure_ascii=False)


def boolean(value):
    return 'True{}' if value else 'False{}'


def bend_list(values):
    return ' <> '.join([*values, 'Nil{}'])


def action(value, indices):
    operation, event_type, *arguments = value
    if operation == 'dispatch':
        return f'T.Dispatch{{{string(event_type)}}}'
    callback, options = arguments
    capture = boolean(options.get('capture', False))
    if operation == 'remove':
        return f'T.Remove{{{string(event_type)}, {indices[callback]}n, {capture}}}'
    assert operation == 'add', operation
    once = boolean(options.get('once', False))
    passive = boolean(options.get('passive', False))
    flags = f'L.Options{{{capture}, {once}, {passive}}}'
    return f'T.Add{{{string(event_type)}, {indices[callback]}n, {flags}}}'


target = '--event-target' in sys.argv
fixture_module = 'event-target-fixture' if target else 'listener-fixture'
lines = ['import Base', f'import ../packages/runtime/test/{fixture_module}.bend as T',
         'import ../packages/runtime/src/listener-registry.bend as L',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for fixture in reference['cases']:
    indices = {name: i for i, name in enumerate(fixture['callbacks'])}
    callbacks = bend_list(f'T.CallbackSpec{{{string(name)}, {bend_list(action(a, indices) for a in actions)}}}'
                          for name, actions in fixture['callbacks'].items())
    actions = bend_list(action(a, indices) for a in fixture['actions'])
    expected = string(','.join(fixture['trace']))
    lines.append(f'    T.run({string(fixture["name"])}, {callbacks}, {actions}, {expected})')
lines.append(f'    IO.print("PASS {len(reference["cases"])} Node listener traversal traces")')
stem = 'event-target-listener-vectors' if target else 'listener-vectors'
source = BUILD / (stem + '.bend')
source.write_text('\n'.join(lines) + '\n')
output = BUILD / ('test-' + stem)
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
layer = 'EventTarget dispatcher' if target else 'listener registry'
print(f'PASS {layer} reference {reference["node"]}; complete EventTarget API remains pending')

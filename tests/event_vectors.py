"""Node Event state traces, executed through pure Bend's typed state hooks."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/event_reference.mjs'], cwd=ROOT, text=True))


def boolean(value):
    return 'True{}' if value else 'False{}'


def string(value):
    return json.dumps(value, ensure_ascii=False)


def options(value):
    return 'E.EventInit{' + ', '.join(boolean(value.get(k, False)) for k in ('bubbles', 'cancelable', 'composed')) + '}'


def properties(value):
    assert value['timeStampStable'], 'Node changed the timestamp during an Event state transition'
    names = ('bubbles', 'cancelable', 'composed', 'defaultPrevented')
    fields = [string(value['eventType']), *(boolean(value[n]) for n in names), 'F.fromBits(1072693248, 1)']
    fields.extend(f'T.target({value[n]})' for n in ('target', 'currentTarget', 'srcElement'))
    fields.extend([str(value['eventPhase']), *(boolean(value[n]) for n in ('cancelBubble', 'returnValue', 'isTrusted'))])
    fields.append(' <> '.join([*(str(v) for v in value['composedPath']), 'Nil{}']))
    return 'E.Properties{' + ', '.join(fields) + '}'


lines = ['import Base', 'import ../packages/runtime/src/event.bend as E',
         'import ../packages/runtime/src/f64.bend as F',
         'import ../packages/runtime/test/event-fixture.bend as T']
checks = 0
for index, fixture in enumerate(reference['cases']):
    lines.extend([f'def fixture{index}() -> IO(Unit):', '  do IO<Unit>:',
                  f'    +event : E.WebEvent<U32> <- E.createAt(U32, "original", {options(fixture["init"])}, F.fromBits(1072693248, 1), False{{}})'])
    for step_index, (kind, *args) in enumerate(fixture['steps']):
        if kind == 'throw':
            # The oracle supplies leave-without-return hooks for this path.
            # This suite tests their state effects, not native error reporting.
            lines.append('    # Throw path: only the finally/leave hook follows.')
            continue
        if kind == 'check':
            checks += 1
            label = string(f'{fixture["name"]}: checkpoint {step_index}')
            call = f'T.check(event, {properties(args[0])}, {label})'
        elif kind in ('prevent', 'stop', 'immediate', 'returned', 'leave', 'finish'):
            method = {'prevent': 'preventDefault', 'stop': 'stopPropagation', 'immediate': 'stopImmediatePropagation',
                      'returned': 'listenerReturned', 'leave': 'leaveListener', 'finish': 'finishDispatch'}[kind]
            call = f'E.{method}(U32, event)'
        elif kind in ('enter', 'bubble', 'return'):
            method = {'enter': 'enterListener', 'bubble': 'setCancelBubble', 'return': 'setReturnValue'}[kind]
            call = f'E.{method}(U32, event, {boolean(args[0])})'
        elif kind == 'init':
            call = f'E.initEvent(U32, event, {string(args[0])}, {boolean(args[1])}, {boolean(args[2])})'
        elif kind == 'begin':
            call = f'T.begin(event, {args[0]})'
        elif kind == 'recursive':
            error = args[0]
            call = f'T.recursive(event, {string(error["name"])}, {string(error["code"])}, {string(error["message"])})'
        elif kind == 'dispatchResult':
            call = f'T.dispatchResult(event, {boolean(args[0])})'
        else:
            raise AssertionError(f'Unknown step {kind}')
        lines.append('    ' + call)
    lines.append('    E.dispose(U32, event)')
lines.extend(['def main() -> IO(Unit):', '  do IO<Unit>:'])
lines.extend(f'    fixture{i}()' for i in range(len(reference['cases'])))
lines.append(f'    IO.print("PASS {len(reference["cases"])} Node Event traces and {checks} property checkpoints")')
source = BUILD / 'event-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-event-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
print(f'PASS Event state reference {reference["node"]}; full EventTarget/clock integration remain pending')

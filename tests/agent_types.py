"""Check canonical agent declarations against pinned upstream field contracts."""
import os
from pathlib import Path
from bend_toolchain import BEND
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
source = (ROOT.parent / 'pi-mono/packages/agent/src/types.ts').read_text()
native = (ROOT / 'packages/agent/src/types.bend').read_text()

for name in ('BeforeToolCallResult', 'AfterToolCallResult', 'AgentContext', 'BeforeToolCallContext', 'AfterToolCallContext', 'ShouldStopAfterTurnContext', 'AgentLoopTurnUpdate'):
    upstream = re.search(r'export interface ' + name + r'\s*\{(.*?)\n}', source, re.S).group(1)
    expected = dict(re.findall(r'^\t(\w+)(\??):', upstream, re.M))
    record = re.search(r'^  ' + name + r'\{([^\n]*)\}', native, re.M).group(1)
    actual = {name: '?' if ty.startswith('Maybe<') else '' for name, ty in re.findall(r'(\w+):\s*([^,}]+)', record)}
    assert actual == expected, (name, expected, actual)

union = source.split('export type AgentEvent =', 1)[1]
expected_events = {}
for body in re.findall(r'\{([^{}]*)\}', union):
    tag = re.search(r'type: "([^"]+)"', body).group(1)
    expected_events[tag] = re.findall(r'(\w+)\??:', body)[1:]
actual_events = {}
for variant, body in re.findall(r'^  (\w+)\{([^\n]*)\}', native.split('type AgentEvent', 1)[1].split('def eventType', 1)[0], re.M):
    tag = re.search(r'case ' + variant + r'\{[^\n]*: "([^"]+)"', native).group(1)
    actual_events[tag] = re.findall(r'(\w+):', body)
assert actual_events == expected_events, (expected_events, actual_events)
assert len(actual_events) == 10

subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/agent/test/message-events.bend', 'build/test-agent-message-events'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run(['build/test-agent-message-events', '--threads', threads], cwd=ROOT, check=True, timeout=30)

subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/agent/test/context.bend', 'build/test-agent-context'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run(['build/test-agent-context', '--threads', threads], cwd=ROOT, check=True, timeout=30)
assert 'export interface PrepareNextTurnContext extends ShouldStopAfterTurnContext {}' in source
assert re.search(r'def PrepareNextTurnContext\([^\n]*\) -> Data:\n  ShouldStopAfterTurnContext<', native)

# Distinct source payload fields must stay independently typed, rather than
# becoming generic JSON or an untyped string envelope.
bend = BEND
for index, expression in enumerate(('T.ToolExecutionUpdate{"id", "tool", "raw", True{}}', 'T.ToolExecutionEnd{"id", "tool", 42, False{}}')):
    path = BUILD / f'invalid-agent-event-{index}.bend'
    path.write_text('import Base\nimport ../packages/agent/src/types.bend as T\nimport ../packages/agent/test/message-events.bend as H\ndef main() -> IO(Unit):\n  H.check(' + expression + ', "invalid")\n')
    result = subprocess.run([bend, str(path), '-o', str(path) + '.c'], cwd=ROOT, text=True, capture_output=True, timeout=30)
    output = result.stdout + result.stderr
    (BUILD / f'invalid-agent-event-{index}.log').write_text(output)
    assert result.returncode != 0, 'incompatible tool event payload accepted'
    expected_type, observed_type = ('U32', 'Bool') if index == 0 else ('Bool', 'U32')
    assert f'- expected : {expected_type}\n' in output, output
    assert f'- observed : {observed_type}\n' in output, output
print('PASS ten upstream agent event field sets, seven context/hook record field sets and independent payload rejection')

source_file = BUILD / 'invalid-agent-validated-args.bend'
source_file.write_text("""import Base
import ../packages/agent/src/types.bend as T
import ../packages/agent/test/context.bend as H
def invalid(value: H.Before()) -> String:
  match value:
    case T.BeforeToolCallContext{_, _, args, _}: args
def main() -> IO(Unit):
  IO.print("unreachable")
""")
result = subprocess.run([bend, str(source_file), '-o', str(source_file) + '.c'], cwd=ROOT, text=True, capture_output=True, timeout=30)
output = result.stdout + result.stderr
(BUILD / 'invalid-agent-validated-args.log').write_text(output)
assert result.returncode != 0, 'validated hook arguments became raw string arguments'
assert '- expected : String\n' in output and '- observed : U32\n' in output, output
print('PASS raw versus validated hook argument type rejection and prepare-next-turn alias')

"""Check canonical agent declarations against pinned upstream field contracts."""
from upstream_pin import UPSTREAM
import os
from pathlib import Path
from bend_toolchain import BEND
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
source = (UPSTREAM / 'packages/agent/src/types.ts').read_text()
native = (ROOT / 'packages/agent/src/types.bend').read_text()

for name in ('BeforeToolCallResult', 'AfterToolCallResult', 'AgentContext', 'BeforeToolCallContext', 'AfterToolCallContext', 'AgentTurnContext', 'PrepareRequestContext', 'AgentLoopTurnUpdate'):
    upstream = re.search(r'export interface ' + name + r'\s*\{(.*?)\n}', source, re.S).group(1)
    expected = dict(re.findall(r'^\t(\w+)(\??):', upstream, re.M))
    record = re.search(r'^  ' + name + r'\{([^\n]*)\}', native, re.M).group(1)
    actual = {name: '?' if ty.startswith('Maybe<') else '' for name, ty in re.findall(r'(\w+):\s*([^,}]+)', record)}
    assert actual == expected, (name, expected, actual)

def native_fields(name):
    record = re.search(r'^  ' + name + r'\{([^\n]*)\}', native, re.M).group(1)
    return {field: '?' if ty.startswith('Maybe<') else '' for field, ty in re.findall(r'(\w+):\s*([^,}]+)', record)}

# AgentRequestUpdate = Omit<AgentLoopTurnUpdate, "messages">.
assert 'export type AgentRequestUpdate = Omit<AgentLoopTurnUpdate, "messages">;' in source
turn_update = native_fields('AgentLoopTurnUpdate')
del turn_update['messages']
assert native_fields('AgentRequestUpdate') == turn_update
# The { action } union becomes one constructor per action.
assert 'export type AgentTurnDecision = { action: "continue" } | { action: "end" };' in source
assert re.search(r'type AgentTurnDecision is Data:\n  ContinueTurn\{\}\n  EndTurn\{\}', native)

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
assert 'export interface PrepareNextTurnContext extends AgentTurnContext {}' in source
assert re.search(r'def PrepareNextTurnContext\([^\n]*\) -> Data:\n  AgentTurnContext<', native)

print('PASS ten upstream agent event field sets, eight context/hook record field sets, the request update, turn decision and prepare-next-turn alias')

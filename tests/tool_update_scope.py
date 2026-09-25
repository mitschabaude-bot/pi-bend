"""Native invocation-scope concurrency and affine-completion ownership checks."""
from pathlib import Path
from bend_toolchain import BEND
import os
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/tool_update_scope_reference.mjs'], cwd=ROOT, text=True))
assert reference == {'alreadyFailed': 'first', 'afterClose': 'second', 'pending': 'second'}, reference
print('PASS pinned tool helper failure precedence and late-update rejection', flush=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/agent/test/tool-update-scope.bend', 'build/test-tool-update-scope'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(BUILD / 'test-tool-update-scope'), '--threads', threads], check=True, timeout=30)

# Copying a ticket would permit two completions for one accepted update.
source = BUILD / 'invalid-update-ticket-copy.bend'
source.write_text('''import Base
import ../packages/agent/src/agent-loop.bend as U

def twice(+ticket: U.Ticket<String>) -> IO(Unit):
  do IO<Unit>:
    U.completeScope(String, ticket, Done{Unit{}})
    U.completeScope(String, ticket, Done{Unit{}})

def main() -> IO(Unit):
  IO.print("invalid program must not compile")
''')
bend = BEND
result = subprocess.run([bend, str(source), '-o', str(BUILD / 'invalid-update-ticket-copy.c')], cwd=ROOT, text=True, capture_output=True)
output = result.stdout + result.stderr
if result.returncode == 0 or 'twice' not in output or not any(word in output.lower() for word in ('duplic', 'data', 'copy', 'affine')):
    raise AssertionError('ticket-copy rejection did not demonstrate affine ownership:\n' + output)
print('PASS compiler rejects duplicated update completion tickets')

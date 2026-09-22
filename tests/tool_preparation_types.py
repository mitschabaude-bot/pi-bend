"""Check internal preparation contracts against pinned upstream records."""
import os
from pathlib import Path
from bend_toolchain import BEND
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
source = (ROOT.parent / 'pi-mono/packages/agent/src/agent-loop.ts').read_text()
native = (ROOT / 'packages/agent/src/agent-loop.bend').read_text()
for name, kind in [('PreparedToolCall', 'prepared'), ('ImmediateToolCallOutcome', 'immediate')]:
    upstream = re.search(r'type ' + name + r' = \{(.*?)\n};', source, re.S).group(1)
    assert f'kind: "{kind}";' in upstream
    expected = re.findall(r'^\t(\w+):', upstream, re.M)
    record = re.search(r'^  ' + name + r'\{([^\n]*)\}', native, re.M).group(1)
    actual = re.findall(r'(\w+):', record)
    assert actual == [field for field in expected if field != 'kind'], (name, expected, actual)

subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/agent/test/tool-preparation-types.bend', 'build/test-tool-preparation-types'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run(['build/test-tool-preparation-types', '--threads', threads], cwd=ROOT, check=True, timeout=30)

print('PASS source preparation fields, discriminators and identities')

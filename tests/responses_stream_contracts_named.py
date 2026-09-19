"""Combined original Responses/grammar contracts and shared driver regression.

One build exercises both public streaming and replay without recompiling their
common dependency graph for each suite. Individual suite runners remain usable.
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
suites = ['openai-responses-message-id', 'openai-responses-foreign-toolcall-id',
          'openai-responses-empty-tool-result', 'openai-responses-namespace', 'constrained-sampling']
expected = []
for suite in suites:
    source = (ROOT.parent / f'pi-mono/packages/ai/test/{suite}.test.ts').read_text()
    native = (ROOT / f'packages/ai/test/{suite}.bend').read_text()
    names = re.findall(r'\bit\("([^"\n]+)"', source)
    ported = re.findall(r'IO.print\("PASS ([^"\n]+)"\)', native)
    assert len(ported) == len(names) and set(ported) == set(names), suite
    expected.extend('PASS ' + name for name in names)

# Retain the original conversion runner's exact foreign-ID fixture check.
foreign_source = (ROOT.parent / 'pi-mono/packages/ai/test/openai-responses-foreign-toolcall-id.test.ts').read_text()
raw = re.search(r'const COPILOT_RAW_TOOL_CALL_ID =\s*"([^"]+)";', foreign_source).group(1)
assert f'def rawId() -> String: "{raw}"' in (ROOT / 'packages/ai/test/openai-responses-foreign-toolcall-id.bend').read_text()

# A single batch must include every case, including future additions.
subprocess.run(['python3', 'tests/responses_stream_driver_check.py', '--single-batch', '--generate-only'], cwd=ROOT, check=True)
driver = (ROOT / 'build/responses-stream-driver-check-0.bend').read_text()
count = len(re.findall(r'^def case\d+\(', driver, re.MULTILINE))
assert count > 0 and f'PASS Responses async driver cases 0–{count-1}' in driver
expected.insert(0, f'PASS Responses async driver cases 0–{count-1}')
source = ROOT / 'build/responses-stream-contracts-named.bend'
source.write_text('''import Base
import ./responses-stream-driver-check-0.bend as Driver
import ../tests/responses-conversion-named.bend as Conversion
import ../packages/ai/test/constrained-sampling.bend as Sampling

def main() -> IO(Unit):
  do IO<Unit>:
    Driver.main()
    Conversion.main()
    Sampling.main()
''')
output = source.with_suffix('')
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    result = subprocess.check_output([str(output), '--threads', threads], cwd=ROOT, text=True, timeout=120)
    assert result.splitlines() == expected, result
    print(result, end='', flush=True)
print(f'PASS {len(expected)-1} original Responses/constrained-sampling cases and {count} driver comparisons on one/four threads', flush=True)

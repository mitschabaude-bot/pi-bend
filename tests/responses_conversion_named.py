"""Original Responses conversion contracts; stream-dependent cases stay pending."""
import re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
suites=['openai-responses-message-id','openai-responses-foreign-toolcall-id','openai-responses-empty-tool-result','openai-responses-namespace']
expected=[]
for suite in suites:
    source=(ROOT.parent/f'pi-mono/packages/ai/test/{suite}.test.ts').read_text()
    native=(ROOT/f'packages/ai/test/{suite}.bend').read_text()
    names=re.findall(r'\bit\("([^"\n]+)"',source)
    ported=re.findall(r'IO.print\("PASS ([^"\n]+)"\)',native)
    if suite=='openai-responses-namespace':assert ported==names[3:] and len(names)==5
    else:assert ported==names
    expected.extend('PASS '+name for name in ported)
# Keep the opaque foreign provider ID identical to the original test fixture.
raw=re.search(r'const COPILOT_RAW_TOOL_CALL_ID =\s*"([^"]+)";', (ROOT.parent/'pi-mono/packages/ai/test/openai-responses-foreign-toolcall-id.test.ts').read_text()).group(1)
assert f'def rawId() -> String: "{raw}"' in (ROOT/'packages/ai/test/openai-responses-foreign-toolcall-id.bend').read_text()
output=ROOT/'build/test-responses-conversion-named'
subprocess.run(['sh','scripts/build-pure.sh','tests/responses-conversion-named.bend',str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    result=subprocess.check_output([str(output),'--threads',threads],cwd=ROOT,text=True,timeout=120)
    assert result.splitlines()==expected,result
    print(result,end='')
print('Responses conversion: three complete named suites and 2/5 namespace cases')

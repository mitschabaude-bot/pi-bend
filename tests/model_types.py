"""Check model field coverage and API-dependent compatibility constraints."""
from upstream_pin import UPSTREAM
import os
from pathlib import Path
from bend_toolchain import BEND
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
upstream = (UPSTREAM / 'packages/ai/src/types.ts').read_text()
native = (ROOT / 'packages/ai/src/types.bend').read_text()

def source_fields(name):
    block = re.search(r'export interface ' + name + r'\b[^\n]*\{(.*?)\n}', upstream, re.S).group(1)
    return dict((field, bool(optional)) for field, optional in re.findall(r'^\t(\w+)(\?)?:', block, re.M))

def bend_fields(name):
    block = re.search(r'^type ' + name + r'\b[^\n]*\n\s+' + name + r'\{([^\n]*)\}', native, re.M).group(1)
    return dict((field, type_name.startswith('Maybe<')) for field, type_name in re.findall(r'(\w+):\s*([^,}]+)', block))

names = ['Model', 'OpenAICompletionsCompat', 'OpenAIResponsesCompat', 'AnthropicMessagesCompat',
         'BedrockCompat', 'MistralConversationsCompat', 'OpenRouterRouting',
         'VercelGatewayRouting', 'AnthropicAllowedFallbackModel', 'ThinkingBudgets']
for name in names:
    assert source_fields(name) == bend_fields(name), (name, source_fields(name), bend_fields(name))
images = source_fields('Model')
for name in ('api', 'provider', 'reasoning', 'contextWindow', 'maxTokens', 'compat'):
    del images[name]
images.update(api=False, provider=False, output=False)
assert images == bend_fields('ImagesModel'), (images, bend_fields('ImagesModel'))

subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/ai/test/model-types.bend', 'build/test-model-types'], cwd=ROOT, check=True)
subprocess.run(['build/test-model-types', '--threads', '1'], cwd=ROOT, check=True, timeout=30)

bend = BEND
for index, api in enumerate(('T.OpenAIResponsesApi{}', 'T.GoogleGenerativeAiApi{}', 'T.CustomModelApi{"custom-example"}')):
    source = BUILD / f'invalid-model-compat-{index}.bend'
    source.write_text('''import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/test/model-types.bend as H
def main() -> IO(Unit):
  H.check(H.model(''' + api + ''', Some{T.BedrockCompat{None{}}}), "invalid")
''')
    result = subprocess.run([bend, str(source), '-o', str(source) + '.c'], cwd=ROOT, text=True, capture_output=True, timeout=30)
    output = result.stdout + result.stderr
    (BUILD / f'invalid-model-compat-{index}.log').write_text(output)
    assert result.returncode != 0, 'API accepted an incompatible compatibility record'
    expected_type = 'OpenAIResponsesCompat' if index == 0 else 'Empty'
    assert re.search(r'- expected : [^\n]*' + expected_type + r'\n', output), output
    assert re.search(r'- observed : [^\n]*BedrockCompat\n', output), output
print('PASS 11 upstream model/compatibility field sets and three invalid API/configuration pairs')

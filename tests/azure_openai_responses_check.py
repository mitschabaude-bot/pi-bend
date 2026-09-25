"""Azure OpenAI Responses requests versus upstream `stream`, no network.

The reference runs the pinned upstream azure-openai-responses.ts with the
real AzureOpenAI SDK and a capturing fetch; the Bend side prepares the same
case and builds the SDK envelope. Both see the case's provider environment
only through options.env. Runs the JavaScript lane (compiled once); pass
--native to also run a native build made separately.
"""
import argparse, json, os, subprocess, sys
from pathlib import Path
from upstream_pin import PIN
from bend_toolchain import BEND

ROOT = Path(__file__).resolve().parents[1]
PI_MONO = Path(os.environ.get('PI_MONO', ROOT.parent / 'pi-mono'))
CATALOG = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/providers/data/azure-openai-responses.json')
ENTRY = 'packages/ai/test/azure-openai-responses-request.bend'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/azure-openai-responses-request')
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--native', action='store_true')
arguments = parser.parse_args()
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=PI_MONO, text=True).strip() == PIN

def tool(name, grammar=False):
    value = dict(name=name, description='A tool', parameters={'type': 'object', 'properties': {'input': {'type': 'string'}}, 'required': ['input']})
    if grammar: value['constrainedSampling'] = {'type': 'grammar', 'variants': {'openai_lark': 'start: /[a-z]+/'}}
    return value

# Contexts of packages/ai/test/openai-responses-request.bend `context(mode)`.
def messages(mode):
    first = dict(role='system', content='initial', timestamp=1)
    if mode: first['toolsAdded'] = [tool('tool', mode == 5)]
    result = [first, dict(role='user', content='hello', timestamp=1)]
    if mode == 2: result += [dict(role='system', content='updated', toolsAdded=[tool('later')], timestamp=2), dict(role='user', content='again', timestamp=3)]
    if mode == 6:
        usage = dict(input=0, output=0, cacheRead=0, cacheWrite=0, totalTokens=0, cost=dict(input=0, output=0, cacheRead=0, cacheWrite=0, total=0))
        result += [dict(role='assistant', api='openai-responses', provider='openai', model='target', content=[dict(type='toolCall', id='call_fixture', name='tool', arguments={'input': 'hello'})], usage=usage, stopReason='toolUse', timestamp=2),
                   dict(role='toolResult', toolCallId='call_fixture', toolName='tool', content=[dict(type='text', text='done')], isError=False, timestamp=3)]
    return result

COMPAT = ['supportsDeveloperRole', 'supportsMidConvoSystemMessages', 'sessionAffinityFormat', 'supportsLongCacheRetention', 'supportsStrictMode', 'supportsOpenAIGrammarTools', 'supportsAdditionalTools', 'supportsToolSearch', 'supportsExplicitPromptCacheMode', 'supportsMaxOutputTokens']
cases = []
def case(options=None, env=None, modelId='gpt-4o-mini', mode=0, compat=None, **model):
    value = dict(modelId=modelId, mode=mode, options={'apiKey': 'test-api-key', **(options or {})}, **model)
    if env is not None: value['options']['env'] = env
    if compat is not None: value['compat'] = compat
    cases.append(value)

AZURE = 'https://my-resource.openai.azure.com'
# Base URL normalization (azure-openai-base-url.test.ts and edge cases).
for url in ['https://marc-quicktests-resource.cognitiveservices.azure.com', 'https://marc-quicktests-resource.ai.azure.com', AZURE,
            'https://my-resource.cognitiveservices.azure.com/openai', 'https://my-resource.cognitiveservices.azure.com/openai/v1',
            'https://my-resource.services.ai.azure.com/openai/v1/responses', 'https://my-proxy.example.com/v1',
            'https://my-resource.openai.azure.com/openai?api-version=2024-12-01', 'https://my-proxy.example.com/v1?custom=true',
            'not-a-url', '  https://my-resource.openai.azure.com//  ', 'https://MY-RESOURCE.OpenAI.Azure.com/openai/', 'https://my-resource.openai.azure.com/openai#frag',
            'https://my-resource.openai.azure.com/other', 'https://my-proxy.example.com', 'https://my-resource.openai.azure.com:8443/openai/v1/responses/', 'http://[::1]:8080/openai']:
    case(env=dict(AZURE_OPENAI_BASE_URL=url))
# Resolution order: options, environment, resource name, model base URL.
case(dict(azureBaseUrl='https://option.openai.azure.com'), dict(AZURE_OPENAI_BASE_URL='https://env.openai.azure.com'))
case(dict(azureBaseUrl='   '), dict(AZURE_OPENAI_BASE_URL='https://env.openai.azure.com'))
case(dict(azureBaseUrl=''), dict(AZURE_OPENAI_RESOURCE_NAME='from-env'))
case(env=dict(AZURE_OPENAI_RESOURCE_NAME='my-resource'))
case(dict(azureResourceName='option-resource'), dict(AZURE_OPENAI_RESOURCE_NAME='env-resource'))
case(dict(azureResourceName='option-resource'), dict(AZURE_OPENAI_BASE_URL='https://base.example.com/v1'))
case(env=dict(AZURE_OPENAI_BASE_URL='   '), baseUrl='https://model.openai.azure.com')
case(baseUrl='https://model.example.com/openai/v1/')
case()
case(dict(apiKey=''), dict(AZURE_OPENAI_BASE_URL=AZURE))
case(dict(apiKey=None))
# API version.
case(env=dict(AZURE_OPENAI_BASE_URL=AZURE, AZURE_OPENAI_API_VERSION='2025-04-01-preview'))
case(dict(azureApiVersion='option-version'), dict(AZURE_OPENAI_BASE_URL=AZURE, AZURE_OPENAI_API_VERSION='env-version'))
case(dict(azureApiVersion=''), dict(AZURE_OPENAI_BASE_URL='https://my-proxy.example.com/v1?api-version=old&x=a b'))
# Deployment names.
case(dict(azureBaseUrl=AZURE, azureDeploymentName='explicit'), dict(AZURE_OPENAI_DEPLOYMENT_NAME_MAP='gpt-4o-mini=mapped'))
for value in ['gpt-4o-mini=mapped', ' other=x , gpt-4o-mini = spaced ', 'gpt-4o-mini=a,gpt-4o-mini=b', 'gpt-4o-mini=a=b', 'gpt-4o-mini=', 'gpt-4o-mini', ',,', '=x,gpt-4o-mini=y', 'gpt-4o=other']:
    case(dict(azureBaseUrl=AZURE, azureDeploymentName=''), dict(AZURE_OPENAI_DEPLOYMENT_NAME_MAP=value))
# Parameters.
case(dict(azureBaseUrl=AZURE, sessionId='x' * 67))
case(dict(azureBaseUrl=AZURE, sessionId=''))
for tokens in [0, 5, 16, 100, 0.5]:
    case(dict(azureBaseUrl=AZURE, maxTokens=tokens))
case(dict(azureBaseUrl=AZURE, temperature=0.5, samplingParams={'top_p': 0.5, 'store': None, 'temperature': 1}))
case(dict(azureBaseUrl=AZURE, toolChoice='required'), mode=1)
case(dict(azureBaseUrl=AZURE, toolChoice={'type': 'function', 'name': 'tool'}), mode=2)
case(dict(azureBaseUrl=AZURE), mode=1, compat={'supportsStrictMode': False})
case(dict(azureBaseUrl=AZURE), mode=5, compat={'supportsOpenAIGrammarTools': True})
case(dict(azureBaseUrl=AZURE), mode=5)
case(dict(azureBaseUrl=AZURE), mode=6)
case(dict(azureBaseUrl=AZURE), mode=2, compat={'supportsMidConvoSystemMessages': True, 'supportsAdditionalTools': True})
# Reasoning.
for model in ['gpt-5-mini', 'o4-mini', 'gpt-4o-mini', 'gpt-5.4']:
    for effort, summary in [(None, None), ('high', None), (None, 'concise'), ('minimal', 'detailed'), ('xhigh', None)]:
        options = dict(azureBaseUrl=AZURE)
        if effort: options['reasoningEffort'] = effort
        if summary: options['reasoningSummary'] = summary
        case(options, modelId=model)
case(dict(azureBaseUrl=AZURE, reasoningSummary=None), modelId='o4-mini')
# Headers and timeout.
case(dict(azureBaseUrl=AZURE, headers={'User-Agent': 'custom-agent'}))
case(dict(azureBaseUrl=AZURE, headers={'api-key': 'override', 'x-extra': 'yes'}), modelHeaders={'x-model': 'model', 'User-Agent': 'model-agent'})
case(dict(azureBaseUrl=AZURE, timeoutMs=30000))

for value in cases:
    value['messages'] = messages(value['mode'])
    value['options'] = {k: v for k, v in value['options'].items() if not (k == 'apiKey' and v is None)}
clean = {k: v for k, v in os.environ.items() if not (k.startswith('AZURE_') or k.startswith('OPENAI_'))}
reference = json.loads(subprocess.check_output(['bun', 'tests/azure_openai_responses_reference.ts', str(PI_MONO), str(CATALOG)], input=json.dumps(cases), text=True, cwd=ROOT, env=clean))

def flags(compat):
    return '.'.join('-' if key not in compat else str(int(compat[key])) for key in COMPAT)
def bend_case(value):
    result = dict(value['options'], modelId=value['modelId'], mode=value['mode'], userAgent=reference['userAgent'], platform=reference['platform'])
    for key in ['baseUrl', 'modelHeaders']:
        if key in value: result[key] = value[key]
    if 'compat' in value: result['compat'] = flags(value['compat'])
    return result
def encode(value): return ','.join(str(ord(c)) for c in json.dumps(value, ensure_ascii=False, separators=(',', ':')))

commands = []
if not arguments.no_build:
    subprocess.run([BEND, ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
commands.append(('bun', ['bun', arguments.prefix + '.js']))
if arguments.native:
    commands += [('native-1', [arguments.prefix, '--threads', '1']), ('native-4', [arguments.prefix, '--threads', '4'])]
for label, command in commands:
    for start in range(0, len(cases), 8):
        args = [part for value, want in zip(cases[start:start + 8], reference['results'][start:start + 8]) for part in (encode(bend_case(value)), encode(want))]
        run = subprocess.run(command + args, cwd=ROOT, capture_output=True, text=True, timeout=300, env=clean)
        assert run.returncode == 0 and run.stdout == 'PASS Azure OpenAI Responses requests\n', (label, start, cases[start:start + 8], reference['results'][start:start + 8], run.stdout, run.stderr)
    requests = sum('url' in value for value in reference['results'])
    print(f'{label}: {len(cases)} Azure request comparisons PASS ({requests} requests, {len(cases) - requests} errors)', flush=True)

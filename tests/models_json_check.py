"""models.json differential check: model-config.ts, provider-composer.ts and
model-runtime.ts against tests/models-json.bend.

Each fixture writes a models.json, runs the upstream ModelRuntime
(tests/models_json_reference.ts under bun, importing $PI_MONO) and the native
fixture with the same environment, and compares the load/composition error,
the provider id order, every models.json provider's name, baseUrl, models,
availability and request auth, and per-model request auth.

Adaptations (documented in model-config.bend / provider-composer.bend):
- JSON syntax errors: the native parser's reason replaces the JavaScript
  engine's text; the surrounding message and file suffix must match exactly.
- Upstream ships more built-in providers; only the port's built-ins (as a
  set) and the custom providers (in order, after the built-ins) are compared.
- Upstream Provider.baseUrl may be undefined; the native string is "".
- Command-backed values need the child-process runtime, absent on the Bun
  lane, so those fixtures run on native runners only.

Usage: models_json_check.py --runner build/models-json[.js] [--threads N]
"""
import argparse, json, os, pathlib, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PI_MONO = pathlib.Path(os.environ.get('PI_MONO', ROOT.parent / 'pi-mono'))
AGENT = PI_MONO / 'packages/coding-agent'
NATIVE_BUILTINS = ['openai', 'openai-codex', 'anthropic', 'google', 'cerebras']
# Ambient keys that would otherwise leak into auth resolution.
AMBIENT = ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'ANTHROPIC_OAUTH_TOKEN', 'GEMINI_API_KEY', 'CEREBRAS_API_KEY']

def custom(**fields):
    return {'baseUrl': 'http://127.0.0.1:9/v1', **fields}

FIXTURES = [
    # baseUrl override (no custom models)
    dict(name='overriding baseUrl changes URL on all built-in models',
         config={'providers': {'openai': {'baseUrl': 'http://127.0.0.1:9/v1'}}},
         env={'OPENAI_API_KEY': 'sk-env'}, refs=['openai/gpt-5.5']),
    dict(name='headers-only override resolves at request time',
         config={'providers': {'anthropic': {'headers': {'x-team': '$TEAM_ID', 'x-fixed': 'fixed'}}}},
         env={'ANTHROPIC_API_KEY': 'sk-ant', 'TEAM_ID': 'team-7'}, refs=['anthropic/claude-sonnet-5']),
    # custom providers
    dict(name='custom openai-completions provider with literal key and env headers',
         config={'providers': {'myprov': custom(api='openai-completions', apiKey='sk-literal', headers={'X-A': '${HDR_ENV}-suffix'},
                  models=[{'id': 'm1'}, {'id': 'm2', 'name': 'Two', 'reasoning': True, 'input': ['text', 'image'], 'contextWindow': 1000, 'maxTokens': 100,
                           'cost': {'input': 1, 'output': 2, 'cacheRead': 0.5, 'cacheWrite': 0, 'tiers': [{'inputTokensAbove': 200000, 'input': 2, 'output': 4, 'cacheRead': 1, 'cacheWrite': 0}]},
                           'thinkingLevelMap': {'off': None, 'high': 'max'}, 'headers': {'X-Model': 'model-header'}}])}},
         env={'HDR_ENV': 'hdr'}, refs=['myprov/m1', 'myprov/m2']),
    dict(name='custom openai-responses and anthropic-messages providers',
         config={'providers': {
             'resp': custom(api='openai-responses', apiKey='$MY_KEY', name='Responses Co', models=[{'id': 'r1', 'promptCache': {'short': 300}}]),
             'anth': custom(baseUrl='http://127.0.0.1:9', api='anthropic-messages', apiKey='plain-key', models=[{'id': 'a1', 'compat': {'supportsEagerToolInputStreaming': False}}])}},
         env={'MY_KEY': 'env-key'}, refs=['resp/r1']),
    dict(name='missing explicit env apiKey keeps provider unavailable',
         config={'providers': {'envprov': custom(api='openai-completions', apiKey='$ABSENT_KEY_A$ABSENT_KEY_B', models=[{'id': 'e1'}])}},
         env={}, refs=[]),
    dict(name='apiKey escapes and braced interpolation',
         config={'providers': {'esc': custom(api='openai-completions', apiKey='$$literal-${PART}$!x', models=[{'id': 'x1'}])}},
         env={'PART': 'mid'}, refs=[]),
    dict(name='authHeader adds a bearer header from the resolved key',
         config={'providers': {'bear': custom(api='openai-completions', apiKey='bear-key', authHeader=True, models=[{'id': 'b1'}]),
                               'nokey': custom(api='openai-completions', authHeader=True, models=[{'id': 'n1'}])}},
         env={}, refs=[]),
    dict(name='command apiKey counts as configured and resolves',
         config={'providers': {'cmd': custom(api='openai-completions', apiKey='!printf "  cmd-key\\n"', models=[{'id': 'c1'}]),
                               'badcmd': custom(api='openai-completions', apiKey='!exit 3', models=[{'id': 'c2'}])}},
         env={}, refs=[], native_only=True),
    # custom models merge behavior
    dict(name='built-in provider custom models inherit api and baseUrl without explicit fields',
         config={'providers': {'openai': {'models': [{'id': 'my-openai-model'}, {'id': 'gpt-5.5', 'name': 'Replaced'}]},
                               'cerebras': {'baseUrl': 'http://127.0.0.1:9/v1', 'compat': {'supportsDeveloperRole': False, 'maxTokensField': 'max_tokens', 'openRouterRouting': {'only': ['a']}},
                                            'models': [{'id': 'c-custom', 'api': 'openai-completions', 'baseUrl': 'http://model-level/v1', 'compat': {'openRouterRouting': {'order': ['b']}, 'supportsStore': True}}]}}},
         env={'OPENAI_API_KEY': 'sk-env'}, refs=[]),
    dict(name='reports every provider composition error',
         config={'providers': {'google': {'name': 'Only a name'}, 'nourl': {'api': 'openai-completions', 'models': [{'id': 'x'}]},
                               'noapi': custom(models=[{'id': 'y'}]), 'badwindow': custom(api='openai-completions', models=[{'id': 'z', 'contextWindow': 0}]),
                               'badmax': custom(api='openai-completions', models=[{'id': 'w', 'maxTokens': -1}]), 'oauthonly': {'oauth': 'radius'}}},
         env={}, refs=[]),
    # modelOverrides
    dict(name='model override applies to a single built-in model',
         config={'providers': {'openai': {'modelOverrides': {
             'gpt-5.5': {'name': 'Overridden', 'reasoning': False, 'contextWindow': 1234, 'cost': {'input': 9}, 'thinkingLevelMap': {'high': None, 'minimal': 'low'},
                         'inputLimits': {'images': {'resize': {'maxWidth': 10}}}, 'promptCache': {'long': 7}, 'samplingParams': {'temperature': 0.5}, 'headers': {'X-Override': 'o'}},
             'does-not-exist': {'name': 'ignored'}}}}},
         env={'OPENAI_API_KEY': 'sk-env'}, refs=['openai/gpt-5.5']),
    dict(name='modelOverrides still apply when provider also defines models',
         config={'providers': {'ov': custom(api='openai-completions', apiKey='k', compat={'supportsStore': False},
                  models=[{'id': 'o1', 'headers': {'X-Def': 'd', 'x-both': 'def'}, 'samplingParams': {'top_p': 0.9}}],
                  modelOverrides={'o1': {'name': 'O One', 'maxTokens': 55, 'headers': {'X-Both': 'override'}, 'compat': {'supportsDeveloperRole': True}}})}},
         env={}, refs=['ov/o1']),
    dict(name='Anthropic model override replaces allowed fallback metadata',
         config={'providers': {'anthropic': {'modelOverrides': {
             'claude-fable-5': {'compat': {'allowedFallbackModels': [
                 {'provider': 'anthropic', 'model': 'claude-opus-5', 'cost': {'input': 5, 'output': 25, 'cacheRead': 0.5, 'cacheWrite': 6.25}},
                 {'provider': 'anthropic', 'model': 'claude-opus-4-8', 'cost': {'input': 4, 'output': 20, 'cacheRead': 0.4, 'cacheWrite': 5}}]}},
             'claude-sonnet-5': {'compat': {'allowedFallbackModels': []}}}}}},
         env={}, refs=[]),
    dict(name='provider-level compat and baseUrl on a Responses built-in',
         config={'providers': {'openai': {'baseUrl': 'http://127.0.0.1:9/v1', 'apiKey': 'from-config', 'compat': {'supportsDeveloperRole': False, 'sessionAffinityFormat': 'openai-nosession'}}}},
         env={}, refs=[]),
    # loading
    dict(name='comments, trailing commas and a BOM are accepted',
         raw='﻿{\n  // providers\n  "providers": {\n    "c": {"baseUrl": "http://h//not-a-comment", "api": "openai-completions", "apiKey": "k", // trailing\n      "models": [{"id": "m", "name": "a,]b"},],\n    },\n  },\n}\n',
         env={}, refs=[]),
    dict(name='invalid JSON reports a parse error', raw='{"providers": {"a": }', env={}, refs=[], parse_error=True),
    dict(name='truncated JSON reports a parse error', raw='{"providers": ', env={}, refs=[], parse_error=True),
    dict(name='schema errors report paths and messages',
         config={'providers': {'a': {'name': '', 'oauth': 'x', 'models': [{}, {'id': 'm', 'input': ['text', 'audio'], 'contextWindow': '1'}], 'headers': {'h': 1},
                                     'compat': {'supportsLongCacheRetention': 'yes'}},
                               'b': 5}},
         env={}, refs=[]),
    dict(name='schema errors stop at the validator capacity',
         config={'providers': {f'p{i}': {'baseUrl': i} for i in range(12)}}, env={}, refs=[]),
    dict(name='missing providers', config={}, env={}, refs=[]),
    dict(name='root must be an object', config=[], env={}, refs=[]),
    dict(name='missing file is an empty configuration', missing=True, env={}, refs=[]),
    dict(name='directory is a read error', directory=True, env={}, refs=[]),
]

def normalized(output):
    """Keep the port's providers, in upstream order."""
    known = set(NATIVE_BUILTINS)
    # The port lists its built-ins in its own order (upstream sorts them).
    output['providers'] = sorted(p for p in output['providers'] if p in known) + [p for p in output['providers'] if p not in UPSTREAM_BUILTINS]
    output['configured'] = [p for p in output['configured'] if p['id'] in known or p['id'] not in UPSTREAM_BUILTINS]
    return output

UPSTREAM_BUILTINS = set()

def run(command, env):
    result = subprocess.run(command, capture_output=True, text=True, timeout=180, env=env)
    assert result.returncode == 0 and not result.stderr.strip(), (command, result.returncode, result.stderr[-2000:])
    return json.loads(result.stdout.strip().splitlines()[-1])

def diff(path, expected, actual, out):
    if isinstance(expected, dict) and isinstance(actual, dict):
        for key in sorted(set(expected) | set(actual)):
            diff(f'{path}.{key}', expected.get(key, '<absent>'), actual.get(key, '<absent>'), out)
    elif isinstance(expected, list) and isinstance(actual, list) and len(expected) == len(actual):
        for index, (e, a) in enumerate(zip(expected, actual)):
            diff(f'{path}[{index}]', e, a, out)
    elif expected != actual:
        out.append(f'{path}: expected {json.dumps(expected)[:300]} got {json.dumps(actual)[:300]}')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default=str(ROOT / 'build/models-json'))
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    bun_lane = args.runner.endswith('.js')
    native = ['bun', args.runner] if bun_lane else [args.runner, '--threads', args.threads, '--']
    failures = 0
    with tempfile.TemporaryDirectory(prefix='pi-models-json-') as folder:
        clean = {k: v for k, v in os.environ.items() if k not in AMBIENT}
        UPSTREAM_BUILTINS.update(run(['bun', str(ROOT / 'tests/models_json_reference.ts'), str(AGENT), str(pathlib.Path(folder) / 'none.json')], clean)['providers'])
        for index, fixture in enumerate(FIXTURES):
            if fixture.get('native_only') and bun_lane:
                print(f'skip (Bun lane has no child processes): {fixture["name"]}')
                continue
            directory = pathlib.Path(folder) / f'case{index}'
            directory.mkdir()
            path = directory / 'models.json'
            if fixture.get('directory'):
                path.mkdir()
            elif 'raw' in fixture:
                path.write_text(fixture['raw'], encoding='utf-8')
            elif not fixture.get('missing'):
                path.write_text(json.dumps(fixture['config'], indent=2))
            env = {k: v for k, v in os.environ.items() if k not in AMBIENT}
            env.update(fixture['env'])
            env['PI_CODING_AGENT_DIR'] = str(directory)
            env['PI_OFFLINE'] = '1'
            expected = run(['bun', str(ROOT / 'tests/models_json_reference.ts'), str(AGENT), str(path), *fixture['refs']], env)
            actual = run([*native, str(path), *fixture['refs']], env)
            expected, actual = normalized(expected), normalized(actual)
            if fixture.get('parse_error'):
                prefix, suffix = 'Failed to parse models.json: ', f'\n\nFile: {path}'
                for output in (expected, actual):
                    assert output['error'].startswith(prefix) and output['error'].endswith(suffix), output['error']
                    output['error'] = prefix + '<engine reason>' + suffix
            problems = []
            diff('', expected, actual, problems)
            if problems:
                failures += 1
                print(f'FAIL {fixture["name"]}:')
                for problem in problems[:15]:
                    print('   ', problem)
            else:
                print(f'ok   {fixture["name"]}')
    assert failures == 0, f'{failures} models.json fixtures differ'
    print(f'{len(FIXTURES)} models.json fixtures match upstream')

if __name__ == '__main__':
    main()

"""upstream config-value-migration.test.ts and runMigrations differential cases.

Each scenario builds an agent directory (and project .pi), copies it, runs the
pinned upstream runMigrations on one copy (tests/migrations_reference.ts, with
PI_CODING_AGENT_DIR) and tests/migrations.bend on the other, and compares the
printed result, console output and resulting trees (paths, contents, file
modes). The upstream suite's three cases additionally assert their own
expectations; their models.json halves (load error for malformed/blank files,
literal API key and header values) run through tests/models-json.bend.
Usage: python3 tests/migrations_check.py [--runner build/migrations[.js]] [--models build/models-json[.js]] [--threads N]
"""
import argparse, json, os, pathlib, shutil, stat, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


def auth_keys(agent, project):
    write(agent / 'auth.json', json.dumps({
        'anthropic': {'type': 'api_key', 'key': 'ANTHROPIC_API_KEY'},
        'openai': {'type': 'api_key', 'key': '$OPENAI_API_KEY'},
        'opencode': {'type': 'api_key', 'key': 'public'},
        'github': {'type': 'oauth', 'access': 'ACCESS_TOKEN', 'refresh': 'REFRESH_TOKEN', 'expires': 1},
    }, indent=2) + '\n')


def malformed(agent, project):
    write(agent / 'models.json', '{\n  "providers": {\n')


def blank(agent, project):
    write(agent / 'models.json', '')


HEADERS_CONFIG = {'providers': {'custom-provider': {
    'baseUrl': 'https://example.com/v1', 'apiKey': 'CUSTOM_API_KEY', 'api': 'openai-completions',
    'headers': {'x-api-key': 'HEADER_API_KEY', 'x-literal': 'literal'},
    'models': [{'id': 'model-a', 'headers': {'x-model-key': 'MODEL_API_KEY'}}],
    'modelOverrides': {'model-b': {'headers': {'x-override-key': 'OVERRIDE_API_KEY'}}},
}}}


def headers(agent, project):
    write(agent / 'models.json', json.dumps(HEADERS_CONFIG, indent=2) + '\n')


def legacy_auth(agent, project):
    write(agent / 'oauth.json', '\ufeff' + json.dumps({'anthropic': {'access': 'a', 'refresh': 'r', 'expires': 5, 'type': 'x'}, 'openai-codex': {'access': 'c'}}))
    write(agent / 'settings.json', json.dumps({'theme': 'dark', 'apiKeys': {'anthropic': 'ignored', 'openai': 'sk-1', 'bad': 3}, 'z': [1]}))


def settings_only(agent, project):
    write(agent / 'settings.json', json.dumps({'apiKeys': {'google': 'g'}}))


def broken_oauth(agent, project):
    write(agent / 'oauth.json', '{broken')
    write(agent / 'settings.json', '{"apiKeys": 1}')


def sessions(agent, project):
    header = lambda cwd: json.dumps({'type': 'session', 'id': 'x', 'cwd': cwd})
    write(agent / 'one.jsonl', header('/home/u/proj') + '\n{"type":"message"}\n')
    write(agent / 'two.jsonl', header('C:\\work\\x:y') + '\n')
    write(agent / 'three.jsonl', json.dumps({'type': 'other', 'cwd': '/a'}) + '\n')
    write(agent / 'four.jsonl', '\n' + header('/b'))
    write(agent / 'five.jsonl', header('') + '\n')
    write(agent / 'six.jsonl', 'not json\n')
    write(agent / 'taken.jsonl', header('/home/u/proj') + '\n')
    write(agent / 'sessions/--home-u-proj--/taken.jsonl', 'existing\n')
    write(agent / 'notes.txt', 'keep')


def tools(agent, project):
    write(agent / 'tools/fd', 'fd-binary')
    write(agent / 'tools/rg', 'old-rg')
    write(agent / 'bin/rg', 'new-rg')
    write(agent / 'tools/custom.ts', 'tool')
    write(agent / 'tools/.DS_Store', '')
    write(project / 'tools/RG', 'x')


def resources(agent, project):
    write(agent / 'commands/a.md', 'a')
    write(project / 'commands/b.md', 'b')
    write(project / 'prompts/keep.md', 'k')
    write(agent / 'hooks/h.ts', 'h')
    write(project / 'hooks/h.ts', 'h')


def keybindings(agent, project):
    write(agent / 'keybindings.json', json.dumps({'cursorUp': 'up', 'app.custom.x': 'ctrl+x', 'expandTools': 'ctrl+o', 'selectUp': ['up'], 'tui.select.up': 'k'}, indent=2))


def keybindings_current(agent, project):
    write(agent / 'keybindings.json', json.dumps({'tui.editor.cursorUp': 'up'}))


def keybindings_malformed(agent, project):
    write(agent / 'keybindings.json', '[1, 2]')


SCENARIOS = [('leaves uppercase auth.json API key values unchanged', auth_keys),
             ('does not throw on malformed models.json during migrations', malformed),
             ('does not throw on blank models.json during migrations', blank),
             ('leaves uppercase models.json API key and header values unchanged', headers),
             ('legacy oauth.json and settings apiKeys', legacy_auth), ('settings apiKeys only', settings_only),
             ('malformed oauth.json and apiKeys', broken_oauth), ('sessions in the agent root', sessions),
             ('managed binaries tools/ to bin/', tools), ('commands/ to prompts/ and hooks warnings', resources),
             ('keybindings.json renames', keybindings), ('current keybindings.json', keybindings_current),
             ('non-object keybindings.json', keybindings_malformed)]


def tree(base):
    out = {}
    for path in sorted(base.rglob('*')):
        rel = str(path.relative_to(base))
        mode = stat.S_IMODE(path.lstat().st_mode)
        out[rel] = ('dir', mode) if path.is_dir() else (path.read_bytes().decode('utf-8', 'replace'), mode)
    return out


def run(command, env):
    result = subprocess.run(command, capture_output=True, text=True, timeout=180, env=env)
    assert result.returncode == 0, (command, result.stdout, result.stderr[-2000:])
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/migrations')
    parser.add_argument('--models', default='build/models-json')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    prefix = lambda runner: ['bun', runner] if runner.endswith('.js') else [runner, '--threads', args.threads, '--']
    env = {k: v for k, v in os.environ.items() if not k.startswith('PI_') and not k.endswith('_API_KEY')}
    env['NO_COLOR'] = '1'
    for name, build in SCENARIOS:
        with tempfile.TemporaryDirectory(prefix='pi-migrations-') as folder:
            folder = pathlib.Path(folder)
            for side in ('upstream', 'bend'):
                build(folder / side / 'agent', folder / side / 'cwd' / '.pi')
                (folder / side / 'cwd').mkdir(parents=True, exist_ok=True)
            before = tree(folder / 'bend')
            expected = run(['bun', str(ROOT / 'tests/migrations_reference.ts'), str(folder / 'upstream/agent'), str(folder / 'upstream/cwd')], env)
            actual = run(prefix(args.runner) + [str(folder / 'bend/agent'), str(folder / 'bend/cwd')], env)
            assert actual.replace(str(folder / 'bend'), '<root>') == expected.replace(str(folder / 'upstream'), '<root>'), (name, expected, actual)
            upstream_tree = {k: (v[0].replace(str(folder / 'upstream'), '<root>') if isinstance(v[0], str) else v[0], v[1]) for k, v in tree(folder / 'upstream').items()}
            bend_tree = {k: (v[0].replace(str(folder / 'bend'), '<root>') if isinstance(v[0], str) else v[0], v[1]) for k, v in tree(folder / 'bend').items()}
            assert upstream_tree == bend_tree, (name, sorted(set(upstream_tree.items()) ^ set(bend_tree.items())))
            if build in (auth_keys, malformed, blank, headers):
                # Upstream asserts: files unchanged and nothing logged.
                assert tree(folder / 'bend') == before, name
                assert actual == 'migratedAuthProviders: \ndeprecationWarnings: \n', (name, actual)
            if build in (malformed, blank):
                models = folder / 'bend/agent/models.json'
                report = json.loads(run(prefix(args.models) + [str(models)], env).splitlines()[-1])
                assert 'Failed to parse models.json' in report['error'] and f'File: {models}' in report['error'], (name, report['error'])
            if build is headers:
                hot = dict(env, CUSTOM_API_KEY='env-CUSTOM_API_KEY', HEADER_API_KEY='env-HEADER_API_KEY', MODEL_API_KEY='env-MODEL_API_KEY', OVERRIDE_API_KEY='env-OVERRIDE_API_KEY')
                report = json.loads(run(prefix(args.models) + [str(folder / 'bend/agent/models.json'), 'custom-provider/model-a'], hot).splitlines()[-1])
                provider = next(p for p in report['configured'] if p['id'] == 'custom-provider')
                assert any(m['id'] == 'model-a' for m in provider['models']), provider
                assert provider['auth']['apiKey'] == 'CUSTOM_API_KEY', provider['auth']
                auth = report['modelAuth']['custom-provider/model-a']
                assert auth['apiKey'] == 'CUSTOM_API_KEY', auth
                assert {k: auth['headers'][k] for k in ('x-api-key', 'x-literal', 'x-model-key')} == {'x-api-key': 'HEADER_API_KEY', 'x-literal': 'literal', 'x-model-key': 'MODEL_API_KEY'}, auth
            print(f'ok {name}')


main()

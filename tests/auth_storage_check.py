"""auth-storage.test.ts and runtime-credentials.test.ts contracts: stored
api-key resolution (templates, commands, scoped env), OAuth passthrough,
modify/delete/list against external edits, in-memory storage, malformed files,
private file creation, and the runtime api-key overlay."""
import json, os, pathlib, stat, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/auth-storage'

for backend, command in [('bun', ['bun', str(PREFIX) + '.js']), ('native-1', [str(PREFIX), '--threads', '1']), ('native-4', [str(PREFIX), '--threads', '4'])]:
    def run(*args, env=None):
        merged = dict(os.environ); merged.pop('TEST_AUTH_STORAGE_KEY', None); merged.update(env or {})
        result = subprocess.run(command + ['--', *args], capture_output=True, text=True, timeout=60, env=merged)
        assert result.returncode == 0 and not result.stderr, (backend, args, result.returncode, result.stderr)
        try:
            return [json.loads(line) for line in result.stdout.splitlines()]
        except json.JSONDecodeError:
            raise AssertionError((backend, args, result.stdout))
    with tempfile.TemporaryDirectory(prefix='pi-test-auth-storage-') as folder:
        auth = pathlib.Path(folder) / 'auth.json'
        def write(data): auth.write_text(json.dumps(data))
        write({'anthropic': {'type': 'api_key', 'key': '$TEST_AUTH_STORAGE_KEY'}})
        assert run('read', str(auth), 'anthropic', env={'TEST_AUTH_STORAGE_KEY': 'environment-key'}) == [{'type': 'api_key', 'key': 'environment-key'}]
        print(f'{backend}: reads and resolves stored API-key credentials', flush=True)
        if backend != 'bun':
            write({'anthropic': {'type': 'api_key', 'key': "!printf 'command-key'"}})
            assert run('read', str(auth), 'anthropic') == [{'type': 'api_key', 'key': 'command-key'}]
            print(f'{backend}: resolves command-backed API-key credentials', flush=True)
        oauth = {'type': 'oauth', 'refresh': 'refresh-token', 'access': 'access-token', 'expires': 1790000000000}
        assert run('read', 'memory:' + json.dumps({'anthropic': oauth}), 'anthropic') == [oauth]
        print(f'{backend}: returns OAuth credentials unchanged', flush=True)
        write({'openai': {'type': 'api_key', 'key': 'first'}})
        assert run('reread', str(auth), 'openai', json.dumps({'openai': {'type': 'api_key', 'key': 'second-key'}})) == [{'type': 'api_key', 'key': 'first'}] * 2 + [{'type': 'api_key', 'key': 'second-key'}]
        print(f'{backend}: rereads a file replaced after an unchanged read', flush=True)
        auth.unlink()
        assert run('reread', str(auth), 'openai', json.dumps({'openai': {'type': 'api_key', 'key': 'created-key'}})) == [None, None, {'type': 'api_key', 'key': 'created-key'}]
        print(f'{backend}: reads a file created after it was absent', flush=True)
        write({'anthropic': {'type': 'api_key', 'key': '$SCOPED_KEY', 'env': {'SCOPED_KEY': 'scoped-value', 'REGION': 'test-region'}}})
        assert run('read', str(auth), 'anthropic') == [{'type': 'api_key', 'key': 'scoped-value', 'env': {'SCOPED_KEY': 'scoped-value', 'REGION': 'test-region'}}]
        print(f'{backend}: credential-scoped env takes precedence and remains inspectable', flush=True)
        write({'anthropic': {'type': 'api_key', 'key': 'old'}, 'openai': {'type': 'api_key', 'key': 'external'}})
        assert run('modify', str(auth), 'anthropic', json.dumps({'type': 'api_key', 'key': 'new'})) == [{'type': 'api_key', 'key': 'new'}]
        assert json.loads(auth.read_text()) == {'anthropic': {'type': 'api_key', 'key': 'new'}, 'openai': {'type': 'api_key', 'key': 'external'}}
        print(f'{backend}: modify persists a credential while preserving unrelated external edits', flush=True)
        write({'anthropic': {'type': 'api_key', 'key': 'stored'}})
        assert run('modify', str(auth), 'anthropic', 'unchanged') == [{'type': 'api_key', 'key': 'stored'}]
        assert run('read', str(auth), 'anthropic') == [{'type': 'api_key', 'key': 'stored'}]
        print(f'{backend}: modify with undefined leaves the current credential unchanged', flush=True)
        write({'anthropic': {'type': 'api_key', 'key': 'anthropic-key'}, 'openai': {'type': 'api_key', 'key': 'openai-key'}, 'google': {'type': 'api_key', 'key': 'external-key'}})
        assert run('delete', str(auth), 'anthropic') == ['ok']
        assert run('list', str(auth)) == [[{'providerId': 'openai', 'type': 'api_key'}, {'providerId': 'google', 'type': 'api_key'}]]
        assert run('read', str(auth), 'anthropic') == [None] and run('read', str(auth), 'google') == [{'type': 'api_key', 'key': 'external-key'}]
        print(f'{backend}: delete removes one credential while preserving others', flush=True)
        memory = 'memory:' + json.dumps({'anthropic': {'type': 'api_key', 'key': 'initial'}})
        assert run('read', memory, 'anthropic') == [{'type': 'api_key', 'key': 'initial'}]
        assert run('modify', memory, 'anthropic', json.dumps({'type': 'api_key', 'key': 'updated'})) == [{'type': 'api_key', 'key': 'updated'}]
        assert run('list', 'memory:{}') == [[]]
        print(f'{backend}: in-memory storage implements the same credential-store behavior', flush=True)
        auth.write_text('{invalid-json')
        assert run('modify', str(auth), 'openai', json.dumps({'type': 'api_key', 'key': 'new'}))[0].get('error')
        assert auth.read_text() == '{invalid-json'
        print(f'{backend}: does not overwrite malformed auth files', flush=True)
        auth.unlink()
        assert run('modify', str(auth), 'openai', json.dumps({'type': 'api_key', 'key': 'fresh'})) == [{'type': 'api_key', 'key': 'fresh'}]
        assert stat.S_IMODE(auth.stat().st_mode) & 0o077 == 0, 'a created auth.json is private'
        assert json.loads(auth.read_text()) == {'openai': {'type': 'api_key', 'key': 'fresh'}}
        auth.write_text('﻿' + json.dumps({'openai': {'type': 'api_key', 'key': 'bom'}}))
        assert run('read', str(auth), 'openai') == [{'type': 'api_key', 'key': 'bom'}]
        # Reads serve the last valid snapshot (upstream reload() preserves it); writes reject invalid files.
        for bad in [{'openai': {'type': 'api_key', 'key': 5}}, {'openai': {'type': 'oauth', 'access': 'a'}}, ['x'], {'openai': 'x'}]:
            write(bad)
            assert run('modify', str(auth), 'openai', json.dumps({'type': 'api_key', 'key': 'new'}))[0].get('error'), bad
            assert json.loads(auth.read_text()) == bad
        print(f'{backend}: creates private files, strips a BOM, and rejects invalid credentials on write', flush=True)
        # RuntimeCredentials
        memory = 'memory:' + json.dumps({'anthropic': {'type': 'api_key', 'key': 'stored-key'}})
        assert run('runtime', memory, 'set:anthropic=runtime-key,read:anthropic,has:anthropic,remove:anthropic,read:anthropic,has:anthropic') == ['ok', {'type': 'api_key', 'key': 'runtime-key'}, True, 'ok', {'type': 'api_key', 'key': 'stored-key'}, False]
        print(f'{backend}: runtime overrides mask stored credentials without persisting', flush=True)
        memory = 'memory:' + json.dumps({'anthropic': {'type': 'oauth', 'access': 'access', 'refresh': 'refresh', 'expires': 1790000000000}})
        assert run('runtime', memory, 'set:anthropic=runtime-key,set:openai=other-runtime-key,list') == ['ok', 'ok', [{'providerId': 'anthropic', 'type': 'api_key'}, {'providerId': 'openai', 'type': 'api_key'}]]
        print(f'{backend}: enumeration merges overrides without exposing keys', flush=True)
        memory = 'memory:' + json.dumps({'anthropic': {'type': 'api_key', 'key': 'stored-key'}})
        assert run('runtime', memory, 'set:anthropic=runtime-key,delete:anthropic,read:anthropic,list') == ['ok', 'ok', None, []]
        print(f'{backend}: delete clears both the override and persisted credential', flush=True)
print('auth_storage_check: PASS')

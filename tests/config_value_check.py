"""resolve-config-value.test.ts contracts: literals, env templates, escapes,
credential-scoped env precedence, shell commands, failures, caching."""
import os, pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/config-value'

for backend, command in [('bun', ['bun', str(PREFIX) + '.js']), ('native-1', [str(PREFIX), '--threads', '1']), ('native-4', [str(PREFIX), '--threads', '4'])]:
    def run(*args, env=None):
        merged = dict(os.environ)
        merged.pop('TEST_CONFIG_LEFT', None); merged.pop('TEST_CONFIG_RIGHT', None); merged.pop('TEST_CONFIG_SCOPED', None)
        merged.update(env or {})
        result = subprocess.run(command + ['--', *args], capture_output=True, text=True, timeout=60, env=merged)
        assert result.returncode == 0 and not result.stderr, (backend, args, result.returncode, result.stderr)
        return result.stdout.rstrip('\n')
    both = {'TEST_CONFIG_LEFT': 'left', 'TEST_CONFIG_RIGHT': 'right'}
    assert run('resolve', 'literal-key') == 'some:literal-key'
    assert run('resolve', '$TEST_CONFIG_LEFT', env=both) == 'some:left'
    assert run('resolve', '${TEST_CONFIG_LEFT}_$TEST_CONFIG_RIGHT', env=both) == 'some:left_right'
    assert run('resolve', '$$TEST_CONFIG_LEFT', env=both) == 'some:$TEST_CONFIG_LEFT'
    assert run('resolve', '$!literal-$TEST_CONFIG_RIGHT', env=both) == 'some:!literal-right'
    assert run('resolve', '$TEST_CONFIG_LEFT') == 'none', 'an unset variable makes the value unresolved'
    assert run('resolve', '${not valid}') == 'some:${not valid}'
    assert run('resolve', '${UNCLOSED') == 'some:${UNCLOSED'
    assert run('resolve', 'a$', env=both) == 'some:a$'
    print(f'{backend}: resolves literals, environment templates, and escapes', flush=True)
    assert run('resolve', '$TEST_CONFIG_SCOPED', 'TEST_CONFIG_SCOPED=credential', env={'TEST_CONFIG_SCOPED': 'process'}) == 'some:credential'
    assert run('resolve', '$TEST_CONFIG_SCOPED', 'TEST_CONFIG_SCOPED=', env={'TEST_CONFIG_SCOPED': 'process'}) == 'some:process', 'an empty scoped value falls back to the process'
    print(f'{backend}: uses credential-scoped environment before process.env', flush=True)
    assert run('names', '${A}_$B-$A$$') == 'A,B'
    assert run('name', '$ONLY') == 'some:ONLY' and run('name', '$A$B') == 'none' and run('name', '!cmd') == 'none'
    assert run('command', '!cmd') == 'True' and run('command', 'literal') == 'False'
    print(f'{backend}: reports referenced variables and command values', flush=True)
    if backend == 'bun':
        # The JS backend has no process primitive (Process.spawn returns ENOSYS); commands are native-only.
        print(f'{backend}: command cases skipped (no JS process primitive)', flush=True)
        continue
    assert run('resolve', "!echo '  spaced-key  '") == 'some:spaced-key'
    assert run('resolve', "!printf 'line1\\nline2'") == 'some:line1\nline2'
    assert run('resolve', "!echo 'hello world' | tr ' ' '-'") == 'some:hello-world'
    print(f'{backend}: executes shell commands and trims their output', flush=True)
    for failing in ['!exit 1', '!nonexistent-command-12345', "!printf ''"]:
        assert run('resolve', failing) == 'none', failing
    print(f'{backend}: returns undefined when command resolution fails', flush=True)
    with tempfile.TemporaryDirectory(prefix='pi-config-value-') as folder:
        counter = pathlib.Path(folder) / 'counter'
        counter.write_text('0')
        escaped = str(counter).replace('"', '\\"')
        success = f"!sh -c 'count=$(cat \"{escaped}\"); echo $((count + 1)) > \"{escaped}\"; echo value'"
        assert run('twice', success) == 'some:value|some:value|some:value'
        assert counter.read_text().strip() == '2', 'cached until cleared, then executed again'
        counter.write_text('0')
        failure = f"!sh -c 'count=$(cat \"{escaped}\"); echo $((count + 1)) > \"{escaped}\"; exit 1'"
        assert run('twice', failure) == 'none|none|none'
        assert counter.read_text().strip() == '2', 'failed commands are cached too'
        print(f'{backend}: caches successful and failed commands until explicitly cleared', flush=True)
        counter.write_text('0')
        assert run('uncached', success) == 'some:value|some:value'
        assert counter.read_text().strip() == '2'
        print(f'{backend}: uncached resolution executes a command on every call', flush=True)
print('config_value_check: PASS')

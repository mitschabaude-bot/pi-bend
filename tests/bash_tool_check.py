"""Public Bash AgentTool contracts, with injected and native operations."""
import argparse
import base64
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['native-1', 'native-4'])
p.add_argument('--prefix', type=Path, default=ROOT / 'build/bash-tool')
a = p.parse_args()


def text(encoded):
    return base64.b64decode(encoded, validate=True).decode('utf-8')


def detail(parts):
    if parts[0] == 'none':
        return None
    if parts[0] == 'present':
        return {'path': None if parts[1] == '-' else text(parts[1])}
    assert parts[0] == 'trunc' and parts[1] == 'true', parts
    return dict(truncated=True, cause=parts[2], total_lines=int(parts[3]), total_bytes=int(parts[4]),
                lines=int(parts[5]), bytes=int(parts[6]), partial=parts[7] == 'true',
                path=None if parts[8] == '-' else text(parts[8]))


def parse(lines):
    result = {'updates': [], 'calls': [], 'hooks': [], 'outcomes': [], 'lines': lines}
    for line in lines:
        parts = line.split('|')
        if parts[0] in ['result', 'update']:
            value = {'blocks': int(parts[1]), 'text': text(parts[2]), 'details': detail(parts[3:])}
            result['updates' if parts[0] == 'update' else 'outcomes'].append(value)
        elif parts[0] == 'error':
            result['outcomes'].append({'error': text(parts[1])})
        elif parts[0] in ['call', 'hook']:
            result['calls' if parts[0] == 'call' else 'hooks'].append(
                {'command': text(parts[1]), 'cwd': text(parts[2]),
                 'env': [None if x == '-' else text(x) for x in parts[3:]]})
        else:
            assert line in ['closed', 'late|ignored'], line
    return result


for backend in a.backends:
    prefix = (['bun', str(a.prefix.with_suffix('.js'))] if backend == 'bun'
              else [str(a.prefix), '--threads', backend.removeprefix('native-')])
    count = 0
    created = set()
    with tempfile.TemporaryDirectory(prefix='public bash ') as folder:
        directory = Path(folder)
        bin_dir = directory / 'bin'
        bin_dir.mkdir()
        child_env = {**os.environ, **{key: 'stale' for key in
            ['PI_SESSION_ID', 'PI_SESSION_FILE', 'PI_PROVIDER', 'PI_MODEL', 'PI_REASONING_LEVEL']}}
        child_env.pop('HOOK_MARKER', None)

        def run(mode, command='remote', seconds='none', shell='/missing/custom-shell', cwd=directory, repeats=1):
            global count
            started = time.monotonic()
            completed = subprocess.run(prefix + [mode, str(bin_dir), str(cwd), shell, command, seconds, str(repeats)],
                                       capture_output=True, text=True, env=child_env, timeout=30)
            assert completed.returncode == 0 and not completed.stderr, (mode, completed.stdout[-2000:], completed.stderr)
            lines = completed.stdout.splitlines()
            assert lines.count('closed') == repeats and lines[-1] == 'closed', lines[-6:]
            value = parse(lines)
            assert len(value['outcomes']) == repeats, value
            # Full output is an intentional user-visible artifact; read it before
            # the test removes its own private temporary file and directory.
            for outcome in value['outcomes'] + value['updates']:
                path = (outcome.get('details') or {}).get('path')
                if path:
                    created.add(Path(path))
                for match in re.finditer(r'Full output: ([^\]\n]+)', outcome.get('text', '') + outcome.get('error', '')):
                    created.add(Path(match[1]))
            value['seconds'] = time.monotonic() - started
            count += 1
            return value

        def ok(value, expected):
            outcome = value['outcomes'][0]
            assert outcome.get('text') == expected and outcome['blocks'] == 1, outcome
            return outcome

        def failed(value, expected):
            assert value['outcomes'] == [{'error': expected}], value['outcomes']

        ordinary = run('mock')
        assert ok(ordinary, 'partial\n')['details'] is None
        assert ordinary['calls'][0]['env'] == [None] * 6
        assert ordinary['updates'][0] == {'blocks': 0, 'text': '', 'details': None}
        assert ordinary['updates'][-1]['text'] == 'partial\n'
        assert all(update['details'] is not None for update in ordinary['updates'][1:])
        assert ok(run('mock-empty'), '(no output)')['details'] is None
        assert ok(run('mock-split'), '€\n')['details'] is None
        failed(run('mock-nonzero'), 'partial\n\n\nCommand exited with code 7')
        failed(run('mock-null'), 'partial\n\n\nCommand terminated without an exit code')
        failed(run('mock-abort'), 'partial\n\n\nCommand aborted')
        failed(run('mock-timeout'), 'partial\n\n\nCommand timed out after 5 seconds')
        failed(run('mock-error'), 'injected failure')
        invalid = run('mock-invalid')
        failed(invalid, 'Bash tool input is invalid. Expected a command and optional numeric timeout.')
        assert not invalid['calls'] and not invalid['updates']
        failed(run('mock', seconds='bad-type'), 'Bash tool input is invalid. Expected a command and optional numeric timeout.')
        # Injected operations bypass local shell lookup and receive prefixed
        # commands, overridden cwd and the final environment after spawnHook.
        prefixed = run('mock-prefix', 'command')
        assert prefixed['calls'][0]['command'] == 'prefix\ncommand'
        hooked = run('mock-hook', 'command')
        assert hooked['hooks'][0]['command'] == 'prefix\ncommand'
        assert hooked['calls'][0]['command'] == 'prefix\ncommand\nhooked'
        assert hooked['calls'][0]['cwd'] == str(directory) + '/hooked'
        assert hooked['calls'][0]['env'] == [None] * 5 + ['yes']
        rejected = run('mock-hook-fail')
        failed(rejected, 'hook failed')
        assert not rejected['calls'] and not rejected['updates']
        exposed = run('mock-context')
        assert exposed['calls'][0]['cwd'] == str(directory) + '/context'
        assert exposed['calls'][0]['env'] == ['session-A', '/tmp/session.json', 'openai', 'model-A', 'high', None]
        assert run('mock-hidden')['calls'][0]['env'] == [None] * 6
        late = run('mock-late')
        ok(late, 'partial\n')
        result_index = next(i for i, line in enumerate(late['lines']) if line.startswith('result|'))
        assert late['lines'][result_index + 1:] == ['late|ignored', 'closed'], late['lines']
        many = run('mock-lines')
        value = many['outcomes'][0]
        d = value['details']
        assert d['truncated'] and d['cause'] == 'lines' and d['total_lines'] == 3000 and d['lines'] == 2000, d
        raw = ''.join(f'{i}\n' for i in range(1, 3001))
        assert Path(d['path']).read_text() == raw
        assert value['text'] == '\n'.join(str(i) for i in range(1001, 3001)) + f'\n\n[Showing lines 1001-3000 of 3000. Full output: {d["path"]}]'
        for mode, ending in [('mock-lines-abort', 'Command aborted'), ('mock-lines-timeout', 'Command timed out after 5 seconds')]:
            value = run(mode)['outcomes'][0]['error']
            match = re.search(r'Full output: ([^\]\n]+)', value)
            assert match and Path(match[1]).read_text() == raw and value.endswith('\n\n' + ending), value[-300:]
        partial = run('mock-partial')['outcomes'][0]
        d = partial['details']
        assert d['truncated'] and d['cause'] == 'bytes' and d['partial'] and d['bytes'] == 51200 and d['total_bytes'] == 60000, d
        assert Path(d['path']).read_bytes() == b'x' * 60000
        assert partial['text'] == 'x' * 51200 + f'\n\n[Showing last 50.0KB of line 1 (line is 58.6KB). Full output: {d["path"]}]'
        chatty = run('mock-chatty')
        assert len(chatty['updates']) < 25, len(chatty['updates'])
        assert '5000\n' in chatty['outcomes'][0]['text']
        assert chatty['updates'][-1]['details']['path'] == chatty['outcomes'][0]['details']['path']
        # Borrowed operation/hook/update callbacks are disposed by this fixture;
        # an erroneous tool-owned disposal therefore fails the runtime above.
        repeated = run('mock', repeats=32)
        assert all(x.get('text') == 'partial\n' for x in repeated['outcomes'])

        if backend != 'bun':
            def native(command, mode='native', **kwargs):
                return run(mode, command, shell=kwargs.pop('shell', '/bin/sh'), **kwargs)
            combined = native('printf hello; printf world >&2')['outcomes'][0]['text']
            assert combined in ['helloworld', 'worldhello']
            ok(native('true'), '(no output)')
            ok(native('printf "command-output\\n"', 'native-prefix'), 'prefix-output\ncommand-output\n')
            ok(native('test -c /dev/stdin && ! test -p /dev/stdin && printf null'), 'null')
            failed(native('printf before; exit 7'), 'before\n\nCommand exited with code 7')
            failed(native('printf before; kill -TERM $$'), 'before\n\nCommand exited with code 143')
            failed(native('printf before; sleep 5', seconds='.12'), 'before\n\nCommand timed out after 0.12 seconds')
            failed(native('printf before; sleep 5', 'native-abort'), 'before\n\nCommand aborted')
            missing = directory / 'missing cwd'
            failed(native('true', cwd=missing), f'Working directory does not exist: {missing}\nCannot execute bash commands.')
            failed(native('true', shell='/missing/custom-shell'), 'Custom shell path not found: /missing/custom-shell')
            for invalid in ['0', '-1', 'nan', 'inf']:
                failed(native('true', seconds=invalid, shell='/missing/custom-shell'), 'Invalid timeout: must be a finite number of seconds')
            failed(native('true', seconds='2147483.648', shell='/missing/custom-shell'), 'Invalid timeout: maximum is 2147483.647 seconds')
            failed(native('true', 'native-preabort', shell='/missing/custom-shell'), 'Command aborted')
            failed(native('true', 'native-preabort', seconds='nan', shell='/missing/custom-shell'), 'Invalid timeout: must be a finite number of seconds')
            repeated = native('ls /proc/$PPID/fd | wc -l', repeats=32)
            counts = [int(value['text']) for value in repeated['outcomes']]
            assert len(set(counts)) == 1 and counts[0] < 25, counts
        for artifact in created:
            assert artifact.is_file(), artifact
            # Remove only spill artifacts created by this fixture.
            artifact.unlink()
            try:
                artifact.parent.rmdir()
            except OSError:
                pass
        print(f'{backend}: {count} public Bash scenarios, retained-late-output ignored, spill bytes and callback/resource cleanup PASS', flush=True)

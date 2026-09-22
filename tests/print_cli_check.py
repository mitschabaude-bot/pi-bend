"""Native print-mode CLI: argument handling, help/version, exit behavior and
(optionally) live text/JSON runs against the OpenAI Responses API.

Build first: BEND_TUS=8 sh scripts/build-pure.sh packages/coding-agent/src/main.bend build/pi-cli
Live checks run when PI_BEND_LIVE=1 and OPENAI_API_KEY are set."""
import json, os, pathlib, re, subprocess, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM = ROOT.parent / 'pi-mono'
CLI = ROOT / 'build/pi-cli'

def source(path):
    return subprocess.check_output(['git', '-C', str(UPSTREAM), 'show', f'46c9de402:packages/coding-agent/{path}'], text=True)

def run(args, stdin=b'', env=None, timeout=120, cwd=ROOT):
    merged = dict(os.environ)
    merged.update(env or {})
    return subprocess.run([str(CLI), '--', *args], input=stdin, capture_output=True, env=merged, timeout=timeout, cwd=cwd)

def expected_help():
    text = source('src/cli/args.ts')
    start = text.index('console.log(`') + len('console.log(`')
    end = text.index('`);', start)
    body = text[start:end]
    body = re.sub(r'\$\{chalk\.bold\("([^"]*)"\)\}', r'\1', body)
    body = body.replace('${chalk.bold(APP_NAME)}', 'pi').replace('${APP_NAME}', 'pi').replace('${extensionFlagsText}', '')
    body = body.replace('${CONFIG_DIR_NAME}', '.pi')
    body = body.replace('${ENV_AGENT_DIR.padEnd(32)}', 'PI_CODING_AGENT_DIR'.ljust(32)).replace('${ENV_SESSION_DIR.padEnd(32)}', 'PI_CODING_AGENT_SESSION_DIR'.ljust(32))
    assert '${' not in body
    return body

def check(condition, name):
    if not condition:
        raise SystemExit(f'FAIL {name}')
    print(f'PASS {name}', flush=True)

version = run(['--version'])
check(version.returncode == 0 and version.stdout == (json.loads(source('package.json'))['version'] + '\n').encode() and version.stderr == b'', 'prints the version and exits 0')

help_ = run(['--help'])
check(help_.returncode == 0 and help_.stdout.decode() == expected_help() + '\n' and help_.stderr == b'', 'prints the upstream help text')

bad_mode = run(['--mode', 'bad', '-p', 'x'])
check(bad_mode.returncode == 1 and bad_mode.stdout == b'' and bad_mode.stderr.startswith(b'Error: '), 'invalid --mode reports an error and exits 1')

missing = run(['--model'])
check(missing.returncode == 1 and b'Error:' in missing.stderr, 'a flag without its value exits 1')

bad_tui = run(['--tui-mode', 'bogus', '-p', 'x'])
check(bad_tui.returncode == 1 and b'Error:' in bad_tui.stderr, 'invalid --tui-mode exits 1')

file_missing = run(['-p', '@/nonexistent/prompt.md'], stdin=b'')
check(file_missing.returncode == 1 and b'File not found' in file_missing.stderr, 'a missing @file exits 1 with a message')

unsupported = run(['--provider', 'nope', '--model', 'x', '-p', 'hi'])
check(unsupported.returncode == 1 and b'Unknown provider "nope"' in unsupported.stderr, 'an unknown provider exits 1')

if os.environ.get('PI_BEND_LIVE') == '1' and os.environ.get('OPENAI_API_KEY'):
    text = run(['--no-tools', '--model', 'gpt-4.1-mini', '-p', 'Reply with exactly the word pong'], timeout=300)
    check(text.returncode == 0 and text.stdout.decode().strip().lower().rstrip('.') == 'pong' and text.stderr == b'', 'text mode prints the final assistant text')

    piped = run(['--no-tools', '--model', 'gpt-4.1-mini', '-p'], stdin=b'Reply with exactly the word ping\n', timeout=300)
    check(piped.returncode == 0 and piped.stdout.decode().strip().lower().rstrip('.') == 'ping', 'piped stdin becomes the prompt')

    events = run(['--no-tools', '--model', 'gpt-4.1-mini', '--mode', 'json', '-p', 'Reply with exactly the word pong'], timeout=300)
    lines = [json.loads(line) for line in events.stdout.decode().splitlines()]
    types = [event['type'] for event in lines]
    header = lines[0]
    check(events.returncode == 0 and header['type'] == 'session' and header['version'] == 3 and re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}', header['id']) and header['cwd'] == str(ROOT), 'JSON mode starts with the session header')
    compact = [t for t in types if t != 'message_update']
    check(compact == ['session', 'agent_start', 'turn_start', 'message_start', 'message_end', 'message_start', 'message_end', 'turn_end', 'agent_end'], 'JSON mode emits the upstream event sequence')
    updates = [event for event in lines if event['type'] == 'message_update']
    check(updates and all('partial' not in event['assistantMessageEvent'] for event in updates) and all(set(event) == {'type', 'usage', 'assistantMessageEvent'} for event in updates), 'message_update events carry usage and snapshot-free assistant events')
    final = [event for event in lines if event['type'] == 'message_end'][-1]['message']
    check(final['role'] == 'assistant' and final['stopReason'] == 'stop' and final['content'][0]['type'] == 'text', 'the final assistant message is complete')

    with tempfile.TemporaryDirectory(prefix='pi-native-cli-tools-') as folder:
        task = run(['--tools', 'read,write', '--model', 'gpt-4.1-mini', '--mode', 'json', '-p',
                    'Use the write tool to create result.txt in the current directory with exactly the text native-cli-integration followed by a newline. Then use the read tool to verify its contents.'],
                   cwd=folder, env={'PI_CODING_AGENT_DIR': str(pathlib.Path(folder) / 'agent')}, timeout=300)
        check(task.returncode == 0 and task.stderr == b'', 'the native CLI completes a real tool task')
        check((pathlib.Path(folder) / 'result.txt').read_bytes() == b'native-cli-integration\n', 'the write tool persists the requested contents')
        task_events = [json.loads(line) for line in task.stdout.decode().splitlines()]
        completed = [event for event in task_events if event['type'] == 'tool_execution_end']
        check({'read', 'write'} <= {event['toolName'] for event in completed} and all(not event['isError'] for event in completed), 'read and write complete through the public tool registry')
        check(task_events[-1]['type'] == 'agent_end', 'the tool loop finishes with agent_end')

    wrong = run(['--no-tools', '--model', 'gpt-4.1-mini', '--api-key', 'sk-invalid', '-p', 'hi'], timeout=300)
    check(wrong.returncode == 1 and wrong.stdout == b'' and wrong.stderr.strip() != b'', 'a rejected request exits 1 with the error on stderr')
if os.environ.get('PI_BEND_CODEX_LIVE') == '1':
    codex = run(['--no-tools', '--provider', 'openai-codex', '--model', 'gpt-5.5', '-p', 'Reply with exactly the word pong'],
                env={'OPENAI_API_KEY': ''}, timeout=300)
    check(codex.returncode == 0 and codex.stdout.decode().strip().lower().rstrip('.') == 'pong' and codex.stderr == b'', 'Codex runs through the existing OAuth login')

print('print_cli_check: all checks passed', flush=True)

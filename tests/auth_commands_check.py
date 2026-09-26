"""upstream auth-check.test.ts and credential-print.test.ts (tests/auth-commands.bend).

Runs with provider API-key variables removed from the environment and a fresh
temporary directory per lane. The CLI case "reports unknown auth options like
package commands" runs against a built CLI when one is given.
Usage: python3 tests/auth_commands_check.py [build/auth-commands.js] [build/auth-commands] [--cli build/pi-cli]
"""
import argparse, os, pathlib, subprocess, tempfile

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('js', nargs='?', default='build/auth-commands.js')
parser.add_argument('native', nargs='?', default='build/auth-commands')
parser.add_argument('--cli')
args = parser.parse_args()
env = {k: v for k, v in os.environ.items() if not (k.endswith('_API_KEY') or k.endswith('_TOKEN') or k.startswith('PI_') or k.startswith('AWS_'))}
lanes = []
if os.path.exists(root / args.js):
    lanes.append(('bun', ['bun', args.js]))
if os.path.exists(root / args.native):
    lanes += [('native-1', [args.native, '--threads', '1', '--']), ('native-4', [args.native, '--threads', '4', '--'])]
assert lanes or args.cli, 'build tests/auth-commands.bend first'
for name, command in lanes:
    with tempfile.TemporaryDirectory(prefix='pi-test-auth-check-') as directory:
        result = subprocess.run(command + [directory, str(root)], cwd=root, capture_output=True, text=True, timeout=600, env=env)
        lines = result.stdout.splitlines()
        assert result.returncode == 0 and len(lines) == 14 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr[-3000:])
        print(f'{name}: {len(lines)} auth check/credential print cases pass')
if args.cli:
    with tempfile.TemporaryDirectory(prefix='pi-auth-cli-') as directory:
        cli_env = dict(env, PI_CODING_AGENT_DIR=directory, PI_OFFLINE='1')
        result = subprocess.run([str(pathlib.Path(args.cli).resolve()), 'auth', 'check', '--provider', 'openai-codex', '--credentails'], cwd=directory, capture_output=True, text=True, timeout=120, env=cli_env)
        assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
        assert 'Unknown option --credentails for "auth check".' in result.stderr, result.stderr
        assert 'Use "pi --help" or "pi auth check --provider <provider> [--json] [--credentials] [--no-refresh]".' in result.stderr, result.stderr
        print('cli: credential print commands reports unknown auth options like package commands')

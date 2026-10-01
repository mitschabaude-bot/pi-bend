#!/usr/bin/env python3
"""Runs the native ports of upstream's SDK and extension-example suites on Bun
and native lanes: each program prints `ok <upstream test name>` per passing
test (or `SKIP <name>` where the Bun lane lacks a process primitive) and dies
on a failure. Programs that need a temp directory get a fresh one.

  bun build/bend-native-toolchain/bend2/main.ts tests/<suite>.bend -o build/<suite>.js
  sh scripts/build-pure.sh tests/<suite>.bend build/<suite>-native
  # sdk-stream-options uses packages/coding-agent/test/sdk-stream-options.bend.
  python3 tests/sdk_suites_check.py [--prefix build/] [--lanes bun,native-1,native-4] [suite ...]
"""
import argparse, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# suite -> (upstream test names in order, needs a temp dir, names that run
# bash and so are skipped on Bun)
SUITES = {
    'plan-mode-extension': ([
        'preserves custom active tools while toggling plan mode',
        'does not prompt when the assistant response contains no plan',
        'queues plan refinement as a follow-up user message',
        'queues plan execution as a follow-up custom message',
    ], False, set()),
    'compaction-extensions-example': ([
        'custom compaction example should type-check correctly',
        'custom compaction example dispatches through modelRegistry.complete',
        'compact event should have correct fields',
    ], False, set()),
    'sdk-session-manager': ([
        'uses agentDir for the default persisted session path',
        'keeps an explicit sessionManager override',
        'derives cwd from an explicit sessionManager when cwd is omitted',
        'exposes current session state to the built-in bash tool',
        'registers SDK custom tools through the session registry',
        'exposes session state before custom bash spawn hooks and supports opting out',
    ], True, {'derives cwd from an explicit sessionManager when cwd is omitted', 'exposes current session state to the built-in bash tool'}),
    'sdk-skills': ([
        'should discover skills by default and expose them on session.skills',
        'should have empty skills when resource loader returns none (--no-skills)',
        'should use provided skills when resource loader supplies them',
    ], True, set()),
    'sdk-stream-options': ([
        'forwards httpIdleTimeoutMs as timeoutMs for OpenAI Codex',
        'defaults timeoutMs from httpIdleTimeoutMs for all providers',
        'lets request timeoutMs override httpIdleTimeoutMs for OpenAI Codex',
        'forwards websocketConnectTimeoutMs from settings',
        'lets request websocketConnectTimeoutMs override settings',
        'forwards provider retry settings',
        'before_provider_headers preserves existing headers and inserts new ones',
        'before_provider_headers isolates a throwing handler and applies the next',
        'runs before_provider_headers on assembled headers without forwarding the transform',
        'SDK stream options disposed',
    ], True, set()),
}


def command(prefix, suite, lane):
    if lane == 'bun':
        return ['bun', str(ROOT / (prefix + suite + '.js'))]
    return [str(ROOT / (prefix + suite + '-native'))]


def run(prefix, suite, lane):
    names, needs_dir, bash = SUITES[suite]
    args = command(prefix, suite, lane)
    env = dict(os.environ)
    if lane != 'bun':
        env['BEND_THREADS'] = lane.split('-')[1]
    with tempfile.TemporaryDirectory(prefix='pi-sdk-' + suite + '-') as temp:
        result = subprocess.run(args + ([temp] if needs_dir else []), capture_output=True, text=True, timeout=600, cwd=ROOT, env=env)
    lines = [line for line in result.stdout.splitlines() if line.startswith(('ok ', 'SKIP '))]
    assert result.returncode == 0, (suite, lane, result.stdout[-2000:], result.stderr[-2000:])
    verdicts = [(line.split(' ', 1)[0], line.split(' ', 1)[1]) for line in lines]
    assert [name for _, name in verdicts] == names, (suite, lane, verdicts)
    skipped = {name for verdict, name in verdicts if verdict == 'SKIP'}
    assert skipped == (bash if lane == 'bun' else set()), (suite, lane, skipped)
    print(f'{suite} {lane}: {len(names) - len(skipped)} pass' + (f', {len(skipped)} skipped (no process primitive)' if skipped else ''))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('suites', nargs='*', default=list(SUITES))
    parser.add_argument('--prefix', default='build/sdk-suites/')
    parser.add_argument('--lanes', default='bun,native-1,native-4')
    args = parser.parse_args()
    for suite in args.suites:
        for lane in args.lanes.split(','):
            run(args.prefix, suite, lane)


if __name__ == '__main__':
    main()

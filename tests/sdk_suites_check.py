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
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# suite -> (upstream test names in order, needs a temp dir, names that run
# bash and so are skipped on Bun)
SUITES = {
    'sdk-extension-metadata': ([
        'metadata and command actions reject calls during loading',
        'assistant output flushes the metadata journal',
        'extension getter reports an unnamed session',
        'emits session_info_changed when AgentSession.setSessionName is called',
        'emits session_info_changed when an extension calls pi.setSessionName',
        'emits session_info_changed to extensions',
        'extension names normalize newlines and clear whitespace-only names',
        'extension labels update and clear the session tree',
        'extension labels reject nonexistent entries without changing history',
        'extension command discovery preserves resolved names, order, descriptions and source metadata',
        'retired metadata and command actions reject after SDK disposal',
    ], True, set()),
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
        'schedules cache warming after a completed session request',
        'waits for the next request instead of restoring cache warming',
    ], True, set()),
    'sdk-provider-events': ([
        'payload handlers replace in order, retain None, and continue after failure',
        'payload failure emits exactly one extension error',
        'response handler keeps status and headers after an earlier handler fails',
        'response failure emits exactly one extension error',
        'session reload creates a new extension generation',
        'reusable factory runs once on reload',
        'payload handlers replace in order, retain None, and continue after failure',
        'payload failure emits exactly one extension error',
        'response handler keeps status and headers after an earlier handler fails',
        'response failure emits exactly one extension error',
        'SDK provider hooks follow the reloaded runner and dispose',
    ], True, set()),
    'sdk-model-events': ([
        'extension thinking actions reject calls during loading',
        'setThinkingLevel returns before a blocked thinking handler and exposes updated state',
        'thinking selection isolates a failing handler',
        'unchanged thinking level emits no selection event',
        'setModel saves the model to the session and emits model_select',
        'model switch clamps thinking and reports effective previous and current levels',
        'model and thinking handler failures remain isolated',
        'same provider and id with changed metadata does not notify',
        'cycleModel reports cycle source and previous current model',
        'auth failure emits no model selection',
        'extension getter reads the bound session thinking level',
        'extension setter records and announces the session level without changing defaults',
        'extension no-op thinking change records and emits nothing',
        'extension thinking setter clamps to current model capabilities',
        'extension model actions remain bound after thinking changes',
        'detached thinking handler can finish after SDK disposal',
        'retired extension thinking actions reject before accessing disposed session callbacks',
        'SDK model events disposed',
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
        if suite == 'sdk-extension-metadata' and result.returncode == 0:
            journals = list(Path(temp).rglob('*.jsonl'))
            assert len(journals) == 1, journals
            entries = [json.loads(line) for line in journals[0].read_text().splitlines()]
            assert [entry.get('name') for entry in entries if entry['type'] == 'session_info'] == ['hello world', 'from extension', 'first', 'second', 'line name', '']
            labels = [entry for entry in entries if entry['type'] == 'label']
            assert [entry.get('label') for entry in labels] == ['favorite', None], labels
            assert labels[0]['targetId'] == labels[1]['targetId']
            assert labels[0]['targetId'] in {entry.get('id') for entry in entries}

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

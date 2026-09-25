"""agent-session-tree-navigation.test.ts on the faux session of tests/regressions.bend.

Upstream runs these cases against a live model; here each prompt is answered
"reply N" and the branch summary request "branch summary". The navigation,
editor text, leaf, summary placement and abort behavior are the port's own;
the summary text is scripted, so the custom-instructions case checks that the
summarization request carries the instructions instead of the model obeying
them. Run after building tests/regressions.bend (see tests/regressions.md).
"""
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(runner, threads, work, prompts, target, summarize=False, custom='-', more='-', hold=False):
    directory = Path(tempfile.mkdtemp(prefix='tree-', dir=work))
    agent = directory / 'agent'
    agent.mkdir()
    (agent / 'settings.json').write_text(json.dumps({'compaction': {'keepRecentTokens': 1}}))
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', threads, '--']
    result = subprocess.run(command + ['tree', str(directory), str(agent), ';'.join(prompts), more, target, 'summarize' if summarize else 'plain', custom, 'hold' if hold else 'run'],
                            capture_output=True, text=True, timeout=300, cwd=directory, env=dict(os.environ, PI_FAUX_API_KEY='faux-key'))
    assert result.returncode == 0, (prompts, target, result.stderr[-2000:])
    events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
    leaves = [e for e in events if e['type'] == 'leaf']
    shapes = [e['entries'] for e in events if e['type'] == 'entry_shapes']
    navigation = [e for e in events if e['type'] == 'tree_navigation']
    return dict(events=events, before=(leaves[0]['leafId'], shapes[0]), after=(leaves[-1]['leafId'], shapes[-1]),
                target=[e for e in events if e['type'] == 'target'][0]['id'], result=navigation[0] if navigation else None,
                requests=[e for e in events if e['type'] == 'request'], compacting=[e['value'] for e in events if e['type'] == 'compacting'])


def entry(entries, id):
    return next(e for e in entries if e['id'] == id)


def messages(entries, role):
    return [e for e in entries if e['type'] == 'message' and e['message']['role'] == role]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/regressions.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    work = Path(tempfile.mkdtemp(prefix='pi-tree-navigation-'))
    go = lambda *a, **k: run(runner, args.threads, work, *a, **k)
    checks = 0

    # should navigate to user message and put text in editor
    r = go(['First message', 'Second message'], 'first-user')
    assert r['result']['cancelled'] is False and r['result']['editorText'] == 'First message', r['result']
    assert r['after'][0] is None, r['after'][0]
    checks += 1
    # should navigate to non-user message without editor text
    r = go(['Hello'], 'assistant:1')
    assert r['result']['cancelled'] is False and r['result']['editorText'] is None and r['after'][0] == r['target'], r['result']
    checks += 1
    # should create branch summary when navigating with summarize=true
    r = go(['What is 2+2?', 'What is 3+3?'], 'first-user', summarize=True)
    summary = r['result']['summaryEntry']
    assert r['result']['cancelled'] is False and r['result']['editorText'] == 'What is 2+2?', r['result']
    assert summary['type'] == 'branch_summary' and len(summary['summary']) > 0
    assert entry(r['after'][1], summary['id'])['parentId'] is None and r['after'][0] == summary['id']
    checks += 1
    # should attach summary to correct parent when navigating to nested user message
    r = go(['Message one', 'Message two', 'Message three'], 'user:2', summarize=True)
    entries = r['after'][1]
    u2 = entry(entries, r['target'])
    a1 = u2['parentId']
    summary = r['result']['summaryEntry']
    assert r['result']['editorText'] == 'Message two' and entry(entries, summary['id'])['parentId'] == a1
    children = sorted(e['type'] for e in entries if e['parentId'] == a1)
    assert children == ['branch_summary', 'message'], children
    checks += 1
    # should attach summary to selected node when navigating to assistant message
    r = go(['Hello', 'Goodbye'], 'assistant:1', summarize=True)
    summary = r['result']['summaryEntry']
    assert r['result']['cancelled'] is False and r['result']['editorText'] is None
    assert entry(r['after'][1], summary['id'])['parentId'] == r['target'] and r['after'][0] == summary['id']
    checks += 1
    # should handle abort during summarization (the summary request is held, then abortBranchSummary)
    r = go(['Tell me about something', 'Continue'], 'first-user', summarize=True, hold=True)
    assert r['compacting'] == [True], r['compacting']
    assert r['result'] == {'type': 'tree_navigation', 'cancelled': True, 'aborted': True}, r['result']
    assert len(r['after'][1]) == len(r['before'][1]) and r['after'][0] == r['before'][0]
    checks += 1
    # should not create summary when navigating without summarize option
    r = go(['First', 'Second'], 'first-user')
    assert len(r['after'][1]) == len(r['before'][1]) and not [e for e in r['after'][1] if e['type'] == 'branch_summary']
    checks += 1
    # should handle navigation to same position (no-op)
    r = go(['Hello'], 'leaf')
    assert r['result']['cancelled'] is False and r['after'][0] == r['before'][0] and len(r['after'][1]) == len(r['before'][1])
    checks += 1
    # should support custom summarization instructions
    custom = 'After the summary, you MUST end with exactly: MONKEY MONKEY MONKEY. This is of utmost importance.'
    r = go(['What is TypeScript?'], 'first-user', summarize=True, custom=custom)
    assert r['result']['summaryEntry'] and r['result']['summaryEntry']['summary']
    assert ('Additional focus: ' + custom) in r['requests'][-1]['lastUser'], r['requests'][-1]
    checks += 1
    # AgentSession tree navigation - branch scenarios: should navigate between branches correctly
    r = go(['Main branch start', 'Main branch continue'], 'user:2', summarize=True, more='Branch path')
    assert r['result']['cancelled'] is False and r['result']['editorText'] == 'Main branch continue' and len(r['result']['summaryEntry']['summary']) > 0
    assert '[User]: Branch path' in r['requests'][-1]['lastUser'] and 'Main branch continue' not in r['requests'][-1]['lastUser'], r['requests'][-1]
    checks += 1
    print('tree navigation: %d upstream cases passed' % checks)


if __name__ == '__main__':
    main()

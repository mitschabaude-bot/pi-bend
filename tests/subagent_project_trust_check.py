"""Port of pi-mono test/suite/regressions/8261-subagent-project-trust.test.ts.

tests/subagent-project-trust.bend runs the native subagent example extension
(packages/coding-agent/examples/extensions/subagent) in a harness session and
prints the confirmation count and the session messages; the assertions in
checks() are upstream's. native_checks() is a native-lane supplement: the
subagent processes themselves, which upstream's regression never reaches.
"""
import argparse, re, tempfile
from pathlib import Path

from regressions_check import Fixtures, last, text_of

RUNNERS = ['subagent-project-trust']


def run_project_agent(f, trusted):
    events = f.session('subagent-project-trust', 'trusted' if trusted else 'untrusted')
    tool_result = next(m for m in last(events, 'messages')['messages'] if m['role'] == 'toolResult')
    return last(events, 'confirm_calls')['count'], text_of(tool_result)


def checks(f):
    count = 0
    # skips per-call confirmation for trusted projects
    confirm_calls, tool_result = run_project_agent(f, trusted=True)
    assert confirm_calls == 0, confirm_calls
    assert 'Canceled:' not in tool_result, tool_result
    count += 1
    # keeps confirmation for untrusted interactive projects
    confirm_calls, tool_result = run_project_agent(f, trusted=False)
    assert confirm_calls == 1, confirm_calls
    assert 'Canceled: project-local agents not approved.' in tool_result, tool_result
    count += 1
    return count


def subagent_run(f, kind):
    events = f.session('subagent-project-trust', 'run', kind)
    tool_result = next(m for m in last(events, 'messages')['messages'] if m['role'] == 'toolResult')
    updates = [e['partialResult'] for e in events if e['type'] == 'tool_execution_update']
    return text_of(tool_result), tool_result['details'], updates


def fake_echo(task, args, prompt):
    """The fake pi's reply (tests/subagent-project-trust.bend fakeOutput)."""
    return 'echo Task: %s | args %s Task: %s | prompt %s' % (task, args, task, prompt)


PROMPT = re.compile(r'--append-system-prompt (\S+/pi-subagent-[^/\s]+/prompt-worker\.md)')
WORKER_ARGS = '-p --no-session --model sub-model --tools read,bash --append-system-prompt %s'


def worker_echo(task, text):
    """The worker's reply, with the temporary system prompt file it was given."""
    prompt_file = PROMPT.search(text).group(1)
    assert not Path(prompt_file).exists() and not Path(prompt_file).parent.exists(), prompt_file
    return fake_echo(task, WORKER_ARGS % prompt_file, 'You are the worker.')


def usage_of(result):
    return result['usage']


def native_checks(f):
    """Native supplement (the Bun lane has no process primitives): the three
    modes against the test binary acting as a fake `pi --mode json`."""
    count = 0
    # single: agent model, tools and system prompt file; usage from message_end
    text, details, updates = subagent_run(f, 'single')
    assert text == worker_echo('hello', text), text
    assert details['mode'] == 'single' and details['agentScope'] == 'user', details
    [result] = details['results']
    assert (result['agent'], result['agentSource'], result['exitCode'], result['model'], result['stopReason'], result['stderr']) == ('worker', 'user', 0, 'sub-model', 'stop', ''), result
    assert usage_of(result) == {'input': 10, 'output': 5, 'cacheRead': 1, 'cacheWrite': 2, 'cost': 0.25, 'contextTokens': 18, 'turns': 1}, result
    assert len(result['messages']) == 1 and result['messages'][0]['role'] == 'assistant', result
    assert [text_of(u) for u in updates] == [text] and updates[0]['details']['results'][0]['exitCode'] == 0, updates
    count += 1
    # single without an agent model: the session's model and thinking level, no prompt file
    text, details, _ = subagent_run(f, 'inherit')
    assert re.fullmatch(re.escape('echo Task: inherit | args -p --no-session --model faux/faux-model --thinking ') + r'[a-z]+' + re.escape(' --tools read Task: inherit | prompt (none)'), text), text
    assert details['results'][0]['model'] == 'faux/faux-model', details
    count += 1
    # single failure: exit code and stderr
    text, details, _ = subagent_run(f, 'failed')
    assert text.startswith('Agent failed: boom'), text
    assert details['results'][0]['exitCode'] == 3 and details['results'][0]['stderr'].startswith('boom'), details
    count += 1
    # chain: {previous} carries the prior step's output; steps are numbered
    text, details, updates = subagent_run(f, 'chain')
    first = worker_echo('first', text)
    assert text == fake_echo('second after <%s>' % first, '-p --no-session --model faux/faux-model --thinking %s --tools read' % re.search(r'--thinking ([a-z]+)', text).group(1), '(none)'), text
    assert details['mode'] == 'chain' and [r['step'] for r in details['results']] == [1, 2], details
    assert [len(u['details']['results']) for u in updates] == [1, 2], updates
    count += 1
    # parallel: summaries in task order, unknown agents and failures reported
    text, details, updates = subagent_run(f, 'parallel')
    sections = text.split('\n\n---\n\n')
    assert sections[0].startswith('Parallel: 2/4 succeeded\n\n### [worker] completed\n\n' + worker_echo('one', sections[0])), sections[0]
    assert sections[1].startswith('### [plain] completed\n\necho Task: two | args -p --no-session --model faux/faux-model --thinking '), sections[1]
    assert re.fullmatch(r'### \[nobody\] failed\n\nUnknown agent: "nobody"\. Available agents: ("worker", "plain"|"plain", "worker")\.', sections[2]), sections[2]
    assert re.fullmatch(r'### \[worker\] failed\n\nboom\n?', sections[3]), sections[3]
    assert [(r['agent'], r['agentSource'], r['exitCode']) for r in details['results']] == [('worker', 'user', 0), ('plain', 'user', 0), ('nobody', 'unknown', 1), ('worker', 'user', 3)], details
    assert text_of(updates[-1]) == 'Parallel: 4/4 done, 0 running...', [text_of(u) for u in updates]
    count += 1
    return count


def main():
    parser = argparse.ArgumentParser()
    for name in RUNNERS:
        parser.add_argument('--' + name, default='build/' + name + '.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runners = {name: str(Path(getattr(args, name.replace('-', '_'))).resolve()) for name in RUNNERS}
    fixtures = Fixtures(runners, args.threads, Path(tempfile.mkdtemp(prefix='pi-subagent-trust-')))
    print('subagent-project-trust: %d upstream cases passed' % checks(fixtures))
    if not runners['subagent-project-trust'].endswith('.js'):
        print('subagent-project-trust: %d native subprocess checks passed' % native_checks(fixtures))


if __name__ == '__main__':
    main()

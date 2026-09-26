"""Ports of pi-mono's harness-based coding-agent suites (packages/coding-agent/test/suite).

tests/suite-harness.bend ports test/suite/harness.ts (createHarness) over the
faux provider of tests/regressions.bend; each block below names the upstream
file and test and applies its assertions to the printed session events and
reports. Adaptations are documented in tests/suite-harness.md.
"""
import argparse, json, tempfile
from pathlib import Path

from regressions_check import Fixtures, of_type, last

RUNNERS = ['suite-harness']


def roles(messages):
    return [m['role'] for m in messages]


def messages(events):
    return last(events, 'messages')['messages']


def entry_kinds(entries):
    return [e['role'] if e['type'] == 'message' else 'custom' if e['type'] == 'custom_message' else e['type'] for e in entries]


def run(f, scenario, *arguments, settings=None):
    return f.session('suite-harness', scenario, *arguments, settings=settings)


def bash_persistence_checks(f):
    """suite/agent-session-bash-persistence.test.ts. 'records bash results immediately while idle',
    'defers bash results while streaming and flushes them before the next prompt', 'executes bash commands
    and records the result', 'keeps newer bash execution tracked when an older execution finishes',
    'records bash output through custom operations' and 'streams bash output to the callback and session
    events' are the bash scenarios of tests/agent_session_check.py."""
    checks = 0
    # cancels running bash commands with abortBash
    events = run(f, 'bash_abort')
    states = {e['label']: (e['running'], e['pending']) for e in of_type(events, 'bash_state')}
    assert states['running'][0] is True and states['after_abort'][0] is False, states
    assert last(events, 'bash_result')['cancelled'] is True, events
    checks += 1
    # aborts all active bash executions
    events = run(f, 'bash_abort_all')
    assert [e['aborted'] for e in of_type(events, 'exec_signal')] == [True, True], events
    assert [e['cancelled'] for e in of_type(events, 'bash_result')] == [True, True], events
    assert last(events, 'bash_state')['running'] is False
    checks += 1
    # persists user, assistant, toolResult, and custom messages in order
    events = run(f, 'custom_order')
    assert last(events, 'sent')['ok'] is True
    # The prompt is declared by the first request, after the queued custom message.
    assert [e['type'] for e in last(events, 'entries')['entries']] == ['custom_message', 'message', 'message', 'message', 'message', 'message'], events
    assert roles(messages(events)) == ['custom', 'system', 'user', 'assistant', 'toolResult', 'assistant'], roles(messages(events))
    checks += 1
    # does not emit message_end for bash execution messages
    events = run(f, 'bash_recorded')
    between = events[[e['type'] for e in events].index('recording') + 1:[e['type'] for e in events].index('recorded')]
    assert [e['message']['role'] for e in between if e['type'] == 'message_end'] == [], between
    assert roles(messages(events))[-1] == 'bashExecution'
    checks += 1
    # persists aborted assistant messages
    events = run(f, 'aborted_assistant')
    persisted = last(events, 'persisted')['messages']
    assert last(events, 'entries')['kinds'][-1] == 'message' and persisted[-1]['role'] == 'assistant' and persisted[-1]['stopReason'] == 'aborted', persisted[-1]
    checks += 1
    return checks


def llm_roles(messages):
    """convertToLlm: custom messages become user messages; bash executions (not in these runs) too."""
    return [{'custom': 'user'}.get(m['role'], m['role']) for m in messages]


def custom_message_ordering_checks(f):
    """suite/regressions/8537-custom-message-tool-result-ordering.test.ts."""
    checks = 0
    events = run(f, 'custom_during_tool', '-')
    # appends the message after the turn's tool results instead of between call and result
    assert roles(messages(events)) == ['system', 'user', 'assistant', 'toolResult', 'custom', 'assistant'], roles(messages(events))
    checks += 1
    # keeps session entries and message events in the same order as agent state
    assert entry_kinds(last(events, 'branch')['entries']) == ['system', 'user', 'assistant', 'toolResult', 'custom', 'assistant']
    assert [e['message']['role'] for e in of_type(events, 'message_start')] == ['system', 'user', 'assistant', 'toolResult', 'custom', 'assistant']
    checks += 1
    # produces an llm history where every tool result follows its tool call
    events = run(f, 'custom_during_tool', 'and now?')
    history = messages(events)
    assert roles(history)[-2:] == ['user', 'assistant'], roles(history)
    open_calls = set()
    for message, role in zip(history, llm_roles(history)):
        if role == 'assistant':
            open_calls = {block['id'] for block in message['content'] if block['type'] == 'toolCall'}
        elif role == 'toolResult':
            assert message['toolCallId'] in open_calls, (message, open_calls)
            open_calls.discard(message['toolCallId'])
        else:
            open_calls = set()
    checks += 1
    return checks


def main():
    parser = argparse.ArgumentParser()
    for name in RUNNERS:
        parser.add_argument('--' + name, default='build/' + name + '.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runners = {name: str(Path(getattr(args, name.replace('-', '_'))).resolve()) for name in RUNNERS}
    work = Path(tempfile.mkdtemp(prefix='pi-suite-'))
    fixtures = Fixtures(runners, args.threads, work)
    checks = bash_persistence_checks(fixtures) + custom_message_ordering_checks(fixtures)
    print('suite-harness: %d upstream cases passed' % checks)


if __name__ == '__main__':
    main()

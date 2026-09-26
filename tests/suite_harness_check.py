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


def text_of(message):
    content = message.get('content')
    if isinstance(content, str):
        return content
    return '\n'.join(part['text'] for part in content or [] if part['type'] == 'text')


def extension_event_checks(f):
    """Regressions that need extension session events (message_end, tool_call, tool_result,
    agent_end, agent_settled) and the ExtensionAPI's sendUserMessage."""
    checks = 0
    # 3982-message-end-cost-override: allows extensions to replace finalized assistant usage cost
    events = run(f, 'message_end_cost')
    assistant = next(m for m in messages(events) if m['role'] == 'assistant')
    assert assistant['usage']['cost']['total'] == 0.123, assistant['usage']
    ended = next(e for e in of_type(events, 'message_end') if e['message']['role'] == 'assistant')
    assert ended['message']['usage']['cost']['total'] == 0.123, ended
    checks += 1
    # 1717-2113-agent-session-event-settlement: keeps persisted assistant/toolResult message order when
    # extension message_end handlers yield
    events = run(f, 'settled_order')
    kinds = entry_kinds(last(events, 'branch')['entries'])
    assert kinds == ['system', 'user', 'assistant', 'toolResult', 'toolResult', 'assistant'], kinds
    first = kinds.index('toolResult')
    assert first > 0 and kinds[first - 1] == 'assistant'
    checks += 1
    # 1717-2113-agent-session-event-settlement: runs tool_call handlers after the assistant tool-use message
    # is settled in the session
    events = run(f, 'tool_call_settled')
    assert [entry_kinds(e['entries']) for e in of_type(events, 'roles_at_tool_call')] == [['system', 'user', 'assistant']], events
    checks += 1
    # 5998-blocked-tool-terminate: lets a tool_call handler terminate the run after blocking execution
    events = run(f, 'blocked_terminate')
    assert last(events, 'remaining')['count'] == 1
    assert 'should not run' not in [text_of(m) for m in messages(events) if m['role'] == 'assistant']
    assert of_type(events, 'tool_execution_end')[0]['result'].get('terminate') is True, of_type(events, 'tool_execution_end')
    assert any(m['role'] == 'toolResult' and m['isError'] for m in messages(events))
    checks += 1
    # 8935-parallel-preflight-abort: does not start prepared tools after a later preflight aborts
    events = run(f, 'preflight_abort')
    assert [e['value'] for e in of_type(events, 'preflight')] == ['first', 'second']
    assert of_type(events, 'executed') == [] and of_type(events, 'result_hook') == [], events
    starts, ends = of_type(events, 'tool_execution_start'), of_type(events, 'tool_execution_end')
    assert len(starts) == 2 and len(ends) == 2
    assert {e['toolCallId'] for e in ends} == {e['toolCallId'] for e in starts}
    assert all(e['isError'] for e in ends)
    results = [m for m in messages(events) if m['role'] == 'toolResult']
    assert [m['toolCallId'] for m in results] == [e['toolCallId'] for e in starts]
    assert [text_of(m) for m in results] == ['Operation aborted', 'Operation aborted'], results
    checks += 1
    # 6363-agent-settled-event: emits one agent_settled event after automatic retry finishes
    events = run(f, 'settled_retry', settings={'retry': {'enabled': True, 'maxRetries': 3, 'baseDelayMs': 1}})
    assert [e['willRetry'] for e in of_type(events, 'agent_end')] == [True, False]
    assert len(of_type(events, 'agent_settled')) == 1
    extension = ['%s:%s' % (e['event'], str(e['idle']).lower()) if 'idle' in e else e['event'] for e in of_type(events, 'extension_event')]
    assert extension == ['agent_end', 'agent_end', 'agent_settled:true'], extension
    checks += 1
    # 6363-agent-settled-event: settles only after follow-ups queued by agent_end handlers run
    events = run(f, 'settled_follow_up')
    assert [text_of(m) for m in messages(events) if m['role'] == 'user'] == ['hello', 'status follow-up']
    assert len(of_type(events, 'agent_end')) == 2 and len(of_type(events, 'agent_settled')) == 1
    assert [e['idle'] for e in of_type(events, 'extension_event')] == [True]
    checks += 1
    # 6363-agent-settled-event: extension command waitForIdle waits for session-level settlement
    events = run(f, 'command_waits_for_idle')
    kinds = [e['type'] for e in events]
    assert kinds.index('released') < kinds.index('command_result'), kinds
    assert [e['idle'] for e in of_type(events, 'command_result')] == [True]
    assert len(of_type(events, 'agent_settled')) == 1 and [e['ok'] for e in of_type(events, 'prompted')] == [True, True]
    checks += 1
    return checks


def tree_cancel_checks(f):
    # 3688-tree-cancel-compacting: clears branch summary state when session_before_tree cancels navigation
    events = run(f, 'tree_cancel_compacting')
    assert last(events, 'tree_navigation') == {'type': 'tree_navigation', 'cancelled': True}, events
    assert last(events, 'compacting')['value'] is False
    assert last(events, 'after')['leafId'] == last(events, 'before')['leafId']
    # 9178-tree-during-compaction: rejects a second navigation while the first is waiting
    # ('rejects navigation before the active leaf can change' is in tests/regressions_check.py)
    events = run(f, 'tree_waiting')
    original = last(events, 'original')['leafId']
    assert last(events, 'tree_error')['error'] == 'Wait for the current compaction or tree navigation to finish before navigating the session tree.'
    assert last(events, 'during')['leafId'] == original
    assert last(events, 'final')['leafId'] == last(events, 'targets')['first']
    return 2


def override_settings(enabled, overrides, **compaction):
    return {'compaction': dict(({'enabled': enabled} if enabled is not None else {}), **compaction, modelOverrides=overrides)}


def compaction_override_checks(f):
    """suite/agent-session-compaction-model-overrides.test.ts (regression coverage for #8133)."""
    checks = 0
    overrides = {'faux/faux-1': {'reserveTokens': 2000, 'keepRecentTokens': 150}}
    # uses model token settings for %s compaction and extension preparation
    for path in ['manual', 'pre-prompt', 'post-run', 'overflow']:
        events = run(f, 'compaction_override', path, settings=override_settings(path != 'manual', overrides, reserveTokens=10, keepRecentTokens=20000))
        preparations = of_type(events, 'preparation')
        assert len(preparations) == 1, (path, preparations)
        assert preparations[0]['settings'] == {'enabled': path != 'manual', 'reserveTokens': 2000, 'keepRecentTokens': 150}, (path, preparations)
        assert preparations[0]['reason'] == {'manual': 'manual', 'overflow': 'overflow'}.get(path, 'threshold'), (path, preparations)
        recent = last(events, 'seeded')['userIds'][-1]
        if path in ('manual', 'pre-prompt'):
            assert preparations[0]['firstKeptEntryId'] == recent, (path, preparations, recent)
        ends = of_type(events, 'compaction_end')
        assert len(ends) == 1 and ends[0]['aborted'] is False and ends[0]['willRetry'] == (path == 'overflow'), (path, ends)
        assert ends[0]['result']['summary'] == 'compacted history'
        assert last(events, 'remaining')['count'] == 0, path
        checks += 1
    # passes resolved budgets to built-in %s summarization
    for path in ['manual', 'automatic']:
        events = run(f, 'compaction_budget', path, settings=override_settings(None, overrides, reserveTokens=10))
        assert [e['maxTokens'] for e in of_type(events, 'request')][:1] == [1600], (path, of_type(events, 'request'))
        recent = last(events, 'seeded')['userIds'][-1]
        compactions = last(events, 'compactions')['entries']
        assert compactions and compactions[0] == {'summary': 'built-in summary', 'firstKeptEntryId': recent}, (path, compactions)
        assert last(events, 'remaining')['count'] == 0
        checks += 1
    # uses the newly selected model without changing ordinary settings
    events = run(f, 'compaction_model_switch', settings=override_settings(None, {'faux/big': {'reserveTokens': 8000, 'keepRecentTokens': 150}}, reserveTokens=10))
    kinds = [e['type'] for e in events]
    assert 'compaction_start' not in kinds[:kinds.index('small_done')], kinds
    ends = of_type(events, 'compaction_end')
    assert len(ends) == 1 and ends[0]['result']['summary'] == 'big model summary', ends
    assert last(events, 'reserve')['reserveTokens'] == 10 and last(events, 'reserve_small')['reserveTokens'] == 10
    checks += 1
    return checks


ENTRY = {'id': 'entry-1', 'parentId': None, 'timestamp': '2026-01-01T00:00:00.000Z'}
USAGE = {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': 0, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}


def entry_messages(f, entry):
    return last(f.call('suite-harness', 'entry_messages', json.dumps(entry)), 'context_messages')['messages']


def lax_content_checks(f):
    """suite/lax-message-content.test.ts. The in-memory cases use the native value for missing content (an
    empty list): Bend tool results, message_end replacements and custom messages always carry content."""
    checks = 0
    # normalizes tool results from untyped tools that omit content
    events = run(f, 'lax_content', 'tool')
    results = [m for m in messages(events) if m['role'] == 'toolResult']
    assert len(results) == 1 and results[0]['content'] == [], results
    assert last(events, 'remaining')['count'] == 0
    checks += 1
    # normalizes null content in message_end extension replacements
    events = run(f, 'lax_content', 'message_end')
    assistants = [m for m in messages(events) if m['role'] == 'assistant']
    assert len(assistants) == 1 and assistants[0]['content'] == [], assistants
    checks += 1
    # normalizes null content in custom messages from extensions
    events = run(f, 'lax_content', 'custom')
    customs = [m for m in messages(events) if m['role'] == 'custom']
    assert len(customs) == 1 and customs[0]['content'] == [], customs
    checks += 1
    # normalizes null or missing content when loading session message entries
    bad = [{'role': 'user', 'content': None, 'timestamp': 1},
           {'role': 'assistant', 'content': None, 'api': 'openai-completions', 'provider': 'openai', 'model': 'test-model', 'usage': USAGE, 'stopReason': 'stop', 'timestamp': 1},
           {'role': 'toolResult', 'toolCallId': 'call_1', 'toolName': 'web_search', 'isError': False, 'timestamp': 1}]
    for message in bad:
        [loaded] = entry_messages(f, dict(ENTRY, type='message', message=message))
        assert loaded['role'] == message['role'] and loaded['content'] == [], loaded
    checks += 1
    # normalizes null content when loading custom message entries
    [loaded] = entry_messages(f, dict(ENTRY, type='custom_message', customType='test', content=None, display=False))
    assert loaded['role'] == 'custom' and loaded['content'] == [], loaded
    checks += 1
    # keeps valid message content untouched when loading session entries
    [loaded] = entry_messages(f, dict(ENTRY, type='message', message={'role': 'user', 'content': 'hello', 'timestamp': 1}))
    assert loaded['role'] == 'user' and loaded['content'] == 'hello', loaded
    checks += 1
    return checks


def queued_slash_checks(f):
    # 2023-queued-slash-command-followup: treats extension-origin queued slash-command follow-ups as raw user
    # text instead of dispatching the command
    events = run(f, 'queued_slash_follow_up')
    assert of_type(events, 'command_run') == [], events
    assert [text_of(m) for m in messages(events) if m['role'] == 'user'] == ['start', '/testcmd queued']
    assert 'queued follow-up handled by model' in [text_of(m) for m in messages(events) if m['role'] == 'assistant']
    return 1


def requests(events):
    return [e['context'] for e in of_type(events, 'request')]


def boundary(f, name, argument='-', settings=None):
    return run(f, 'boundary', name, argument, settings=settings)


def entries_of(events):
    return last(events, 'session_entries')['entries']


COMPACT_RECENT = {'compaction': {'enabled': True, 'keepRecentTokens': 1, 'reserveTokens': 0}}


def boundary_checks(f):
    """suite/agent-session-boundaries.test.ts (see tests/suite-harness.md for the cases not ported).
    `requests[i]` upstream is the i-th request of a response factory; here it is the serialized context of the
    request after the first."""
    checks = 0
    # commits a retain-none turn_end compaction and explicitly continues once
    events = boundary(f, 'handoff')
    compactions = [e for e in entries_of(events) if 'summary' in e]
    assert len(compactions) == 1 and compactions[0]['summary'] == 'exact handoff' and compactions[0]['firstKeptEntryId'] == compactions[0]['id'], compactions
    later = requests(events)[1:]
    assert len(later) == 1 and 'exact handoff' in later[0] and 'discarded prompt' not in later[0] and 'discarded response' not in later[0], later
    assert len(of_type(events, 'boundary')) == 2 and len(of_type(events, 'agent_settled')) == 1
    checks += 1
    # preserves %s queue scheduling around a turn_end handoff
    for kind in ['steering', 'follow-up', 'both']:
        events = boundary(f, 'queue', kind)
        later = requests(events)[1:]
        assert 'exact handoff' in later[0], (kind, later)
        if kind == 'steering':
            assert len(requests(events)) == 2 and 'queued steering' in later[0] and 'queued follow-up' not in later[0], (kind, later)
        elif kind == 'follow-up':
            assert len(requests(events)) == 2 and 'queued follow-up' in later[0], (kind, later)
        else:
            assert len(requests(events)) == 3 and 'queued steering' in later[0] and 'queued follow-up' not in later[0] and 'queued follow-up' in later[1], (kind, later)
        checks += 1
    # keeps a boundary replacement verbatim through threshold compaction
    events = boundary(f, 'replacement', settings=COMPACT_RECENT)
    assert of_type(events, 'compaction_start'), events
    later = requests(events)[1:]
    assert len(later) == 1 and 'EXACT-REPLACEMENT-INSTRUCTION' in later[0], len(later)
    checks += 1
    # keeps boundary input verbatim through threshold compaction when metadata follows it
    events = boundary(f, 'unsent', settings=COMPACT_RECENT)
    assert of_type(events, 'compaction_start'), events
    later = requests(events)[1:]
    assert len(later) == 1 and 'EXACT-UNSENT-INSTRUCTION' in later[0], len(later)
    checks += 1
    # continues from an agent_before_settle custom message before final settlement
    events = boundary(f, 'settle_custom')
    assert 'continue now' in requests(events)[1]
    assert {'customMessage': 'test-continuation', 'display': False} in entries_of(events)
    assert len(of_type(events, 'agent_start')) == 2 and len(of_type(events, 'agent_settled')) == 1
    checks += 1
    # persists custom context queued by agent_end before pre-settlement continuation
    events = boundary(f, 'settle_pending')
    first = of_type(events, 'boundary')[0]
    assert 'queued after agent end' in json.dumps(first['pendingMessages']) and 'queued after agent end' not in json.dumps(first['contextMessages']), first
    assert 'queued after agent end' in requests(events)[1]
    assert {'customMessage': 'agent-end-context', 'display': False} in entries_of(events)
    checks += 1
    # keeps a pre-settlement follow-up deferred until the explicit continuation would stop
    events = boundary(f, 'settle_follow_up')
    later = requests(events)[1:]
    assert len(requests(events)) == 3 and 'boundary context' in later[0] and 'queued follow-up' not in later[0] and 'queued follow-up' in later[1], later
    checks += 1
    # refreshes canonical context before publishing boundary entry notifications
    events = run(f, 'refresh_notifications')
    snapshots = of_type(events, 'append_snapshot')
    assert len(snapshots) == 2 and all('committed context' in json.dumps(e['messages']) for e in snapshots), snapshots
    checks += 1
    # persists custom context sent during pre-settlement before continuing
    events = boundary(f, 'settle_persist')
    assert len(requests(events)) == 2 and 'persist before continue' in requests(events)[1]
    assert {'customMessage': 'pending-boundary', 'display': False} in entries_of(events)
    checks += 1
    # does not consume queued input when pre-settlement drafts leave system-only context
    events = boundary(f, 'settle_system_only')
    assert len(requests(events)) == 1 and last(events, 'pending')['count'] == 1, events
    checks += 1
    # commits pre-settlement drafts but suppresses continuation when aborted during the hook
    events = run(f, 'settle_abort')
    assert len(requests(events)) == 1 and {'custom': 'committed-after-abort'} in entries_of(events)
    assert len(of_type(events, 'agent_settled')) == 1
    checks += 1
    # does not compact from usage belonging to a boundary-omitted assistant
    events = boundary(f, 'omitted_usage', settings={'compaction': {'enabled': True, 'keepRecentTokens': 1, 'reserveTokens': 300}})
    assert of_type(events, 'compaction_start') == [] and last(events, 'context_usage')['tokens'] < 2000, last(events, 'context_usage')
    checks += 1
    # does not trigger successful-response overflow from usage captured before a boundary edit
    events = boundary(f, 'edited_usage', settings=COMPACT_RECENT)
    assert of_type(events, 'compaction_start') == [] and last(events, 'context_usage')['tokens'] < 2000, last(events, 'context_usage')
    checks += 1
    # does not treat retained pre-compaction assistant usage as post-compaction usage
    assert last(run(f, 'retained_usage'), 'context_usage')['tokens'] is None
    checks += 1
    # does not let an invalid explicit continuation suppress natural tool continuation
    events = boundary(f, 'invalid_continue')
    assert len(requests(events)) == 2 and last(events, 'remaining')['count'] == 0
    checks += 1
    return checks


def durable_length_checks(f):
    """The durable length recovery block of suite/agent-session-boundaries.test.ts."""
    checks = 0
    # keeps truncated tool attempts in context for the natural next turn
    events = boundary(f, 'length_tool')
    assert of_type(events, 'executed') == [] and len(requests(events)) == 2
    assert 'may be truncated' in requests(events)[1]
    assert not [e for e in entries_of(events) if 'contextEdit' in e]
    checks += 1
    # resets length recovery after a successful intermediate assistant turn
    events = boundary(f, 'length_reset', settings={'compaction': {'keepRecentTokens': 1, 'reserveTokens': 0}})
    lengths = [e['assistant'] for e in entries_of(events) if e.get('length')]
    omitted = [e['contextEdit'] for e in entries_of(events) if 'contextEdit' in e]
    assert len(lengths) == 2 and set(lengths) <= set(omitted) and len(requests(events)) == 3, (lengths, omitted)
    checks += 1
    # gives a distinct queued follow-up its own length-recovery budget
    events = boundary(f, 'length_budget', settings={'compaction': {'keepRecentTokens': 1, 'reserveTokens': 0}})
    lengths = [e['assistant'] for e in entries_of(events) if e.get('length')]
    omitted = [e['contextEdit'] for e in entries_of(events) if 'contextEdit' in e]
    assert len(lengths) == 2 and set(lengths) <= set(omitted) and len(requests(events)) == 4, (lengths, omitted)
    checks += 1
    # finishes retry bookkeeping when a retry receives a nonretryable error
    events = boundary(f, 'retry_nonretryable', settings={'retry': {'enabled': True, 'maxRetries': 2, 'baseDelayMs': 1}})
    assert len(requests(events)) == 2
    assert {'type': 'auto_retry_end', 'success': False, 'attempt': 1, 'finalError': 'invalid_api_key'} in of_type(events, 'auto_retry_end'), of_type(events, 'auto_retry_end')
    checks += 1
    # recovers an explicit overflow error after a retained boundary replacement
    events = boundary(f, 'overflow_replacement', settings=COMPACT_RECENT)
    assert len(requests(events)) == 2
    overflow = of_type(events, 'boundary')[0]['messageEntryId']
    edits = [e for e in entries_of(events) if e.get('contextEdit') == overflow]
    assert edits and edits[-1]['omitted'] is True, edits
    checks += 1
    # keeps follow-up work behind an automatic error retry
    events = boundary(f, 'error_follow_up', settings={'retry': {'enabled': True, 'maxRetries': 2, 'baseDelayMs': 1}})
    later = requests(events)[1:]
    assert len(requests(events)) == 3 and 'queued follow-up' not in later[0] and 'queued follow-up' in later[1], later
    lifecycle = [e['type'] for e in events if e['type'] in ('agent_end', 'auto_retry_start')]
    assert lifecycle[:2] == ['agent_end', 'auto_retry_start'], lifecycle
    checks += 1
    # marks the exhausted retry run as final
    events = boundary(f, 'retry_exhausted', settings={'retry': {'enabled': True, 'maxRetries': 1, 'baseDelayMs': 1}})
    assert [e['willRetry'] for e in of_type(events, 'agent_end')] == [True, False]
    assert any(e['success'] is False and e['attempt'] == 1 for e in of_type(events, 'auto_retry_end'))
    checks += 1
    # keeps omissions and does not retry when recovery compaction fails
    events = boundary(f, 'recovery_failed', settings={'compaction': {'keepRecentTokens': 1, 'reserveTokens': 0}, 'retry': {'enabled': False, 'maxRetries': 0, 'baseDelayMs': 1}})
    entries = entries_of(events)
    assert [e for e in entries if 'contextEdit' in e] and not [e for e in entries if 'summary' in e]
    assert any(e.get('text') == 'partial response' for e in entries)
    assert 'partial response' not in json.dumps(last(events, 'session_entries')['projected'])
    assert len(requests(events)) == 2
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
    checks = bash_persistence_checks(fixtures) + custom_message_ordering_checks(fixtures) + extension_event_checks(fixtures) + tree_cancel_checks(fixtures) + compaction_override_checks(fixtures) + lax_content_checks(fixtures) + queued_slash_checks(fixtures) + boundary_checks(fixtures) + durable_length_checks(fixtures)
    print('suite-harness: %d upstream cases passed' % checks)


if __name__ == '__main__':
    main()

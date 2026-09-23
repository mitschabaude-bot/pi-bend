"""AgentSession core: prompt persistence, queue bookkeeping and recorded mutations over a faux provider.

Scenario names cite the upstream tests whose assertions they port
(suite/agent-session-runtime.test.ts, agent-session-runtime-events.test.ts, agent-queues).
"""
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run_configured(runner, threads, work, settings, scenario, *arguments):
    scenario_dir = Path(tempfile.mkdtemp(prefix=scenario + '-', dir=work))
    agent_dir = scenario_dir / 'agent'
    agent_dir.mkdir()
    (agent_dir / 'settings.json').write_text(json.dumps(settings))
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', threads, '--']
    output = subprocess.run(command + [scenario, str(scenario_dir), str(agent_dir), *arguments], capture_output=True, text=True, timeout=300, cwd=scenario_dir)
    assert output.returncode == 0, (scenario, arguments, output.stderr[-2000:])
    return [json.loads(line) for line in output.stdout.splitlines() if line.startswith('{')]

def run_retry(runner, threads, work, settings, responses, cancel='run'):
    return run_configured(runner, threads, work, {'retry': settings}, 'retry', responses, cancel)

# Scripted responses: "text#tokens" reports context usage, "~text" stops at
# the length limit, "!message" fails with that error.
def run_compact(runner, threads, work, settings, prompts, responses, action):
    return run_configured(runner, threads, work, settings, 'compact', prompts, responses, action)

def only(events, kind):
    found = [e for e in events if e['type'] == kind]
    assert len(found) == 1, (kind, found)
    return found[0]

def retry_events(events):
    return ['start:%d' % e['attempt'] if e['type'] == 'auto_retry_start' else 'end:%s' % str(e['success']).lower() for e in events if e['type'] in ('auto_retry_start', 'auto_retry_end')]

def run(runner, threads, scenario, work):
    project = work / scenario; project.mkdir()
    agent = work / (scenario + '-agent'); agent.mkdir()
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', threads, '--']
    result = subprocess.run(command + [scenario, str(project), str(agent)], capture_output=True, text=True, timeout=300, cwd=ROOT)
    assert result.returncode == 0, (scenario, result.returncode, result.stderr[-2000:], result.stdout[-1000:])
    return [json.loads(line) for line in result.stdout.splitlines()]

def types(events):
    return [e['type'] for e in events]

OVERFLOW = '!prompt is too long: 213462 tokens > 200000 maximum'
KEEP_RECENT = {'compaction': {'keepRecentTokens': 1}}

def compaction_checks(runner, threads, work):
    checks = 0
    # should trigger manual compaction via compact(); should emit compaction events; should persist compaction to session file (agent-session-compaction.test.ts); reports manual reason for compact() (#5217)
    events = run_compact(runner, threads, work, KEEP_RECENT, 'one;two', 'a1;a2;history summary;prefix summary', 'manual')
    order = [e['type'] for e in events if e['type'] in ('prompt_done', 'compaction_start', 'compaction_end', 'compact_result')]
    assert order == ['prompt_done', 'prompt_done', 'compaction_start', 'compaction_end', 'compact_result'], order
    assert only(events, 'compaction_start')['reason'] == 'manual'
    end = only(events, 'compaction_end')
    result = only(events, 'compact_result')['result']
    assert end['reason'] == 'manual' and end['aborted'] is False and end['willRetry'] is False and end['result'] == result, end
    assert result['summary'] == 'history summary\n\n---\n\n**Turn Context (split turn):**\n\nprefix summary', result
    assert result['tokensBefore'] > 0 and result['estimatedTokensAfter'] > 0 and result['firstKeptEntryId'], result
    # should maintain valid session state after compaction: the summary opens the rebuilt context
    messages = only(events, 'messages')['messages']
    assert [m['role'] for m in messages] == ['compactionSummary', 'assistant'] and messages[0]['summary'] == result['summary'], messages
    assert only(events, 'entries')['kinds'] == ['message'] * 4 + ['compaction'] and only(events, 'compacting')['value'] is False
    lines = [json.loads(l) for l in Path(only(events, 'session')['file']).read_text().splitlines()]
    stored = [l for l in lines if l['type'] == 'compaction']
    assert len(stored) == 1 and stored[0]['summary'] == result['summary'] and stored[0]['firstKeptEntryId'] == result['firstKeptEntryId'], stored
    assert stored[0]['firstKeptEntryId'] == lines[4]['id'] and lines[4]['message']['role'] == 'assistant', 'the split turn keeps its last assistant message'
    checks += 9
    # persists usage from pi-generated manual compaction: one prefix-summary request for a one-turn session
    events = run_compact(runner, threads, work, KEEP_RECENT, 'one', 'a1;prefix summary#10', 'manual')
    result = only(events, 'compact_result')['result']
    assert result['usage']['totalTokens'] == 10 and result['usage']['input'] == 10, result
    lines = [json.loads(l) for l in Path(only(events, 'session')['file']).read_text().splitlines()]
    assert [l['usage'] for l in lines if l['type'] == 'compaction'] == [result['usage']] and only(events, 'remaining')['count'] == 0
    checks += 2
    # does not persist a length-limited summary (#7048)
    events = run_compact(runner, threads, work, KEEP_RECENT, 'one', 'a1;~partial summar', 'manual')
    assert only(events, 'compact_failed')['error'] == 'Turn prefix summarization failed: generation hit the token cap and the summary is incomplete'
    assert only(events, 'compaction_end')['errorMessage'] == 'Compaction failed: ' + only(events, 'compact_failed')['error']
    assert 'compaction' not in only(events, 'entries')['kinds']
    checks += 3
    # compaction retries transient summarization failures (#6647)
    retrying = dict(KEEP_RECENT, retry={'enabled': True, 'maxRetries': 3, 'baseDelayMs': 1})
    # retries a transient `terminated` summarization error and compacts successfully
    events = run_compact(runner, threads, work, retrying, 'one', 'a1;!terminated;!terminated;recovered summary#10', 'manual')
    assert 'recovered summary' in only(events, 'compact_result')['result']['summary'] and only(events, 'remaining')['count'] == 0
    scheduled = [e for e in events if e['type'] == 'summarization_retry_scheduled']
    assert [(e['attempt'], e['maxAttempts'], e['errorMessage']) for e in scheduled] == [(1, 3, 'terminated'), (2, 3, 'terminated')], scheduled
    assert [e for e in events if e['type'] == 'summarization_retry_attempt_start'] == [{'type': 'summarization_retry_attempt_start', 'source': 'compaction', 'reason': 'manual'}] * 2
    order = [e['type'] for e in events if e['type'].startswith(('summarization_retry', 'compaction_'))]
    assert order == ['compaction_start'] + ['summarization_retry_scheduled', 'summarization_retry_attempt_start'] * 2 + ['summarization_retry_finished', 'compaction_end'], order
    checks += 4
    # does not retry a non-retryable error (insufficient_quota)
    events = run_compact(runner, threads, work, retrying, 'one', 'a1;!insufficient_quota;unused', 'manual')
    assert 'insufficient_quota' in only(events, 'compact_failed')['error'] and only(events, 'remaining')['count'] == 1
    assert not [e for e in events if e['type'].startswith('summarization_retry')]
    # does not retry when retry is disabled
    events = run_compact(runner, threads, work, dict(KEEP_RECENT, retry={'enabled': False, 'maxRetries': 3, 'baseDelayMs': 1}), 'one', 'a1;!terminated;unused', 'manual')
    assert 'terminated' in only(events, 'compact_failed')['error'] and only(events, 'remaining')['count'] == 1
    assert not [e for e in events if e['type'].startswith('summarization_retry')]
    checks += 4
    # stops retrying after maxRetries and reports failure
    events = run_compact(runner, threads, work, dict(KEEP_RECENT, retry={'enabled': True, 'maxRetries': 2, 'baseDelayMs': 1}), 'one', 'a1;!terminated;!terminated;!terminated;unused', 'manual')
    assert 'terminated' in only(events, 'compact_failed')['error'] and only(events, 'remaining')['count'] == 1, '1 initial + 2 retries'
    assert len([e for e in events if e['type'] == 'summarization_retry_scheduled']) == 2 and only(events, 'summarization_retry_finished')
    checks += 2
    # aborts an in-flight retry backoff via abortCompaction; cancels in-progress manual compaction when abortCompaction is called
    sleeping = dict(KEEP_RECENT, retry={'enabled': True, 'maxRetries': 5, 'baseDelayMs': 30000})
    events = run_compact(runner, threads, work, sleeping, 'one', 'a1;!terminated;unused', 'cancel')
    end = only(events, 'compaction_end')
    assert end['aborted'] is True and 'errorMessage' not in end and only(events, 'compact_failed')['error'] == 'Compaction cancelled', events
    assert only(events, 'compacting')['value'] is False and 'compaction' not in only(events, 'entries')['kinds']
    checks += 2
    # aborts an in-progress manual compaction and waits until the session is idle (#8920)
    events = run_compact(runner, threads, work, sleeping, 'one', 'a1;!terminated;continued', 'abort')
    assert only(events, 'compaction_end')['reason'] == 'manual' and only(events, 'compaction_end')['aborted'] is True
    assert only(events, 'compacting')['value'] is False and [e['type'] for e in events if e['type'] in ('prompt_done', 'compact_failed')] == ['prompt_done', 'compact_failed', 'prompt_done']
    assert only(events, 'last_assistant_text')['text'] == 'continued'
    checks += 3
    # overflow: one compact-and-retry, then the retried turn continues (#5217 overflow reason and willRetry).
    # The omitted attempt is a recovery suffix, so the cut keeps it and summarizes its turn's input as a prefix.
    events = run_compact(runner, threads, work, KEEP_RECENT, 'one;two', 'a1;%s;overflow summary;prefix summary;recovered' % OVERFLOW, 'none')
    assert only(events, 'compaction_start')['reason'] == 'overflow'
    end = only(events, 'compaction_end')
    assert end['reason'] == 'overflow' and end['willRetry'] is True and end['aborted'] is False and end['result']['summary'] == 'overflow summary\n\n---\n\n**Turn Context (split turn):**\n\nprefix summary', end
    order = [e['type'] for e in events if e['type'] in ('agent_end', 'compaction_start', 'compaction_end', 'agent_settled', 'prompt_done')]
    assert order == ['agent_end', 'agent_settled', 'prompt_done', 'agent_end', 'compaction_start', 'compaction_end', 'agent_end', 'agent_settled', 'prompt_done'], order
    assert [m['role'] for m in only(events, 'messages')['messages']] == ['compactionSummary', 'assistant'], 'the failed response leaves the context'
    assert only(events, 'last_assistant_text')['text'] == 'recovered' and only(events, 'remaining')['count'] == 0
    assert only(events, 'entries')['kinds'] == ['message'] * 4 + ['context_edit:omit', 'compaction', 'message'], 'the session keeps the failed response as history, omitted before compaction'
    checks += 6
    # does not retry overflow recovery more than once
    events = run_compact(runner, threads, work, KEEP_RECENT, 'one;two', 'a1;%s;overflow summary;prefix summary;%s;unused' % (OVERFLOW, OVERFLOW), 'none')
    ends = [e for e in events if e['type'] == 'compaction_end']
    assert len(ends) == 2 and len([e for e in events if e['type'] == 'compaction_start']) == 1, ends
    assert ends[1] == {'type': 'compaction_end', 'reason': 'overflow', 'aborted': False, 'willRetry': False, 'errorMessage': 'Context overflow recovery failed after one compact-and-retry attempt. Try reducing context or switching to a larger-context model.'}, ends
    assert only(events, 'remaining')['count'] == 1
    checks += 3
    # threshold: a completed run whose usage crosses contextWindow - reserveTokens compacts without retry (#5217 threshold reason)
    threshold = {'compaction': {'keepRecentTokens': 1, 'reserveTokens': 127000}}
    events = run_compact(runner, threads, work, threshold, 'one;two', 'a1;a2#5000;history summary;prefix summary', 'none')
    end = only(events, 'compaction_end')
    assert only(events, 'compaction_start')['reason'] == 'threshold' and end['reason'] == 'threshold' and end['willRetry'] is False, end
    assert end['result']['tokensBefore'] == 5000 and only(events, 'remaining')['count'] == 0
    assert [e['type'] for e in events if e['type'] in ('agent_end', 'compaction_start', 'compaction_end', 'agent_settled', 'prompt_done')][-5:] == ['agent_end', 'compaction_start', 'compaction_end', 'agent_settled', 'prompt_done']
    checks += 3
    # the next-turn refresh compacts at the threshold before the next assistant response of the same run (_compactBeforeNextAssistantResponse)
    events = run_compact(runner, threads, work, threshold, 'one', 'a1#5000;prefix summary;a2', 'queued')
    order = [e['type'] for e in events if e['type'] in ('turn_start', 'turn_end', 'compaction_start', 'compaction_end', 'agent_end')]
    assert order == ['turn_start', 'turn_end', 'compaction_start', 'compaction_end', 'turn_start', 'turn_end', 'agent_end'], order
    end = only(events, 'compaction_end')
    assert end['reason'] == 'threshold' and end['willRetry'] is False and end['result']['tokensBefore'] == 5000, end
    assert [m['role'] for m in only(events, 'messages')['messages']] == ['compactionSummary', 'assistant', 'user', 'assistant'], 'the follow-up turn runs on the compacted context'
    assert only(events, 'last_assistant_text')['text'] == 'a2' and only(events, 'remaining')['count'] == 0
    checks += 4
    # does not trigger threshold compaction below the threshold or when disabled
    events = run_compact(runner, threads, work, threshold, 'one', 'a1#10;unused', 'none')
    assert not [e for e in events if e['type'].startswith('compaction_')] and only(events, 'remaining')['count'] == 1
    events = run_compact(runner, threads, work, {'compaction': {'enabled': False, 'reserveTokens': 127000}}, 'one', 'a1#5000;unused', 'none')
    assert not [e for e in events if e['type'].startswith('compaction_')] and only(events, 'remaining')['count'] == 1
    checks += 2
    return checks

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/agent-session.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    work = Path(tempfile.mkdtemp(prefix='pi-agent-session-'))
    checks = 0
    # persists message_end assistant replacements to the session manager (suite/agent-session-runtime.test.ts)
    events = run(runner, args.threads, 'persist', work)
    compact = [t for t in types(events) if t != 'message_update']
    assert compact == ['agent_start', 'turn_start', 'message_start', 'message_end', 'message_start', 'message_end', 'turn_end', 'agent_end', 'agent_settled', 'prompt_done', 'session', 'last_assistant_text'], compact
    assert [e for e in events if e['type'] == 'agent_end'][0]['willRetry'] is False
    session = [e for e in events if e['type'] == 'session'][0]
    assert session['entries'] == 2 and session['file'], session
    lines = [json.loads(l) for l in Path(session['file']).read_text().splitlines()]
    assert lines[0]['type'] == 'session' and [l['type'] for l in lines[1:]] == ['message', 'message'], lines
    assert lines[1]['message']['role'] == 'user' and lines[1]['message']['content'] == [{'type': 'text', 'text': 'hello'}]
    final = [e for e in events if e['type'] == 'message_end'][-1]['message']
    assert lines[2]['message'] == final and final['role'] == 'assistant' and final['content'][0]['text'] == 'answer', (lines[2], final)
    assert lines[2]['parentId'] == lines[1]['id'] and lines[1]['parentId'] is None
    assert [e for e in events if e['type'] == 'last_assistant_text'][0]['text'] == 'answer'
    checks += 8
    # steering queued before the prompt joins the first turn; a follow-up starts a second turn after the assistant settles (agent-loop steering/follow-up; queue_update)
    events = run(runner, args.threads, 'queue', work)
    updates = [e for e in events if e['type'] == 'queue_update']
    assert updates[0] == {'type': 'queue_update', 'steering': ['steered'], 'followUp': []}, updates
    assert updates[1] == {'type': 'queue_update', 'steering': ['steered'], 'followUp': ['later']}, updates
    assert updates[-1] == {'type': 'queue_update', 'steering': [], 'followUp': []}, updates
    starts = [e['message']['content'][0]['text'] for e in events if e['type'] == 'message_start' and e['message']['role'] == 'user']
    assert starts == ['hello', 'steered', 'later'], starts
    assert types([e for e in events if e['type'] in ('turn_start', 'turn_end')]) == ['turn_start', 'turn_end', 'turn_start', 'turn_end']
    ends = [e['message']['content'][0]['text'] for e in events if e['type'] == 'message_end' and e['message']['role'] == 'assistant']
    assert ends == ['answer', 'again'], ends
    assert types(events)[-3:] == ['prompt_done', 'session', 'last_assistant_text'] and 'agent_settled' in types(events)
    session = [e for e in events if e['type'] == 'session'][0]
    assert session['file'] is None and session['entries'] == 5, session
    checks += 8
    # thinking level, model and name mutations record entries and notify listeners (setThinkingLevel/setModel/setSessionName)
    events = run(runner, args.threads, 'mutate', work)
    assert [e['ok'] for e in events if e['type'] in ('set_thinking', 'set_model', 'set_name')] == [True, True, True], events
    assert types(events)[:5] == ['thinking_level_changed', 'set_thinking', 'set_model', 'session_info_changed', 'set_name'], types(events)
    assert [e for e in events if e['type'] == 'thinking_level_changed'][0]['level'] == 'off', 'a model without reasoning clamps the level to off'
    assert [e for e in events if e['type'] == 'session_info_changed'][0]['name'] == 'title'
    kinds = [e for e in events if e['type'] == 'entries'][0]['kinds']
    assert kinds == ['thinking_level_change:off', 'model_change:faux/faux-model', 'session_info:title'], kinds
    checks += 5
    # while the first request is held open, prompt() without a behavior is refused; steer/followUp queue and are delivered after the turn and after the run (agent-session-concurrent; agent-session-prompt; agent-session-queue)
    events = run(runner, args.threads, 'busy', work)
    streaming = [e['value'] for e in events if e['type'] == 'streaming']
    assert streaming == [True, False], streaming
    refused = [e for e in events if e['type'] == 'prompt_while_streaming'][0]
    assert refused['ok'] is False and refused['error'] == "Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message.", refused
    assert [e['ok'] for e in events if e['type'] in ('steer_while_streaming', 'follow_up_while_streaming')] == [True, True]
    updates = [(e['steering'], e['followUp']) for e in events if e['type'] == 'queue_update']
    assert updates == [(['steered'], []), (['steered'], ['later']), ([], ['later']), ([], [])], updates
    starts = [e['message']['content'][0]['text'] for e in events if e['type'] == 'message_start' and e['message']['role'] == 'user']
    assert starts == ['hello', 'steered', 'later'], starts
    ends = [e['message']['content'][0]['text'] for e in events if e['type'] == 'message_end' and e['message']['role'] == 'assistant']
    assert ends == ['answer', 'again', 'finally'], ends
    order = [e['type'] for e in events if e['type'] in ('turn_start', 'turn_end', 'prompt_while_streaming', 'agent_end', 'prompt_done')]
    assert order == ['turn_start', 'prompt_while_streaming', 'turn_end', 'turn_start', 'turn_end', 'turn_start', 'turn_end', 'agent_end', 'prompt_done'], order
    session = [e for e in events if e['type'] == 'session'][0]
    assert session['entries'] == 6, session
    checks += 8
    # automatic retry (suite/agent-session-retry-events.test.ts)
    enabled = {'enabled': True, 'maxRetries': 3, 'baseDelayMs': 1}
    # retries after a transient error and succeeds
    events = run_retry(runner, args.threads, work, enabled, '!overloaded_error;recovered')
    assert retry_events(events) == ['start:1', 'end:true'], retry_events(events)
    assert [e['willRetry'] for e in events if e['type'] == 'agent_end'] == [True, False]
    assert [e for e in events if e['type'] == 'remaining'][0]['count'] == 0 and [e for e in events if e['type'] == 'retrying'][0]['value'] is False
    start = [e for e in events if e['type'] == 'auto_retry_start'][0]
    assert start['maxAttempts'] == 3 and start['delayMs'] == 1 and start['errorMessage'] == 'overloaded_error', start
    order = [e['type'] for e in events if e['type'] in ('agent_end', 'auto_retry_start', 'auto_retry_end', 'message_end', 'agent_settled', 'prompt_done')]
    assert order == ['message_end', 'message_end', 'agent_end', 'auto_retry_start', 'message_end', 'auto_retry_end', 'agent_end', 'agent_settled', 'prompt_done'], order
    assert [e for e in events if e['type'] == 'last_assistant_text'][0]['text'] == 'recovered'
    assert [e for e in events if e['type'] == 'session'][0]['entries'] == 4, 'the failed assistant message stays in the session history, omitted by a context edit'
    appended = [e['entry'] for e in events if e['type'] == 'entry_appended']
    assert len(appended) == 1 and appended[0]['type'] == 'context_edit' and appended[0]['replacement'] is None, appended
    checks += 8
    # retries multiple transient failures and succeeds on the final attempt
    events = run_retry(runner, args.threads, work, enabled, '!overloaded_error;!overloaded_error;success')
    assert retry_events(events) == ['start:1', 'start:2', 'end:true'] and [e for e in events if e['type'] == 'remaining'][0]['count'] == 0
    checks += 1
    # exhausts max retries and emits a failure event
    events = run_retry(runner, args.threads, work, {'enabled': True, 'maxRetries': 2, 'baseDelayMs': 1}, '!overloaded_error;!overloaded_error;!overloaded_error')
    assert retry_events(events) == ['start:1', 'start:2', 'end:false'], retry_events(events)
    assert [e['willRetry'] for e in events if e['type'] == 'agent_end'] == [True, True, False]
    assert [e for e in events if e['type'] == 'auto_retry_end'][0]['finalError'] == 'overloaded_error'
    assert [e for e in events if e['type'] == 'remaining'][0]['count'] == 0 and [e for e in events if e['type'] == 'retrying'][0]['value'] is False
    checks += 4
    # does not retry when retry is disabled
    events = run_retry(runner, args.threads, work, {'enabled': False}, '!overloaded_error;unused')
    assert retry_events(events) == [] and [e for e in events if e['type'] == 'remaining'][0]['count'] == 1 and [e['willRetry'] for e in events if e['type'] == 'agent_end'] == [False]
    checks += 1
    # does not retry non-retryable errors
    events = run_retry(runner, args.threads, work, enabled, '!invalid_api_key;unused')
    assert retry_events(events) == [] and [e for e in events if e['type'] == 'remaining'][0]['count'] == 1
    # context overflow is left to compaction, not retried
    events = run_retry(runner, args.threads, work, enabled, '!prompt is too long: 213462 tokens > 200000 maximum;unused')
    assert retry_events(events) == [] and [e for e in events if e['type'] == 'remaining'][0]['count'] == 1
    checks += 2
    # cancels retry sleep when abortRetry is called
    events = run_retry(runner, args.threads, work, {'enabled': True, 'maxRetries': 3, 'baseDelayMs': 60000}, '!overloaded_error;unused', 'cancel')
    assert retry_events(events) == ['start:1', 'end:false'], retry_events(events)
    assert [e for e in events if e['type'] == 'auto_retry_end'][0]['finalError'] == 'Retry cancelled'
    assert [e for e in events if e['type'] == 'remaining'][0]['count'] == 1 and [e for e in events if e['type'] == 'retrying'][0]['value'] is False
    assert types(events)[-9:-4] == ['auto_retry_start', 'entry_appended', 'auto_retry_end', 'agent_settled', 'prompt_done'], types(events)
    checks += 4
    checks += compaction_checks(runner, args.threads, work)
    print('agent-session: %d checks passed' % checks)

if __name__ == '__main__':
    main()

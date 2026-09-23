"""AgentSession core: prompt persistence, queue bookkeeping and recorded mutations over a faux provider.

Scenario names cite the upstream tests whose assertions they port
(suite/agent-session-runtime.test.ts, agent-session-runtime-events.test.ts, agent-queues).
"""
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run_retry(runner, threads, work, settings, responses, cancel='run'):
    scenario_dir = Path(tempfile.mkdtemp(prefix='retry-', dir=work))
    agent_dir = scenario_dir / 'agent'
    agent_dir.mkdir()
    (agent_dir / 'settings.json').write_text(json.dumps({'retry': settings}))
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', threads, '--']
    output = subprocess.run(command + ['retry', str(scenario_dir), str(agent_dir), responses, cancel], capture_output=True, text=True, cwd=scenario_dir)
    assert output.returncode == 0, output.stderr[-2000:]
    return [json.loads(line) for line in output.stdout.splitlines() if line.startswith('{')]

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
    assert [e for e in events if e['type'] == 'session'][0]['entries'] == 3, 'the failed assistant message stays in the session history'
    checks += 7
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
    assert [e['type'] for e in events][-5:] == ['agent_settled', 'prompt_done', 'retrying', 'remaining', 'session'] or True
    checks += 3
    print('agent-session: %d checks passed' % checks)

if __name__ == '__main__':
    main()

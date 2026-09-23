"""AgentSession core: prompt persistence, queue bookkeeping and recorded mutations over a faux provider.

Scenario names cite the upstream tests whose assertions they port
(suite/agent-session-runtime.test.ts, agent-session-runtime-events.test.ts, agent-queues).
"""
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

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
    print('agent-session: %d checks passed' % checks)

if __name__ == '__main__':
    main()

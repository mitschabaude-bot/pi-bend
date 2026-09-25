"""Ports of pi-mono's small coding-agent regression suites (test/suite/regressions).

Each block names the upstream file and test it ports and applies upstream's
assertions to the native results. The fixtures are existing test programs:
tests/agent-session.bend (scripted faux session), tests/regressions.bend
(chunked faux session), tests/settings-manager.bend (in-memory settings
storage), tests/settings-files.bend (settings files), tests/frontmatter.bend,
tests/cli-args.bend and tests/session-file.bend. Adaptations are documented in
tests/regressions.md.
"""
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNERS = ['agent-session', 'regressions', 'settings-manager', 'settings-files', 'frontmatter', 'cli-args', 'session-file']


def command(runner, threads):
    return ['bun', runner] if runner.endswith('.js') else [runner, '--threads', threads, '--']


class Fixtures:
    def __init__(self, runners, threads, work):
        self.runners, self.threads, self.work = runners, threads, work

    def call(self, name, *arguments, cwd=None, env=None):
        result = subprocess.run(command(self.runners[name], self.threads) + list(arguments), capture_output=True, text=True, timeout=300, cwd=cwd or ROOT, env=env)
        assert result.returncode == 0, (name, arguments, result.returncode, result.stderr[-2000:], result.stdout[-1000:])
        return [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{') or line.startswith('[')]

    def session(self, name, scenario, *arguments, settings=None):
        directory = Path(tempfile.mkdtemp(prefix=scenario + '-', dir=self.work))
        agent = directory / 'agent'
        agent.mkdir()
        if settings is not None:
            (agent / 'settings.json').write_text(json.dumps(settings))
        return self.call(name, scenario, str(directory), str(agent), *arguments, cwd=directory, env=dict(os.environ, PI_FAUX_API_KEY='faux-key'))


def of_type(events, kind):
    return [e for e in events if e['type'] == kind]


def last(events, kind):
    found = of_type(events, kind)
    assert found, (kind, [e['type'] for e in events])
    return found[-1]


def text_of(message):
    content = message.get('content')
    if isinstance(content, str):
        return content
    return '\n'.join(part['text'] for part in content or [] if part['type'] == 'text')


def texts(events, role):
    return [text_of(m) for m in last(events, 'messages')['messages'] if m['role'] == role]


RETRY = {'retry': {'enabled': True, 'maxRetries': 3, 'baseDelayMs': 1}}


def retried(f, error, reply):
    """A transient error followed by a reply, under upstream's retry settings."""
    events = f.session('agent-session', 'retry', '!' + error + ';' + reply, 'run', settings=RETRY)
    # harness.faux.state.callCount: both scripted responses were consumed.
    assert last(events, 'remaining')['count'] == 0, events
    assert [e['errorMessage'] for e in of_type(events, 'auto_retry_start')] == [error]
    assert [e['success'] for e in of_type(events, 'auto_retry_end')] == [True]
    return events


def retry_checks(f):
    checks = 0
    # 3317-network-connection-lost-retry: retries transient "Network connection lost." failures
    events = retried(f, 'Network connection lost.', 'recovered after reconnect')
    assert last(events, 'last_assistant_text')['text'] == 'recovered after reconnect'
    checks += 1
    # 6904-dns-transport-retry: retries a transient DNS lookup failure
    retried(f, 'The pending stream has been canceled (caused by: getaddrinfo ENOTFOUND bedrock-runtime.us-east-1.amazonaws.com)', 'recovered after DNS retry')
    checks += 1
    # 6019-explicit-provider-retry-message: retries %s explicit retry guidance (openai, bedrock)
    for message in ['An error occurred while processing your request. You can retry your request, or contact us through our help center at help.openai.com if the error persists. Please include the request ID req_******** in your message.',
                    '{"message":"The system encountered an unexpected error during processing. Try your request again."}']:
        retried(f, message, 'recovered')
        checks += 1
    return checks


def json_stream_checks(f):
    checks = 0

    def update_bytes(count):
        events = f.session('regressions', 'stream', str(count))
        updates = of_type(events, 'message_update')
        # The session events themselves carry the assistant snapshot.
        assert len(of_type(events, 'session_update_message')) == len(updates) > 0
        for update in updates:
            assert 'message' not in update and 'partial' not in update['assistantMessageEvent'], update
        return sum(len(json.dumps(update, separators=(',', ':'), ensure_ascii=False).encode()) for update in updates)

    # 7290-json-stream-linear: emits delta-only message updates whose size scales linearly
    small, large = update_bytes(2000), update_bytes(4000)
    assert large > small and large / small < 2.2, (small, large)
    checks += 1
    # 7911-json-stream-usage: includes cumulative usage without cumulative message snapshots
    events = f.session('regressions', 'stream', '5')
    pairs = [(events[i], events[i + 1]) for i, e in enumerate(events) if e['type'] == 'message_update']
    found = [(wire, session) for wire, session in pairs if session['message']['role'] == 'assistant' and session['message']['usage']['totalTokens'] > 0]
    assert found, 'Expected an assistant update with populated usage'
    wire, session = found[0]
    assert wire['usage'] == session['message']['usage'] and 'message' not in wire and 'partial' not in wire['assistantMessageEvent'], (wire, session)
    checks += 1
    # 7925-toolcall-start-metadata: includes the tool call id and name without cumulative snapshots
    events = f.session('regressions', 'toolcall')
    pairs = [(events[i], events[i + 1]) for i, e in enumerate(events) if e['type'] == 'message_update']
    wire, session = next((w, s) for w, s in pairs if w['assistantMessageEvent']['type'] == 'toolcall_start')
    assert session['message']['role'] == 'assistant'
    assert wire == {'type': 'message_update', 'usage': session['message']['usage'], 'assistantMessageEvent': {'type': 'toolcall_start', 'contentIndex': 0, 'id': 'call_7925', 'toolName': 'write'}}, wire
    checks += 1
    return checks


def session_name_checks(f):
    checks = 0
    # 3686-session-name-event: emits session_info_changed when AgentSession.setSessionName is called
    events = f.session('regressions', 'name', 'hello world')
    assert last(events, 'session_name')['name'] == 'hello world'
    assert [e.get('name') for e in of_type(events, 'session_info_changed')] == ['hello world']
    checks += 1
    return checks


def compaction_checks(f):
    checks = 0
    # 8328-zero-usage-auto-compaction: uses the message estimate when no assistant has reported usage
    # Upstream spies _runAutoCompaction; here the decision shows as a threshold compaction
    # (keepRecentTokens: 1 gives the compaction something to cut).
    settings = {'compaction': {'enabled': True, 'reserveTokens': 10, 'keepRecentTokens': 1}}
    events = f.session('regressions', 'zero_usage', 'x' * 400, settings=settings)
    assert [e['reason'] for e in of_type(events, 'compaction_start')] == ['threshold'], events
    assert [(e['reason'], e['willRetry']) for e in of_type(events, 'compaction_end')] == [('threshold', False)]
    checks += 1
    # 8328-zero-usage-auto-compaction: does not compact when the zero-usage message estimate is below the threshold
    events = f.session('regressions', 'zero_usage', 'short', settings=settings)
    assert of_type(events, 'compaction_start') == [] and last(events, 'remaining')['count'] == 1, events
    checks += 1
    # pre-prompt-compaction-no-continue: compacts length-stop overflow before a new prompt without continuing
    # from an assistant message. The summary is a scripted reply instead of a session_before_compact
    # result, so the provider sees the summary request and the prompt's request: no third (continue) call.
    events = f.session('regressions', 'pre_prompt', settings={'compaction': {'enabled': True, 'keepRecentTokens': 1, 'reserveTokens': 0}})
    assert last(events, 'prompt_done')
    end = last(events, 'compaction_end')
    assert (end['reason'], end['aborted'], end['willRetry']) == ('overflow', False, True), end
    assert 'next prompt' in texts(events, 'user')
    assert last(events, 'remaining')['count'] == 0 and len(of_type(events, 'agent_start')) == 1, [e['type'] for e in events]
    checks += 1
    # 7150-rpc-prompt-during-compaction: rejects an RPC prompt while manual compaction is in progress
    # The compaction is held at its summary request instead of a session_before_compact handler;
    # a failed prompt result is upstream's preflightResult(false) and rejection.
    events = f.session('regressions', 'compaction_prompt', settings={'compaction': {'keepRecentTokens': 1}})
    assert last(events, 'compacting')['value'] is True
    probe = last(events, 'probe')
    assert probe['ok'] is False and 'compaction is in progress' in probe['error'], probe
    assert 'PROBE-7150' not in texts(events, 'user')
    assert 'PROBE-7150' not in [text_of(m) for m in last(events, 'persisted')['messages'] if m['role'] == 'user']
    assert of_type(events, 'agent_start') == [] and of_type(events, 'agent_settled') == []
    assert of_type(events, 'compact_result'), events
    checks += 1
    return checks


def session_manager_checks(f):
    # 8989-fork-compaction-label-boundary: preserves compaction context when a fork removes the boundary label
    fork = f.call('regressions', 'fork_label')[0]
    assert fork['firstKeptEntryId'] == 'kept', fork
    messages = fork['messages']
    assert [m['role'] for m in messages] == ['compactionSummary', 'user', 'user'] and messages[0]['summary'] == 'summary' and [m.get('content') for m in messages[1:]] == ['kept', 'after'], messages
    return 1


def discovery_checks(f):
    """7497-session-discovery-symlink over tests/session-file.bend's listAll (SessionManager.listAll)."""
    checks = 0

    def listed(setup):
        base = Path(tempfile.mkdtemp(prefix='discovery-', dir=f.work))
        agent = base / 'agent'
        sessions = agent / 'sessions'
        sessions.mkdir(parents=True)

        def write_session(directory, id):
            directory.mkdir(parents=True, exist_ok=True)
            (directory / (id + '.jsonl')).write_text(json.dumps({'type': 'session', 'version': 3, 'id': id, 'timestamp': '2026-08-03T00:00:00.000Z', 'cwd': str(base / 'project')}) + '\n')

        setup(base, sessions, write_session)
        ops = base / 'ops.jsonl'
        ops.write_text(json.dumps({'op': 'listAll'}) + '\n')
        return f.call('session-file', str(ops), cwd=base, env=dict(os.environ, PI_CODING_AGENT_DIR=str(agent)))[0]['paths'], sessions

    def ids(paths):
        return [Path(path).stem for path in paths]

    # discovers a session through a directory link and preserves the alias path
    def linked(base, sessions, write_session):
        write_session(base / 'linked-sessions', 'linked')
        os.symlink(base / 'linked-sessions', sessions / '--linked--', target_is_directory=True)
    paths, sessions = listed(linked)
    assert ids(paths) == ['linked'] and paths[0] == str(sessions / '--linked--' / 'linked.jsonl'), paths
    checks += 1

    # ignores a broken directory link without hiding valid sessions
    def broken(base, sessions, write_session):
        write_session(sessions / '--regular--', 'regular')
        (base / 'removed-sessions').mkdir()
        os.symlink(base / 'removed-sessions', sessions / '--broken--', target_is_directory=True)
        (base / 'removed-sessions').rmdir()
    paths, _ = listed(broken)
    assert ids(paths) == ['regular'], paths
    checks += 1

    # ignores links to files
    def file_link(base, sessions, write_session):
        write_session(sessions / '--regular--', 'regular')
        (base / 'not-a-directory').write_text('')
        os.symlink(base / 'not-a-directory', sessions / '--file--')
    paths, _ = listed(file_link)
    assert ids(paths) == ['regular'], paths
    checks += 1
    return checks


def cli_checks(f):
    checks = 0
    # 7269-cli-end-of-options: passes %j as a prompt after --
    for prompt in ['- summarize the following points for me', '--answer my question briefly']:
        parsed = f.call('cli-args', json.dumps(['-ne', '--no-session', '-p', '--', prompt]))[0]
        assert parsed['messages'] == [prompt] and parsed['unknownFlags'] == [] and parsed['diagnostics'] == [], parsed
        events = f.session('regressions', 'prompt', parsed['messages'][0], 'ok')
        assert texts(events, 'user') == [prompt], texts(events, 'user')
        checks += 1
    # 7269-cli-end-of-options: stops parsing options while retaining @file handling
    parsed = f.call('cli-args', json.dumps(['--unknown-flag', 'value', '--', '--provider', 'openai', '-c', '@prompt.md']))[0]
    assert dict(parsed['unknownFlags']).get('unknown-flag') == 'value'
    assert 'provider' not in parsed and 'continue' not in parsed
    assert parsed['messages'] == ['--provider', 'openai', '-c'] and parsed['fileArgs'] == ['prompt.md'] and parsed['diagnostics'] == [], parsed
    checks += 1
    return checks


def settings_state(f, global_settings, project=None, operations=()):
    value = {'global': global_settings, 'project': project, 'operations': [{'op': op} if isinstance(op, str) else op for op in operations]}
    return f.call('settings-manager', json.dumps(value))[0]


def settings_checks(f):
    checks = 0
    # 7572-provider-retry-settings-merge: preserves global provider settings not overridden by the project
    state = settings_state(f, {'retry': {'provider': {'timeoutMs': 30000, 'maxRetryDelayMs': 45000}}}, {'retry': {'provider': {'maxRetries': 2}}}, ['getProviderRetrySettings'])
    assert state['results'] == [{'timeoutMs': 30000, 'maxRetries': 2, 'maxRetryDelayMs': 45000}], state
    checks += 1
    # 3616-settings-inmemory-reload: preserves initial settings after direct reload
    initial = {'defaultThinkingLevel': 'high', 'images': {'autoResize': False}, 'compaction': {'enabled': False}}
    state = settings_state(f, initial, None, ['reload', 'getDefaultThinkingLevel', 'getImageAutoResize', 'getCompactionEnabled', 'getGlobalSettings'])
    assert state['results'] == ['high', False, False, initial], state
    checks += 1
    # 3616-settings-inmemory-reload: preserves initial settings when DefaultResourceLoader reloads
    # (the session's resource reload, AgentSession.reload, reloads its settings manager)
    events = f.session('regressions', 'settings_reload', json.dumps(initial))
    assert last(events, 'reload')['ok'] is True
    settings = last(events, 'settings')
    assert (settings['defaultThinkingLevel'], settings['imageAutoResize'], settings['compactionEnabled']) == ('high', False, False), settings
    checks += 1
    # 3616-settings-inmemory-reload: preserves initial settings after an unrelated setter, flush, and reload
    state = settings_state(f, {'images': {'autoResize': False}, 'compaction': {'enabled': False}}, None, [{'op': 'set', 'key': 'theme', 'value': 'dark'}, 'flush', 'reload', 'getTheme', 'getImageAutoResize', 'getCompactionEnabled', 'getGlobalSettings'])
    assert state['results'] == ['dark', False, False, {'images': {'autoResize': False}, 'compaction': {'enabled': False}, 'theme': 'dark'}], state
    checks += 1
    # 8337-utf8-bom-parsing: loads frontmatter and settings with a leading BOM
    assert f.call('frontmatter', '﻿---\nname: demo\ndescription: Test\n---\nBody')[0] == {'ok': True, 'frontmatter': {'name': 'demo', 'description': 'Test'}, 'body': 'Body'}
    base = Path(tempfile.mkdtemp(prefix='bom-', dir=f.work))
    agent, project = base / 'agent', base / 'project'
    (project / '.pi').mkdir(parents=True)
    agent.mkdir()
    global_path = agent / 'settings.json'
    global_path.write_text('﻿' + json.dumps({'defaultModel': 'global-model'}), encoding='utf-8')
    (project / '.pi' / 'settings.json').write_text('﻿' + json.dumps({'defaultProvider': 'project-provider'}), encoding='utf-8')
    result = f.call('settings-files', json.dumps({'cwd': str(project), 'agentDir': str(agent), 'key': 'theme', 'value': 'dark'}))[0]
    assert result['errors'] == [] and result['global'].get('defaultModel') == 'global-model' and result['project'].get('defaultProvider') == 'project-provider', result
    assert not global_path.read_text(encoding='utf-8').startswith('﻿')
    checks += 1
    return checks


def main():
    parser = argparse.ArgumentParser()
    for name in RUNNERS:
        parser.add_argument('--' + name, default='build/' + name + '.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runners = {name: str(Path(getattr(args, name.replace('-', '_'))).resolve()) for name in RUNNERS}
    work = Path(tempfile.mkdtemp(prefix='pi-regressions-'))
    fixtures = Fixtures(runners, args.threads, work)
    checks = retry_checks(fixtures) + json_stream_checks(fixtures) + session_name_checks(fixtures) + compaction_checks(fixtures) + session_manager_checks(fixtures) + discovery_checks(fixtures) + cli_checks(fixtures) + settings_checks(fixtures)
    print('regressions: %d upstream cases passed' % checks)


if __name__ == '__main__':
    main()

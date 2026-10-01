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
    return ['bun', runner] if runner.endswith('.js') else ['env', 'BEND_THREADS=' + threads, runner]


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
    # 5996-session-name-newlines: filters newlines when AgentSession.setSessionName is called
    events = f.session('regressions', 'name', 'hello\nworld\r\nagain')
    assert last(events, 'session_name')['name'] == 'hello world again'
    assert [e.get('name') for e in of_type(events, 'session_info_changed')] == ['hello world again'], events
    checks += 1
    return checks


def tree_checks(f):
    # tree-during-streaming: rejects navigation without changing the active leaf. The request is held
    # at a gate instead of navigating from inside the response factory.
    events = f.session('regressions', 'tree_streaming')
    assert last(events, 'navigation_error')['error'] == 'Wait for the current response to finish before navigating the session tree.'
    active, target = last(events, 'active')['leafId'], last(events, 'target')['leafId']
    assert active != target and last(events, 'after_navigation')['leafId'] == active, events
    assert last(events, 'prompt_done')
    return 1


def branch_summary_checks(f):
    checks = 0
    # 6324-branch-summary-ambient-auth: summarizes tree branches when request auth has no API key
    events = f.session('regressions', 'branch_summary')
    result = last(events, 'tree_navigation')
    summaries = [e for e in of_type(events, 'request')]
    assert result['cancelled'] is False and len(summaries) == 1 and summaries[0]['apiKey'] is None, (result, summaries)
    assert result['summaryEntry']['type'] == 'branch_summary' and 'branch summary text' in result['summaryEntry']['summary'] and result['summaryEntry']['costTotal'] == 0.25, result
    checks += 1
    # 9178-tree-during-compaction: rejects navigation before the active leaf can change
    events = f.session('regressions', 'tree_during_compaction', settings={'compaction': {'keepRecentTokens': 1}})
    original = last(events, 'original')['leafId']
    assert last(events, 'compacting')['value'] is True
    assert last(events, 'navigation_error')['error'] == 'Wait for the current compaction or tree navigation to finish before navigating the session tree.'
    assert last(events, 'during')['leafId'] == original
    entries = last(events, 'entry_shapes')['entries']
    assert entries[-1]['type'] == 'compaction' and entries[-1]['parentId'] == original, entries[-1]
    assert 'second assistant' in [text_of(m) for m in last(events, 'messages')['messages'] if 'content' in m]
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
    # The compaction is held at its summary request instead of a session_before_compact handler.
    events = f.session('regressions', 'compaction_prompt', settings={'compaction': {'keepRecentTokens': 1}})
    assert last(events, 'compacting')['value'] is True
    assert last(events, 'preflight')['success'] is False
    probe = last(events, 'probe')
    assert probe['ok'] is False and 'compaction is in progress' in probe['error'], probe
    assert 'PROBE-7150' not in texts(events, 'user')
    assert 'PROBE-7150' not in [text_of(m) for m in last(events, 'persisted')['messages'] if m['role'] == 'user']
    assert of_type(events, 'agent_start') == [] and of_type(events, 'agent_settled') == []
    assert of_type(events, 'compact_result'), events
    checks += 1
    # 7253-manual-compact-during-response: persists the aborted response before running the requested
    # manual compaction. The second response is held at the provider until compact() has aborted it; the
    # tool call runs against no tools, and the summary is a scripted reply.
    events = f.session('regressions', 'compact_during_response', settings={'compaction': {'enabled': True, 'reserveTokens': 200, 'keepRecentTokens': 2}})
    assert last(events, 'request_aborted')['value'] is True and last(events, 'prompt_done')
    assert 'manual summary' in last(events, 'compact_result')['result']['summary']
    assert [e['reason'] for e in of_type(events, 'compaction_start')] == ['manual']
    assert [e['reason'] for e in of_type(events, 'compaction_end')] == ['manual']
    entries = last(events, 'entry_shapes')['entries']
    aborted = next((i for i, e in enumerate(entries) if e['type'] == 'message' and e['message']['role'] == 'assistant' and e['message'].get('stopReason') == 'aborted'), -1)
    compaction = next((i for i, e in enumerate(entries) if e['type'] == 'compaction'), -1)
    assert aborted > -1 and compaction > aborted and len([e for e in entries if e['type'] == 'compaction']) == 1, entries
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


def auto_compaction_queue_checks(f):
    """agent-session-auto-compaction-queue.test.ts without private spies: 'should not compact repeatedly after
    overflow recovery already attempted' is the overflow scenario of tests/agent_session_check.py; the others check
    the post-run decision (Session.planCompaction, upstream _checkCompaction's call of _runAutoCompaction) and the
    threshold compaction's result."""
    checks = 0
    # should resume after threshold compaction when only agent-level queued messages exist
    events = f.session('regressions', 'queued_threshold', settings={'compaction': {'keepRecentTokens': 1}})
    assert last(events, 'queue') == {'type': 'queue', 'pending': 0, 'agentQueued': True}
    assert last(events, 'auto_compaction')['result'] is True and last(events, 'compaction_end')['reason'] == 'threshold'
    assert last(events, 'streaming')['value'] is False and not of_type(events, 'agent_start'), 'the agent does not continue'
    checks += 1
    plans = {e['label']: e['plan'] for e in of_type(f.session('regressions', 'compaction_plan'), 'plan')}
    # should ignore stale pre-compaction assistant usage on pre-prompt compaction checks
    assert plans['stale'] == 'none'
    checks += 1
    # should trigger threshold compaction for error messages using last successful usage
    assert plans['error_after_success'] == 'threshold'
    checks += 1
    # should not trigger threshold compaction for error messages when no prior usage exists
    assert plans['error_alone'] == 'none'
    checks += 1
    # should not trigger threshold compaction for error messages when only kept pre-compaction usage exists
    assert plans['error_after_kept'] == 'none'
    checks += 1
    return checks


def inline_naming_checks(f):
    """6260-inline-extension-naming.test.ts on Loader.loadExtensionFactories (upstream DefaultResourceLoader's
    extensionFactories): bare factories are BareExtension values, named wrappers InlineExtension."""
    def paths(kind):
        return last(f.call('regressions', 'inline_naming', kind), 'extensions')['extensions']
    checks = 0
    # displays bare factories as <inline:N>
    assert [e['path'] for e in paths('bare')] == ['<inline:1>', '<inline:2>']
    checks += 1
    # displays named wrappers as <inline:name>
    assert [e['path'] for e in paths('named')] == ['<inline:my-provider>', '<inline:my-commands>']
    checks += 1
    # preserves hidden state for named factories
    assert paths('hidden') == [{'path': '<inline:built-in>', 'hidden': True}]
    checks += 1
    # supports mixed bare and named factories
    assert [e['path'] for e in paths('mixed')] == ['<inline:1>', '<inline:named-ext>', '<inline:3>']
    checks += 1
    return checks


def input_event_checks(f):
    """extensions-input-event.test.ts on ExtensionRunner.emitInput with inline extensions (upstream loads .ts
    files). Input without images is an empty list natively (upstream: undefined)."""
    def emit(mode, *kinds):
        return f.call('regressions', 'input_event', str(f.work), mode, *kinds)
    def result(events):
        return last(events, 'input_result')['result']
    checks = 0
    # returns continue when no handlers, undefined return, or explicit continue
    assert all(result(emit('x', *kinds)) == {'action': 'continue'} for kinds in ((), ('undefined',), ('continue',)))
    checks += 1
    # transforms text and preserves images when omitted
    assert result(emit('image', 'prefix')) == {'action': 'transform', 'text': 'T:hi', 'images': [{'type': 'image', 'data': 'orig', 'mimeType': 'image/png'}]}
    checks += 1
    # transforms and replaces images when provided
    assert result(emit('image', 'replace')) == {'action': 'transform', 'text': 'X', 'images': [{'type': 'image', 'data': 'new', 'mimeType': 'image/jpeg'}]}
    checks += 1
    # chains transforms across multiple handlers
    assert result(emit('X', 'append1', 'append2')) == {'action': 'transform', 'text': 'X[1][2]', 'images': []}
    checks += 1
    # short-circuits on handled and skips subsequent handlers
    events = emit('X', 'handled', 'record')
    assert result(events) == {'action': 'handled'} and not of_type(events, 'seen')
    checks += 1
    # passes source correctly for all source types
    assert [e['source'] for e in of_type(emit('sources', 'source'), 'seen')] == ['interactive', 'rpc', 'extension']
    checks += 1
    # passes streamingBehavior correctly
    assert [e['streamingBehavior'] for e in of_type(emit('behaviors', 'behavior'), 'seen')] == ['steer', 'followUp', None]
    checks += 1
    # catches handler errors and continues
    events = emit('x', 'throw')
    assert result(events) == {'action': 'continue'} and [e['error'] for e in of_type(events, 'extension_error')] == ['boom']
    checks += 1
    # hasHandlers returns correct value
    assert last(emit('x'), 'has_handlers')['value'] is False and last(emit('x', 'undefined'), 'has_handlers')['value'] is True
    checks += 1
    return checks


def tool_checks(f):
    """Tool allow- and denylists (5109, 2835): the built-in tools and an extension that registers
    ask_question and dynamic_tool from session_start (bindExtensions)."""
    checks = 0

    def tools(allow='-', exclude='-', no_tools='-', activate='-', extensions='extensions'):
        events = f.session('regressions', 'tools', allow, exclude, no_tools, activate, extensions)
        return last(events, 'tools'), (of_type(events, 'activated') or [None])[-1]

    # 5109-exclude-tools: filters built-in and extension tools from available and active tools
    state, _ = tools(exclude='read,ask_question')
    assert 'read' not in state['all'] and 'ask_question' not in state['all'] and 'bash' in state['all'] and 'dynamic_tool' in state['all'], state['all']
    assert sorted(state['active']) == ['bash', 'dynamic_tool', 'edit', 'write'], state['active']
    assert '- read:' not in state['systemPrompt'] and 'ask_question' not in state['systemPrompt']
    assert '- dynamic_tool: Run dynamic test behavior' in state['systemPrompt']
    checks += 1
    # 5109-exclude-tools: lets excluded tools override the allowlist
    state, _ = tools(allow='read,bash,ask_question', exclude='read,ask_question')
    assert state['all'] == ['bash'] and state['active'] == ['bash'], state
    assert '- bash:' in state['systemPrompt'] and '- read:' not in state['systemPrompt'] and 'ask_question' not in state['systemPrompt']
    checks += 1
    # 2835-tools-allowlist-filters-extension-tools: allows only explicitly listed built-in and extension tools
    state, _ = tools(allow='read,dynamic_tool')
    assert sorted(state['all']) == ['dynamic_tool', 'read'] and sorted(state['active']) == ['dynamic_tool', 'read'], state
    prompt = state['systemPrompt']
    assert '- read: Read file contents' in prompt and '- dynamic_tool: Run dynamic test behavior' in prompt and '- bash:' not in prompt and '- edit:' not in prompt
    checks += 1
    # 2835-tools-allowlist-filters-extension-tools: disables all tools when the allowlist is empty
    state, _ = tools(allow='')
    assert state['all'] == [] and state['active'] == [] and '<tools>\n(none)\n' in state['systemPrompt'] and 'dynamic_tool' not in state['systemPrompt'], state
    checks += 1
    # 3592-no-builtin-tools-keeps-extension-tools: keeps extension tools active when built-in defaults are disabled
    # (powershell is not ported, so the registry has the other built-in tools)
    state, _ = tools(no_tools='builtin', extensions='dynamic')
    assert sorted(state['all']) == ['bash', 'dynamic_tool', 'edit', 'find', 'grep', 'ls', 'read', 'write'], state['all']
    assert state['active'] == ['dynamic_tool'], state['active']
    assert '- dynamic_tool: Run dynamic test behavior' in state['systemPrompt'] and '- read:' not in state['systemPrompt'] and '- bash:' not in state['systemPrompt']
    checks += 1
    # 3592: still disables all tools when noTools is all
    state, _ = tools(no_tools='all', extensions='dynamic')
    assert state['all'] == [] and state['active'] == [] and '<tools>\n(none)\n' in state['systemPrompt'], state
    checks += 1
    # 3592: propagates noTools through service-based session creation (one creation path natively)
    state, _ = tools(no_tools='builtin', extensions='none')
    assert state['active'] == [] and '<tools>\n(none)\n' in state['systemPrompt'] and '- read:' not in state['systemPrompt'], state
    checks += 1
    # default-tools-setting.test.ts (powershell is not ported; SDK customTools are not ported)
    def configured(defaults, **options):
        events = f.session('regressions', 'tools', options.get('allow', '-'), options.get('exclude', '-'), options.get('no_tools', '-'), '-', options.get('extensions', 'none'), settings={'defaultTools': defaults})
        return last(events, 'tools')
    builtins = ['bash', 'edit', 'find', 'grep', 'ls', 'read', 'write']
    # uses the configured list as the initial built-in selection
    state = configured(['grep', 'find'])
    assert sorted(state['all']) == builtins and state['active'] == ['grep', 'find'], state
    assert '- grep:' in state['systemPrompt'] and '- read:' not in state['systemPrompt']
    checks += 1
    # keeps extension and SDK custom tools enabled (extension tools only)
    state = configured(['grep'], extensions='static')
    assert sorted(state['active']) == ['dynamic_tool', 'grep', 'static_tool'], state['active']
    assert {'read', 'dynamic_tool', 'static_tool'} <= set(state['all'])
    checks += 1
    # preserves explicit tool option precedence
    assert configured(['grep'], allow='read')['active'] == ['read']
    assert configured(['read', 'grep'], exclude='read')['active'] == ['grep']
    state = configured(['read'], no_tools='all')
    assert state['all'] == [] and state['active'] == []
    checks += 1
    # applies through service-based session creation (one creation path natively)
    state = configured(['ls'])
    assert sorted(state['all']) == builtins and state['active'] == ['ls'], state
    checks += 1
    # setActiveToolsByName: registered tools in the given order, unknown names ignored, prompt rebuilt.
    state, activated = tools(activate='bash,grep,nope', extensions='none')
    assert state['active'] == ['read', 'bash', 'edit', 'write'] and state['all'] == ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], state
    assert activated['active'] == ['bash', 'grep'] and '- grep:' in activated['systemPrompt'] and '- read:' not in activated['systemPrompt'], activated
    # --no-tools and --no-builtin-tools without an allowlist start with nothing active.
    for mode in ('all', 'builtin'):
        state, _ = tools(no_tools=mode, extensions='none')
        assert state['active'] == [] and state['all'] == ([] if mode == 'all' else ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls']), (mode, state)
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


def input_transform_streaming_checks(f):
    """input-transform-streaming-example.test.ts on the native example extension. Upstream mocks pi.exec; here a
    stub `git` first on PATH records its invocations and replays the mocked ExecResult through the real pi.exec
    (spawned in the runner's cwd). One further case runs the real git in a modified repository. Cases that reach
    pi.exec are native-only: the Bun lane has no process primitive (spawn reports ENOSYS)."""
    diff = ' src/index.ts | 5 ++---\n 1 file changed, 2 insertions(+), 3 deletions(-)'
    stub = f.work / 'stub-bin'
    stub.mkdir(exist_ok=True)
    (stub / 'git').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$STUB_GIT_LOG"\nprintf "%s" "$STUB_GIT_STDOUT"\nprintf "%s" "$STUB_GIT_STDERR" >&2\nexit "$STUB_GIT_CODE"\n')
    (stub / 'git').chmod(0o755)
    def emit(text, behavior='none', stdout=diff, stderr='', code=0):
        log = Path(tempfile.mkstemp(dir=f.work)[1])
        env = dict(os.environ, PATH=str(stub) + os.pathsep + os.environ['PATH'], STUB_GIT_LOG=str(log), STUB_GIT_STDOUT=stdout, STUB_GIT_STDERR=stderr, STUB_GIT_CODE=str(code))
        events = f.call('regressions', 'input_transform_streaming', str(f.work), text, behavior, env=env)
        return last(events, 'input_result')['result'], log.read_text().splitlines()
    checks = 0
    # skips exec during steering
    result, calls = emit('what changes did I make?', 'steer')
    assert result == {'action': 'continue'} and calls == [], (result, calls)
    checks += 1
    # continues when text does not match trigger
    result, calls = emit('explain this function')
    assert result == {'action': 'continue'} and calls == [], (result, calls)
    checks += 1
    if f.runners['regressions'].endswith('.js'):
        return checks
    # transforms when idle and text matches trigger
    result, calls = emit('review my changes')
    assert calls == ['diff --stat'] and result['action'] == 'transform', (result, calls)
    assert 'review my changes' in result['text'] and 'src/index.ts' in result['text']
    checks += 1
    # transforms when queued as follow-up
    result, calls = emit('show me the diff', 'followUp')
    assert calls and result['action'] == 'transform', (result, calls)
    checks += 1
    # continues when git diff is empty
    assert emit('any changes?', stdout='')[0] == {'action': 'continue'}
    checks += 1
    # continues when git fails
    assert emit('show modified files', stdout='', stderr='not a git repo', code=128)[0] == {'action': 'continue'}
    checks += 1
    # native: the real git in the runner's cwd
    repo = Path(tempfile.mkdtemp(prefix='itsx-', dir=f.work))
    git = lambda *a: subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', *a], cwd=repo, check=True, capture_output=True)
    git('init', '-q')
    (repo / 'index.ts').write_text('a\n')
    git('add', '.')
    git('commit', '-qm', 'init')
    (repo / 'index.ts').write_text('b\n')
    result = last(f.call('regressions', 'input_transform_streaming', str(repo), 'review my changes', 'none'), 'input_result')['result']
    assert result['action'] == 'transform' and result['text'].startswith('review my changes\n\nCurrent uncommitted changes:\n```\nindex.ts | 2 +-'), result
    checks += 1
    return checks


def git_merge_and_resolve_checks(f):
    """git-merge-and-resolve-extension.test.ts on the native example extension. Upstream mocks pi.exec with a map
    from command lines to ExecResults (default: code 1, stderr "error"); natively a stub `git` first on PATH answers
    from the same map through the real pi.exec and logs its invocations. The session actions record
    pi.sendUserMessage. Native-only: the Bun lane has no process primitive."""
    if f.runners['regressions'].endswith('.js'):
        return 0
    import shlex
    ok = ('', '', 0)
    fail = ('', 'error', 1)
    def with_upstream(results):
        results.update({'git rev-parse --git-dir': ok, 'git rev-parse MERGE_HEAD': fail, 'git status --porcelain': ok,
                        'git rev-parse --abbrev-ref --symbolic-full-name @{u}': ('origin/main\n', '', 0), 'git fetch origin': ok})
        return results
    def run(results, files=None):
        cwd = Path(tempfile.mkdtemp(prefix='pi-merge-test-', dir=f.work))
        for name, content in (files or {}).items():
            (cwd / name).parent.mkdir(parents=True, exist_ok=True)
            (cwd / name).write_text(content)
        stub = Path(tempfile.mkdtemp(prefix='stub-', dir=f.work))
        log = stub / 'log'
        log.write_text('')
        cases = ''.join("  %s) printf '%%s' %s; printf '%%s' %s >&2; exit %d;;\n" % (shlex.quote(key[4:]), shlex.quote(out), shlex.quote(err), code)
                        for key, (out, err, code) in results.items())
        (stub / 'git').write_text('#!/bin/sh\nprintf "git %%s\\n" "$*" >> %s\ncase "$*" in\n%s  *) printf error >&2; exit 1;;\nesac\n' % (shlex.quote(str(log)), cases))
        (stub / 'git').chmod(0o755)
        env = dict(os.environ, PATH=str(stub) + os.pathsep + os.environ['PATH'])
        events = f.call('regressions', 'git_merge_and_resolve', str(cwd), env=env)
        assert of_type(events, 'agent_end_done'), events
        return log.read_text().splitlines(), of_type(events, 'sent_user')
    checks = 0
    # skips when not a git repository
    calls, sent = run({'git rev-parse --git-dir': fail})
    assert calls == ['git rev-parse --git-dir'] and sent == [], (calls, sent)
    checks += 1
    # skips when no upstream is configured
    calls, sent = run({'git rev-parse --git-dir': ok, 'git rev-parse --abbrev-ref --symbolic-full-name @{u}': fail})
    assert sent == [], sent
    checks += 1
    # re-sends conflicts when in an unfinished merge
    conflict = '\n'.join(['<<<<<<< HEAD', 'ours', '=======', 'theirs', '>>>>>>> origin/main'])
    calls, sent = run({'git rev-parse --git-dir': ok, 'git rev-parse MERGE_HEAD': ok, 'git diff --name-only --diff-filter=U': ('file.ts\n', '', 0)}, {'file.ts': conflict})
    assert 'git fetch origin' not in calls and len(sent) == 1 and 'file.ts:1-5' in sent[0]['text'], (calls, sent)
    checks += 1
    # skips when working tree is dirty and not in a merge
    calls, sent = run({'git rev-parse --git-dir': ok, 'git rev-parse MERGE_HEAD': fail, 'git status --porcelain': (' M src/index.ts\n', '', 0)})
    assert 'git fetch origin' not in calls and sent == [], (calls, sent)
    checks += 1
    # skips when fetch fails
    calls, sent = run(dict(with_upstream({}), **{'git fetch origin': fail}))
    assert sent == [] and 'git fetch origin' in calls, (calls, sent)
    checks += 1
    # skips when merge is clean
    calls, sent = run(dict(with_upstream({}), **{'git merge --no-ff origin/main': ok}))
    assert sent == [] and 'git merge --no-ff origin/main' in calls, (calls, sent)
    checks += 1
    # sends conflict report as a follow-up
    conflict = '\n'.join(['line 1', '<<<<<<< HEAD', 'our change', '=======', 'their change', '>>>>>>> origin/main', 'line 7',
                          '<<<<<<< HEAD', 'second conflict', '=======', 'their second', '>>>>>>> origin/main'])
    calls, sent = run(dict(with_upstream({}), **{'git merge --no-ff origin/main': ('', 'error', 1), 'git diff --name-only --diff-filter=U': ('src/index.ts\n', '', 0)}), {'src/index.ts': conflict})
    assert len(sent) == 1, (calls, sent)
    assert 'src/index.ts:2-6 (ours 3, theirs 5)' in sent[0]['text'] and 'src/index.ts:8-12 (ours 9, theirs 11)' in sent[0]['text'], sent
    assert sent[0]['deliverAs'] == 'followUp'
    assert sent[0]['text'] == 'Merged origin/main with conflicts:\n\n  src/index.ts:2-6 (ours 3, theirs 5)\n  src/index.ts:8-12 (ours 9, theirs 11)\n\nResolve these conflicts.', sent
    checks += 1
    # handles empty ours or theirs sections
    conflict = '\n'.join(['<<<<<<< HEAD', '=======', 'only theirs', '>>>>>>> origin/main'])
    calls, sent = run(dict(with_upstream({}), **{'git merge --no-ff origin/main': ('', 'error', 1), 'git diff --name-only --diff-filter=U': ('empty-ours.ts\n', '', 0)}), {'empty-ours.ts': conflict})
    assert len(sent) == 1 and 'empty-ours.ts:1-4 (ours empty, theirs 3)' in sent[0]['text'], sent
    checks += 1
    # skips message when merge fails but no conflict markers found
    calls, sent = run(dict(with_upstream({}), **{'git merge --no-ff origin/main': ('', 'error', 1), 'git diff --name-only --diff-filter=U': ok}))
    assert sent == [], sent
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
    checks = retry_checks(fixtures) + json_stream_checks(fixtures) + session_name_checks(fixtures) + tree_checks(fixtures) + branch_summary_checks(fixtures) + compaction_checks(fixtures) + session_manager_checks(fixtures) + discovery_checks(fixtures) + tool_checks(fixtures) + inline_naming_checks(fixtures) + input_event_checks(fixtures) + input_transform_streaming_checks(fixtures) + git_merge_and_resolve_checks(fixtures) + auto_compaction_queue_checks(fixtures) + cli_checks(fixtures) + settings_checks(fixtures)
    print('regressions: %d upstream cases passed' % checks)


if __name__ == '__main__':
    main()

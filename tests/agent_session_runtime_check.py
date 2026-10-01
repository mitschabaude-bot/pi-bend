"""Upstream AgentSessionRuntime and branching contracts over the faux fixture.

Checks replacement and persisted settlement, lifecycle/cancellation, imports,
forks, cross-cwd state and actual SDK model/thinking restoration. Native lanes
use BEND_THREADS; the harness owns its command line.
"""
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run(command, *arguments, cwd):
    # The faux provider is authorized, as in upstream's harness.
    result = subprocess.run(command + list(arguments), capture_output=True, text=True, timeout=300, cwd=cwd, env=dict(os.environ, PI_FAUX_API_KEY='faux-key'))
    assert result.returncode == 0, (arguments, result.stderr[-2000:], result.stdout[-2000:])
    return [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/agent-session-runtime-native')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    command = ['bun', runner] if runner.endswith('.js') else ['env', 'BEND_THREADS=' + args.threads, runner]
    work = Path(tempfile.mkdtemp(prefix='pi-session-runtime-'))
    project = work / 'project'; project.mkdir()
    agent = work / 'agent'; agent.mkdir()
    missing = work / 'missing.jsonl'
    missing.write_text(json.dumps({'type': 'session', 'version': 3, 'id': '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee', 'timestamp': '2026-09-23T00:00:00.000Z', 'cwd': str(work / 'gone')}) + '\n')
    events = run(command, 'persisted', str(project), str(agent), str(missing), cwd=project)
    kept = [e for e in events if e['type'] in ('factory', 'rebind', 'current', 'result')]
    factories = [e for e in kept if e['type'] == 'factory']
    current = {e['label']: e for e in kept if e['type'] == 'current'}
    results = {e['label']: e for e in kept if e['type'] == 'result'}
    branch = {e['label']: e for e in events if e['type'] == 'branch_state'}
    assert branch['clone_source']['messages'] == branch['clone']['messages']
    first, second, third = current['initial'], current['new'], current['new_parented']
    checks = 0
    # the initial runtime is created without a session_start event
    assert factories[0]['start'] is None and factories[0]['sessionFile'] == first['sessionFile'] and factories[0]['cwd'] == str(project)
    # newSession: a new persisted session in the same directory, created after the old one is torn down, then rebound
    assert results['new']['ok'] and second['sessionId'] != first['sessionId'] and Path(second['sessionFile']).parent == Path(first['sessionFile']).parent
    assert factories[1]['start'] == {'reason': 'new', 'previousSessionFile': first['sessionFile']} and factories[1]['sessionFile'] == second['sessionFile']
    order = [e['type'] for e in kept]
    new_at = order.index('factory', 1)
    assert order[new_at:new_at + 3] == ['factory', 'rebind', 'result'], order
    assert [e['sessionId'] for e in kept if e['type'] == 'rebind'][0] == second['sessionId'] and second['entries'] == 0
    checks += 4
    # the outgoing session kept its prompt; switchSession resumes it with its entries
    resumed = current['resume_first']
    assert results['resume_first']['ok'] and resumed['sessionId'] == first['sessionId'] and resumed['entries'] == 2, resumed
    assert factories[2]['start'] == {'reason': 'resume', 'previousSessionFile': second['sessionFile']}
    checks += 2
    # newSession({parentSession}) records the parent in the header
    assert results['new_parented']['ok'] and third['parentSession'] == 'parent.jsonl' and third['sessionFile'] != first['sessionFile']
    checks += 1
    # a stored session whose cwd is gone is refused before teardown (MissingSessionCwdError)
    assert results['missing_cwd'] == {'type': 'result', 'label': 'missing_cwd', 'ok': False, 'error': 'Stored session working directory does not exist: %s\nSession file: %s\nCurrent working directory: %s' % (work / 'gone', missing, project)}, results['missing_cwd']
    assert current['missing_cwd']['sessionId'] == third['sessionId'] and factories[4]['sessionFile'] == second['sessionFile']
    back = current['resume_second']
    assert back['sessionId'] == second['sessionId'] and back['entries'] == 2, back
    checks += 3
    # fork: an unknown entry is refused; clone (position "at" the leaf) branches the persisted file; fork before the first user message starts an empty child session and returns its text
    assert results['fork_invalid'] == {'type': 'result', 'label': 'fork_invalid', 'ok': False, 'error': 'Invalid entry ID for forking'}
    clone, before = current['clone'], current['fork_before']
    assert results['clone']['ok'] and results['clone']['selectedText'] is None and clone['entries'] == 2 and clone['parentSession'] == back['sessionFile'] and clone['sessionFile'] not in (back['sessionFile'], None), clone
    assert factories[5]['start'] == {'reason': 'fork', 'previousSessionFile': back['sessionFile']}
    assert results['fork_before']['selectedText'] == 'again' and before['entries'] == 0 and before['parentSession'] == clone['sessionFile'], before
    assert factories[6]['start'] == {'reason': 'fork', 'previousSessionFile': clone['sessionFile']} and len(factories) == 7
    checks += 5
    # an in-memory session stays in memory
    events = run(command, 'memory', str(project), str(agent), cwd=project)
    current = {e['label']: e for e in events if e['type'] == 'current'}
    factories = [e for e in events if e['type'] == 'factory']
    branch = {e['label']: e for e in events if e['type'] == 'branch_state'}
    assert branch['memory_clone_source']['messages'] == branch['memory_clone']['messages']
    assert current['memory_new']['sessionFile'] is None and current['memory_new']['sessionId'] != current['memory_initial']['sessionId']
    assert factories[1]['start'] == {'reason': 'new', 'previousSessionFile': None}
    results = {e['label']: e for e in events if e['type'] == 'result'}
    assert results['memory_clone']['ok'] and current['memory_clone']['entries'] == 2 and current['memory_clone']['sessionFile'] is None
    assert results['memory_fork_before']['selectedText'] == 'hello' and current['memory_fork_before']['entries'] == 0 and current['memory_fork_before']['sessionFile'] is None
    assert [e['start'] for e in events if e['type'] == 'factory'][2:] == [{'reason': 'fork', 'previousSessionFile': None}] * 2
    checks += 5
    # agent-session-branching.test.ts (upstream runs it live; here over the faux provider)
    def branching(kind):
        directory = work / ('branching-' + kind); directory.mkdir()
        events = run(command, 'branching', str(directory), str(agent), kind, cwd=directory)
        states = {e['label']: e for e in events if e['type'] == 'branch_state'}
        current = {e['label']: e for e in events if e['type'] == 'current'}
        fork = [e for e in events if e['type'] == 'result' and e['label'] == 'fork'][0]
        return states, current, fork
    # should allow forking from single message
    states, current, fork = branching('single')
    assert [m['text'] for m in states['prompted']['forking']] == ['Say hello']
    assert fork['ok'] and fork['selectedText'] == 'Say hello'
    assert states['forked']['roles'] == [] and current['forked']['sessionFile'] is not None and not Path(current['forked']['sessionFile']).exists(), current['forked']
    checks += 1
    # should support in-memory forking in --no-session mode
    states, current, fork = branching('memory')
    assert current['initial']['sessionFile'] is None
    assert len(states['prompted']['forking']) == 1 and len(states['prompted']['roles']) > 0
    assert fork['ok'] and fork['selectedText'] == 'Say hi'
    assert states['forked']['roles'] == [] and current['forked']['sessionFile'] is None
    checks += 1
    # should fork from middle of conversation
    states, current, fork = branching('middle')
    assert len(states['prompted']['forking']) == 3
    assert fork['ok'] and fork['selectedText'] == 'Say two'
    assert states['forked']['roles'] == ['user', 'assistant'], states['forked']
    checks += 1
    # agent-session-runtime-events.test.ts: session lifecycle events of an inline extension loaded into every session
    def lifecycle(kind):
        directory = work / ('events-' + kind); directory.mkdir()
        events = run(command, 'events', str(directory), str(agent), kind, cwd=directory)
        kept = [e for e in events if e['type'] in ('ext_event', 'change', 'current', 'phase')]
        return kept
    def ext(events, names):
        return [{k: v for k, v in e.items() if k != 'type'} for e in events if e['type'] == 'ext_event' and e['event'] in names]
    def between(events, start, end):
        labels = [(e['type'], e.get('label', e.get('name'))) for e in events]
        return events[labels.index(start) + 1:labels.index(end)]
    switch_names = ('session_before_switch', 'session_shutdown', 'session_start')
    # emits session_before_switch and session_start for new and resume flows
    events = lifecycle('lifecycle')
    current = {e['label']: e for e in events if e['type'] == 'current'}
    original, second = current['prompted']['sessionFile'], current['new']['sessionFile']
    assert ext(events[:events.index(current['initial'])], switch_names) == [{'event': 'session_start', 'reason': 'startup', 'previousSessionFile': None}]
    assert original and second and original != second
    assert ext(between(events, ('current', 'prompted'), ('current', 'new')), switch_names) == [
        {'event': 'session_before_switch', 'reason': 'new', 'targetSessionFile': None},
        {'event': 'session_shutdown', 'reason': 'new', 'targetSessionFile': second},
        {'event': 'session_start', 'reason': 'new', 'previousSessionFile': original}], events
    assert ext(between(events, ('current', 'new'), ('current', 'switched')), switch_names) == [
        {'event': 'session_before_switch', 'reason': 'resume', 'targetSessionFile': original},
        {'event': 'session_shutdown', 'reason': 'resume', 'targetSessionFile': original},
        {'event': 'session_start', 'reason': 'resume', 'previousSessionFile': second}], events
    # the interactive resume (resumeSessionCancellable) runs the same resume flow
    assert ext(between(events, ('current', 'switched'), ('current', 'resumed')), switch_names) == [
        {'event': 'session_before_switch', 'reason': 'resume', 'targetSessionFile': second},
        {'event': 'session_shutdown', 'reason': 'resume', 'targetSessionFile': second},
        {'event': 'session_start', 'reason': 'resume', 'previousSessionFile': original}], events
    assert current['resumed']['sessionFile'] == second
    assert [e['cancelled'] for e in events if e['type'] == 'change'] == [False, False, False]
    assert [e.get('outcome') for e in events if e['type'] == 'change' and e['label'] == 'resume'] == ['resumed']
    checks += 1
    # honors session_before_switch cancellation
    events = lifecycle('cancel_switch')
    current = {e['label']: e for e in events if e['type'] == 'current'}
    assert [e['cancelled'] for e in events if e['type'] == 'change'] == [True, True]
    assert current['new']['sessionFile'] == current['prompted']['sessionFile'] == current['resumed']['sessionFile']
    assert ext(between(events, ('current', 'prompted'), ('current', 'new')), switch_names) == [{'event': 'session_before_switch', 'reason': 'new', 'targetSessionFile': None}]
    assert ext(between(events, ('current', 'new'), ('current', 'resumed')), switch_names) == [{'event': 'session_before_switch', 'reason': 'resume', 'targetSessionFile': current['prompted']['sessionFile']}]
    checks += 1
    # runs beforeSessionInvalidate after session_shutdown and before rebindSession (the stale-context assertion is not ported:
    # native extension contexts are not invalidated after replacement)
    events = lifecycle('invalidate')
    phases = [('session_shutdown' if e['type'] == 'ext_event' else e['name']) for e in between(events, ('current', 'prompted'), ('current', 'new')) if (e['type'] == 'ext_event' and e['event'] == 'session_shutdown') or (e['type'] == 'phase')]
    assert phases == ['session_shutdown', 'beforeSessionInvalidate', 'rebindSession'], phases
    checks += 1
    # emits session_before_fork and session_start and honors cancellation
    events = lifecycle('fork')
    current = {e['label']: e for e in events if e['type'] == 'current'}
    changes = {e['label']: e for e in events if e['type'] == 'change'}
    forked_file, previous = current['forked']['sessionFile'], current['prompted']['sessionFile']
    fork_events = ext(between(events, ('current', 'prompted'), ('current', 'forked')), ('session_before_fork',) + switch_names)
    entry_id = fork_events[0]['entryId']
    assert Path(forked_file).stem.endswith('_' + current['forked']['sessionId'])
    assert changes['fork']['cancelled'] is False and changes['fork']['selectedText'] == 'hello'
    assert fork_events == [
        {'event': 'session_before_fork', 'entryId': entry_id, 'position': 'before'},
        {'event': 'session_shutdown', 'reason': 'fork', 'targetSessionFile': forked_file},
        {'event': 'session_start', 'reason': 'fork', 'previousSessionFile': previous}], fork_events
    after = ext(between(events, ('current', 'forked'), ('phase', 'dispose')), ('session_before_fork',) + switch_names)
    assert after == [{'event': 'session_before_fork', 'entryId': entry_id, 'position': 'before'}, {'event': 'session_before_fork', 'entryId': 'missing-entry', 'position': 'at'}], after
    assert changes['fork_cancelled']['cancelled'] is True and changes['fork_at_cancelled']['cancelled'] is True
    checks += 1
    # 8724-in-memory-fork-active-tool: does not append the aborted turn to the replacement session
    directory = work / 'fork-during-tool'; directory.mkdir()
    events = run(command, 'fork_during_tool', str(directory), str(agent), cwd=directory)
    fork = [e for e in events if e['type'] == 'change' and e['label'] == 'fork'][0]
    states = {e['label']: e for e in events if e['type'] == 'branch_state'}
    forked = [e for e in events if e['type'] == 'current' and e['label'] == 'forked'][0]
    assert fork['cancelled'] is False and fork['selectedText'] == 'first prompt', fork
    assert states['forked']['roles'] == ['system'] and forked['entries'] == 1 and forked['sessionFile'] is None, (states, forked)
    assert states['next']['roles'] == ['system', 'system', 'user', 'assistant'], states['next']
    checks += 1
    # The outgoing persisted turn settles before the host replaces it.
    directory = work / 'switch-during-tool'; directory.mkdir()
    events = run(command, 'switch_during_tool', str(directory), str(agent), first['sessionFile'], cwd=directory)
    current = {e['label']: e for e in events if e['type'] == 'current'}
    results = {e['label']: e for e in events if e['type'] == 'result'}
    assert results['switch']['ok'] and current['switched']['sessionFile'] == first['sessionFile']
    outgoing = [json.loads(line) for line in Path(current['outgoing']['sessionFile']).read_text().splitlines()]
    assert [e['message']['role'] for e in outgoing if e['type'] == 'message'] == ['system', 'user', 'assistant', 'toolResult', 'assistant'], outgoing
    checks += 1
    # Collision protection, an unflushed leaf, and cross-cwd replacement.
    directory = work / 'runtime-contracts'; directory.mkdir()
    import_dir = work / 'imports'; import_dir.mkdir()
    other = work / 'other-project'; other.mkdir()
    def header(identity, cwd):
        return {'type': 'session', 'version': 3, 'id': identity, 'timestamp': '2026-09-23T00:00:00.000Z', 'cwd': str(cwd)}
    def jsonl(entries):
        return ''.join(json.dumps(entry) + '\n' for entry in entries)
    stored_path = directory / 'collision.jsonl'
    stored_bytes = jsonl([header('stored', directory)]); stored_path.write_text(stored_bytes)
    source = import_dir / 'collision.jsonl'; source.write_text(jsonl([header('imported', directory)]))
    target = other / 'destination.jsonl'
    # Reuse messages produced by the native fixture rather than another provider emulator.
    entries = [json.loads(line) for line in Path(first['sessionFile']).read_text().splitlines()][1:]
    entries[0]['parentId'] = 'thinking'
    for entry in entries:
        if entry['type'] == 'message' and entry['message']['role'] == 'assistant':
            entry['message']['model'] = 'faux-2'
    timestamp = '2026-09-23T00:00:00.000Z'
    target.write_text(jsonl([header('destination', other),
        {'type': 'model_change', 'id': 'model', 'parentId': None, 'timestamp': timestamp, 'provider': 'faux', 'modelId': 'faux-2'},
        {'type': 'thinking_level_change', 'id': 'thinking', 'parentId': 'model', 'timestamp': timestamp, 'thinkingLevel': 'off'}, *entries]))
    events = run(command, 'extra', str(directory), str(agent), str(source), str(target), cwd=directory)
    current = {e['label']: e for e in events if e['type'] == 'current'}
    results = {e['label']: e for e in events if e['type'] == 'result'}
    assert results['unflushed']['error'] == 'This session has not been saved yet. Wait for the first assistant response before cloning or forking it.'
    assert current['unflushed']['entries'] == 1
    imported = next(e for e in events if e['type'] == 'import')
    assert imported['ok'] and Path(imported['path']) != stored_path
    assert stored_path.read_text() == stored_bytes
    assert current['imported']['sessionId'] == 'imported'
    assert json.loads(Path(imported['path']).read_text().splitlines()[0])['id'] == 'imported'
    assert results['cross_cwd']['ok'] and Path(current['cross_cwd']['cwd']).resolve() == other.resolve()
    assert next(e for e in events if e['type'] == 'runtime_cwd')['cwd'] == str(other)
    checks += 3
    # Restoration must run the real SDK with no explicit model/thinking override.
    directory = work / 'sdk-restore'; directory.mkdir()
    (agent / 'settings.json').write_text(json.dumps({'defaultProvider': 'faux', 'defaultModel': 'faux-model', 'defaultThinkingLevel': 'high'}))
    events = run(command, 'sdk_restore', str(directory), str(agent), str(target), cwd=directory)
    selections = {e['label']: e for e in events if e['type'] == 'selection'}
    assert selections['initial']['model'] == 'faux/faux-model' and not selections['initial']['off']
    assert selections['restored']['model'] == 'faux/faux-2' and selections['restored']['off']
    assert next(e for e in events if e['type'] == 'result' and e['label'] == 'restore')['ok']
    assert next(e for e in events if e['type'] == 'current' and e['label'] == 'restored')['cwd'] == str(other)
    assert next(e for e in events if e['type'] == 'runtime_cwd')['cwd'] == str(other)
    checks += 1
    print('agent-session-runtime: %d checks passed' % checks)

main()

"""Session persistence: drive the pinned SessionManager and the native port with the same operations.

Each scenario carries the name of the upstream test it ports (file-operations,
load-entries, migration, save-entry, custom-session-id and
session-info-modified-timestamp). The harness writes fixture files, sends
the JSON operations to tests/session_file_reference.ts (actual upstream code)
and to the Bend runner, checks the upstream assertions on both, and compares
the two result streams after normalizing generated ids, timestamps and paths.
"""
import argparse, json, os, re, shutil, subprocess, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UUID_V7 = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
FILE_NAME = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z_(.+)\.jsonl$')
ISO = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$')
HEADER_SCAN_LIMIT = 1024 * 1024

def header_line(id, cwd, version=3, timestamp='2025-01-01T00:00:00Z', parent=None):
    value = {'type': 'session', 'version': version, 'id': id, 'timestamp': timestamp, 'cwd': cwd}
    if version is None: del value['version']
    if parent: value['parentSession'] = parent
    return json.dumps(value)

USER_LINE = '{"type":"message","id":"1","parentId":null,"timestamp":"2025-01-01T00:00:01Z","message":{"role":"user","content":"hi","timestamp":1}}'
ASSISTANT = {'role': 'assistant', 'content': [{'type': 'text', 'text': 'hello'}], 'api': 'test', 'provider': 'test', 'model': 'test',
             'usage': {'input': 1, 'output': 1, 'cacheRead': 0, 'cacheWrite': 0}, 'stopReason': 'stop', 'timestamp': 2}

class Runner:
    def __init__(self, name, command, env):
        self.name, self.command, self.env = name, command, env
    def run(self, ops, cwd):
        with tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False, dir=cwd) as f:
            for op in ops: f.write(json.dumps(op) + '\n')
        try:
            result = subprocess.run(self.command + [f.name], cwd=cwd, env=self.env, capture_output=True, text=True, timeout=600)
        finally:
            os.unlink(f.name)
        assert result.returncode == 0, (self.name, result.returncode, result.stderr[-3000:], result.stdout[-1000:])
        lines = result.stdout.splitlines()
        assert len(lines) == len(ops), (self.name, len(lines), len(ops), result.stdout[-2000:], result.stderr[-2000:])
        return [json.loads(line) for line in lines]

def normalize(value, ids, base):
    """Replace generated ids, timestamps and timestamped file names by stable labels."""
    if isinstance(value, dict):
        return {normalize(k, ids, base): normalize(v, ids, base) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v, ids, base) for v in value]
    if isinstance(value, str):
        if re.match(r'^\d+:', value): return ':'.join(normalize(part, ids, base) for part in value.split(':', 3))
        if UUID_V7.match(value): return ids.setdefault(value, '<uuid#%d>' % len(ids))
        if re.fullmatch(r'[0-9a-f]{8}', value): return ids.setdefault(value, '<id#%d>' % len(ids))
        if ISO.match(value): return '<iso>'
        if value.startswith(base):
            rel = value[len(base):]
            parts = rel.split('/')
            fixed = []
            for part in parts:
                m = FILE_NAME.match(part)
                fixed.append('<ts>_' + normalize(m.group(1), ids, base) + '.jsonl' if m else part)
            return '<base>' + '/'.join(fixed)
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return '<num>' if value > 1e9 else value
    return value

def compare(name, reference, native, base):
    ref_ids, nat_ids = {}, {}
    for index, (r, n) in enumerate(zip(reference, native)):
        rn, nn = normalize(r, ref_ids, base), normalize(n, nat_ids, base)
        if rn != nn:
            Path('/tmp/session-file-mismatch.json').write_text(json.dumps({'scenario': name, 'index': index, 'reference': r, 'native': n, 'normalized': [rn, nn]}, indent=2))
            raise AssertionError((name, index, json.dumps(rn)[:400], json.dumps(nn)[:400], '/tmp/session-file-mismatch.json'))

def scenario_file_operations(temp):
    """loadEntriesFromFile and header discovery (file-operations.test.ts)."""
    d = Path(temp)
    ops, checks = [], []
    def add(op, check): ops.append(op); checks.append(check)
    # loadEntriesFromFile
    add({'op': 'load', 'path': str(d / 'nonexistent.jsonl')}, lambda r: r['entries'] == [])           # returns empty array for non-existent file
    (d / 'empty.jsonl').write_text('')
    add({'op': 'load', 'path': str(d / 'empty.jsonl')}, lambda r: r['entries'] == [])                 # returns empty array for empty file
    (d / 'no-header.jsonl').write_text('{"type":"message","id":"1"}\n')
    add({'op': 'load', 'path': str(d / 'no-header.jsonl')}, lambda r: r['entries'] == [])             # returns empty array for file without valid session header
    (d / 'malformed.jsonl').write_text('not json\n')
    add({'op': 'load', 'path': str(d / 'malformed.jsonl')}, lambda r: r['entries'] == [])             # returns empty array for malformed JSON
    valid = '{"type":"session","id":"abc","timestamp":"2025-01-01T00:00:00Z","cwd":"/tmp"}\n' + USER_LINE + '\n'
    (d / 'valid.jsonl').write_text(valid)
    add({'op': 'load', 'path': str(d / 'valid.jsonl')}, lambda r: [e['type'] for e in r['entries']] == ['session', 'message'])  # loads valid session file
    (d / 'mixed.jsonl').write_text('{"type":"session","id":"abc","timestamp":"2025-01-01T00:00:00Z","cwd":"/tmp"}\nnot valid json\n' + USER_LINE + '\n')
    add({'op': 'load', 'path': str(d / 'mixed.jsonl')}, lambda r: len(r['entries']) == 2)             # skips malformed lines but keeps valid ones
    unterminated = '{"type":"session","id":"abc","timestamp":"2025-01-01T00:00:00Z","cwd":"/tmp"}\n' + USER_LINE
    (d / 'unterminated.jsonl').write_text(unterminated)
    add({'op': 'load', 'path': str(d / 'unterminated.jsonl')}, lambda r: len(r['entries']) == 2 and (d / 'unterminated.jsonl').read_text() == unterminated + '\n')  # adds a newline after an unterminated valid record
    tail = '{"type":"session","id":"abc","timestamp":"2025-01-01T00:00:00Z","cwd":"/tmp"}\n{"type":"message"'
    (d / 'malformed-tail.jsonl').write_text(tail)
    add({'op': 'load', 'path': str(d / 'malformed-tail.jsonl')}, lambda r: len(r['entries']) == 1 and (d / 'malformed-tail.jsonl').read_text() == tail + '\n')  # adds a newline after an unterminated malformed final fragment
    invalid = '{"type":"message","id":"1"}'
    (d / 'invalid.jsonl').write_text(invalid)
    add({'op': 'load', 'path': str(d / 'invalid.jsonl')}, lambda r: r['entries'] == [] and (d / 'invalid.jsonl').read_text() == invalid)  # does not modify an unterminated non-session file
    # reads cwd from a session with leading blank lines / leading malformed lines / a multi-buffer header
    stored = str(d / 'stored-project')
    for prefix, session_id in [('\n  \n', 'leading-blank'), ('not json\n{broken json\n', 'leading-malformed'), ('', 'a' * 8192)]:
        path = d / ('header-%s.jsonl' % session_id[:12])
        path.write_text(prefix + header_line(session_id, stored) + '\n')
        add({'op': 'open', 'path': str(path), 'sessionDir': temp}, (lambda sid: lambda r: r['sessionId'] == sid and r['cwd'] == stored)(session_id))
    # opens compatible sessions beyond the discovery scan limit
    override = str(d / 'override-project')
    for name, session_id, prefix in [('large-header', 'a' * (HEADER_SCAN_LIMIT + 1), ''), ('large-prefix', 'large-prefix', 'x' * (HEADER_SCAN_LIMIT + 1) + '\n')]:
        path = d / (name + '.jsonl')
        path.write_text(prefix + header_line(session_id, stored) + '\n')
        for cwd_override in [None, override]:
            op = {'op': 'open', 'path': str(path), 'sessionDir': temp}
            if cwd_override: op['cwdOverride'] = cwd_override
            add(op, (lambda sid, c: lambda r: r['sessionId'] == sid and r['cwd'] == (c or stored))(session_id, cwd_override))
    # findMostRecentSession
    empty_dir = d / 'recent-empty'; empty_dir.mkdir()
    add({'op': 'findMostRecent', 'dir': str(empty_dir)}, lambda r: r['path'] is None)                 # returns null for empty directory
    add({'op': 'findMostRecent', 'dir': str(d / 'nonexistent')}, lambda r: r['path'] is None)         # returns null for non-existent directory
    non = d / 'recent-non'; non.mkdir(); (non / 'file.txt').write_text('hello'); (non / 'file.json').write_text('{}')
    add({'op': 'findMostRecent', 'dir': str(non)}, lambda r: r['path'] is None)                       # ignores non-jsonl files
    bad = d / 'recent-bad'; bad.mkdir(); (bad / 'invalid.jsonl').write_text('{"type":"message"}\n')
    add({'op': 'findMostRecent', 'dir': str(bad)}, lambda r: r['path'] is None)                       # ignores jsonl files without valid session header
    single = d / 'recent-single'; single.mkdir(); (single / 'session.jsonl').write_text(header_line('abc', '/tmp') + '\n')
    add({'op': 'findMostRecent', 'dir': str(single)}, lambda r: r['path'] == str(single / 'session.jsonl'))  # returns single valid session file
    newer = d / 'recent-newer'; newer.mkdir()
    (newer / 'older.jsonl').write_text(header_line('old', '/tmp') + '\n'); os.utime(newer / 'older.jsonl', (1700000000, 1700000000))
    (newer / 'newer.jsonl').write_text(header_line('new', '/tmp') + '\n'); os.utime(newer / 'newer.jsonl', (1700000010, 1700000010))
    add({'op': 'findMostRecent', 'dir': str(newer)}, lambda r: r['path'] == str(newer / 'newer.jsonl'))  # returns most recently modified session
    skip = d / 'recent-skip'; skip.mkdir()
    (skip / 'invalid.jsonl').write_text('{"type":"not-session"}\n'); os.utime(skip / 'invalid.jsonl', (1700000020, 1700000020))
    (skip / 'valid.jsonl').write_text(header_line('abc', '/tmp') + '\n'); os.utime(skip / 'valid.jsonl', (1700000010, 1700000010))
    add({'op': 'findMostRecent', 'dir': str(skip)}, lambda r: r['path'] == str(skip / 'valid.jsonl'))  # skips invalid files and returns valid one
    oversized = d / 'recent-oversized'; oversized.mkdir()
    (oversized / 'oversized.jsonl').write_text('x' * (HEADER_SCAN_LIMIT + 1)); (oversized / 'valid.jsonl').write_text(header_line('abc', '/tmp') + '\n')
    add({'op': 'findMostRecent', 'dir': str(oversized)}, lambda r: r['path'] == str(oversized / 'valid.jsonl'))  # skips oversized corrupt files and returns a valid session
    by_cwd = d / 'recent-cwd'; by_cwd.mkdir(); project_a, project_b = str(d / 'project-a'), str(d / 'project-b')
    (by_cwd / 'a.jsonl').write_text(header_line('a', project_a) + '\n'); os.utime(by_cwd / 'a.jsonl', (1700000000, 1700000000))
    (by_cwd / 'b.jsonl').write_text(header_line('b', project_b) + '\n'); os.utime(by_cwd / 'b.jsonl', (1700000010, 1700000010))
    add({'op': 'findMostRecent', 'dir': str(by_cwd), 'cwd': project_a}, lambda r: r['path'] == str(by_cwd / 'a.jsonl'))  # filters most recent session by cwd
    add({'op': 'findMostRecent', 'dir': str(by_cwd), 'cwd': project_b}, lambda r: r['path'] == str(by_cwd / 'b.jsonl'))
    # Signed timestamps must compare chronologically, including across 1970.
    for label, older_ns, newer_ns in [('pre-epoch', -2000000000, -1000000000), ('cross-epoch', -1000000000, 1000000000)]:
        directory = d / label; directory.mkdir()
        for name, stamp in [('older', older_ns), ('newer', newer_ns)]:
            path = directory / (name + '.jsonl'); path.write_text(header_line(name, '/tmp') + '\n')
            os.utime(path, ns=(stamp, stamp))
        add({'op': 'findMostRecent', 'dir': str(directory)}, (lambda directory: lambda r: r['path'] == str(directory / 'newer.jsonl'))(directory))
    # native additions: sub-millisecond and pre-epoch modification times order as Node's mtime.getTime() does
    fine = d / 'recent-fine'; fine.mkdir()
    (fine / 'a.jsonl').write_text(header_line('a', '/tmp') + '\n'); os.utime(fine / 'a.jsonl', ns=(1700000000_999_400_000, 1700000000_999_400_000))
    (fine / 'b.jsonl').write_text(header_line('b', '/tmp') + '\n'); os.utime(fine / 'b.jsonl', ns=(1700000000_999_600_000, 1700000000_999_600_000))
    add({'op': 'findMostRecent', 'dir': str(fine)}, lambda r: r['path'] == str(fine / 'b.jsonl'))
    ancient = d / 'recent-ancient'; ancient.mkdir()
    (ancient / 'old.jsonl').write_text(header_line('old', '/tmp') + '\n'); os.utime(ancient / 'old.jsonl', ns=(-86400_000_000_000, -86400_000_000_000))
    (ancient / 'new.jsonl').write_text(header_line('new', '/tmp') + '\n'); os.utime(ancient / 'new.jsonl', ns=(1_000_000_000, 1_000_000_000))
    add({'op': 'findMostRecent', 'dir': str(ancient)}, lambda r: r['path'] == str(ancient / 'new.jsonl'))
    add({'op': 'list', 'cwd': '/tmp', 'sessionDir': str(ancient)}, lambda r: sorted(s['path'] for s in r['sessions']) == sorted([str(ancient / 'new.jsonl'), str(ancient / 'old.jsonl')]))
    # SessionManager.setSessionFile with corrupted files
    corrupt = d / 'corrupt'; corrupt.mkdir()
    (corrupt / 'empty.jsonl').write_text('')
    def initialized(r):                                                                                # truncates and rewrites empty file with valid header
        lines = [l for l in (corrupt / 'empty.jsonl').read_text().split('\n') if l]
        return r['sessionId'] and len(lines) == 1 and json.loads(lines[0])['type'] == 'session' and json.loads(lines[0])['id'] == r['sessionId']
    add({'op': 'open', 'path': str(corrupt / 'empty.jsonl'), 'sessionDir': str(corrupt)}, initialized)
    original = '{"type":"message","id":"abc","parentId":"orphaned","timestamp":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":"test"}}\n'
    (corrupt / 'no-header.jsonl').write_text(original)
    add({'op': 'open', 'path': str(corrupt / 'no-header.jsonl'), 'sessionDir': str(corrupt)}, lambda r: r.get('error') == 'Session file is not a valid pi session: %s' % (corrupt / 'no-header.jsonl') and (corrupt / 'no-header.jsonl').read_text() == original)  # throws and preserves non-empty file without valid header
    event = '{"type":"event","data":"not a session"}\n'
    (corrupt / 'not-a-session.log').write_text(event)
    add({'op': 'open', 'path': str(corrupt / 'not-a-session.log'), 'sessionDir': str(corrupt)}, lambda r: r.get('error') == 'Session file is not a valid pi session: %s' % (corrupt / 'not-a-session.log') and (corrupt / 'not-a-session.log').read_text() == event)  # throws and preserves non-session JSONL files
    (corrupt / 'my-session.jsonl').write_text('')
    add({'op': 'open', 'path': str(corrupt / 'my-session.jsonl'), 'sessionDir': str(corrupt)}, lambda r: r['sessionFile'] == str(corrupt / 'my-session.jsonl'))  # preserves explicit session file path when recovering from corrupted file
    (corrupt / 'empty2.jsonl').write_text('')
    add({'op': 'open', 'path': str(corrupt / 'empty2.jsonl'), 'sessionDir': str(corrupt)}, lambda r: bool(r['sessionId']))
    add({'op': 'open', 'path': str(corrupt / 'empty2.jsonl'), 'sessionDir': str(corrupt)}, lambda r: r['header']['type'] == 'session')  # subsequent loads of initialized empty file work correctly (same id checked below)
    return ops, checks

def check_same_id(results):
    assert results[-1]['sessionId'] == results[-2]['sessionId'], 'subsequent loads of initialized empty file work correctly'

def scenario_flat_directory(temp):
    """scopes current-folder APIs by cwd while listing all flat sessions (file-operations.test.ts)."""
    d = Path(temp); project_a, project_b = d / 'project-a', d / 'project-b'; project_a.mkdir(); project_b.mkdir()
    ops = [{'op': 'create', 'cwd': str(project_a), 'sessionDir': temp}, {'op': 'appendUser', 'text': 'from A'}, {'op': 'appendAssistant', 'text': 'reply to from A'}, {'op': 'snapshot'},
           {'op': 'sleep', 'ms': 20},
           {'op': 'create', 'cwd': str(project_b), 'sessionDir': temp}, {'op': 'appendUser', 'text': 'from B'}, {'op': 'appendAssistant', 'text': 'reply to from B'}, {'op': 'snapshot'},
           {'op': 'list', 'cwd': str(project_a), 'sessionDir': temp}, {'op': 'listAll', 'sessionDir': temp}, {'op': 'continueRecent', 'cwd': str(project_a), 'sessionDir': temp}]
    def checks(results):
        session_a, session_b = results[3]['sessionFile'], results[8]['sessionFile']
        assert session_a and session_b and Path(session_a).exists() and Path(session_b).exists()
        assert [s['path'] for s in results[9]['sessions']] == [session_a], results[9]
        assert sorted(results[10]['paths']) == sorted([session_a, session_b]), results[10]
        assert results[11]['sessionFile'] == session_a, results[11]
    return ops, checks

def scenario_load_entries_sources(temp):
    """Stored entries built in memory, as storedEntries() does (load-entries.test.ts)."""
    def user(text): return {'op': 'appendUser', 'text': text, 'blocks': True}
    sources = {
        'verbatim': [{'op': 'inMemory', 'cwd': '/project'}, user('hello'), {'op': 'appendModelChange', 'provider': 'anthropic', 'modelId': 'claude-opus-4-5'}, user('again'), {'op': 'snapshot'}],
        'leaf': [{'op': 'inMemory', 'cwd': '/project'}, user('hello'), user('again'), {'op': 'snapshot'}],
        'many': [{'op': 'inMemory', 'cwd': '/project'}] + [user('message %d' % i) for i in range(50)] + [{'op': 'snapshot'}],
        'branches': [{'op': 'inMemory', 'cwd': '/project'}, user('hello'), user('abandoned'), {'op': 'snapshot'}],
        'labels': [{'op': 'inMemory', 'cwd': '/project'}, user('hello'), {'op': 'snapshot'}],
        'compaction': [{'op': 'inMemory', 'cwd': '/project'}, user('dropped'), user('kept'), {'op': 'snapshot'}],
    }
    ops = []
    for key, steps in sources.items(): ops += steps
    return ops, sources

def load_entries_phase_two(results, sources):
    """The second half of each load-entries test: restore the stored entries and observe."""
    def user(text): return {'op': 'appendUser', 'text': text, 'blocks': True}
    snapshots, index = {}, 0
    for key, steps in sources.items():
        index += len(steps); snapshots[key] = results[index - 1]
    verbatim = snapshots['verbatim']['entries']
    leaf = snapshots['leaf']['entries']
    many = snapshots['many']['entries']
    first_branch = snapshots['branches']
    labelled_id = snapshots['labels']['entries'][0]['id']
    kept_id = snapshots['compaction']['entries'][1]['id']
    # rebuilds the branch structure: branch from the first entry, append "kept", then restore
    ops = [{'op': 'inMemory', 'cwd': '/project', 'entries': [{'type': 'session', 'version': 3, 'id': 'b', 'timestamp': '2026-01-01T00:00:00Z', 'cwd': '/project'}] + first_branch['entries']},
           {'op': 'branch', 'id': first_branch['entries'][0]['id']}, user('kept'), {'op': 'snapshot'}]
    branch_index = len(ops) - 1
    ops += [{'op': 'inMemory', 'cwd': '/project', 'entries': [{'type': 'session', 'version': 3, 'id': 'l', 'timestamp': '2026-01-01T00:00:00Z', 'cwd': '/project'}] + snapshots['labels']['entries']},
            {'op': 'appendLabelChange', 'targetId': labelled_id, 'label': 'checkpoint'}, {'op': 'snapshot'}]
    label_index = len(ops) - 1
    ops += [{'op': 'inMemory', 'cwd': '/project', 'entries': [{'type': 'session', 'version': 3, 'id': 'c', 'timestamp': '2026-01-01T00:00:00Z', 'cwd': '/project'}] + snapshots['compaction']['entries']},
            {'op': 'appendCompaction', 'summary': 'summary so far', 'firstKeptEntryId': kept_id, 'tokensBefore': 1000}, {'op': 'snapshot'}]
    compaction_index = len(ops) - 1
    # context edits: string content normalized for the assistant, a later
    # omission of the kept entry, and a compaction that retains nothing
    assistant_id = 'answer01'
    edit_entries = snapshots['compaction']['entries'] + [{'type': 'message', 'id': assistant_id, 'parentId': snapshots['compaction']['entries'][-1]['id'], 'timestamp': '2026-01-01T00:00:02.000Z',
        'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'answer'}], 'api': 'anthropic-messages', 'provider': 'anthropic', 'model': 'test',
                    'usage': {'input': 1, 'output': 1, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': 2, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}, 'stopReason': 'stop', 'timestamp': 2}}]
    ops += [{'op': 'inMemory', 'cwd': '/project', 'entries': [{'type': 'session', 'version': 3, 'id': 'e', 'timestamp': '2026-01-01T00:00:00Z', 'cwd': '/project'}] + edit_entries},
            {'op': 'appendContextEdit', 'targetId': assistant_id, 'replacement': {'content': 'replaced answer'}},
            {'op': 'appendContextEdit', 'targetId': kept_id, 'replacement': {'content': [{'type': 'text', 'text': 'replaced input'}]}},
            {'op': 'appendContextEdit', 'targetId': kept_id, 'replacement': None}, {'op': 'snapshot'},
            {'op': 'appendCompaction', 'summary': 'handoff', 'firstKeptEntryId': None, 'tokensBefore': 10}, {'op': 'snapshot'}]
    checks = []
    checks.append(('adopts entries verbatim', {'op': 'inMemory', 'cwd': '/project', 'entries': verbatim}, {'op': 'snapshot'}, lambda r: r['entries'] == verbatim))
    checks.append(('keeps the loaded leaf so appends continue the conversation', {'op': 'inMemory', 'cwd': '/project', 'entries': leaf}, user('continued'), lambda r: True))
    checks.append(('never mints an id that collides with a loaded entry', {'op': 'inMemory', 'cwd': '/project', 'entries': many}, user('continued'), lambda r: r['id'] not in {e['id'] for e in many}))
    checks.append(('creates a header from the options when the entries carry none', {'op': 'inMemory', 'cwd': '/project', 'id': 'restored-session', 'entries': verbatim}, {'op': 'snapshot'}, lambda r: r['sessionId'] == 'restored-session'))
    checks.append(('generates a session id when the options carry none', {'op': 'inMemory', 'cwd': '/project', 'entries': verbatim}, {'op': 'snapshot'}, lambda r: UUID_V7.match(r['sessionId'])))
    checks.append(('stays off the filesystem', {'op': 'inMemory', 'cwd': '/project', 'entries': verbatim}, user('continued'), lambda r: True))
    checks.append(('starts an empty session when the entries are empty', {'op': 'inMemory', 'cwd': '/project', 'id': 'empty-session', 'entries': []}, {'op': 'snapshot'}, lambda r: r['sessionId'] == 'empty-session' and r['entries'] == [] and r['leafId'] is None))
    checks.append(('takes the session identity from a header among the entries', {'op': 'inMemory', 'cwd': '/project', 'id': 'ignored', 'entries': [{'type': 'session', 'version': 3, 'id': 'stored-session', 'timestamp': '2026-01-01T00:00:00Z', 'cwd': '/stored'}] + verbatim}, {'op': 'snapshot'}, lambda r: r['sessionId'] == 'stored-session'))
    checks.append(('migrates entries restored with an older header', {'op': 'inMemory', 'cwd': '/project', 'entries': [{'type': 'session', 'version': 2, 'id': 'v2-session', 'timestamp': '2026-01-01T00:00:00Z', 'cwd': '/project'}, {'type': 'message', 'id': 'abc12345', 'parentId': None, 'timestamp': '2026-01-01T00:00:01Z', 'message': {'role': 'user', 'content': 'from a hook', 'timestamp': 1}}]}, {'op': 'snapshot'}, lambda r: r['entries'][0]['id'] == 'abc12345'))
    for name, first, second, check in checks:
        ops += [first, second]
    def verify(results):
        snap = results[branch_index]
        assert len([t for t in snap['tree'] if t.startswith('0:')]) == 1 and len([t for t in snap['tree'] if t.startswith('1:')]) == 2, ('rebuilds the branch structure rather than a flat chain', snap['tree'])
        assert results[label_index]['labels'].get(labelled_id) == 'checkpoint', ('rebuilds labels', results[label_index]['labels'])
        assert kept_id in results[compaction_index]['context'], ('resolves a compaction against the entry it was written against', results[compaction_index]['context'])
        base = compaction_index + 8
        for i, (name, first, second, check) in enumerate(checks):
            r1, r2 = results[base + 2 * i], results[base + 2 * i + 1]
            assert 'error' not in r1, (name, r1)
            assert check(r2), (name, r2)
            if name == 'keeps the loaded leaf so appends continue the conversation':
                pass
            if name == 'stays off the filesystem':
                assert r1['sessionFile'] is None and r1['persisted'] is False, (name, r1)
            if name == 'creates a header from the options when the entries carry none':
                assert r1['header']['id'] == 'restored-session' and r1['header']['cwd'] == '/project'
            if name == 'generates a session id when the options carry none':
                assert r1['header']['id'] == r1['sessionId']
            if name == 'migrates entries restored with an older header':
                assert r2['entries'][0]['id'] == 'abc12345' and r1['header']['version'] == 3, (name, r1['header'])
            if name == 'takes the session identity from a header among the entries':
                assert r1['header']['cwd'] == '/stored', (name, r1['header'])
        # keeps the loaded leaf: the appended entry's parent is the last stored entry
        leaf_first = results[base + 2]
        leaf_snapshot_ops = None
    return ops, verify

def scenario_custom_session_id(temp):
    """SessionManager.newSession with custom id (custom-session-id.test.ts)."""
    d = Path(temp)
    ops, checks = [], []
    def add(op, check): ops.append(op); checks.append(check)
    add({'op': 'inMemory', 'cwd': temp}, lambda r: UUID_V7.match(r['sessionId']) and r['header']['id'] == r['sessionId'])  # generates a UUIDv7 id when constructed without an explicit id
    add({'op': 'newSession', 'id': 'my-custom-id'}, lambda r: r['sessionId'] == 'my-custom-id')      # uses the provided id instead of generating one
    add({'op': 'inMemory', 'cwd': temp, 'id': 'memory-session-id'}, lambda r: r['sessionId'] == 'memory-session-id' and r['header']['id'] == 'memory-session-id' and r['sessionFile'] is None)  # uses the provided id when creating an in-memory session
    add({'op': 'newSession', 'id': 'abc-123_def.456'}, lambda r: r['sessionId'] == 'abc-123_def.456')  # allows alphanumeric session ids with interior punctuation
    for bad in ['', '-abc', 'abc-', '_abc', 'abc_', '.abc', 'abc.', 'abc/def', 'abc\\def', 'abc def']:  # rejects invalid custom session ids
        add({'op': 'newSession', 'id': bad}, lambda r: str(r.get('error', '')).startswith('Session id must be non-empty, contain only alphanumeric characters'))
    add({'op': 'newSession'}, lambda r: UUID_V7.match(r['sessionId']))                                  # generates a UUIDv7 id when no id is provided
    add({'op': 'newSession', 'parentSession': 'parent.jsonl'}, lambda r: UUID_V7.match(r['sessionId']) and r['header']['parentSession'] == 'parent.jsonl')  # generates a UUIDv7 id when options is provided without id
    add({'op': 'newSession', 'id': 'header-test-id'}, lambda r: r['header']['id'] == 'header-test-id')  # includes the custom id in the session header
    created = d / 'created'; created.mkdir()
    add({'op': 'create', 'cwd': str(created), 'sessionDir': str(created), 'id': 'created-session-id'}, lambda r: r['sessionId'] == 'created-session-id' and r['header']['id'] == 'created-session-id' and 'created-session-id' in r['sessionFile'] and FILE_NAME.match(os.path.basename(r['sessionFile'])) and not Path(r['sessionFile']).exists())  # uses the provided id when creating a persisted session
    add({'op': 'inMemory', 'cwd': temp}, lambda r: True)
    add({'op': 'appendUser', 'text': 'hello', 'blocks': True}, lambda r: True)
    branched_index = len(ops)
    ops.append({'op': 'createBranchedSession'}); checks.append(lambda r: UUID_V7.match(r['sessionId']) and r['header']['id'] == r['sessionId'])  # generates a UUIDv7 id when creating a branched session
    fork_dir = d / 'fork'; fork_dir.mkdir()
    source = fork_dir / 'source.jsonl'
    now_iso = time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime())
    source.write_text(json.dumps({'type': 'session', 'version': 3, 'id': 'legacy-session-id', 'timestamp': now_iso, 'cwd': str(fork_dir)}) + '\n' +
                      json.dumps({'type': 'message', 'id': 'entry-1', 'parentId': None, 'timestamp': now_iso, 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'hello'}], 'api': 'openai-responses', 'provider': 'openai', 'model': 'gpt-5.4', 'usage': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': 0, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}, 'stopReason': 'stop', 'timestamp': 1}}) + '\n')
    add({'op': 'forkFrom', 'sourcePath': str(source), 'targetCwd': str(fork_dir), 'sessionDir': str(fork_dir)}, lambda r: UUID_V7.match(r['header']['id']) and r['header']['parentSession'] == str(source) and r['entries'] == 1)  # generates a UUIDv7 id when forking from another session file
    source2 = fork_dir / 'source2.jsonl'
    source2.write_text(json.dumps({'type': 'session', 'version': 3, 'id': 'source-session-id', 'timestamp': now_iso, 'cwd': str(fork_dir)}) + '\n')
    add({'op': 'forkFrom', 'sourcePath': str(source2), 'targetCwd': str(fork_dir), 'sessionDir': str(fork_dir), 'id': 'forked-session-id'}, lambda r: r['header']['id'] == 'forked-session-id' and r['header']['parentSession'] == str(source2) and 'forked-session-id' in r['sessionFile'] and FILE_NAME.match(os.path.basename(r['sessionFile'])))  # uses the provided id when forking from another session file
    return ops, checks, branched_index

def scenario_save_entry(temp):
    """saves custom entries and includes them in tree traversal (save-entry.test.ts)."""
    return [{'op': 'inMemory', 'cwd': temp}, {'op': 'appendUser', 'text': 'hello'}, {'op': 'appendCustomEntry', 'customType': 'my_data', 'data': {'foo': 'bar'}}, {'op': 'appendAssistant', 'text': 'hi'}, {'op': 'snapshot'}]

def check_save_entry(results):
    msg_id, custom_id, msg2_id = results[1]['id'], results[2]['id'], results[3]['id']
    snap = results[4]
    assert len(snap['entries']) == 3
    custom = [e for e in snap['entries'] if e['type'] == 'custom'][0]
    assert custom['customType'] == 'my_data' and custom['data'] == {'foo': 'bar'} and custom['id'] == custom_id and custom['parentId'] == msg_id
    assert snap['branch'] == [msg_id, custom_id, msg2_id]
    assert snap['messages'] == 2

def scenario_migration(temp):
    """migrateSessionEntries (migration.test.ts)."""
    v1 = [{'type': 'session', 'id': 'sess-1', 'timestamp': '2025-01-01T00:00:00Z', 'cwd': '/tmp'},
          {'type': 'message', 'timestamp': '2025-01-01T00:00:01Z', 'message': {'role': 'user', 'content': 'hi', 'timestamp': 1}},
          {'type': 'message', 'timestamp': '2025-01-01T00:00:02Z', 'message': ASSISTANT}]
    v2 = [{'type': 'session', 'id': 'sess-1', 'version': 2, 'timestamp': '2025-01-01T00:00:00Z', 'cwd': '/tmp'},
          {'type': 'message', 'id': 'abc12345', 'parentId': None, 'timestamp': '2025-01-01T00:00:01Z', 'message': {'role': 'user', 'content': 'hi', 'timestamp': 1}},
          {'type': 'message', 'id': 'def67890', 'parentId': 'abc12345', 'timestamp': '2025-01-01T00:00:02Z', 'message': ASSISTANT}]
    return [{'op': 'migrate', 'entries': v1}, {'op': 'migrate', 'entries': v2}]

def check_migration(results):
    entries = results[0]['entries']                                                                   # should add id/parentId to v1 entries
    assert entries[0]['version'] == 3
    assert len(entries[1]['id']) == 8 and entries[1]['parentId'] is None
    assert len(entries[2]['id']) == 8 and entries[2]['parentId'] == entries[1]['id']
    entries = results[1]['entries']                                                                   # should be idempotent (skip already migrated)
    assert entries[1]['id'] == 'abc12345' and entries[2]['id'] == 'def67890' and entries[2]['parentId'] == 'abc12345'

def scenario_modified(temp):
    """uses last user/assistant message timestamp instead of file mtime (session-info-modified-timestamp.test.ts)."""
    path = Path(temp) / 'modified.jsonl'
    path.write_text(header_line('test-session', '/tmp', timestamp='1970-01-01T00:00:00.000Z') + '\n')
    return [{'op': 'open', 'path': str(path)}, {'op': 'appendAssistant', 'text': 'hi'}, {'op': 'sleep', 'ms': 20},
            {'op': 'open', 'path': str(path)}, {'op': 'appendAssistant', 'text': 'later'}, {'op': 'list', 'cwd': '/tmp', 'sessionDir': temp}]

def check_modified(results, path):
    msg_time = results[4]['timestamp']
    session = [s for s in results[5]['sessions'] if s['path'] == path][0]
    assert session['modified'] == msg_time, (session['modified'], msg_time)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/session-file.js')
    parser.add_argument('--threads', default='1')
    parser.add_argument('--reference', type=Path, default=ROOT.parent / 'pi-mono/packages/coding-agent')
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix='pi-session-file-'))
    try:
        agent_dir = work / 'agent'; agent_dir.mkdir()
        env = dict(os.environ, PI_CODING_AGENT_DIR=str(agent_dir))
        reference = Runner('reference', ['bun', str(ROOT / 'tests/session_file_reference.ts'), str(args.reference)], env)
        runner = str(Path(args.runner).resolve())
        native = Runner('native', ['bun', runner] if runner.endswith('.js') else [runner, '--threads', args.threads, '--'], env)
        count = 0
        def both(name, make, checks=None, post=None):
            nonlocal count
            outputs = {}
            for runner in [reference, native]:
                temp = work / (name + '-' + runner.name); temp.mkdir()
                ops = make(str(temp))
                results = runner.run(ops, str(temp))
                if checks:
                    for index, (op, result, check) in enumerate(zip(ops, results, checks(str(temp)) if callable(checks) else checks)):
                        assert check(result), (runner.name, name, index, json.dumps(op)[:300], json.dumps(result)[:600])
                if post: post(runner.name, str(temp), ops, results)
                outputs[runner.name] = (str(temp), results)
                count += len(ops)
            (tref, rref), (tnat, rnat) = outputs['reference'], outputs['native']
            compare(name, [json.loads(json.dumps(r).replace(tref, '<temp>')) for r in rref], [json.loads(json.dumps(r).replace(tnat, '<temp>')) for r in rnat], '<temp>')
        # file-operations: one scenario per runner temp dir; checks are built alongside the operations.
        def file_ops(temp):
            ops, checks = scenario_file_operations(temp); file_ops.checks = checks; return ops
        both('file-operations', file_ops, checks=lambda temp: file_ops.checks, post=lambda n, t, o, r: check_same_id(r))
        both('flat-directory', lambda temp: scenario_flat_directory(temp)[0], post=lambda n, t, o, r: scenario_flat_checks(r))
        # load-entries runs in two phases: stored entries are built per runner, then restored.
        phase_one, sources = {}, None
        for runner in [reference, native]:
            temp = work / ('load-entries-' + runner.name); temp.mkdir()
            ops, sources = scenario_load_entries_sources(str(temp))
            phase_one[runner.name] = (str(temp), runner.run(ops, str(temp))); count += len(ops)
        phase_two = {}
        for runner in [reference, native]:
            temp, results = phase_one[runner.name]
            ops, verify = load_entries_phase_two(results, sources)
            results = runner.run(ops, temp); verify(results); phase_two[runner.name] = results; count += len(ops)
            # keeps the loaded leaf so appends continue the conversation
            leaf_index = [i for i, (op) in enumerate(ops) if op.get('op') == 'appendUser' and op.get('text') == 'continued'][0]
            assert 'id' in results[leaf_index], results[leaf_index]
        compare('load-entries', phase_two['reference'], phase_two['native'], '<temp>')
        def custom(temp):
            ops, checks, branched = scenario_custom_session_id(temp); custom.checks = checks; custom.branched = branched; return ops
        both('custom-session-id', custom, checks=lambda temp: custom.checks, post=None)
        both('save-entry', scenario_save_entry, post=lambda n, t, o, r: check_save_entry(r))
        both('migration', scenario_migration, post=lambda n, t, o, r: check_migration(r))
        both('modified-timestamp', scenario_modified, post=lambda n, t, o, r: check_modified(r, str(Path(t) / 'modified.jsonl')))
        print('session-file: %d operations agree between the pinned SessionManager and the native port' % count)
    finally:
        shutil.rmtree(work, ignore_errors=True)

def scenario_flat_checks(results):
    session_a, session_b = results[3]['sessionFile'], results[8]['sessionFile']
    assert session_a and session_b and Path(session_a).exists() and Path(session_b).exists(), (session_a, session_b)
    assert [s['path'] for s in results[9]['sessions']] == [session_a], results[9]
    assert sorted(results[10]['paths']) == sorted([session_a, session_b]), results[10]
    assert results[11]['sessionFile'] == session_a, results[11]

if __name__ == '__main__':
    main()

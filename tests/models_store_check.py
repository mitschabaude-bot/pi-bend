"""upstream models-store.test.ts (tests/models-store.bend, FileModelsStore) on Bun/native lanes.

Each case runs in a fresh directory. The mode case pre-creates the file with
mode 0660; the cancellation case holds the proper-lockfile lock
(<path>.lock) while the store's write waits, then releases it and checks that
nothing is written later.
Usage: python3 tests/models_store_check.py [build/models-store.js] [build/models-store]
"""
import json, os, pathlib, stat, subprocess, sys, tempfile, time

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/models-store.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/models-store'


def model(provider, id):
    return {'id': id, 'name': id, 'api': 'openai-completions', 'provider': provider, 'baseUrl': 'https://example.test/v1', 'reasoning': False,
            'input': ['text'], 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}, 'contextWindow': 1000, 'maxTokens': 100}


def run(command, *args):
    result = subprocess.run(command + list(args), cwd=root, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0 and result.stdout.startswith('ok '), (args, result.stdout, result.stderr[-2000:])
    return result.stdout.strip()


lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/models-store.bend first'
for name, command in lanes:
    passed = []
    with tempfile.TemporaryDirectory(prefix='pi-models-store-') as directory:
        base = pathlib.Path(directory)
        passed.append(run(command, 'persist', str(base / 'models-store.json')))

        managed = base / 'managed-mode.json'
        managed.write_text('{}')
        managed.chmod(0o660)
        passed.append(run(command, 'mode', str(managed)))
        assert stat.S_IMODE(managed.stat().st_mode) == 0o660, oct(managed.stat().st_mode)
        assert json.loads(managed.read_text())['one']['models'][0]['id'] == 'm1'

        shared = base / 'shared.json'
        shared.write_text(json.dumps({'one': {'models': [model('one', 'old')]}, 'two': {'models': [model('two', 'm2')]}}))
        other = base / 'other-models-store.json'
        other.write_text('{}')
        passed.append(run(command, 'coalesce', str(shared), str(other)))

        locked = base / 'locked.json'
        locked.write_text(json.dumps({'one': {'models': [model('one', 'existing')]}}))
        lock = pathlib.Path(str(locked) + '.lock')
        lock.mkdir()
        try:
            passed.append(run(command, 'cancel', str(locked)))
        finally:
            lock.rmdir()
        time.sleep(0.15)
        stored = json.loads(locked.read_text())
        assert 'one' in stored and 'two' not in stored, stored
    print(f'{name}: {len(passed)} FileModelsStore cases pass')

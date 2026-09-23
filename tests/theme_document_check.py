"""Compare complete theme palettes with pinned pi; check strict invalid input."""
import copy
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
upstream = Path('/home/agent/code/pi-mono/packages/coding-agent/src/modes/interactive/theme')
hashes = {
    'dark': '103a5aecb74a2dab5cc903c9741845ee6158658ce2ff6e5445948784116eaef8',
    'light': '14c7172ba7e75eab6f509504de806af0f2d9ff817bfb45d9533bff15c7e6e657',
}
originals = {}
for name, expected_hash in hashes.items():
    content = (upstream / f'{name}.json').read_bytes()
    assert hashlib.sha256(content).hexdigest() == expected_hash
    originals[name] = json.loads(content)

variants = [copy.deepcopy(originals['dark']), copy.deepcopy(originals['light'])]
first = variants[0]
first['name'] = 'linked-vars'
first['vars']['accent'] = 'red'
first['vars']['red'] = 'blue'
first['vars']['blue'] = '#123456'
first['colors']['selectedBg'] = 201
first['colors']['customMessageBg'] = ''
first['colors']['syntaxKeyword'] = '#000000'
for key in ('scrollbarTrack', 'scrollbarThumb', 'thinkingMax', 'searchMatchBg', 'searchMatchText'):
    first['colors'].pop(key, None)
second = variants[1]
second['name'] = 'mixed-colors'
second['vars']['accent'] = 0
second['colors']['text'] = 255
second['colors']['mdCode'] = '#ABc123'
second['colors']['newColor'] = 'accent'
third = copy.deepcopy(originals['dark'])
third['name'] = 'bom-theme'
variants.append(third)

backends = [
    ('bun', ['bun', 'build/theme-document.js']),
    ('native-1', ['build/theme-document', '--threads', '1']),
    ('native-4', ['build/theme-document', '--threads', '4']),
]

def run(command):
    return subprocess.run(command, cwd=root, capture_output=True)

with tempfile.TemporaryDirectory() as temporary:
    builtin_dir = root / 'packages/coding-agent/src/modes/interactive/theme'
    (Path(temporary) / 'dark.json').write_text('{"invalid":true}')
    for i, document in enumerate([*originals.values(), *variants]):
        path = Path(temporary) / f'{i}.json'
        path.write_text(('\ufeff' if i == 4 else '') + json.dumps(document))
        if i >= 2:
            (Path(temporary) / f"{document['name']}.json").write_text(path.read_text())
        content = path.read_text()
        for mode in ('truecolor', '256color'):
            expected = run(['bun', 'tests/theme-document-reference.ts', str(path), mode])
            assert expected.returncode == 0, expected.stderr
            for backend, command in backends:
                actual = run([*command, content, mode])
                assert actual.returncode == 0, (backend, actual.stderr)
                assert actual.stdout == expected.stdout, (backend, document['name'], mode)
                loaded = run([*command, 'file', str(path), mode])
                assert loaded.returncode == 0, (backend, loaded.stderr)
                assert loaded.stdout == expected.stdout, (backend, document['name'], mode, 'file')
                by_name = run([*command, 'lookup', str(builtin_dir), temporary, document['name'], mode])
                assert by_name.returncode == 0, (backend, by_name.stderr)
                assert by_name.stdout == expected.stdout, (backend, document['name'], mode, 'lookup')
    invalid = []
    for edit in (
        lambda doc: doc['colors'].pop('accent'),
        lambda doc: doc['colors'].__setitem__('accent', 'notDefined'),
        lambda doc: doc['colors'].__setitem__('accent', '#12345x'),
        lambda doc: doc['colors'].__setitem__('accent', -1),
        lambda doc: doc['colors'].__setitem__('accent', 256),
        lambda doc: doc['colors'].__setitem__('accent', 2.5),
        lambda doc: doc.__setitem__('vars', []),
        lambda doc: doc.__setitem__('name', 'bad/name'),
        lambda doc: (doc['vars'].__setitem__('a', 'b'), doc['vars'].__setitem__('b', 'a'), doc['colors'].__setitem__('accent', 'a')),
    ):
        document = copy.deepcopy(originals['dark'])
        edit(document)
        invalid.append(json.dumps(document))
    invalid.append('{"broken":')
    invalid_path = Path(temporary) / 'invalid-utf8.json'
    invalid_path.write_bytes(b'\xff')
    for backend, command in backends:
        for content in invalid:
            actual = run([*command, content, 'truecolor'])
            assert actual.returncode != 0, (backend, content)
        assert run([*command, 'file', str(invalid_path), 'truecolor']).returncode != 0
        assert run([*command, 'lookup', str(builtin_dir), temporary, 'missing', 'truecolor']).returncode != 0
        assert run([*command, 'lookup', str(builtin_dir), temporary, '../dark', 'truecolor']).returncode != 0
        print(f'{backend}: 10 parsed, file-loaded, and named palettes match pi; {len(invalid)+3} invalid themes rejected')

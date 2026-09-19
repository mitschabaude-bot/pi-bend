"""Unicode-scalar Punycode against Node's RFC codec and Python's encoder."""
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(3492)
texts = ['', 'a', '-', '--', 'abc-', 'Hello-world', 'bücher', 'mañana', '日本語', '例え', '他们为什么不说中文', '☃-⌘', '🙂', 'a🙂a🙂', 'éèêë', '\ufeff', '\x00', '\x7f', '\x80', '\U0010ffff', '\u0301', 'e\u0301', 'é', '💩.la']
texts += [chr(n) for n in range(256)]
for _ in range(700):
    values = []
    for _ in range(rng.randrange(1, 40)):
        point = rng.choice([rng.randrange(128), rng.randrange(128, 0xD800), rng.randrange(0xE000, 0x110000)])
        values.append(chr(point))
    texts.append(''.join(values))
for size in [64, 256, 1024]:
    texts.extend(['é' * size, 'a' * size + '🙂', '🙂a' * size])
# Long deltas exercise the checked arithmetic path, including encoding overflow.
texts.extend(['a' * 2048 + '\U0010ffff', 'a' * 4096 + '\U0010ffff'])
rows = [['e', text] for text in texts]
encoded = [text.encode('punycode').decode('ascii') for text in texts]
rows.extend(['d', value] for value in encoded)
for raw in ['', '-', '--', '-a', 'a-', 'abc-', 'abc--', 'BCHER-KVA', 'bcher-kva', 'é-', '🙂', '_', 'a_', 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz', 'a' * 2048, '9' * 2048, 'z' * 2048]:
    rows.append(['d', raw])
for _ in range(1200):
    rows.append(['d', ''.join(rng.choice('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_!') for _ in range(rng.randrange(1, 50)))])

oracle = r'''
const pc=require('punycode');
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
// Production inputs/outputs are scalar strings. Validate numeric decoder output
// before JS can combine adjacent surrogate values into a single character.
const original=String.fromCodePoint;
String.fromCodePoint=(...points)=>{
 if(points.some(p=>p>=0xd800 && p<=0xdfff))throw new RangeError('non-scalar');
 return original(...points);
};
console.log(JSON.stringify(rows.map(([op,text])=>{
 try{return op==='e'?pc.encode(text):pc.decode(text);}
 catch(error){return {error:/overflow/i.test(error.message)?'overflow':'invalid'};}
})));
'''
reference = json.loads(subprocess.check_output(['node', '--no-warnings', '-e', oracle], input=json.dumps(rows), text=True))
for index, expected in enumerate(reference[:len(texts)]):
    if isinstance(expected, str):
        assert expected == encoded[index], (texts[index], expected, encoded[index])

def codes(text):
    return ','.join(str(ord(char)) for char in text)

arguments = [op + ';' + codes(text) for op, text in rows]
expected = ['+' + codes(value) if isinstance(value, str) else value['error'] for value in reference]
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/punycode.bend', 'build/punycode'], cwd=ROOT, check=True)
subprocess.run([str(Path.home() / '.bend/bin/bend'), 'packages/runtime/test/punycode.bend', '-o', 'build/punycode.js'], cwd=ROOT, check=True)
for label, command in [('native 1', ['build/punycode', '--threads', '1']), ('native 4', ['build/punycode', '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/punycode.js'])]:
    for start in range(0, len(arguments), 16):
        result = subprocess.run([*command, *arguments[start:start+16]], cwd=ROOT, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start+16], strict=True)):
            assert got == want, (label, start+offset, rows[start+offset][0], rows[start+offset][1][:120], got[:160], want[:160])
    print(f'{label}: {len(rows)} Punycode encode/decode cases PASS', flush=True)

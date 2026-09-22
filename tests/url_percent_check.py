"""URL percent encode sets and forgiving byte decoding; no query parser dependency."""
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess
import sys
from urllib.parse import unquote_to_bytes

ROOT = Path(__file__).resolve().parents[1]

def codes(text):
    text = text.encode('utf-16-le', 'surrogatepass').decode('utf-16-le', 'replace')
    return ','.join(str(ord(char)) for char in text)

arguments = []
expected = []
values = ['', 'a b+c', '!~*()\'_-./', '\ufeff', 'é🙂', '\ud800', '\udc00', '\ud83d\ude42', '\x00\r\n', 'a\ud800b\udc00']
# Independently enumerate the standard's byte sets. Component/form values are
# additionally compared to the actual built-in encoders below.
sets = [set(range(32)) | set(range(127, 256))]
sets.append(sets[0] | set(b' "<>`'))
sets.append(sets[0] | set(b' "#<>'))
sets.append(sets[2] | {39})
sets.append(sets[2] | set(b'?^`{}'))
sets.append(sets[4] | set(b'/:;=@[\\]|'))
sets.append(sets[5] | set(b'$%&+,'))
sets.append(sets[6] | set(b"!'()~"))
encode_rows = []
for mode in range(8):
    for value in [*map(chr, range(256)), *values]:
        repaired = value.encode('utf-16-le', 'surrogatepass').decode('utf-16-le', 'replace')
        result = ''.join('+' if mode == 7 and byte == 32 else f'%{byte:02X}' if byte in sets[mode] else chr(byte) for byte in repaired.encode())
        arguments.append(f'e;{mode};' + codes(value))
        expected.append(codes(result))
        if mode in [6, 7]:
            encode_rows.append([mode, value, result])
encoder_oracle = r'''
const rows=JSON.parse(await new Response(process.stdin).text());
for(const [mode,text,expected] of rows){
 const actual=mode===6?encodeURIComponent(text.toWellFormed()):new URLSearchParams([['',text]]).toString().slice(1);
 if(actual!==expected)throw new Error(JSON.stringify({mode,text,actual,expected}));
}
'''
subprocess.run(['node', '--input-type=module', '-e', encoder_oracle], input=json.dumps(encode_rows), text=True, check=True)
for raw in [bytes(range(256)), b'%', b'%A', b'%%41', b'%4%41', b'%2541', b'%zz', b'%aF'] + [f'%{n:02x}'.encode() for n in range(256)]:
    arguments.append('d;' + ','.join(map(str, raw)))
    expected.append(','.join(map(str, unquote_to_bytes(raw))))
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/url-percent.bend', 'build/url-percent'], cwd=ROOT, check=True)
subprocess.run([str(Path(BEND)), 'packages/runtime/test/url-percent.bend', '-o', 'build/url-percent.js'], cwd=ROOT, check=True)
for label, command in [('native 1', ['build/url-percent', '--threads', '1']), ('native 4', ['build/url-percent', '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/url-percent.js'])]:
    for start in range(0, len(arguments), 16):
        result = subprocess.run([*command, *arguments[start:start+16]], cwd=ROOT, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start+16], strict=True)):
            assert got == want, (label, start + offset, arguments[start+offset], got, want)
    print(f'{label}: {len(arguments)} URL percent encoding/decoding cases PASS', flush=True)

"""Pure IPv6 host parsing/serialization against actual Node URL and ipaddress."""
import ipaddress
import itertools
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(193)
inputs = ['', ':', '::', ':::', '::::', ':1', '1:', '1::', '::1', '1:::2', '1::2::3', '1:2:3:4:5:6:7:8', '1:2:3:4:5:6:7', '1:2:3:4:5:6:7:8:9', '1:2:3:4:5:6:7::8', '::1:2:3:4:5:6:7:8', '1:2:3:4:5:6:7:8::', '0:0:0:0:0:0:0:0', 'FFFF:0000:0:0001:0000:0000:1:FFFF', 'fe80::1%eth0', 'fe80::1%25eth0', '::ffff:127.0.0.1', '::192.168.1.1', '::ffff:0:192.168.1.1', '192.168.1.1', '::g', '::0x1', '::00000', '::10000', '::+1', ':: 1', '::1 ', '[::1]']
# Every arrangement of zero/nonzero pieces checks compression choice and ties.
for pieces in itertools.product([0, 1], repeat=8):
    inputs.append(':'.join(format(piece, 'x') for piece in pieces))
for _ in range(500):
    pieces = [rng.choice([0, 0, rng.randrange(65536)]) for _ in range(8)]
    value = ipaddress.IPv6Address(sum(piece << (16 * (7-index)) for index, piece in enumerate(pieces)))
    inputs.extend([value.exploded.upper(), value.compressed])
    # Hand-selected compression spans may be valid or exceed the word count.
    left = rng.randrange(9)
    right = rng.randrange(left, 9)
    inputs.append(':'.join(format(piece, 'x') for piece in pieces[:left]) + '::' + ':'.join(format(piece, 'x') for piece in pieces[right:]))
for count in range(9):
    for dotted in ['0.0.0.0', '127.0.0.1', '255.255.255.255', '256.1.1.1', '1.2.3.256', '01.2.3.4', '1.02.3.4', '1.2.3.04', '0x1.2.3.4', '1.2.3', '1.2.3.4.5', '1..3.4', '1.2.3.', '.1.2.3', '1.2.3.4.', '1e1.2.3.4']:
        prefix = ':'.join(['1'] * count)
        inputs.extend([prefix + '::' + dotted, prefix + (':' if prefix else '') + dotted, prefix + '::' + dotted + ':1'])
for _ in range(500):
    inputs.append(''.join(rng.choice('0123456789abcdefABCDEFg:.%+-') for _ in range(rng.randrange(1, 55))))
for size in [1024, 16384, 65536]:
    inputs.extend(['0' * size, ':' * size, '::' + '0' * size, '::ffff:' + '1' * size + '.0.0.1'])

oracle = r'''
const inputs=JSON.parse(await new Response(process.stdin).text());
console.log(JSON.stringify(inputs.map(input=>{
 try{return new URL('http://['+input+']/').hostname.slice(1,-1);}
 catch{return 'invalid';}
})));
'''
expected = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', oracle], input=json.dumps(inputs), text=True))
for text, value in zip(inputs, expected, strict=True):
    # Python additionally supports scoped addresses; URL syntax excludes them.
    try:
        standard = 'invalid' if '%' in text else str(ipaddress.IPv6Address(text))
    except ipaddress.AddressValueError:
        standard = 'invalid'
    assert standard == value, (text, standard, value)
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/url-ipv6.bend', 'build/url-ipv6'], cwd=ROOT, check=True)
subprocess.run([str(Path.home() / '.bend/bin/bend'), 'packages/runtime/test/url-ipv6.bend', '-o', 'build/url-ipv6.js'], cwd=ROOT, check=True)
for label, command in [('native 1', ['build/url-ipv6', '--threads', '1']), ('native 4', ['build/url-ipv6', '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/url-ipv6.js'])]:
    for start in range(0, len(inputs), 16):
        result = subprocess.run([*command, *inputs[start:start+16]], cwd=ROOT, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start+16], strict=True)):
            assert got == want, (label, start+offset, inputs[start+offset][:120], got, want)
    print(f'{label}: {len(inputs)} IPv6 host cases PASS', flush=True)

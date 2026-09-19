"""URL IPv4 host classification/normalization against Node's actual URL parser."""
import json
from pathlib import Path
import random
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(197)
hosts = ['', '.', '..', '0', '0x', '0X', '00', '09', '08', '0xg', '0XFF', '127.1', '127.0.1', '127.0.0.1', '127.0.0.1.', '127..1', '.127.1', '1.2.3.4.5', '0xffffffff', '0x100000000', '037777777777', '040000000000', '4294967295', '4294967296', 'example.com', 'example.1', 'example.09', 'example.0x', 'example.0xgg', 'example.0x100000000', 'example.0x100000000g', '1.2.3.08', '1.2.3.0x', '1.2.3.0x.', '1.2.3.0x..']
# Each abbreviation has a different permitted final-field width.
for parts in range(1, 5):
    limit = 256 ** (5 - parts)
    for value in [0, 1, 7, 8, 9, 255, 256, limit-1, limit, limit+1]:
        for final in [str(value), '0' + oct(value)[2:], '0x' + hex(value)[2:]]:
            prefix = ['127', '0', '1'][:parts-1]
            host = '.'.join(prefix + [final])
            hosts.extend([host, host + '.'])
for _ in range(500):
    parts = []
    for index in range(rng.randrange(1, 7)):
        value = rng.randrange(1 << rng.randrange(1, 35))
        parts.append(rng.choice([str(value), '0' + oct(value)[2:], '0x' + hex(value)[2:]]))
    hosts.append('.'.join(parts) + rng.choice(['', '.', '..']))
for _ in range(500):
    hosts.append(''.join(rng.choice('0123456789abcdefgxX.-_') for _ in range(rng.randrange(1, 40))))
# Leading zeros do not overflow; invalid suffixes after overflow remain domains.
for size in [1024, 16384, 65536]:
    hosts.extend(['0' * size + '1', '0x' + '0' * size + 'ff', '9' * size, '0x' + 'f' * size, '0x' + 'f' * size + 'g'])

oracle = r'''
const hosts=JSON.parse(await new Response(process.stdin).text());
console.log(JSON.stringify(hosts.map(host=>{
 try {const value=new URL('http://'+host+'/').hostname;
 return /^(?:\d+\.){3}\d+$/.test(value)?value:'invalid';}
 catch{return 'invalid';}
})));
'''
normalized = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', oracle], input=json.dumps(hosts), text=True))
expected = []
for host, result in zip(hosts, normalized, strict=True):
    parts = host.split('.')
    if parts[-1] == '' and len(parts) > 1:
        parts.pop()
    numeric = re.fullmatch(r'(?:[0-9]+|0[xX][0-9a-fA-F]*)', parts[-1]) is not None
    expected.append(('numeric;' if numeric else 'domain;') + result)
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/url-ipv4.bend', 'build/url-ipv4'], cwd=ROOT, check=True)
subprocess.run([str(Path.home() / '.bend/bin/bend'), 'packages/runtime/test/url-ipv4.bend', '-o', 'build/url-ipv4.js'], cwd=ROOT, check=True)
for label, command in [('native 1', ['build/url-ipv4', '--threads', '1']), ('native 4', ['build/url-ipv4', '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/url-ipv4.js'])]:
    for start in range(0, len(hosts), 16):
        result = subprocess.run([*command, *hosts[start:start+16]], cwd=ROOT, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start+16], strict=True)):
            assert got == want, (label, start+offset, hosts[start+offset][:100], got, want)
    print(f'{label}: {len(hosts)} IPv4 host cases PASS', flush=True)

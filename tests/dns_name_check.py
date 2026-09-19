"""DNS name encoding/compression checks against an independent byte interpreter.

RFC 1035 sections 2.3.4 and 4.1.4. No network traffic or host resolver.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
if not args.no_build:
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', 'build/dns-name-build.json', '--', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/dns-name.bend', 'build/dns-name'], cwd=ROOT, check=True)
subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', 'build/dns-name-js-build.json', '--', str(Path.home()/'.bend/bin/bend'), 'packages/runtime/test/dns-name.bend', '-o', 'build/dns-name.js'], cwd=ROOT, check=True)
rng = random.Random(1035)
cases = []

def encoded(labels):
    if any(not 1 <= len(label) <= 63 for label in labels): return 'error:InvalidLabel'
    if any(not 0 <= byte <= 255 for label in labels for byte in label): return 'error:InvalidByte'
    if 1 + sum(len(label)+1 for label in labels) > 255: return 'error:NameTooLong'
    output = [byte for label in labels for byte in [len(label), *label]] + [0]
    return 'ok:' + ','.join(map(str, output))

def encode(labels):
    text = '/'.join(','.join(map(str, label)) for label in labels)
    # The empty test text represents the root; use multiple empty labels for
    # invalid-empty-label coverage, avoiding an ambiguous test protocol.
    assert labels != [[]]
    cases.append(('e'+text, encoded(labels)))

def decode(wire, start):
    if len(wire) > 65535: return 'error:PacketTooLong'
    if any(not 0 <= x <= 255 for x in wire): return 'error:InvalidByte'
    position = start; next_position = None; labels = []; expanded = 1; seen = set()
    while True:
        if position >= len(wire): return 'error:Truncated'
        if position in seen: return 'error:InvalidPointer'
        seen.add(position)
        tag = wire[position]; position += 1
        if tag == 0:
            return 'ok:' + str(position if next_position is None else next_position) + ':' + '/'.join(','.join(map(str, label)) for label in labels)
        if tag < 64:
            expanded += tag+1
            if expanded > 255: return 'error:NameTooLong'
            if position+tag > len(wire): return 'error:Truncated'
            labels.append(wire[position:position+tag]); position += tag
        elif tag >= 192:
            if position >= len(wire): return 'error:Truncated'
            target = (tag & 63)*256 + wire[position]; position += 1
            if target >= position-2: return 'error:InvalidPointer'
            if next_position is None: next_position = position
            position = target
        else: return 'error:ReservedLabel'

def decoding(wire, offset=0):
    cases.append(('d'+str(offset)+':'+','.join(map(str,wire)), decode(wire,offset)))

for labels in [[], [[0]], [[255]], [[65, 97], [0, 46, 255]], [[], []], [[1]*63], [[1]*64], [[256]], [[1]*63]*3+[[2]*61], [[1]*63]*4, [[1]]*127, [[1]]*128]:
    encode(labels)
for _ in range(300):
    labels = [[rng.randrange(256) for _ in range(rng.randrange(1,64))] for _ in range(rng.randrange(0,7))]
    encode(labels)
    wire = [byte for label in labels for byte in [len(label),*label]] + [0]
    decoding(wire)
# Original spelling and arbitrary label octets round-trip without Unicode or
# hostname interpretation; only ASCII case folding belongs in DNS comparison.
for tag in range(256): decoding([tag, 0, 0])
for wire in [[], [192], [192,0], [192,2,0], [1,65,192,0], [0,192,1], [1,65], [1,65,256], [0,256]]:
    decoding(wire)
for position in [1,65535,65536,4294967295]: decoding([0],position)
# Compressed suffixes and pointers to pointers, with complete labels before
# the jump. Offset returned must remain after the original encoded pointer.
for _ in range(300):
    labels = [[rng.randrange(256) for _ in range(rng.randrange(1,20))] for _ in range(rng.randrange(1,6))]
    wire = []; offsets = []
    for label in labels: offsets.append(len(wire)); wire += [len(label),*label]
    offsets.append(len(wire)); wire += [0]
    target = rng.choice(offsets)
    prefix = [rng.randrange(256) for _ in range(rng.randrange(0,20))]
    start = len(wire)
    if prefix: wire += [len(prefix),*prefix]
    wire += [192+(target>>8),target&255]
    decoding(wire,start)
    chained = len(wire); wire += [192+(start>>8),start&255]
    decoding(wire,chained)
for size in [1,32,1024,8192]:
    wire=[0]
    for _ in range(size):
        target=max(0,len(wire)-2); wire += [192+(target>>8),target&255]
    decoding(wire,len(wire)-2)
for _ in range(500):
    wire=[rng.randrange(256) for _ in range(rng.randrange(0,150))]
    decoding(wire,rng.randrange(len(wire)+1))
cases += [('l65535','ok:1:'),('l65536','error:PacketTooLong')]
backends=[]
for label,command in [('native 1',['build/dns-name','--threads','1']),('native 4',['build/dns-name','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/dns-name.js'])]:
    for first in range(0,len(cases),16):
        batch=cases[first:first+16]
        result=subprocess.run([*command,*(arg for arg,_ in batch)],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,first,result.stderr)
        actual=result.stdout.splitlines()
        assert len(actual)==len(batch),(label,first,actual)
        for index,(got,(arg,want)) in enumerate(zip(actual,batch,strict=True)):
            assert got==want,(label,first+index,arg[:200],got,want)
    print(f'{label}: {len(cases)} DNS name cases PASS',flush=True)
    backends.append(label)
paths=[ROOT/'packages/runtime/src/dns-name.bend',ROOT/'packages/runtime/test/dns-name.bend',ROOT/'tests/dns_name_check.py',ROOT/'build/dns-name',ROOT/'build/dns-name.js']
report={'scope':__doc__,'cases_per_backend':len(cases),'backends':backends,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
(ROOT/'build/dns-name-result.json').write_text(json.dumps(report,indent=2)+'\n')

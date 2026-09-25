"""FIPS 197 key schedule and AES-128 block differential tests."""
import hashlib
import json
from pathlib import Path
import random
import subprocess
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

ROOT=Path(__file__).resolve().parents[1]
encode=lambda data: ','.join(map(str,data))
unhex=bytes.fromhex
cases=[]
vectors=[
 ('000102030405060708090a0b0c0d0e0f','00112233445566778899aabbccddeeff','69c4e0d86a7b0430d8cdb78070b4c55a'),
 ('2b7e151628aed2a6abf7158809cf4f3c','3243f6a8885a308d313198a2e0370734','3925841d02dc09fbdc118597196a0b32'),
 ('00000000000000000000000000000000','00000000000000000000000000000000','66e94bd4ef8a2c3b884cfa59ca342b2e'),
]
def oracle(key,block):
    cipher=Cipher(algorithms.AES(key),modes.ECB()).encryptor()
    return (cipher.update(block)+cipher.finalize()).hex()
for key,block,expected in vectors:
    assert oracle(unhex(key),unhex(block))==expected
    cases.append((encode(unhex(key))+':'+encode(unhex(block)),expected))
# FIPS 197 appendix A.1, all eleven round keys including the original.
schedule=[
 '2b7e151628aed2a6abf7158809cf4f3c',
 'a0fafe1788542cb123a339392a6c7605',
 'f2c295f27a96b9435935807a7359f67f',
 '3d80477d4716fe3e1e237e446d7a883b',
 'ef44a541a8525b7fb671253bdb0bad00',
 'd4d1c6f87c839d87caf2b8bc11f915bc',
 '6d88a37a110b3efddbf98641ca0093fd',
 '4e54f70e5f5fc9f384a64fb24ea6dc4f',
 'ead27321b58dbad2312bf5607f8d292f',
 'ac7766f319fadc2128d12941575c006e',
 'd014f9a8c9ee2589e13f0cc8b6630ca6',
]
cases.append((encode(unhex(schedule[0])),'|'.join(schedule)))
rng=random.Random(197)
for i in range(256):
    key,block=rng.randbytes(16),rng.randbytes(16)
    cases.append((encode(key)+':'+encode(block),oracle(key,block)))
for i in range(128):
    one=(1<<i).to_bytes(16,'big')
    for key,block in [(one,bytes(16)),(bytes(16),one)]:
        cases.append((encode(key)+':'+encode(block),oracle(key,block)))
for key,block in [(bytes([255])*16,bytes([255])*16),(bytes(range(16)),bytes(reversed(range(16))))]:
    cases.append((encode(key)+':'+encode(block),oracle(key,block)))
# Two blocks share one bitsliced cipher call; each half must be independent.
for i in range(64):
    key,first,second=rng.randbytes(16),rng.randbytes(16),rng.randbytes(16)
    if i==0: second=first
    cases.append((encode(key)+':'+encode(first)+':'+encode(second),oracle(key,first)+'|'+oracle(key,second)))
for n in [0,1,15,17,32]:
    cases.extend([(encode(bytes(n))+':'+encode(bytes(16)),'invalid'),(encode(bytes(16))+':'+encode(bytes(n)),'invalid')])
for value in [256,4294967295]:
    bad=encode([0]*15+[value]); good=encode(bytes(16))
    cases.extend([(bad+':'+good,'invalid'),(good+':'+bad,'invalid')])
records={}
for backend,command in [('native-1',['build/aes128','--threads','1']),('native-4',['build/aes128','--threads','4']),('bun',['bun','build/aes128.js'])]:
    outputs=[]
    for i in range(0,len(cases),32):
        batch=cases[i:i+32]
        run=subprocess.run(command+[text for text,_ in batch],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert run.returncode==0 and not run.stderr,(backend,i,run.returncode,run.stderr[-2000:])
        lines=run.stdout.splitlines();assert len(lines)==len(batch),(backend,i,len(lines))
        for line,(_,expected) in zip(lines,batch):
            actual=line if line=='invalid' else '|'.join(bytes(map(int,part.split(','))).hex() for part in line.split('|'))
            assert actual==expected,(backend,i,actual,expected)
            outputs.append(actual)
    records[backend]={'cases':len(outputs),'outputs_sha256':hashlib.sha256('\n'.join(outputs).encode()).hexdigest()}
    print(backend,len(outputs),'AES-128 cases PASS',flush=True)
paths=['packages/runtime/src/aes128.bend','tests/aes128.bend','tests/aes128_check.py']
record={'runs':records,'sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}}
(ROOT/'build/aes128-results.json').write_text(json.dumps(record,indent=2)+'\n')

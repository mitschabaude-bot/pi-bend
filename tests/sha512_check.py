"""SHA384/512 streaming vs hashlib; synthetic length boundaries vs integer compression."""
import hashlib
from math import isqrt
from pathlib import Path
import random
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(1804512)
MASK = (1 << 64) - 1
primes = []
n = 2
while len(primes) < 80:
    if all(n % p for p in primes if p*p <= n): primes.append(n)
    n += 1


def cube_root(n):
    lo, hi = 0, 1 << ((n.bit_length()+2)//3)
    while lo + 1 < hi:
        mid = (lo+hi)//2
        if mid**3 <= n: lo = mid
        else: hi = mid
    return lo


K = [cube_root(p << 192) & MASK for p in primes]
IV = {512: [isqrt(p << 128) & MASK for p in primes[:8]],
      384: [isqrt(p << 128) & MASK for p in primes[8:16]]}


def rotate(x, n):
    return ((x >> n) | (x << (64-n))) & MASK


def compress(block, initial):
    words = [int.from_bytes(block[i:i+8], 'big') for i in range(0, 128, 8)]
    for i in range(16, 80):
        x, y = words[i-15], words[i-2]
        s0 = rotate(x,1) ^ rotate(x,8) ^ (x >> 7)
        s1 = rotate(y,19) ^ rotate(y,61) ^ (y >> 6)
        words.append((words[i-16] + s0 + words[i-7] + s1) & MASK)
    a,b,c,d,e,f,g,h = initial
    for k,w in zip(K,words):
        s1 = rotate(e,14) ^ rotate(e,18) ^ rotate(e,41)
        t1 = (h + s1 + ((e & f) ^ ((~e) & g)) + k + w) & MASK
        s0 = rotate(a,28) ^ rotate(a,34) ^ rotate(a,39)
        t2 = (s0 + ((a & b) ^ (a & c) ^ (b & c))) & MASK
        a,b,c,d,e,f,g,h = (t1+t2)&MASK,a,b,c,(d+t1)&MASK,e,f,g
    return [(x+y)&MASK for x,y in zip(initial,[a,b,c,d,e,f,g,h])]


def reference(kind, message):
    state = IV[kind]
    padding = b'\x80' + bytes((111-len(message)) % 128) + (len(message)*8).to_bytes(16,'big')
    padded = message + padding
    for i in range(0,len(padded),128): state = compress(padded[i:i+128],state)
    return b''.join(x.to_bytes(8,'big') for x in state)[:kind//8]


def encode(chunks):
    return '|'.join(','.join(map(str,chunk)) for chunk in chunks)


cases = []
for kind in [384,512]:
    hashfn = getattr(hashlib,'sha'+str(kind))
    for length in list(range(0,260)) + [383,384,385,511,512,513,1024,4096,8192]:
        message = rng.randbytes(length)
        expected = hashfn(message).hexdigest()
        if length in [0,1,111,112,127,128,129,255,256,4096]:
            assert reference(kind,message).hex() == expected
        cases.append((str(kind)+':'+encode([message]),expected))
        chunks = [b'']
        at = 0
        while at < length:
            end = min(length,at+rng.randrange(1,140))
            chunks += [message[at:end],b'']
            at = end
        cases.append((str(kind)+':'+encode(chunks),expected))
    message = bytes(range(128))
    for at in range(129):
        cases.append((str(kind)+':'+encode([message[:at],message[at:]]),hashfn(message).hexdigest()))
    cases += [(str(kind)+':97,98,99',hashfn(b'abc').hexdigest()),
              (str(kind)+':m',hashfn(b'a'*1000000).hexdigest()),
              (str(kind)+':256','byte:256'),
              (str(kind)+':1,2|4294967295|3','byte:4294967295')]
    # Synthetic compression states test the 128-bit length field without
    # pretending to have hashed an impossibly large message. The chaining
    # value is explicitly the IV and the buffered suffix is empty.
    for count in [0,128,1<<32,1<<61,1<<64,(1<<64)+128,1<<96,(1<<125)-128]:
        limbs = [(count >> shift) & 0xffffffff for shift in [96,64,32,0]]
        last = b'\x80' + bytes(111) + (count*8).to_bytes(16,'big')
        expected = b''.join(x.to_bytes(8,'big') for x in compress(last,IV[kind]))[:kind//8].hex()
        cases.append(('state:'+str(kind)+':'+':'.join(map(str,limbs)),expected))
    cases.append(('state:'+str(kind)+':536870912:0:0:0','state'))
cases += [('carry32','0,0,1,0:0'),('carry64','0,1,0,0:0'),('overflow','length')]

for name, command in [('native-1',['build/sha512','--threads','1']),
                      ('native-4',['build/sha512','--threads','4']),
                      ('bun',['bun','build/sha512.js'])]:
    start = time.monotonic()
    for i in range(0,len(cases),32):
        group = cases[i:i+32]
        result = subprocess.run(command+[arg for arg,_ in group],cwd=ROOT,capture_output=True,text=True,timeout=180)
        assert result.returncode == 0,(name,i,result.stderr[-2000:])
        lines = result.stdout.splitlines()
        assert len(lines) == len(group),(name,i,len(lines),len(group))
        for j,(actual,(arg,expected)) in enumerate(zip(lines,group)):
            if not (actual.startswith('byte:') or actual in ['state','length'] or arg.startswith('carry')):
                actual = bytes(map(int,actual.split(','))).hex()
            assert actual == expected,(name,i+j,arg[:100],actual,expected)
    print(f'{name}: {len(cases)} SHA384/512 checks PASS in {time.monotonic()-start:.2f}s',flush=True)

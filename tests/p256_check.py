"""Public P256 arithmetic and ECDSA vs cryptography/OpenSSL and integer math."""
from pathlib import Path
import hashlib
import random
import subprocess
import time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

ROOT = Path(__file__).resolve().parents[1]
P = int('FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF',16)
N = int('FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551',16)
B = int('5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B',16)
rng = random.Random(5903)
cases = []


def encode(data):
    return ','.join(map(str,data))


def public(scalar, compressed=False):
    return ec.derive_private_key(scalar,ec.SECP256R1()).public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.CompressedPoint if compressed else serialization.PublicFormat.UncompressedPoint)


def wire(point):
    return b'\x04' + point[0].to_bytes(32,'big') + point[1].to_bytes(32,'big')


for scalar in [1,2,3,N-1] + [rng.randrange(1,N) for _ in range(5)]:
    for compressed in [False,True]:
        cases.append(('k:' + encode(public(scalar,compressed)),encode(public(scalar))))
for data in [b'',b'\x00',public(1)[:-1],b'\x06'+public(1)[1:],b'\x04'+bytes(64),
             b'\x02'+P.to_bytes(32,'big'), b'\x04'+P.to_bytes(32,'big')+bytes(32),
             [4]+[0]*63+[256]]:
    cases.append(('k:' + encode(data),'key'))
for x in range(1,100):
    rhs = (x*x*x-3*x+B)%P
    if pow(rhs,(P-1)//2,P) == P-1:
        cases.append(('k:' + encode(b'\x02'+x.to_bytes(32,'big')),'key'))
        break
for a,b in [(1,1),(1,2),(1,N-1),(2,N-1)]:
    result = (a+b)%N
    cases.append(('a:'+encode(public(a))+':'+encode(public(b)),encode(public(result)) if result else 'infinity'))
for scalar in [0,1,2,3,N,N+1]:
    cases.append(('m:'+encode(public(1))+':'+encode(scalar.to_bytes(32,'big')),encode(public(scalar%N)) if scalar%N else 'infinity'))
for scalar,message,compressed in [(1,b'sample',False),(123456789,b'',True),(rng.randrange(1,N),bytes(range(256)),False)]:
    private = ec.derive_private_key(scalar,ec.SECP256R1())
    signature = private.sign(message,ec.ECDSA(hashes.SHA256()))
    key = public(scalar,compressed)
    cases.append(('v:'+encode(key)+':'+encode(message)+':'+encode(signature),'ok'))
    if scalar == 1:
        r,s = utils.decode_dss_signature(signature)
        cases.append(('v:'+encode(key)+':'+encode(message)+':'+encode(utils.encode_dss_signature(r,N-s)),'ok'))
        cases.append(('v:'+encode(key)+':'+encode(message+b'x')+':'+encode(signature),'signature'))
        cases.append(('v:'+encode(key)+':'+encode(message)+':'+encode(utils.encode_dss_signature(r,(s% (N-1))+1)),'signature'))
for r,s in [(0,1),(1,0),(N,1),(1,N),(N+1,1),(1,N+1)]:
    cases.append(('v:'+encode(public(1))+'::'+encode(utils.encode_dss_signature(r,s)),'signature'))
for signature,expected in [(b'\x30\x00','signature'),(b'\x30\x03\x02\x01\x01','signature'),
                           (b'\x30\x06\x02\x01\xff\x02\x01\x01','encoding'),
                           (b'\x30\x07\x02\x02\x00\x01\x02\x01\x01','encoding'),
                           (b'\x30\x06\x02\x01\x01\x02\x01\x01\x00','encoding')]:
    cases.append(('v:'+encode(public(1))+'::'+encode(signature),expected))

# Affine reference arithmetic is only used to construct rare verification
# cases; OpenSSL independently confirms the valid signature below.
def add(a,b):
    if a is None: return b
    if b is None: return a
    if a[0] == b[0]:
        if (a[1]+b[1])%P == 0: return None
        slope = (3*a[0]*a[0]-3)*pow(2*a[1],-1,P)%P
    else:
        slope = (b[1]-a[1])*pow(b[0]-a[0],-1,P)%P
    x = (slope*slope-a[0]-b[0])%P
    return x,(slope*(a[0]-x)-a[1])%P


def multiply(k,point):
    result = None
    while k:
        if k&1: result=add(result,point)
        point=add(point,point)
        k>>=1
    return result


g = ec.derive_private_key(1,ec.SECP256R1()).public_key().public_numbers()
g = (g.x,g.y)
message = b'projective verification edge'
z = int.from_bytes(hashlib.sha256(message).digest(),'big')
# u1*G + u2*Q = infinity must reject.
key = public((-z)%N)
cases.append(('v:'+encode(key)+':'+encode(message)+':'+encode(utils.encode_dss_signature(1,1)),'signature'))
# Cover the x=r+n branch, which random signatures almost never encounter.
x=N
while True:
    x+=1
    rhs=(x*x*x-3*x+B)%P
    y=pow(rhs,(P+1)//4,P)
    if y*y%P==rhs: break
r=x-N
q=multiply(pow(r,-1,N),add((x,y),multiply((-z)%N,g)))
signature=utils.encode_dss_signature(r,1)
key=ec.EllipticCurvePublicNumbers(*q,ec.SECP256R1()).public_key()
key.verify(signature,message,ec.ECDSA(hashes.SHA256()))
cases.append(('v:'+encode(wire(q))+':'+encode(message)+':'+encode(signature),'ok'))

for name,command in [('native-1',['build/p256','--threads','1']),
                     ('native-4',['build/p256','--threads','4']),
                     ('bun',['bun','build/p256.js'])]:
    start=time.monotonic()
    run=subprocess.run(command+[arg for arg,_ in cases],cwd=ROOT,capture_output=True,text=True,timeout=600)
    assert run.returncode==0,(name,run.stderr[-2000:])
    lines=run.stdout.splitlines()
    assert len(lines)==len(cases),(name,len(lines),len(cases))
    for i,(actual,(_,expected)) in enumerate(zip(lines,cases)):
        assert actual==expected,(name,i,actual[:100],expected[:100])
    print(f'{name}: {len(cases)} P256 checks PASS in {time.monotonic()-start:.2f}s',flush=True)

"""X509 wire extraction and native RSA signatures, not certificate trust."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import subprocess
import random
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec, padding
from cryptography.x509.oid import NameOID

ROOT = Path(__file__).resolve().parents[1]


def encode(data):
    return ','.join(map(str, data))


def tlv(tag, data):
    size = len(data)
    length = bytes([size]) if size < 128 else bytes([128 + (size.bit_length()+7)//8]) + size.to_bytes((size.bit_length()+7)//8, 'big')
    return bytes([tag]) + length + data


def split(data):
    size, pos = data[1], 2
    if size >= 128:
        count = size & 127
        size = int.from_bytes(data[pos:pos+count], 'big')
        pos += count
    return data[:pos+size], data[pos:pos+size], data[pos+size:]


def children(data):
    _, rest, tail = split(data)
    assert not tail
    result = []
    while rest:
        node, _, rest = split(rest)
        result.append(node)
    return result


def make_certificate(name, public_key, issuer, signing_key, serial):
    now = datetime.now(timezone.utc)
    return (x509.CertificateBuilder().subject_name(name).issuer_name(issuer).public_key(public_key)
            .serial_number(serial).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=1))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), False)
            .add_extension(x509.BasicConstraints(ca=(name == issuer), path_length=2 if name == issuer else None), True)
            .sign(signing_key, hashes.SHA256()))


issuer = rsa.generate_private_key(public_exponent=65537, key_size=2048)
other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'test issuer')])
subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
root = make_certificate(name, issuer.public_key(), name, issuer, 1)
wrong = make_certificate(name, other.public_key(), name, other, 2)
certs = [root,
         make_certificate(subject, other.public_key(), name, issuer, 128),
         make_certificate(subject, ec.generate_private_key(ec.SECP256R1()).public_key(), name, issuer, 129)]
root_der = root.public_bytes(serialization.Encoding.DER)
wrong_der = wrong.public_bytes(serialization.Encoding.DER)
cases = []
for certificate in certs:
    wire = certificate.public_bytes(serialization.Encoding.DER)
    tbs, algorithm, signature = children(wire)
    cases.append(('p:' + encode(wire), encode(certificate.tbs_certificate_bytes) + '|' + encode(algorithm) + '|' + encode(certificate.signature)))
    key = certificate.public_key()
    if isinstance(key, rsa.RSAPublicKey):
        numbers = key.public_numbers()
        exponent = numbers.e.to_bytes((numbers.e.bit_length()+7)//8, 'big')
        cases.append(('k:' + encode(wire), str(numbers.n) + '|' + encode(exponent) + '|' + str((numbers.n.bit_length()+7)//8) + '|' + str(numbers.n.bit_length())))
    else:
        cases.append(('k:' + encode(wire), 'algorithm'))
    cases.append(('v:' + encode(root_der) + ':' + encode(wire), 'ok'))
    cases.append(('v:' + encode(wrong_der) + ':' + encode(wire), 'signature'))
    bad = bytearray(wire)
    bad[-1] ^= 1
    cases.append(('v:' + encode(root_der) + ':' + encode(bad), 'signature'))

# Signature algorithm consistency is checked even before RSA verification.
tbs, algorithm, signature = children(root_der)
fields = children(tbs)
assert fields[0] == b'\xa0\x03\x02\x01\x02'
assert fields[2] == algorithm
changed_algorithm = algorithm[:-3] + b'\x0c\x05\x00'
changed_fields = list(fields)
changed_fields[2] = changed_algorithm
bad = tlv(48, tlv(48, b''.join(changed_fields)) + algorithm + signature)
cases.append(('v:' + encode(root_der) + ':' + encode(bad), 'certificate'))
bad = tlv(48, tbs + changed_algorithm + signature)
cases.append(('v:' + encode(root_der) + ':' + encode(bad), 'algorithm'))

# A v1 certificate omits the DEFAULT version and contains no v3 extensions.
v1_tbs = tlv(48, b''.join(fields[1:7]))
v1_signature = issuer.sign(v1_tbs, padding.PKCS1v15(), hashes.SHA256())
v1 = tlv(48, v1_tbs + algorithm + tlv(3, b'\x00' + v1_signature))
numbers = issuer.public_key().public_numbers()
cases.append(('k:' + encode(v1), str(numbers.n) + '|1,0,1|256|2048'))
cases.append(('v:' + encode(root_der) + ':' + encode(v1), 'ok'))
for version in [0, 3]:
    bad_fields = [tlv(160, b'\x02\x01' + bytes([version]))] + fields[1:]
    bad = tlv(48, tlv(48, b''.join(bad_fields)) + algorithm + signature)
    cases.append(('k:' + encode(bad), 'certificate'))

for size in [0, 1, 2, 3, 4, len(root_der)-1]:
    cases.append(('p:' + encode(root_der[:size]), 'encoding'))
for bad, expected in [(root_der + b'\x00', 'encoding'), (b'\x30\x80\x00\x00', 'encoding'),
                      (tlv(48, b''), 'certificate'), (tlv(48, tbs + algorithm), 'certificate'),
                      (tlv(48, tbs + algorithm + signature + b'\x05\x00'), 'certificate'),
                      (tlv(48, tbs + algorithm + b'\x03\x01\x00'), 'certificate'),
                      (tlv(48, tbs + algorithm + b'\x03\x02\x01\x80'), 'certificate')]:
    cases.append(('p:' + encode(bad), expected))

# A canonical TLV with a negative RSA modulus must not become an unsigned key.
spki = children(fields[6])
_, bit_content, _ = split(spki[1])
modulus, exponent = children(bit_content[1:])
_, modulus_content, _ = split(modulus)
assert modulus_content[0] == 0
bad_key = tlv(48, tlv(2, modulus_content[1:]) + exponent)
bad_spki = tlv(48, spki[0] + tlv(3, b'\x00' + bad_key))
bad_fields = fields[:6] + [bad_spki] + fields[7:]
bad = tlv(48, tlv(48, b''.join(bad_fields)) + algorithm + signature)
cases.append(('k:' + encode(bad), 'encoding'))

def milliseconds(value):
    delta = value - datetime(1970, 1, 1, tzinfo=timezone.utc)
    return delta.days * 86400000 + delta.seconds * 1000 + delta.microseconds // 1000


def words(value):
    value %= 2**64
    return str(value >> 32) + ',' + str(value & (2**32-1))


def time_wire(value, generalized=True):
    year = f'{value.year:04}' if generalized else f'{value.year % 100:02}'
    text = year + f'{value.month:02}{value.day:02}{value.hour:02}{value.minute:02}{value.second:02}Z'
    return tlv(24 if generalized else 23, text.encode())


rng = random.Random(5280)
for year in [1, 1900, 1950, 1969, 1970, 1999, 2000, 2049, 2050, 2100, 2400, 9999]:
    for month, day in [(1, 1), (2, 28), (12, 31)]:
        value = datetime(year, month, day, 23, 59, 59, tzinfo=timezone.utc)
        cases.append(('t:' + encode(time_wire(value)), words(milliseconds(value))))
        if 1950 <= year <= 2049:
            cases.append(('t:' + encode(time_wire(value, False)), words(milliseconds(value))))
for _ in range(60):
    value = datetime(rng.randrange(1,10000), rng.randrange(1,13), rng.randrange(1,29),
                     rng.randrange(24), rng.randrange(60), rng.randrange(60), tzinfo=timezone.utc)
    cases.append(('t:' + encode(time_wire(value)), words(milliseconds(value))))
for year in [2000, 2024, 2400]:
    value = datetime(year, 2, 29, tzinfo=timezone.utc)
    cases.append(('t:' + encode(time_wire(value)), words(milliseconds(value))))
for text in ['20230229000000Z', '21000229000000Z', '19000229000000Z', '20260001000000Z',
             '20261301000000Z', '20260100000000Z', '20260431000000Z', '20260101240000Z',
             '20260101006000Z', '20260101000060Z', '20260101000000+0000', '20260101000000.0Z',
             '202601010000Z', '20260101000000z', '202a0101000000Z', '100000101000000Z']:
    cases.append(('t:' + encode(tlv(24, text.encode())), 'time'))
for text in ['5001010000Z', '500101000000+0000', '500101000000.0Z', '500101000000z', '5a0101000000Z']:
    cases.append(('t:' + encode(tlv(23, text.encode())), 'time'))
cases.append(('t:' + encode(tlv(4, b'20260101000000Z')), 'time'))

for start, end in [(datetime(1950,1,1,tzinfo=timezone.utc), datetime(2000,1,1,tzinfo=timezone.utc)),
                   (datetime(1969,12,31,23,59,59,tzinfo=timezone.utc), datetime(1970,1,1,tzinfo=timezone.utc)),
                   (datetime(2050,1,1,tzinfo=timezone.utc), datetime(9999,12,31,23,59,59,tzinfo=timezone.utc))]:
    period = tlv(48, time_wire(start) + time_wire(end))
    cases.append(('range:' + encode(period), words(milliseconds(start)) + '|' + words(milliseconds(end))))
    cases.append(('range:' + encode(tlv(48,time_wire(end)+time_wire(start))), 'time'))
    changed_fields = list(fields)
    changed_fields[4] = period
    dated = tlv(48, tlv(48,b''.join(changed_fields)) + algorithm + signature)
    for at, expected in [(milliseconds(start)-1,'early'),(milliseconds(start),'ok'),
                         (milliseconds(end),'ok'),(milliseconds(end)+1,'expired')]:
        cases.append(('a:' + encode(dated) + ':' + words(at).replace(',',':'), expected))
value = datetime(2000,2,29,tzinfo=timezone.utc)
cases.append(('range:' + encode(tlv(48,time_wire(value)*2)), words(milliseconds(value)) + '|' + words(milliseconds(value))))
for content in [b'', time_wire(value), time_wire(value)*3]:
    cases.append(('range:' + encode(tlv(48,content)), 'time'))

def integer_node(value):
    raw = value.to_bytes(max(1,(value.bit_length()+7)//8),'big')
    return tlv(2,(b'\x00' if raw[0] >= 128 else b'') + raw)


def extension(oid, value, critical=None):
    flag = b'' if critical is None else tlv(1,critical)
    return tlv(48,tlv(6,oid)+flag+tlv(4,value))


def with_optional(optional, version=2):
    first = [] if version == 0 else [tlv(160,integer_node(version))]
    return tlv(48,tlv(48,b''.join(first + fields[1:7]) + optional) + algorithm + signature)


bc_oid = bytes([85,29,19])
san_oid = bytes([85,29,17])
leaf = tlv(48,b'')
ca = tlv(48,b'\x01\x01\xff')
for data, expected in [(leaf,'leaf:none'),(ca,'ca:none')]:
    cases.append(('basic:' + encode(data),expected))
for value in [0,1,2,255,256,2**256]:
    data = tlv(48,b'\x01\x01\xff' + integer_node(value))
    cases.append(('basic:' + encode(data),'ca:' + str(value)))
for content, expected in [(b'\x01\x01\x00','certificate'),(b'\x01\x01\x01','certificate'),
                          (integer_node(0),'certificate'),(b'\x01\x01\xff\x02\x01\xff','encoding'),
                          (b'\x01\x01\xff\x02\x02\x00\x01','encoding'),
                          (b'\x01\x01\xff' + integer_node(0)*2,'certificate')]:
    cases.append(('basic:' + encode(tlv(48,content)),expected))

for certificate in certs:
    wire = certificate.public_bytes(serialization.Encoding.DER)
    extensions_field = children(children(wire)[0])[-1]
    _, sequence_bytes, _ = split(extensions_field)
    expected = 'extensions'
    for item in children(sequence_bytes):
        items = children(item)
        _, oid, _ = split(items[0])
        critical = len(items) == 3
        _, value, _ = split(items[-1])
        expected += '|' + encode(oid) + ':' + str(int(critical)) + ':' + encode(value)
    cases.append(('ex:' + encode(wire),expected))

unknown_oid = bytes([42,3,4])
for critical in [None,b'\xff']:
    ex = extension(unknown_oid,b'opaque',critical)
    wire = with_optional(tlv(163,tlv(48,ex)))
    cases.append(('ex:' + encode(wire),'extensions|' + encode(unknown_oid) + ':' + str(int(critical is not None)) + ':' + encode(b'opaque')))

valid = extension(bc_oid,ca,b'\xff')
for contents, expected in [(b'','certificate'),(valid+valid,'duplicate'),
                           (valid+extension(bc_oid,leaf),'duplicate'),
                           (extension(bc_oid,ca,b'\x00'),'certificate'),
                           (extension(bc_oid,ca,b'\x01'),'certificate'),
                           (extension(b'',leaf),'certificate'),
                           (extension(b'\x80\x2a',leaf),'certificate'),
                           (extension(b'\x2a\x80\x01',leaf),'certificate'),
                           (extension(b'\x2a\x81',leaf),'certificate'),
                           (tlv(48,tlv(6,bc_oid)+tlv(4,leaf)+tlv(5,b'')),'certificate')]:
    cases.append(('ex:' + encode(with_optional(tlv(163,tlv(48,contents)))),expected))

ext_field = tlv(163,tlv(48,valid))
uid1, uid2 = tlv(129,b'\x00\x80'), tlv(130,b'\x07\x80')
for version in [0,1,2]:
    cases.append(('ex:' + encode(with_optional(b'',version)),'extensions'))
    cases.append(('ex:' + encode(with_optional(ext_field,version)), 'extensions|85,29,19:1:' + encode(ca) if version == 2 else 'certificate'))
    cases.append(('ex:' + encode(with_optional(uid1+uid2,version)), 'certificate' if version == 0 else 'extensions'))
for optional, expected in [(uid2+uid1,'certificate'),(uid1+uid1,'certificate'),
                           (tlv(161,b'\x00'),'certificate'),(tlv(129,b'\x01\x01'),'encoding'),
                           (ext_field+uid1,'certificate'),(ext_field+ext_field,'certificate'),
                           (tlv(163,tlv(48,valid)+tlv(5,b'')),'encoding')]:
    cases.append(('ex:' + encode(with_optional(optional)),expected))

for name, command in [('native-1', ['build/x509', '--threads', '1']),
                      ('native-4', ['build/x509', '--threads', '4']),
                      ('bun', ['bun', 'build/x509.js'])]:
    run = subprocess.run(command + [arg for arg, _ in cases], cwd=ROOT, capture_output=True, text=True, timeout=180)
    assert run.returncode == 0, (name, run.stderr[-2000:])
    lines = run.stdout.splitlines()
    assert len(lines) == len(cases), (name, len(lines), len(cases))
    for i, (actual, (_, expected)) in enumerate(zip(lines, cases)):
        assert actual == expected, (name, i, actual[:100], expected[:100])
    print(f'{name}: {len(cases)} X509 checks PASS', flush=True)

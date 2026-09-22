"""X509 wire extraction and native RSA/ECDSA signatures, not certificate trust."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import subprocess
import sys
import random
import ipaddress
import tempfile
import ctypes
import ctypes.util
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec, padding
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = sys.argv[1] if len(sys.argv) > 1 else "build/x509"


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


def make_certificate(name, public_key, issuer, signing_key, serial, algorithm=None):
    now = datetime.now(timezone.utc)
    return (x509.CertificateBuilder().subject_name(name).issuer_name(issuer).public_key(public_key)
            .serial_number(serial).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=1))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), False)
            .add_extension(x509.BasicConstraints(ca=(name == issuer), path_length=2 if name == issuer else None), True)
            .add_extension(x509.KeyUsage(name != issuer, False, False, False, False, name == issuer, name == issuer, False, False), True)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), False)
            .sign(signing_key, algorithm or hashes.SHA256()))


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
        cases.append(('k:' + encode(wire), 'p256:' + encode(key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)[1:])))
    cases.append(('v:' + encode(root_der) + ':' + encode(wire), 'ok'))
    cases.append(('v:' + encode(wrong_der) + ':' + encode(wire), 'signature'))
    bad = bytearray(wire)
    bad[-1] ^= 1
    cases.append(('v:' + encode(root_der) + ':' + encode(bad), 'signature'))

# ECDSA issuer signs both RSA and P256 subject keys. Verification dispatches
# on the issuer key and signature algorithm, not the subject key algorithm.
ec_issuer = ec.generate_private_key(ec.SECP256R1())
ec_other = ec.generate_private_key(ec.SECP256R1())
ec_root = make_certificate(name, ec_issuer.public_key(), name, ec_issuer, 10)
ec_wrong = make_certificate(name, ec_other.public_key(), name, ec_other, 11)
ec_root_der = ec_root.public_bytes(serialization.Encoding.DER)
ec_wrong_der = ec_wrong.public_bytes(serialization.Encoding.DER)
for cert in [ec_root, make_certificate(subject, other.public_key(), name, ec_issuer, 12)]:
    wire = cert.public_bytes(serialization.Encoding.DER)
    ec_issuer.public_key().verify(cert.signature, cert.tbs_certificate_bytes, ec.ECDSA(hashes.SHA256()))
    cases.append(('v:' + encode(ec_root_der) + ':' + encode(wire), 'ok'))
    cases.append(('v:' + encode(ec_wrong_der) + ':' + encode(wire), 'curve'))
    cases.append(('v:' + encode(root_der) + ':' + encode(wire), 'algorithm'))
    bad = bytearray(wire)
    bad[-1] ^= 1
    cases.append(('v:' + encode(ec_root_der) + ':' + encode(bad), 'curve'))
cases.append(('v:' + encode(ec_root_der) + ':' + encode(root_der), 'algorithm'))
# Certificate ECDSA hash and curve are independent: P256 with SHA384
# truncates the digest; P384 with SHA256 uses the entire shorter digest.
for curve in [ec.SECP256R1(), ec.SECP384R1()]:
    signer = ec.generate_private_key(curve)
    authority = make_certificate(name,signer.public_key(),name,signer,21)
    authority_der = authority.public_bytes(serialization.Encoding.DER)
    if curve.key_size == 384:
        cases.append(('k:'+encode(authority_der),'p384:'+encode(signer.public_key().public_bytes(serialization.Encoding.X962,serialization.PublicFormat.UncompressedPoint)[1:])))
    for algorithm in [hashes.SHA256(),hashes.SHA384()]:
        certificate = make_certificate(subject,ec_issuer.public_key(),name,signer,22,algorithm)
        signer.public_key().verify(certificate.signature,certificate.tbs_certificate_bytes,ec.ECDSA(algorithm))
        wire = certificate.public_bytes(serialization.Encoding.DER)
        cases.append(('v:'+encode(authority_der)+':'+encode(wire),'ok'))
        bad = bytearray(wire); bad[-1] ^= 1
        cases.append(('v:'+encode(authority_der)+':'+encode(bad),'curve'))

# EC algorithm parameters must identify P256 exactly; compressed points work.
etbs, ealg, esig = children(ec_root_der)
efields = children(etbs)
espki = children(efields[6])
public = ec_issuer.public_key()
for point_format in [serialization.PublicFormat.CompressedPoint, serialization.PublicFormat.UncompressedPoint]:
    point = public.public_bytes(serialization.Encoding.X962, point_format)
    replacement = tlv(48, espki[0] + tlv(3, b'\x00' + point))
    wire = tlv(48, tlv(48, b''.join(efields[:6] + [replacement] + efields[7:])) + ealg + esig)
    expected = 'p256:' + encode(public.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)[1:])
    cases.append(('k:' + encode(wire), expected))
for alg, point, expected in [(espki[0][:-1] + b'\x08', b'\x04' + bytes(64), 'algorithm'),
                              (espki[0], b'\x04' + bytes(64), 'curve'),
                              (espki[0], b'\x00', 'curve')]:
    replacement = tlv(48, alg + tlv(3, b'\x00' + point))
    wire = tlv(48, tlv(48, b''.join(efields[:6] + [replacement] + efields[7:])) + ealg + esig)
    cases.append(('k:' + encode(wire), expected))
# Explicit NULL is not legal for ecdsa-with-SHA256. Keep inner/outer identical
# so this tests algorithm selection rather than the consistency check.
invalid_alg = tlv(48, split(ealg)[1] + b'\x05\x00')
bad_fields = efields[:2] + [invalid_alg] + efields[3:]
wire = tlv(48, tlv(48,b''.join(bad_fields)) + invalid_alg + esig)
cases.append(('v:' + encode(ec_root_der) + ':' + encode(wire), 'algorithm'))

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
cases.append(('v:' + encode(root_der) + ':' + encode(bad), 'certificate'))

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

for mask in range(1,512):
    flags = [bool(mask & (1 << i)) for i in range(9)]
    text = ''.join('1' if b else '0' for b in flags).rstrip('0')
    unused = -len(text) % 8
    payload = int(text + '0'*unused,2).to_bytes((len(text)+7)//8,'big')
    wire = tlv(3,bytes([unused]) + payload)
    if flags[4] or not (flags[7] or flags[8]):
        assert x509.KeyUsage(*flags).public_bytes() == wire
    cases.append(('ku:' + encode(wire),str(mask)))
for wire, expected in [(b'\x03\x01\x00','certificate'),(b'\x03\x02\x00\x00','certificate'),
                       (b'\x03\x02\x00\x80','certificate'),(b'\x03\x03\x00\x80\x00','certificate'),
                       (b'\x03\x03\x06\x00\x40','certificate'),(b'\x03\x02\x07\x81','encoding'),
                       (b'\x03\x04\x07\x80\x00\x80','certificate'),(b'\x23\x02\x07\x80','encoding')]:
    cases.append(('ku:' + encode(wire),expected))
server_purpose = bytes([43,6,1,5,5,7,3,1])
client_purpose = bytes([43,6,1,5,5,7,3,2])
any_purpose = bytes([85,29,37,0])
for purposes in [[server_purpose],[client_purpose],[any_purpose],
                 [server_purpose,client_purpose,unknown_oid],[unknown_oid,server_purpose],
                 [server_purpose,server_purpose]]:
    wire = tlv(48,b''.join(tlv(6,p) for p in purposes))
    cases.append(('eku:' + encode(wire),'purposes' + ''.join('|' + encode(p) for p in purposes)))
assert x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]).public_bytes() == tlv(48,tlv(6,server_purpose))
for content in [b'',tlv(6,b''),tlv(6,b'\x80\x2a'),tlv(6,b'\x2a\x80\x01'),
                tlv(6,b'\x2a\x81'),tlv(4,server_purpose),tlv(38,server_purpose)]:
    cases.append(('eku:' + encode(tlv(48,content)),'certificate'))
cases.append(('eku:' + encode(tlv(48,tlv(6,server_purpose)) + b'\x00'),'encoding'))

san_values = [x509.DNSName('localhost'),x509.DNSName('*.example.com'),x509.DNSName('xn--bcher-kva.example'),
              x509.IPAddress(ipaddress.ip_address('127.0.0.1')),x509.IPAddress(ipaddress.ip_address('2001:db8::1')),
              x509.RFC822Name('test@example.com'),x509.UniformResourceIdentifier('https://example.com/path'),
              x509.RegisteredID(x509.ObjectIdentifier('1.2.3.4')),
              x509.DirectoryName(subject),x509.OtherName(x509.ObjectIdentifier('1.2.3.4'),tlv(12,b'value'))]
for values in [[value] for value in san_values] + [san_values]:
    wire = x509.SubjectAlternativeName(values).public_bytes()
    expected = 'names'
    for value,node in zip(values,children(wire)):
        if isinstance(value,x509.DNSName): kind, data = 'dns',value.value.encode()
        elif isinstance(value,x509.IPAddress): kind, data = 'ip',value.value.packed
        elif isinstance(value,x509.RFC822Name): kind, data = 'mail',value.value.encode()
        elif isinstance(value,x509.UniformResourceIdentifier): kind, data = 'uri',value.value.encode()
        elif isinstance(value,x509.RegisteredID): kind, data = 'oid',unknown_oid
        else: kind, data = 'structured',node
        expected += '|' + kind + ':' + encode(data)
    cases.append(('san:' + encode(wire),expected))
# IA5 is decoded without normalization or identity matching. Embedded bytes
# stay intact; the identity policy must separately reject unsuitable DNS names.
for text in [b'EXAMPLE.com',b'api*.example.com',b'a,b.example',b'a\x00.example']:
    cases.append(('san:' + encode(tlv(48,tlv(130,text))),'names|dns:' + encode(text)))
for tag in [129,130,134]:
    for value in [b'',b'\x80',b'\xff',b'\xc3\xa4']:
        cases.append(('san:' + encode(tlv(48,tlv(tag,value))),'certificate'))
for size in [0,1,3,5,15,17,32]:
    cases.append(('san:' + encode(tlv(48,tlv(135,bytes(size)))),'certificate'))
for value in [b'',b'\x80\x2a',b'\x2a\x80\x01',b'\x2a\x81']:
    cases.append(('san:' + encode(tlv(48,tlv(136,value))),'certificate'))
for tag in [128,131,132,133,137,162,167,168,169]:
    cases.append(('san:' + encode(tlv(48,tlv(tag,b'\x05\x00'))),'certificate'))
cases += [('san:' + encode(tlv(48,b'')),'certificate'),
          ('san:' + encode(tlv(48,tlv(164,b'\x30\x01'))),'encoding'),
          ('san:' + encode(tlv(48,tlv(130,b'example.com')) + b'\x00'),'encoding')]

# Certificate policy is checked independently of signature/name/time/path
# construction. OpenSSL is the external oracle for purpose and intermediate
# constraints; TLS1.3's digitalSignature requirement is stricter than the
# protocol-independent sslserver purpose (which also permits RSA encipherment).
def policy_certificate(cert_name, public, issuer_name, signer, basic, usage, eku, extra=None, identifiers=False, period=None):
    now = datetime.now(timezone.utc)
    start,end = period or (now-timedelta(days=1),now+timedelta(days=1))
    builder = (x509.CertificateBuilder().subject_name(cert_name).issuer_name(issuer_name).public_key(public)
               .serial_number(500).not_valid_before(start).not_valid_after(end))
    if identifiers:
        builder = builder.add_extension(x509.SubjectKeyIdentifier.from_public_key(public),False)
        builder = builder.add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(signer.public_key()),False)
    if basic is not None:
        builder = builder.add_extension(x509.BasicConstraints(*basic),True)
    if usage is not None:
        builder = builder.add_extension(x509.KeyUsage(bool(usage&1),False,bool(usage&4),False,False,bool(usage&32),False,False,False),True)
    if eku is not None:
        builder = builder.add_extension(x509.ExtendedKeyUsage(eku),False)
    if extra is not None:
        builder = builder.add_extension(*extra)
    return builder.sign(signer,hashes.SHA256())


def cert_wire(cert):
    return cert.public_bytes(serialization.Encoding.DER)


with tempfile.TemporaryDirectory(prefix='pi-bend-x509-policy-') as temp:
    folder = Path(temp)
    (folder/'root.pem').write_bytes(root.public_bytes(serialization.Encoding.PEM))
    def openssl_accepts(leaf, intermediates=()):
        (folder/'leaf.pem').write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
        args = ['openssl','verify','-CAfile',str(folder/'root.pem'),'-purpose','sslserver']
        if intermediates:
            (folder/'chain.pem').write_bytes(b''.join(cert.public_bytes(serialization.Encoding.PEM) for cert in intermediates))
            args += ['-untrusted',str(folder/'chain.pem')]
        result = subprocess.run(args+[str(folder/'leaf.pem')],capture_output=True,text=True,timeout=10)
        return result.returncode == 0
    server_oid, client_oid, any_oid = ExtendedKeyUsageOID.SERVER_AUTH, ExtendedKeyUsageOID.CLIENT_AUTH, ExtendedKeyUsageOID.ANY_EXTENDED_KEY_USAGE
    for eku in [None,[server_oid],[client_oid],[any_oid],[any_oid,server_oid],[ExtendedKeyUsageOID.CODE_SIGNING]]:
        for usage in [None,1,4,5]:
            cert = policy_certificate(subject,other.public_key(),name,issuer,(False,None),usage,eku)
            purpose_ok = eku is None or server_oid in eku
            assert openssl_accepts(cert) == purpose_ok,(eku,usage)
            expected = 'purpose' if not purpose_ok else ('usage' if usage==4 else 'ok')
            cases.append(('server:'+encode(cert_wire(cert)),expected))
    for critical in [False,True]:
        extra = (x509.UnrecognizedExtension(x509.ObjectIdentifier('1.2.3.4.5'),b'opaque'),critical)
        cert = policy_certificate(subject,other.public_key(),name,issuer,(False,None),1,None,extra)
        assert openssl_accepts(cert) == (not critical)
        cases.append(('server:'+encode(cert_wire(cert)),'critical' if critical else 'ok'))
    intermediate_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'intermediate')])
    leaf = policy_certificate(subject,issuer.public_key(),intermediate_name,other,(False,None),1,None)
    for basic in [None,(False,None),(True,None),(True,0),(True,1)]:
        for usage in [None,1,32,33]:
            for eku in [None,[server_oid],[client_oid],[any_oid]]:
                ca = basic is not None and basic[0]
                allowed_usage = usage is None or usage&32
                allowed_purpose = eku is None or server_oid in eku
                intermediate = policy_certificate(intermediate_name,other.public_key(),name,issuer,basic,usage,eku)
                accepted = openssl_accepts(leaf,[intermediate])
                assert accepted == bool(ca and allowed_usage and allowed_purpose),(basic,usage,eku,accepted)
                expected = 'ca' if not ca else ('usage' if not allowed_usage else ('purpose' if not allowed_purpose else 'ok'))
                cases.append(('issuer:0:'+encode(cert_wire(intermediate)),expected))
    child_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'child CA')])
    child = policy_certificate(child_name,other.public_key(),intermediate_name,other,(True,0),32,None)
    child_leaf = policy_certificate(subject,issuer.public_key(),child_name,other,(False,None),1,None)
    for maximum in [0,1,2,None]:
        intermediate = policy_certificate(intermediate_name,other.public_key(),name,issuer,(True,maximum),32,None)
        assert openssl_accepts(child_leaf,[child,intermediate]) == (maximum is None or maximum>=1)
        for count in [0,1,2,3,2**80]:
            expected = 'ok' if maximum is None or count<=maximum else 'path'
            cases.append(('issuer:'+str(count)+':'+encode(cert_wire(intermediate)),expected))
    # A critical name constraint cannot be ignored while that implementation
    # remains pending, even though OpenSSL can process it.
    constrained = policy_certificate(intermediate_name,other.public_key(),name,issuer,(True,None),32,None,
                                     (x509.NameConstraints([x509.DNSName('example.com')],None),True))
    cases.append(('issuer:0:'+encode(cert_wire(constrained)),'critical'))
    san = policy_certificate(subject,other.public_key(),name,issuer,(False,None),1,None,
                             (x509.SubjectAlternativeName([x509.DNSName('localhost')]),True))
    assert openssl_accepts(san)
    cases.append(('server:'+encode(cert_wire(san)),'ok'))

# Read-only OpenSSL name comparison is a test oracle, never a production
# dependency. Keep allocations alive for d2i and free every parsed name.
crypto = ctypes.CDLL(ctypes.util.find_library('crypto'))
crypto.d2i_X509_NAME.argtypes = [ctypes.c_void_p,ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte)),ctypes.c_long]
crypto.d2i_X509_NAME.restype = ctypes.c_void_p
crypto.X509_NAME_cmp.argtypes = [ctypes.c_void_p,ctypes.c_void_p]
crypto.X509_NAME_cmp.restype = ctypes.c_int
crypto.X509_NAME_free.argtypes = [ctypes.c_void_p]

def openssl_name(wire):
    buffer = (ctypes.c_ubyte*len(wire)).from_buffer_copy(wire)
    cursor = ctypes.cast(buffer,ctypes.POINTER(ctypes.c_ubyte))
    result = crypto.d2i_X509_NAME(None,ctypes.byref(cursor),len(wire))
    assert result,wire.hex()
    return result

def name_equal(left,right):
    a = openssl_name(left)
    try:
        b = openssl_name(right)
        try: return crypto.X509_NAME_cmp(a,b)==0
        finally: crypto.X509_NAME_free(b)
    finally: crypto.X509_NAME_free(a)

def attribute(tag,data,oid=b'\x55\x04\x03'):
    return tlv(48,tlv(6,oid)+tlv(tag,data))

def dn(*rdns):
    return tlv(48,b''.join(tlv(49,b''.join(sorted(values))) for values in rdns))

def compare_name(left,right,expected):
    assert name_equal(left,right)==expected,(left.hex(),right.hex(),expected)
    cases.append(('dn:'+encode(left)+':'+encode(right),'same' if expected else 'different'))

plain = dn([attribute(12,b'alice smith')])
for tag,data in [(12,b'  ALICE\t \nSmith  '),(19,b' ALICE  Smith '),(20,b'Alice Smith'),
                 (22,b'ALICE\rSMITH'),(30,'Alice Smith'.encode('utf-16-be')),
                 (28,'Alice Smith'.encode('utf-32-be'))]:
    compare_name(plain,dn([attribute(tag,data)]),True)
for text in ['München','東京','😀','\ufeffAlice','', 'a\x00b']:
    original = dn([attribute(12,text.encode())])
    compare_name(original,dn([attribute(28,text.encode('utf-32-be'))]),True)
    if all(ord(c)<=65535 for c in text):
        compare_name(original,dn([attribute(30,text.encode('utf-16-be'))]),True)
compare_name(dn([attribute(20,b'M\xfcnchen')]),dn([attribute(12,'München'.encode())]),True)
for left,right in [('Ä','ä'),('é','e\u0301'),('alice','\ufeffalice'),('a b','a\u00a0b'),('a\x00b','ab')]:
    compare_name(dn([attribute(12,left.encode())]),dn([attribute(12,right.encode())]),False)
a,b = attribute(12,b' Alice '),attribute(12,b'Example',b'\x55\x04\x0a')
c,d = attribute(19,b'alice'),attribute(12,b' EXAMPLE ',b'\x55\x04\x0a')
compare_name(dn([a,b]),dn([d,c]),True)
compare_name(dn([a],[b]),dn([c,d]),False)
compare_name(dn([a],[b]),dn([d],[c]),False)
compare_name(dn([a,a]),dn([c]),False)
compare_name(dn([a,a]),dn([c,c]),True)
compare_name(dn(),dn(),True)
for tag,data in [(18,b' 12  3 '),(3,b'\x00\xaa'),(48,b'\x02\x01\x01')]:
    value = dn([attribute(tag,data)])
    compare_name(value,value,True)
compare_name(dn([attribute(18,b' 123 ')]),dn([attribute(18,b'123')]),False)
compare_name(dn([attribute(18,b'123')]),dn([attribute(19,b'123')]),False)
# Strict encodings are validated before any canonicalization or comparison.
for tag,data in [(12,b'\xc0\x80'),(12,b'\xed\xa0\x80'),(19,b'not@printable'),
                 (19,b'a\tb'),(22,b'\x80'),(30,b'\x00'),(30,b'\xd8\x00'),
                 (28,b'\x00\x11\x00\x00'),(28,b'\x00\x00\xd8\x00'),(28,b'\x00\x00\x00'),(18,b'abc')]:
    cases.append(('dn:'+encode(dn([attribute(tag,data)]))+':'+encode(plain),'certificate'))
for malformed in [tlv(48,tlv(49,b'')),tlv(48,a),dn([tlv(48,tlv(6,b'')+tlv(12,b'a'))]),
                  dn([tlv(48,tlv(6,b'\x80\x2a')+tlv(12,b'a'))]),dn([tlv(48,tlv(6,b'\x55\x04\x03'))]),
                  tlv(48,tlv(49,b''.join(sorted([a,b],reverse=True))))]:
    cases.append(('dn:'+encode(malformed)+':'+encode(plain),'certificate'))
cases.append(('dn:'+encode(dn([attribute(26,b'Alice')]))+':'+encode(plain),'name-encoding'))
cases += [('self:'+encode(root_der),'same'),('self:'+encode(certs[1].public_bytes(serialization.Encoding.DER)),'different')]

# Verify a supplied candidate path against an explicitly configured anchor.
# OpenSSL partial_chain expresses this explicit trust, independently of future
# trust-store loading/path discovery and hostname authorization.
with tempfile.TemporaryDirectory(prefix='pi-bend-x509-path-') as temp:
    folder = Path(temp)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    stamp = milliseconds(now)
    high,low = words(stamp).split(',')
    def chain_cert(cert_name, public, issuer_name, signer, basic, usage, eku=None, **kwargs):
        return policy_certificate(cert_name,public,issuer_name,signer,basic,usage,eku,identifiers=True,**kwargs)
    def path_case(anchor,leaf,chain,expected,oracle=True):
        if oracle:
            (folder/'anchor.pem').write_bytes(anchor.public_bytes(serialization.Encoding.PEM))
            (folder/'leaf.pem').write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
            args = ['openssl','verify','-trusted',str(folder/'anchor.pem'),'-partial_chain','-purpose','sslserver','-attime',str(stamp//1000)]
            if chain:
                (folder/'chain.pem').write_bytes(b''.join(c.public_bytes(serialization.Encoding.PEM) for c in chain))
                args += ['-untrusted',str(folder/'chain.pem')]
            result = subprocess.run(args+[str(folder/'leaf.pem')],capture_output=True,text=True,timeout=10)
            assert (result.returncode==0)==(expected=='ok'),(expected,result.stdout,result.stderr)
        args = ['chain',high,low,encode(cert_wire(anchor)),encode(cert_wire(leaf))]+[encode(cert_wire(c)) for c in chain]
        cases.append((':'.join(args),expected))
    middle_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'middle')])
    anchor = chain_cert(name,issuer.public_key(),name,issuer,(True,2),32)
    middle = chain_cert(middle_name,other.public_key(),name,issuer,(True,0),32)
    target = chain_cert(subject,issuer.public_key(),middle_name,other,(False,None),1)
    direct = chain_cert(subject,other.public_key(),name,issuer,(False,None),1)
    path_case(anchor,direct,[],'ok')
    path_case(anchor,target,[middle],'ok')
    path_case(anchor,target,[middle,anchor],'ok')
    path_case(direct,direct,[],'ok')
    path_case(wrong,direct,[],'signature')
    path_case(anchor,target,[],'issuer')
    bad_middle = chain_cert(middle_name,other.public_key(),name,other,(True,0),32)
    path_case(anchor,target,[bad_middle],'signature')
    for basic,usage,eku,expected in [((False,None),1,None,'ca'),((True,None),1,None,'usage'),((True,None),32,[ExtendedKeyUsageOID.CLIENT_AUTH],'purpose')]:
        candidate = chain_cert(middle_name,other.public_key(),name,issuer,basic,usage,eku)
        path_case(anchor,target,[candidate],expected)
    encipher = chain_cert(subject,other.public_key(),name,issuer,(False,None),4)
    path_case(anchor,encipher,[],'usage',oracle=False) # TLS1.3 signing requirement.
    expired_period = (now-timedelta(days=3),now-timedelta(days=2))
    future_period = (now+timedelta(days=2),now+timedelta(days=3))
    for period,expected in [(expired_period,'expired'),(future_period,'early')]:
        invalid_leaf = chain_cert(subject,other.public_key(),name,issuer,(False,None),1,period=period)
        path_case(anchor,invalid_leaf,[],expected)
        invalid_middle = chain_cert(middle_name,other.public_key(),name,issuer,(True,0),32,period=period)
        path_case(anchor,target,[invalid_middle],expected)
    expired_anchor = chain_cert(name,issuer.public_key(),name,issuer,(True,2),32,period=expired_period)
    path_case(expired_anchor,direct,[],'expired')
    zero_anchor = chain_cert(name,issuer.public_key(),name,issuer,(True,0),32)
    path_case(zero_anchor,target,[middle],'path')
    rollover = chain_cert(name,other.public_key(),name,issuer,(True,0),32)
    rollover_leaf = chain_cert(subject,issuer.public_key(),name,other,(False,None),1)
    path_case(zero_anchor,rollover_leaf,[rollover],'ok')
    # A configured anchor's own signature is not part of this candidate path.
    cross_anchor = chain_cert(name,issuer.public_key(),middle_name,other,(True,2),32)
    path_case(cross_anchor,direct,[],'ok')
    unknown = (x509.UnrecognizedExtension(x509.ObjectIdentifier('1.2.3.4.5'),b'opaque'),True)
    invalid_leaf = chain_cert(subject,other.public_key(),name,issuer,(False,None),1,extra=unknown)
    path_case(anchor,invalid_leaf,[],'critical')
    for critical in [False,True]:
        constraints = (x509.NameConstraints([x509.DNSName('example.com')],None),critical)
        constrained = chain_cert(middle_name,other.public_key(),name,issuer,(True,0),32,extra=constraints)
        path_case(anchor,target,[constrained],'critical' if critical else 'constraint',oracle=False)
    # Empty subjects require a critical, nonempty SAN. Empty issuer names fail.
    empty_name = x509.Name([])
    for critical,expected in [(True,'ok'),(False,'certificate')]:
        unnamed = chain_cert(empty_name,other.public_key(),name,issuer,(False,None),1,
                             extra=(x509.SubjectAlternativeName([x509.DNSName('localhost')]),critical))
        path_case(anchor,unnamed,[],expected,oracle=critical)
    unnamed = chain_cert(empty_name,other.public_key(),name,issuer,(False,None),1)
    path_case(anchor,unnamed,[],'certificate',oracle=False)

    def discover_case(leaf,peers,anchors,expected,oracle=True):
        if oracle and anchors:
            (folder/'anchors.pem').write_bytes(b''.join(c.public_bytes(serialization.Encoding.PEM) for c in anchors))
            (folder/'leaf.pem').write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
            args=['openssl','verify','-trusted',str(folder/'anchors.pem'),'-partial_chain','-purpose','sslserver','-attime',str(stamp//1000)]
            if peers:
                (folder/'peers.pem').write_bytes(b''.join(c.public_bytes(serialization.Encoding.PEM) for c in peers))
                args+=['-untrusted',str(folder/'peers.pem')]
            run=subprocess.run(args+[str(folder/'leaf.pem')],capture_output=True,text=True,timeout=10)
            assert (run.returncode==0)==(expected=='ok'),(expected,run.stdout,run.stderr)
        peer_text='|'.join(encode(cert_wire(c)) for c in peers)
        anchor_text='|'.join(encode(cert_wire(c)) for c in anchors)
        cases.append((':'.join(['discover',high,low,encode(cert_wire(leaf)),peer_text,anchor_text]),expected))

    discover_case(direct,[],[anchor],'ok')
    discover_case(target,[middle],[anchor],'ok')
    discover_case(target,[anchor,middle],[anchor],'ok')
    discover_case(target,[middle,anchor],[anchor],'ok')
    discover_case(target,[middle,middle,anchor],[anchor],'ok')
    discover_case(direct,[],[wrong,anchor],'ok')
    discover_case(target,[middle],[expired_anchor,anchor],'ok')
    discover_case(direct,[],[direct],'ok')
    discover_case(target,[],[middle],'ok') # Explicit intermediate trust.
    discover_case(target,[middle,anchor],[],'untrusted',oracle=False)
    discover_case(direct,[anchor],[],'untrusted',oracle=False)
    discover_case(target,[middle,anchor],[wrong],'untrusted')
    discover_case(target,[],[anchor],'untrusted')
    discover_case(target,[middle],[zero_anchor],'untrusted')
    discover_case(rollover_leaf,[rollover],[zero_anchor],'ok')
    discover_case(direct,[],[cross_anchor],'ok')
    for period in [expired_period,future_period]:
        invalid_middle=chain_cert(middle_name,other.public_key(),name,issuer,(True,0),32,period=period)
        discover_case(target,[invalid_middle,middle],[anchor],'ok')
    non_ca=chain_cert(middle_name,other.public_key(),name,issuer,(False,None),1)
    discover_case(target,[non_ca,middle],[anchor],'ok')
    discover_case(target,[non_ca],[anchor],'untrusted')
    wrong_key=chain_cert(middle_name,issuer.public_key(),name,issuer,(True,0),32)
    discover_case(target,[wrong_key,middle],[anchor],'ok')
    discover_case(target,[middle,wrong_key],[anchor],'ok')
    # The first same-key issuer reaches a dead end, so search must backtrack.
    dead_name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'untrusted authority')])
    dead_end=chain_cert(middle_name,other.public_key(),dead_name,issuer,(True,0),32)
    discover_case(target,[dead_end,middle],[anchor],'ok',oracle=False)
    discover_case(target,[dead_end],[anchor],'untrusted')
    # A real signature cycle cannot establish trust, and must terminate.
    cycle_name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'cycle')])
    cycle_a=chain_cert(middle_name,other.public_key(),cycle_name,issuer,(True,None),32)
    cycle_b=chain_cert(cycle_name,issuer.public_key(),middle_name,other,(True,None),32)
    discover_case(target,[cycle_a,cycle_b],[wrong],'untrusted')
    discover_case(target,[cycle_a,cycle_b,middle],[anchor],'ok',oracle=False)
    discover_case(target,[target,middle],[anchor],'ok')
    malformed_target=chain_cert(subject,other.public_key(),name,issuer,(False,None),1,period=expired_period)
    discover_case(malformed_target,[],[anchor],'expired')

for name, command in [('native-1', [ARTIFACT, '--threads', '1']),
                      ('native-4', [ARTIFACT, '--threads', '4']),
                      ('bun', ['bun', ARTIFACT+'.js'])]:
    run = subprocess.run(command + [arg for arg, _ in cases], cwd=ROOT, capture_output=True, text=True, timeout=600)
    assert run.returncode == 0, (name, run.stderr[-2000:])
    lines = run.stdout.splitlines()
    assert len(lines) == len(cases), (name, len(lines), len(cases))
    for i, (actual, (_, expected)) in enumerate(zip(lines, cases)):
        assert actual == expected, (name, i, actual[:100], expected[:100])
    print(f'{name}: {len(cases)} X509 checks PASS', flush=True)

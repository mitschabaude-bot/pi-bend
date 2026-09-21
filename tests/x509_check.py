"""X509 wire extraction and native RSA signatures, not certificate trust."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import subprocess
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

for name, command in [('native-1', ['build/x509', '--threads', '1']),
                      ('native-4', ['build/x509', '--threads', '4']),
                      ('bun', ['bun', 'build/x509.js'])]:
    run = subprocess.run(command + [arg for arg, _ in cases], cwd=ROOT, capture_output=True, text=True, timeout=180)
    assert run.returncode == 0, (name, run.stderr[-2000:])
    lines = run.stdout.splitlines()
    assert len(lines) == len(cases), (name, len(lines), len(cases))
    for i, (actual, (_, expected)) in enumerate(zip(lines, cases)):
        assert actual == expected, (name, i, actual[:100], expected[:100])
    print(f'{name}: {len(cases)} X509 extraction/signature checks PASS', flush=True)

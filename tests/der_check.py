"""Canonical DER framing and certificate byte preservation against references."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import random
import subprocess
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec
from cryptography.x509.oid import NameOID

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(5280)
cases = []


def encode(values):
    return ','.join(map(str, values))


def identifier(cls, constructed, number):
    first = cls * 64 + int(constructed) * 32
    if number < 31:
        return bytes([first + number])
    groups = [number & 127]
    number >>= 7
    while number:
        groups.append(128 | (number & 127))
        number >>= 7
    return bytes([first + 31] + list(reversed(groups)))


def header(cls, constructed, tag, size):
    length = bytes([size]) if size < 128 else bytes([128 + (size.bit_length()+7)//8]) + size.to_bytes((size.bit_length()+7)//8, 'big')
    return identifier(cls, constructed, tag) + length


def add_node(cls, constructed, tag, content, rest=b''):
    prefix = header(cls, constructed, tag, len(content))
    wire = prefix + content
    cases.append(('r:' + encode(wire + rest), f'{cls}:{int(constructed)}:{tag}|' + encode(prefix) + '|' + encode(content) + '|' + encode(rest)))
    cases.append(('o:' + encode(wire), encode(wire)))
    return wire


for cls in range(4):
    for constructed in [False, True]:
        for tag in [1, 2, 16, 30, 31, 127, 128, 16383, 16384, 2**32-1]:
            add_node(cls, constructed, tag, rng.randbytes(rng.randrange(12)), b'\x05\x00')
for size in [0, 1, 127, 128, 255, 256, 20000]:
    add_node(0, False, 4, rng.randbytes(size))
for value in [0, 1, 127, 128, 255, 256, 65535, 2**2048-1]:
    unsigned = value.to_bytes(max(1, (value.bit_length()+7)//8), 'big')
    content = (b'\x00' if unsigned[0] >= 128 else b'') + unsigned
    wire = header(0, False, 2, len(content)) + content
    cases.append(('u:' + encode(wire), 'ok:' + encode(unsigned)))
for unused in range(8):
    data = b'\xaa\x80'
    cases.append(('b:' + encode(b'\x03\x03' + bytes([unused]) + data), str(unused) + ':' + encode(data)))
cases.append(('b:3,1,0', '0:'))

bad = [([], 'truncated'), ([4], 'truncated'), ([4, 1], 'truncated'),
       ([4, 128, 0, 0], 'canonical'), ([4, 255], 'canonical'),
       ([4, 129, 127], 'canonical'), ([4, 130, 0, 128], 'canonical'),
       ([4, 133, 1, 0, 0, 0, 0], 'limit'), ([4, 132, 255, 255, 255, 255], 'truncated'),
       ([0, 0], 'canonical'), ([32, 0], 'canonical'), ([31, 30, 0], 'canonical'),
       ([31, 128, 31, 0], 'canonical'), ([31, 255, 255, 255, 255, 127, 0], 'limit'),
       ([31, 129], 'truncated'), ([256, 0], 'byte'), ([4, 256], 'byte'),
       ([31, 256], 'byte'), ([4, 129, 256], 'byte'), ([4, 1, 256], 'byte')]
for wire, expected in bad:
    cases.append(('r:' + encode(wire), expected))
for wire, expected in [(b'\x02\x00', 'value'), (b'\x02\x01\x80', 'value'),
                       (b'\x02\x02\x00\x01', 'canonical'), (b'\x02\x02\x00\x00', 'canonical'),
                       (b'\x22\x01\x01', 'tag'), (b'\x04\x01\x01', 'tag')]:
    cases.append(('u:' + encode(wire), expected))
for wire, expected in [(b'\x03\x00', 'value'), (b'\x03\x01\x01', 'canonical'),
                       (b'\x03\x02\x08\x00', 'value'), (b'\x03\x02\x01\x01', 'canonical'),
                       (b'\x23\x01\x00', 'tag')]:
    cases.append(('b:' + encode(wire), expected))
cases.append(('o:5,0,5,0', 'trailing'))


def reference_node(data):
    pos, first = 1, data[0]
    number = first & 31
    if number == 31:
        number = 0
        while True:
            byte = data[pos]
            pos += 1
            number = (number << 7) | (byte & 127)
            if byte < 128:
                break
    size = data[pos]
    pos += 1
    if size >= 128:
        count = size & 127
        size = int.from_bytes(data[pos:pos+count], 'big')
        pos += count
    return (first >> 6, bool(first & 32), number), data[:pos], data[pos:pos+size], data[pos+size:]


def certificate_nodes(data):
    while data:
        (cls, constructed, number), prefix, content, rest = reference_node(data)
        assert prefix == header(cls, constructed, number, len(content))
        add_node(cls, constructed, number, content, rest)
        if constructed:
            certificate_nodes(content)
        data = rest


for key in [rsa.generate_private_key(public_exponent=65537, key_size=2048), ec.generate_private_key(ec.SECP256R1())]:
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
    now = datetime.now(timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(128).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=1))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), False)
            .sign(key, hashes.SHA256()))
    wire = cert.public_bytes(serialization.Encoding.DER)
    certificate_nodes(wire)
    # The exact first child is the independently exposed signed TBSCertificate.
    _, _, content, _ = reference_node(wire)
    _, prefix, body, _ = reference_node(content)
    assert prefix + body == cert.tbs_certificate_bytes
    cases.append(('o:' + encode(cert.tbs_certificate_bytes), encode(cert.tbs_certificate_bytes)))

for name, command in [('native-1', ['build/der', '--threads', '1']),
                      ('native-4', ['build/der', '--threads', '4']),
                      ('bun', ['bun', 'build/der.js'])]:
    run = subprocess.run(command + [arg for arg, _ in cases], cwd=ROOT, capture_output=True, text=True, timeout=90)
    assert run.returncode == 0, (name, run.stderr[-2000:])
    lines = run.stdout.splitlines()
    assert len(lines) == len(cases), (name, len(lines), len(cases))
    for i, (actual, (_, expected)) in enumerate(zip(lines, cases)):
        assert actual == expected, (name, i, actual[:100], expected[:100])
    print(f'{name}: {len(cases)} DER checks PASS', flush=True)

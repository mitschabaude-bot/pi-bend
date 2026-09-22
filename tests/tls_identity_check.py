"""SAN-only identity policy: DNS label boundaries and typed IP identities.

Generated certificates exercise the real DER parser. OpenSSL checks the shared
DNS/IP subset; CN fallback and partial wildcards are intentionally excluded.
Composed authorization also requires a valid path to an explicit trust anchor.
"""
from datetime import datetime, timedelta, timezone
from ipaddress import ip_address
from pathlib import Path
import argparse
import subprocess
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/tls-identity')
parser.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
args = parser.parse_args()
cases = []


def dns(reference, presented, expected):
    cases.append((f'dns|{reference}|{presented}', 'ok' if expected else 'mismatch'))


for reference, presented, expected in [
    ('api.example.com', 'api.example.com', True),
    ('API.Example.COM', 'api.EXAMPLE.com', True),
    ('api.example.com.', 'api.example.com', True),
    ('api.example.com', 'api.example.com.', True),
    ('api.example.com', '*.example.com', True),
    ('xn--bcher-kva.example.com', '*.example.com', True),
    ('example.com', '*.example.com', False),
    ('a.b.example.com', '*.example.com', False),
    ('api.example.net', '*.example.com', False),
    ('api.example.com.evil', '*.example.com', False),
    ('api.example.com', 'a*.example.com', False),
    ('api.example.com', '*pi.example.com', False),
    ('api.example.com', '*.*.com', False),
    ('api.example.com', 'api.*.com', False),
    ('api', '*', False),
    ('', '', False), ('.', '.', False),
]:
    dns(reference, presented, expected)

for invalid in ['', '.', '..', 'a..b', '.example.com', 'a.example.com..',
                '-a.example', 'a-.example', 'a_b.example', 'a b.example',
                'bücher.example', 'a' * 64 + '.example']:
    dns(invalid, invalid, False)
    dns(invalid, '*.example', False)
for size in (1, 62, 63, 64):
    label = 'a' * size
    dns(label + '.example', '*.example', size <= 63)
for size in (60, 61, 62, 63):
    name = '.'.join(['a' * 63] * 3 + ['b' * size])
    dns(name, name, len(name) <= 253)

key = ec.generate_private_key(ec.SECP256R1())
subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'cn.example.com')])
now = datetime.now(timezone.utc)


def certificate(names):
    builder = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
               .public_key(key.public_key()).serial_number(1)
               .not_valid_before(now - timedelta(days=1))
               .not_valid_after(now + timedelta(days=1)))
    if names is not None:
        extension = names if isinstance(names, x509.UnrecognizedExtension) else x509.SubjectAlternativeName(names)
        builder = builder.add_extension(extension, critical=False)
    return builder.sign(key, hashes.SHA256())


def check(cert, kind, reference, expected):
    raw = cert.public_bytes(serialization.Encoding.DER)
    cases.append((f'{kind}|{reference}|' + ','.join(map(str, raw)), expected))


with tempfile.TemporaryDirectory(prefix='pi-bend-identity-') as temp:
    path = Path(temp) / 'leaf.pem'
    leaf = certificate([x509.DNSName('api.example.com'), x509.DNSName('*.tools.example.com'),
                        x509.IPAddress(ip_address('192.0.2.17')),
                        x509.IPAddress(ip_address('2001:db8::17'))])
    path.write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
    shared = [('cert', 'api.example.com', True), ('cert', 'API.EXAMPLE.COM', True),
              ('cert', 'a.tools.example.com', True), ('cert', 'a.b.tools.example.com', False),
              ('cert', 'cn.example.com', False), ('cert', 'other.example.com', False),
              ('v4', '192.0.2.17', True), ('v4', '192.0.2.18', False),
              ('v6', '2001:db8::17', True), ('v6', '2001:db8::18', False),
              ('v6', '::ffff:192.0.2.17', False)]
    for kind, reference, expected in shared:
        option = '-checkhost' if kind == 'cert' else '-checkip'
        oracle = subprocess.run(['openssl', 'x509', '-in', str(path), '-noout', option, reference],
                                check=True, capture_output=True, text=True)
        assert ('does match certificate' in oracle.stdout) == expected, oracle.stdout
        check(leaf, kind, reference, 'ok' if expected else 'mismatch')
    check(leaf, 'cert', '-invalid.example', 'reference')
    check(certificate(None), 'cert', 'cn.example.com', 'missing')
    check(certificate([x509.DNSName('a*.example.com')]), 'cert', 'api.example.com', 'mismatch')
    check(certificate([x509.DNSName('192.0.2.17')]), 'v4', '192.0.2.17', 'mismatch')
    check(certificate([x509.IPAddress(ip_address('192.0.2.17'))]), 'cert', '192.0.2.17', 'mismatch')
    check(certificate([x509.UniformResourceIdentifier('https://api.example.com'),
                       x509.RFC822Name('api@example.com')]), 'cert', 'api.example.com', 'mismatch')
    check(certificate([x509.DNSName('api.example.com\x00.evil')]), 'cert', 'api.example.com', 'mismatch')
    malformed = x509.UnrecognizedExtension(x509.oid.ExtensionOID.SUBJECT_ALTERNATIVE_NAME, b'\x30\x03\x87\x01\x7f')
    check(certificate(malformed), 'v4', '127.0.0.1', 'certificate')

    # Fixed verification time isolates path/time policy from wall-clock changes.
    epoch = datetime.fromtimestamp(1700000000, timezone.utc)
    root_key = ec.generate_private_key(ec.SECP256R1())
    root_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'identity root')])
    root = (x509.CertificateBuilder().subject_name(root_name).issuer_name(root_name)
            .public_key(root_key.public_key()).serial_number(2)
            .not_valid_before(epoch - timedelta(days=2)).not_valid_after(epoch + timedelta(days=2))
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
            .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, False, False), critical=True)
            .sign(root_key, hashes.SHA256()))

    def signed_leaf(expired=False):
        return (x509.CertificateBuilder().subject_name(subject).issuer_name(root_name)
                .public_key(key.public_key()).serial_number(3)
                .not_valid_before(epoch - timedelta(days=2))
                .not_valid_after(epoch + timedelta(days=-1 if expired else 1))
                .add_extension(x509.SubjectAlternativeName([x509.DNSName('api.example.com')]), critical=False)
                .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                .add_extension(x509.KeyUsage(True, False, False, False, False, False, False, False, False), critical=True)
                .sign(root_key, hashes.SHA256()))

    def encoded(cert):
        return ','.join(map(str, cert.public_bytes(serialization.Encoding.DER))) if cert else ''

    issued = signed_leaf()
    for reference, anchor, target, expected in [
        ('api.example.com', root, issued, 'ok'),
        ('other.example.com', root, issued, 'mismatch'),
        ('api.example.com', None, issued, 'untrusted'),
        ('api.example.com', leaf, issued, 'untrusted'),
        ('api.example.com', root, signed_leaf(True), 'expired'),
        ('api.example.com', root, None, 'certificate'),
    ]:
        cases.append((f'trust|{reference}|{encoded(anchor)}|{encoded(target)}', expected))

    for backend in args.backends:
        command = {'bun': ['bun', args.prefix + '.js'],
                   'native-1': [args.prefix, '--threads', '1'],
                   'native-4': [args.prefix, '--threads', '4']}[backend]
        run = subprocess.run(command + [value for value, _ in cases], cwd=ROOT,
                             capture_output=True, text=True, timeout=120)
        assert run.returncode == 0, (backend, run.stderr[-2000:])
        actual = run.stdout.splitlines()
        assert len(actual) == len(cases), (backend, len(actual), len(cases), run.stderr[-2000:])
        for result, (value, expected) in zip(actual, cases):
            assert result == expected, (backend, value[:100], result, expected)
        print(f'{backend}: {len(cases)} identity checks PASS ({len(shared)} OpenSSL comparisons)', flush=True)

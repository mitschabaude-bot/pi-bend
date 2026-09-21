"""ClientHello wire checks and local OpenSSL server interoperability.

Build tests/tls13-handshake.bend to build/tls13-handshake and .js first.
This checks the initial client flight, not authenticated TLS completion.
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import random
import hashlib
import hmac
import ssl
import subprocess
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa, x25519
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(8446)


def encode(values):
    return ','.join(map(str, values))


def octets(text):
    return bytes(map(int, text.split(','))) if text else b''


class Cursor:
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def take(self, count):
        assert self.offset + count <= len(self.data)
        result = self.data[self.offset:self.offset + count]
        self.offset += count
        return result

    def vector(self, width):
        return self.take(int.from_bytes(self.take(width), 'big'))

    def end(self):
        assert self.offset == len(self.data), (self.offset, len(self.data))


def extensions(raw):
    cursor = Cursor(raw)
    entries = {}
    while cursor.offset < len(raw):
        kind = int.from_bytes(cursor.take(2), 'big')
        assert kind not in entries
        entries[kind] = cursor.vector(2)
    return entries


def inspect(line, host, seed):
    raw, saved = map(octets, line.split('|'))
    cursor = Cursor(raw)
    assert cursor.take(3) == b'\x16\x03\x01'
    hello = cursor.vector(2)
    cursor.end()
    assert saved == hello
    cursor = Cursor(hello)
    assert cursor.take(1) == b'\x01'
    body = cursor.vector(3)
    cursor.end()
    cursor = Cursor(body)
    assert cursor.take(2) == b'\x03\x03'
    random_bytes = cursor.take(32)
    session = cursor.vector(1)
    assert len(session) == 32
    assert cursor.vector(2) == b'\x13\x01'
    assert cursor.vector(1) == b'\x00'
    ext = extensions(cursor.vector(2))
    cursor.end()
    assert set(ext) == ({10, 13, 43, 51, 16} if host is None else {0, 10, 13, 43, 51, 16})
    assert ext[10] == b'\x00\x02\x00\x1d'
    assert ext[13] == b'\x00\x04\x04\x03\x08\x04'
    assert ext[43] == b'\x02\x03\x04'
    assert ext[16] == b'\x00\x09\x08http/1.1'
    share = Cursor(ext[51])
    entries = Cursor(share.vector(2))
    share.end()
    assert entries.take(2) == b'\x00\x1d'
    public = entries.vector(2)
    entries.end()
    assert len(public) == 32
    if host is not None:
        names = Cursor(ext[0])
        entry = Cursor(names.vector(2))
        names.end()
        assert entry.take(1) == b'\x00'
        assert entry.vector(2).decode('ascii') == host
        entry.end()
    if seed is not None:
        assert random_bytes == seed[:32] and session == seed[64:]
        expected = x25519.X25519PrivateKey.from_private_bytes(seed[32:64]).public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        assert public == expected
    return raw, session


def server_context(folder, algorithm):
    key = ec.generate_private_key(ec.SECP256R1()) if algorithm == 'ecdsa' else rsa.generate_private_key(65537, 2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
    now = datetime.now(timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
            .public_key(key.public_key()).serial_number(1)
            .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=1))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), False)
            .sign(key, hashes.SHA256()))
    certificate, private = folder / 'certificate.pem', folder / 'key.pem'
    certificate.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    private.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                         serialization.NoEncryption()))
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.set_ecdh_curve('X25519')
    context.set_alpn_protocols(['http/1.1'])
    context.load_cert_chain(certificate, private)
    seen = []
    context.set_servername_callback(lambda connection, name, context: seen.append(name))
    return context, seen


def accepted(context, seen, wire, session, host):
    incoming, outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
    server = context.wrap_bio(incoming, outgoing, server_side=True)
    incoming.write(wire)
    try:
        server.do_handshake()
        raise AssertionError('ClientHello alone cannot complete a handshake')
    except ssl.SSLWantReadError:
        pass
    assert seen.pop() == host
    records = Cursor(outgoing.read())
    assert records.take(3) == b'\x16\x03\x03'
    server_hello = records.vector(2)
    response = Cursor(server_hello)
    assert response.take(1) == b'\x02'
    hello = Cursor(response.vector(3))
    response.end()
    assert hello.take(2) == b'\x03\x03'
    hello.take(32)
    assert hello.vector(1) == session
    assert hello.take(3) == b'\x13\x01\x00'
    selected = extensions(hello.vector(2))
    hello.end()
    assert selected[43] == b'\x03\x04'
    assert selected[51][:4] == b'\x00\x1d\x00\x20' and len(selected[51]) == 36
    assert server.selected_alpn_protocol() == 'http/1.1'
    while records.offset < len(records.data):
        header = records.take(3)
        body = records.vector(2)
        if header[0] == 23:
            return server_hello, header + len(body).to_bytes(2, 'big') + body, selected[51][4:]
        assert header[0] == 20 and body == b'\x01'
    raise AssertionError('server sent no protected handshake record')


def expand(secret, label, context, size):
    label = b'tls13 ' + label
    info = size.to_bytes(2, 'big') + bytes([len(label)]) + label + bytes([len(context)]) + context
    return hmac.digest(secret, info + b'\x01', 'sha256')[:size]


def verify_keys(line, seed, client_hello, flight):
    server_hello, encrypted, point = flight
    shared = x25519.X25519PrivateKey.from_private_bytes(seed[32:64]).exchange(x25519.X25519PublicKey.from_public_bytes(point))
    early = hmac.digest(bytes(32), bytes(32), 'sha256')
    secret = hmac.digest(expand(early, b'derived', hashlib.sha256(b'').digest(), 32), shared, 'sha256')
    transcript = hashlib.sha256(client_hello[5:] + server_hello).digest()
    client = expand(secret, b'c hs traffic', transcript, 32)
    server = expand(secret, b's hs traffic', transcript, 32)
    actual_secret, actual_client, actual_server, sent, received = line.split('|')
    assert list(map(octets, [actual_secret, actual_client, actual_server])) == [secret, client, server]
    inner = AESGCM(expand(server, b'key', b'', 16)).decrypt(expand(server, b'iv', b'', 12), encrypted[5:], encrypted[:5]).rstrip(b'\x00')
    assert received == str(inner[-1]) + ':' + encode(inner[:-1])
    sent = octets(sent)
    assert AESGCM(expand(client, b'key', b'', 16)).decrypt(expand(client, b'iv', b'', 12), sent[5:], sent[:5]) == b'\x14\x00\x00\x00\x16'


def malformed(hello):
    cases = [(hello[:n], 'malformed') for n in [0, 1, 3, 4, 37, 40, len(hello) - 1]]
    for index, error in [(0, 'malformed'), (3, 'malformed'), (4, 'parameters'), (38, 'parameters'),
                         (39, 'parameters'), (71, 'parameters'), (73, 'parameters'), (75, 'parameters'), (77, 'parameters')]:
        changed = bytearray(hello)
        changed[index] ^= 1
        cases.append((changed, error))
    changed = bytearray(hello)
    changed[6:38] = bytes.fromhex('cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c')
    cases.append((changed, 'retry'))
    changed = list(hello)
    changed[-1] = 256
    cases.append((changed, 'malformed'))
    # Rewrite extension vectors while preserving framing; these must fail negotiation.
    raw_ext = hello[76:]
    ext = extensions(raw_ext)
    key_ext = b'\x003' + len(ext[51]).to_bytes(2, 'big') + ext[51]
    version_ext = b'\x00+' + len(ext[43]).to_bytes(2, 'big') + ext[43]
    for replacement in [key_ext, version_ext, version_ext * 2 + key_ext,
                        version_ext + key_ext + b'\x00\x00\x00\x00']:
        body = hello[4:74] + len(replacement).to_bytes(2, 'big') + replacement
        cases.append((b'\x02' + len(body).to_bytes(3, 'big') + body, 'parameters'))
    replacement = version_ext + key_ext[:8] + bytes(32)
    body = hello[4:74] + len(replacement).to_bytes(2, 'big') + replacement
    cases.append((b'\x02' + len(body).to_bytes(3, 'big') + body, 'key'))
    return cases


valid_hosts = [None, 'localhost', 'example.com', 'EXAMPLE.com', 'a', 'xn--bcher-kva.example',
               'a-b.example', 'a' * 63 + '.example', '.'.join(['a' * 63] * 3 + ['b' * 61])]
valid_cases = []
for host in valid_hosts:
    seed = rng.randbytes(96)
    valid_cases.append(('d:' + (host or '-') + ':' + encode(seed), host, seed))
valid_cases += [('os:localhost', 'localhost', None), ('os:-', None, None)]
seed = encode(bytes(range(96)))
invalid_cases = [('d:' + name + ':' + seed, 'name') for name in [
    '', '.', 'a.', '.a', 'a..b', '-a', 'a-', 'bad_name', 'a/b', 'a b',
    'b\u00fccher.example', 'a' * 64, '.'.join(['a' * 63] * 4), '[127.0.0.1]',
]]
invalid_cases += [('d:localhost:' + encode(bytes(size)), 'randomness') for size in [0, 1, 32, 64, 95, 97, 128]]
invalid_cases += [('d:localhost:' + encode([0] * pos + [256] + [0] * (95 - pos)), 'randomness') for pos in [0, 31, 32, 63, 64, 95]]
invalid_cases += [('e:' + str(code), 'entropy:' + str(code)) for code in [4, 5, 11, 38]]
invalid_cases += [('os:bad_name', 'name')]

with tempfile.TemporaryDirectory(prefix='pi-bend-tls-') as temp:
    contexts = [server_context(Path(temp), algorithm) for algorithm in ['rsa', 'ecdsa']]
    for name, command in [('native-1', ['build/tls13-handshake', '--threads', '1']),
                          ('native-4', ['build/tls13-handshake', '--threads', '4']),
                          ('bun', ['bun', 'build/tls13-handshake.js'])]:
        commands = [arg for arg, _, _ in valid_cases] + [arg for arg, _ in invalid_cases]
        run = subprocess.run(command + commands, cwd=ROOT, capture_output=True, text=True, timeout=90)
        assert run.returncode == 0, (name, run.stderr[-2000:])
        lines = run.stdout.splitlines()
        assert len(lines) == len(commands), (name, len(lines), len(commands))
        flights = []
        for line, (_, host, seed) in zip(lines, valid_cases):
            wire, session = inspect(line, host, seed)
            for context, seen in contexts:
                flight = accepted(context, seen, wire, session, host)
                if host == 'localhost' and seed is not None:
                    flights.append((seed, wire, flight))
        for line, (_, expected) in zip(lines[len(valid_cases):], invalid_cases):
            assert line == expected, (name, line, expected)
        for seed, wire, flight in flights:
            hello, encrypted, _ = flight
            prefix = 'n:localhost:' + encode(seed) + ':'
            probes = [hello]
            # Accept either legal ordering of the two ServerHello extensions.
            reverse = hello[:76] + hello[82:] + hello[76:82]
            probes.append(reverse)
            bad = malformed(hello)
            args = [prefix + encode(h) + ':' + encode(encrypted) for h in probes]
            args += [prefix + encode(h) + ':' for h, _ in bad]
            output = subprocess.run(command + args, cwd=ROOT, capture_output=True, text=True, timeout=90)
            assert output.returncode == 0, (name, output.stderr[-2000:])
            results = output.stdout.splitlines()
            assert len(results) == len(args)
            verify_keys(results[0], seed, wire, flight)
            # Reordering changes the transcript and thus the traffic keys: the old
            # encrypted flight must fail even though the new parameters are legal.
            assert results[1].endswith('|receive-error'), (name, results[1])
            for actual, (_, expected) in zip(results[2:], bad):
                assert actual == expected, (name, actual, expected)
        print(f'{name}: {len(commands)} initialization checks; {len(valid_cases) * 2} OpenSSL flights; native bidirectional keys and ServerHello rejection checks PASS', flush=True)

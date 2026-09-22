"""Exercise the native session against OpenSSL and independently sealed flights.

The test authorizer pins a generated leaf. Trust paths/hostname policy are
separately tested; this suite checks that authorization gates the session.
Tickets are disabled until the session implements post-handshake messages.
"""
from pathlib import Path
import hashlib
import hmac
import subprocess
import sys
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from tls13_handshake_check import (server_context, accepted, encode, octets,
                                   expand, Cursor, handshake_message)

ROOT = Path(__file__).resolve().parents[1]
SEED = bytes(range(96))


def record(kind, body):
    return bytes([kind, 3, 3]) + len(body).to_bytes(2, 'big') + body


def protected(secret, sequence, body, kind=22):
    iv = expand(secret, b'iv', b'', 12)
    nonce = (int.from_bytes(iv, 'big') ^ sequence).to_bytes(12, 'big')
    head = bytes([23, 3, 3]) + (len(body) + 17).to_bytes(2, 'big')
    return head + AESGCM(expand(secret, b'key', b'', 16)).encrypt(nonce, body + bytes([kind]), head)


def secrets_and_messages(hello, flight):
    shared = x25519.X25519PrivateKey.from_private_bytes(SEED[32:64]).exchange(
        x25519.X25519PublicKey.from_public_bytes(flight[2]))
    early = hmac.digest(bytes(32), bytes(32), 'sha256')
    secret = hmac.digest(expand(early, b'derived', hashlib.sha256(b'').digest(), 32), shared, 'sha256')
    digest = hashlib.sha256(hello[5:] + flight[0]).digest()
    peer = expand(secret, b's hs traffic', digest, 32)
    clear = b''
    for sequence, wire in enumerate(flight[3]):
        nonce = (int.from_bytes(expand(peer, b'iv', b'', 12), 'big') ^ sequence).to_bytes(12, 'big')
        inner = AESGCM(expand(peer, b'key', b'', 16)).decrypt(nonce, wire[5:], wire[:5]).rstrip(b'\0')
        assert inner[-1] == 22
        clear += inner[:-1]
    cursor, messages = Cursor(clear), []
    while cursor.offset < len(clear):
        kind = cursor.take(1)[0]
        messages.append(handshake_message(kind, cursor.vector(3)))
    assert [m[0] for m in messages] == [8, 11, 15, 20]
    master = hmac.digest(expand(secret, b'derived', hashlib.sha256(b'').digest(), 32), bytes(32), 'sha256')
    app = expand(master, b's ap traffic', hashlib.sha256(hello[5:] + flight[0] + clear).digest(), 32)
    return peer, app, messages


def check(command, algorithm, folder, streaming=False):
    context, seen = server_context(folder, algorithm)
    cert = x509.load_pem_x509_certificate((folder / 'certificate.pem').read_bytes()).public_bytes(serialization.Encoding.DER)
    count = 0

    def invoke(operations=(), pin=cert, expected='connected'):
        nonlocal count
        argument = ':'.join([encode(SEED), encode(pin), *operations])
        completed = subprocess.run(command + [argument], cwd=ROOT, text=True, capture_output=True, timeout=120)
        assert completed.returncode == 0, completed.stderr[-3000:]
        lines = completed.stdout.splitlines()
        expected_line = expected if expected.startswith('error:') else 'state:' + expected
        assert lines[-1] == expected_line, (lines[-1:], expected_line)
        count += 1
        return [octets(line[4:]) for line in lines if line.startswith('out:')], [octets(line[3:]) for line in lines if line.startswith('in:')]

    initial, _ = invoke(expected='hello')
    hello = initial[0]
    flight = accepted(context, seen, hello, SEED[64:], 'localhost')
    peer, app, messages = secrets_and_messages(hello, flight)
    head = record(22, flight[0])
    ccs = record(20, b'\1')
    prefix = ['r' + encode(head), 'r' + encode(ccs)]
    operations = prefix + ['r' + encode(wire) for wire in flight[3]]
    outgoing, incoming = invoke(operations + ['s' + encode(b'ping'), 's' + encode(b' again')])
    assert incoming == [] and outgoing[0] == hello and len(outgoing) == 4
    server, transport_in, transport_out = flight[4:]
    transport_in.write(outgoing[1])
    server.do_handshake()
    assert server.version() == 'TLSv1.3' and server.selected_alpn_protocol() == 'http/1.1'
    for wire, expected in zip(outgoing[2:], [b'ping', b' again']):
        transport_in.write(wire)
        assert server.read() == expected
    assert transport_out.pending == 0
    server.write(b'pong')
    reply1 = transport_out.read()
    server.write(b' again')
    reply2 = transport_out.read()
    replay, data = invoke(operations + ['s' + encode(b'ping'), 's' + encode(b' again'), 'r' + encode(reply1), 'r' + encode(reply2)])
    assert replay == outgoing and data == [b'pong', b' again']

    if streaming:
        # Socket chunking is independent of both record and handshake framing.
        stream = head + ccs + b''.join(flight[3]) + reply1 + reply2
        expected_out, expected_in = outgoing[:2], [b'pong', b' again']
        for widths in [[len(stream)], [1], [2, 3, 5, 7, 11, 13], [4096]]:
            chunks, offset, index = [], 0, 0
            while offset < len(stream):
                width = widths[index % len(widths)]
                chunks.append(stream[offset:offset + width])
                offset += width
                index += 1
            actual_out, actual_in = invoke(['r' + encode(chunk) for chunk in chunks])
            assert (actual_out, actual_in) == (expected_out, expected_in)
        # A send between two pieces of an incoming record preserves its buffer.
        actual_out, actual_in = invoke(operations + ['r' + encode(reply1[:7]), 's' + encode(b'ping'),
                                                     'r' + encode(reply1[7:])])
        assert actual_out == outgoing[:3] and actual_in == [b'pong']
        # A later invalid record must not erase valid records in the same read.
        bad = bytearray(reply2); bad[-1] ^= 1
        actual_out, actual_in = invoke(['r' + encode(head + ccs + b''.join(flight[3]) + reply1 + bad)], expected='error:record:mac')
        assert (actual_out, actual_in) == (expected_out, [b'pong'])
        # Reject oversized advertised lengths before receiving their bodies.
        invoke(['r23,3,3,65,1'], expected='error:record')
        invoke(['r22,3,3,64,1'], expected='error:record')
        invoke(['r22,3,3,0,1,256'], expected='error:record')
        invoke(['r'], expected='hello')
        _, actual_in = invoke(['r' + encode(stream + protected(app, 2, b'\1\0', 21) + b'garbage')], expected='read-closed')
        assert actual_in == expected_in
        return count

    # The same handshake succeeds with different legal record boundaries.
    for chunks in [[b''.join(messages)], messages,
                   [b''.join(messages)[:7], b''.join(messages)[7:-1], b''.join(messages)[-1:]]]:
        changed, data = invoke(prefix + ['r' + encode(protected(peer, i, chunk)) for i, chunk in enumerate(chunks)])
        assert changed == outgoing[:2] and data == []
    # ServerHello itself may be fragmented, and CCS may appear in that window.
    changed, _ = invoke(['r' + encode(record(22, flight[0][:3])), 'r' + encode(ccs),
                         'r' + encode(record(22, flight[0][3:]))] + operations[2:])
    assert changed == outgoing[:2]

    # No application writer exists before authentication finishes.
    invoke(['s' + encode(b'early')], expected='error:unexpected')
    invoke(prefix + ['s' + encode(b'early')], expected='error:unexpected')
    invoke(operations, pin=b'', expected='error:handshake:certificate')
    invoke(prefix + ['r' + encode(protected(peer, 0, b'early', 23))], expected='error:unexpected')
    invoke(prefix + ['r' + encode(protected(peer, 0, messages[1]))], expected='error:handshake:handshake')
    invoke(prefix + ['r' + encode(protected(peer, 0, messages[0] + messages[2]))], expected='error:handshake:handshake')
    # Correctly encrypted malicious flights exercise signature and Finished,
    # independently from record authentication.
    for index, expected in [(2, 'error:handshake:certificate'), (3, 'error:handshake:finished')]:
        altered = list(messages)
        altered[index] = altered[index][:-1] + bytes([altered[index][-1] ^ 1])
        invoke(prefix + ['r' + encode(protected(peer, 0, b''.join(altered)))], expected=expected)
    corrupted = bytearray(flight[3][0]); corrupted[-1] ^= 1
    invoke(prefix + ['r' + encode(corrupted)], expected='error:record:mac')
    invoke(operations + ['r' + encode(ccs)], expected='error:unexpected')
    invoke(operations + ['r' + encode(head)], expected='error:unexpected')
    invoke(['r' + encode(record(22, flight[0] + messages[0]))], expected='error:unexpected')
    invoke(prefix + ['r' + encode(protected(peer, 0, b''.join(messages) + b'\4'))], expected='error:unexpected')
    invoke(operations + ['r' + encode(reply1), 'r' + encode(reply1)], expected='error:record:mac')
    invoke(operations + ['r' + encode(protected(app, 0, b'\1\0', 21))], expected='read-closed')
    invoke(operations + ['r' + encode(protected(app, 0, b'\2\40', 21))], expected='error:alert:32')
    close_record = 'r' + encode(protected(app, 0, b'\1\0', 21))
    invoke(operations + [close_record, 's1'], expected='read-closed')
    invoke(operations + [close_record, 'r999'], expected='read-closed')
    invoke(operations + [close_record, 'c'], expected='closed')
    invoke(operations + ['c', 'c'], expected='write-closed')
    invoke(operations + ['c', 's1'], expected='error:unexpected')
    _, data = invoke(operations + ['c', 'r' + encode(reply1)], expected='write-closed')
    assert data == [b'pong']
    invoke(operations + ['r' + encode(protected(app, 0, b'\2\0', 21))], expected='read-closed')
    invoke(['r' + encode(record(22, b''))], expected='error:unexpected')
    invoke(prefix + ['r' + encode(protected(peer, 0, b''))], expected='error:record')
    invoke(['r' + encode(record(21, b'\1\x5a'))], expected='hello')
    invoke(['r' + encode(record(21, b'\2\x28'))], expected='error:alert:40')
    invoke(prefix + ['r' + encode(protected(peer, 0, b'\1\x5a', 21)),
                     'r' + encode(protected(peer, 1, b''.join(messages)))])
    invoke(['r' + encode(head[:1] + b'\0\0' + head[3:])] + operations[1:])
    invoke(operations, pin=cert[:-1] + bytes([cert[-1] ^ 1]), expected='error:handshake:certificate')
    # Real OpenSSL closure in both directions, after the two application writes.
    final_out, _ = invoke(operations + ['s' + encode(b'ping'), 's' + encode(b' again'), 'c'], expected='write-closed')
    transport_in.write(final_out[-1])
    server.unwrap()
    server_close = transport_out.read()
    _, data = invoke(operations + ['c', 'r' + encode(reply1), 'r' + encode(reply2), 'r' + encode(server_close)], expected='closed')
    assert data == [b'pong', b' again']
    return count


if __name__ == '__main__':
    streaming = '--stream' in sys.argv[1:]
    stem = 'build/tls13-client-stream' if streaming else 'build/tls13-client'
    selected = [arg for arg in sys.argv[1:] if arg != '--stream']
    with tempfile.TemporaryDirectory(prefix='pi-bend-client-') as temp:
        for backend, command in [('native-1', [stem, '--threads', '1']),
                                 ('native-4', [stem, '--threads', '4']),
                                 ('bun', ['bun', stem + '.js'])]:
            if selected and selected[0] != backend:
                continue
            count = 0
            for algorithm in (['ecdsa'] if streaming else ['rsa', 'ecdsa', 'ecdsa384']):
                cases = check(command, algorithm, Path(temp), streaming=streaming)
                count += cases
                print(f'{backend}/{algorithm}: {cases} flows PASS', flush=True)
            scope = 'socket chunking and prefix preservation' if streaming else 'RSA/P256/P384 authentication and closure'
            print(f'{backend}: {count} session flows; {scope} PASS', flush=True)

"""Authenticated HTTPS through the modular OpenAI provider and native runtime.

Only the test server uses Python/OpenSSL. The client performs DNS/hosts routing,
TLS/PKI, request serialization, SSE decoding and provider lifecycle in Bend.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import os
import socket
import subprocess
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from fetch_https_check import trusted_context, ROOT

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/native-openai')
parser.add_argument('backend', choices=['bun', 'native-1', 'native-4'])
args = parser.parse_args()
answer = 'Native HTTPS → modular Responses ✓'
item = {'type': 'message', 'id': 'msg-local', 'role': 'assistant', 'content': []}
events = [
    {'type': 'response.created', 'response': {'id': 'resp-local'}},
    {'type': 'response.output_item.added', 'output_index': 0, 'item': item},
    {'type': 'response.output_text.delta', 'output_index': 0, 'delta': answer},
    {'type': 'response.output_item.done', 'output_index': 0,
     'item': {**item, 'content': [{'type': 'output_text', 'text': answer}]}},
    {'type': 'response.completed', 'response': {'id': 'resp-local', 'status': 'completed',
     'usage': {'input_tokens': 8, 'output_tokens': 9, 'total_tokens': 17}}},
]


def serve(listener, context):
    raw, _ = listener.accept()
    raw.settimeout(180)
    with context.wrap_socket(raw, server_side=True) as stream:
        data = bytearray()
        while b'\r\n\r\n' not in data:
            part = stream.recv(16384)
            assert part, 'request closed before headers'
            data.extend(part)
        head, body = bytes(data).split(b'\r\n\r\n', 1)
        lines = head.decode('ascii').split('\r\n')
        assert lines[0] == 'POST /v1/responses HTTP/1.1', lines[0]
        headers = dict(line.lower().split(': ', 1) for line in lines[1:])
        assert headers['authorization'] == 'bearer fixture-key'
        length = int(headers['content-length'])
        while len(body) < length:
            part = stream.recv(16384)
            assert part, 'request closed before body'
            body += part
        assert len(body) == length
        request = json.loads(body)
        assert request['model'] == 'fixture-model', request
        assert request['stream'] is True and request['store'] is False, request
        assert request['input'][0]['content'][0]['text'] == 'hello native provider', request
        wire = ''.join('data: ' + json.dumps(event, ensure_ascii=False) + '\n\n' for event in events).encode()
        stream.sendall(f'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {len(wire)}\r\n\r\n'.encode() + wire)
        assert stream.recv(1) == b'', 'provider did not retire its transport'


with tempfile.TemporaryDirectory(prefix='pi-native-provider-') as temporary, ThreadPoolExecutor(max_workers=1) as executor:
    directory = Path(temporary)
    context, root = trusted_context(directory, 'localhost')
    root_path = directory / 'root.pem'
    root_path.write_bytes(x509.load_der_x509_certificate(root).public_bytes(serialization.Encoding.PEM))
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(180)
        server = executor.submit(serve, listener, context)
        command = ['bun', args.prefix + '.js'] if args.backend == 'bun' else [args.prefix, '--threads', args.backend[-1]]
        run = subprocess.run(command + [str(root_path), 'fixture-model', f'https://localhost:{listener.getsockname()[1]}/v1', 'hello native provider'],
                             cwd=ROOT, env={**os.environ, 'OPENAI_API_KEY': 'fixture-key'},
                             capture_output=True, text=True, timeout=240)
        assert run.returncode == 0, (run.returncode, run.stdout[-2000:], run.stderr[-2000:])
        assert run.stdout.strip() == answer, run.stdout
        server.result(timeout=10)
    print(f'{args.backend}: authenticated modular OpenAI provider PASS', flush=True)

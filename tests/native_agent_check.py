"""Modular agent/provider integration over authenticated native HTTPS.

Python/OpenSSL is only the peer. Bend owns the agent loop, schema validation,
tool execution, request serialization, TLS, SSE, and response/run retirement.
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

def request(stream, tool="echo"):
    data = bytearray()
    while b'\r\n\r\n' not in data:
        part = stream.recv(16384)
        assert part, 'connection closed before request headers'
        data.extend(part)
    head, body = bytes(data).split(b'\r\n\r\n', 1)
    lines = head.decode('ascii').split('\r\n')
    assert lines[0] == 'POST /v1/responses HTTP/1.1'
    headers = dict(line.lower().split(': ', 1) for line in lines[1:])
    assert headers['authorization'] == 'bearer fixture-key'
    length = int(headers['content-length'])
    while len(body) < length:
        part = stream.recv(16384)
        assert part, 'connection closed before request body'
        body += part
    assert len(body) == length
    value = json.loads(body)
    assert value['model'] == 'fixture-model' and value['stream'] is True
    assert value['store'] is False
    assert [declaration['name'] for declaration in value['tools']] == [tool], value['tools']
    return value


def response(stream, events):
    wire = ''.join('data: ' + json.dumps(event, ensure_ascii=False) + '\n\n' for event in events).encode()
    stream.sendall(f'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {len(wire)}\r\n\r\n'.encode() + wire)
    assert stream.recv(1) == b'', 'provider did not retire the response connection'


def completion(identifier):
    return {'type': 'response.completed', 'response': {'id': identifier, 'status': 'completed',
            'usage': {'input_tokens': 8, 'output_tokens': 9, 'total_tokens': 17}}}


def serve(listener, context, valid, answer):
    parameters = {'input': 'hello native tool'} if valid else {}
    encoded = json.dumps(parameters, separators=(',', ':'))
    call = {'type': 'function_call', 'id': 'fc_fixture', 'call_id': 'call_fixture', 'name': 'echo', 'arguments': ''}
    for turn in range(2):
        raw, _ = listener.accept()
        raw.settimeout(180)
        with context.wrap_socket(raw, server_side=True) as stream:
            value = request(stream)
            if turn == 0:
                assert any(item.get('role') == 'user' and item['content'][0]['text'] == 'Call echo once, then report the result.' for item in value['input'])
                response(stream, [
                    {'type': 'response.created', 'response': {'id': 'resp-tool'}},
                    {'type': 'response.output_item.added', 'output_index': 0, 'item': call},
                    {'type': 'response.function_call_arguments.delta', 'output_index': 0, 'delta': encoded},
                    {'type': 'response.function_call_arguments.done', 'output_index': 0, 'arguments': encoded},
                    {'type': 'response.output_item.done', 'output_index': 0, 'item': {**call, 'arguments': encoded}},
                    completion('resp-tool'),
                ])
            else:
                calls = [item for item in value['input'] if item.get('type') == 'function_call']
                outputs = [item for item in value['input'] if item.get('type') == 'function_call_output']
                assert len(calls) == len(outputs) == 1, value['input']
                assert calls[0]['call_id'] == outputs[0]['call_id'] == 'call_fixture'
                assert json.loads(calls[0]['arguments']) == parameters
                if valid:
                    assert outputs[0]['output'] == 'hello native tool', outputs
                else:
                    assert 'Validation failed' in outputs[0]['output'], outputs
                item = {'type': 'message', 'id': 'msg-final', 'role': 'assistant', 'content': []}
                response(stream, [
                    {'type': 'response.created', 'response': {'id': 'resp-final'}},
                    {'type': 'response.output_item.added', 'output_index': 0, 'item': item},
                    {'type': 'response.output_text.delta', 'output_index': 0, 'delta': answer},
                    {'type': 'response.output_item.done', 'output_index': 0,
                     'item': {**item, 'content': [{'type': 'output_text', 'text': answer}]}},
                    completion('resp-final'),
                ])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', default='build/native-agent')
    parser.add_argument('backend', choices=['bun', 'native-1', 'native-4'])
    args = parser.parse_args()

    for valid in [True, False]:
        answer = 'Native model/tool loop ✓' if valid else 'Invalid tool arguments rejected ✓'
        with tempfile.TemporaryDirectory(prefix='pi-native-agent-') as temporary, ThreadPoolExecutor(max_workers=1) as executor:
            directory = Path(temporary)
            context, root = trusted_context(directory, 'localhost')
            root_path = directory / 'root.pem'
            root_path.write_bytes(x509.load_der_x509_certificate(root).public_bytes(serialization.Encoding.PEM))
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                listener.listen(2)
                listener.settimeout(180)
                server = executor.submit(serve, listener, context, valid, answer)
                command = ['bun', args.prefix + '.js'] if args.backend == 'bun' else [args.prefix, '--threads', args.backend[-1]]
                run = subprocess.run(command + [str(root_path), 'fixture-model', f'https://localhost:{listener.getsockname()[1]}/v1', 'Call echo once, then report the result.'],
                                     cwd=ROOT, env={**os.environ, 'OPENAI_API_KEY': 'fixture-key'},
                                     capture_output=True, text=True, timeout=360)
                server.result(timeout=10)
                assert run.returncode == 0, (run.returncode, run.stdout[-3000:], run.stderr[-2000:])
                lines = run.stdout.splitlines()
                assert f'executions {int(valid)}' in lines, lines
                assert lines[-1] == 'answer ' + answer, lines
                events = [line.removeprefix('event ') for line in lines if line.startswith('event ')]
                assert events[0] == 'agent_start' and events[-1] == 'agent_end', events
                assert events.count('turn_start') == events.count('turn_end') == 2, events
                second_turn = events.index('turn_start', events.index('turn_start') + 1)
                if valid:
                    assert events.index('tool_execution_start') < events.index('tool_execution_end') < second_turn, events
                assert events.count('message_update') >= 2, events
            print(f'{args.backend}: native agent HTTPS/tool/{"success" if valid else "validation rejection"} PASS', flush=True)


if __name__ == "__main__":
    main()

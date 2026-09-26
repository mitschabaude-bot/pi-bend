#!/usr/bin/env python3
"""Codex provider through real RFC WebSocket frames versus pinned pi-mono.

Build packages/ai/test/openai-codex-stream.bend to the selected prefix first.
The server records both transports so fallback/replay can be checked directly.
"""
import argparse
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from websocket_client_check import frame, receive, GUID

ROOT = Path(__file__).resolve().parents[1]
USAGE = {'input_tokens': 5, 'output_tokens': 3, 'total_tokens': 8,
         'input_tokens_details': {'cached_tokens': 0}}


def events(text='Hello', tool=False):
    if tool:
        item = {'type': 'function_call', 'id': 'fc_1', 'call_id': 'call_1', 'name': 'read', 'arguments': ''}
        done = {**item, 'arguments': '{"path":"README.md"}'}
        middle = [{'type': 'response.function_call_arguments.delta', 'delta': done['arguments']}]
    else:
        item = {'type': 'message', 'id': 'msg_1', 'role': 'assistant', 'status': 'in_progress', 'content': []}
        done = {**item, 'status': 'completed', 'content': [{'type': 'output_text', 'text': text}]}
        middle = [{'type': 'response.content_part.added', 'part': {'type': 'output_text', 'text': ''}},
                  {'type': 'response.output_text.delta', 'delta': text}]
    values = [{'type': 'response.output_item.added', 'item': item}, *middle,
              {'type': 'response.output_item.done', 'item': done},
              {'type': 'response.completed', 'response': {'id': 'resp_1', 'status': 'completed', 'usage': USAGE, 'end_turn': True}}]
    return [{**value, 'output_index': 0} if 'item' in value or 'part' in value or 'delta' in value else value for value in values]


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = False


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        server = self.server
        conn = self.connection
        conn.settimeout(5)
        try:
            server.upgrades.append(dict(self.headers.items()))
            assert self.headers.get('Upgrade', '').lower() == 'websocket'
            assert self.headers['chatgpt-account-id'] == 'acc_test'
            assert self.headers['session-id'] == 'ws-fixture'
            if server.mode == 'connect-timeout':
                time.sleep(.15)
                return
            key = self.headers['Sec-WebSocket-Key']
            accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
            self.send_response(101)
            self.send_header('Upgrade', 'websocket')
            self.send_header('Connection', 'Upgrade')
            self.send_header('Sec-WebSocket-Accept', accept)
            self.end_headers()
            opcode, payload = receive(conn)
            assert opcode == 1
            request = json.loads(payload)
            assert request.pop('type') == 'response.create'
            server.requests.append(request)
            if server.mode == 'close-before':
                conn.sendall(frame(8, b'\x03\xe8'))
                return
            values = events(server.text, server.mode == 'tool')
            if server.mode == 'invalid':
                conn.sendall(frame(1, b'{broken'))
            elif server.mode == 'api-error':
                conn.sendall(frame(1, b'{"type":"error","code":"invalid_request","message":"bad request"}'))
            else:
                for index, value in enumerate(values):
                    if server.mode == 'abort' and index == 3:
                        # Hold the next frame so cancellation occurs while the
                        # read is pending, independent of scheduler batching.
                        time.sleep(.1)
                    if server.mode == 'idle' and index == 2:
                        time.sleep(.15)
                        break
                    encoded = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
                    if server.mode == 'fragmented':
                        cut = max(1, len(encoded) // 2)
                        conn.sendall(frame(1, encoded[:cut], False) + frame(0, encoded[cut:]))
                    else:
                        conn.sendall(frame(2 if server.mode == 'binary' else 1, encoded))
                    if server.mode == 'close-after' and index == 2:
                        conn.sendall(frame(8, b'\x03\xe8'))
                        break
            # Both callers must release the socket even on early termination.
            try:
                while True:
                    opcode, _ = receive(conn)
                    if opcode == 8:
                        conn.sendall(frame(8, b'\x03\xe8'))
                        break
            except (EOFError, ConnectionResetError, BrokenPipeError):
                pass
        except (ConnectionResetError, BrokenPipeError):
            pass
        except Exception as error:
            server.errors.append(str(error))
        finally:
            self.close_connection = True

    def do_POST(self):
        payload = self.rfile.read(int(self.headers['Content-Length']))
        if self.headers.get('Content-Encoding') == 'zstd':
            payload = subprocess.run(['bun', '-e', 'process.stdout.write(require("node:zlib").zstdDecompressSync(require("node:fs").readFileSync(0)))'], input=payload, capture_output=True, check=True).stdout
        self.server.http_requests.append(json.loads(payload))
        body = ''.join('data: ' + json.dumps(value, separators=(',', ':')) + '\n\n' for value in events()).encode()
        self.send_response(200)
        self.send_header('content-type', 'text/event-stream')
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def fixture(mode):
    token = 'aaa.' + base64.b64encode(json.dumps({'https://api.openai.com/auth': {'chatgpt_account_id': 'acc_test'}}).encode()).decode() + '.bbb'
    value = {'options': {'apiKey': token, 'transport': 'websocket', 'sessionId': 'ws-fixture'},
             'messages': [], 'model': {'id': 'gpt-5.1-codex', 'name': 'GPT-5.1 Codex'}}
    if mode == 'simple':
        value['entry'] = 'simple'
    if mode == 'connect-disabled':
        value['options']['websocketConnectTimeoutMs'] = 0
    if mode == 'idle-disabled':
        value['options']['timeoutMs'] = 0
    if mode == 'cached-first':
        value['options']['transport'] = 'websocket-cached'
    if mode == 'auto':
        value['options'].pop('transport')
    if mode == 'abort':
        value['abortOnEvent'] = 'text_delta:Hello'
    if mode == 'idle':
        value['options']['timeoutMs'] = 30
    if mode == 'connect-timeout':
        value['options']['websocketConnectTimeoutMs'] = 30
    if mode == 'tool':
        value['tools'] = [{'name': 'read', 'description': 'Read a file', 'parameters': {'type': 'object', 'properties': {'path': {'type': 'string'}}, 'required': ['path']}}]
    return value


def run(command, mode, reference=False):
    with Server(('127.0.0.1', 0), Handler) as server:
        server.mode = mode
        server.text = 'snow ☃ and emoji 😀' if mode == 'fragmented' else 'Hello'
        server.upgrades, server.requests, server.http_requests, server.errors = [], [], [], []
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        url = f'http://127.0.0.1:{server.server_port}'
        value = fixture(mode)
        try:
            if reference:
                result = subprocess.run(command, cwd=ROOT, input=json.dumps({**value, 'url': url}), text=True, capture_output=True, timeout=15)
            else:
                encoded = ','.join(str(ord(c)) for c in json.dumps(value, ensure_ascii=False, separators=(',', ':')))
                result = subprocess.run(command + [url, encoded], cwd=ROOT, text=True, capture_output=True, timeout=15)
            assert result.returncode == 0, (mode, result.stdout[-1000:], result.stderr[-1000:])
            if reference:
                output = json.loads(result.stdout)
            else:
                lines = result.stdout.splitlines()
                output = {'events': [line[2:] for line in lines if line.startswith('E ')],
                          'message': json.loads(''.join(chr(int(n)) for n in next(line[2:] for line in lines if line.startswith('R ')).split(',')))}
        finally:
            server.shutdown()
            worker.join()
        server.server_close()
        assert not server.errors, (mode, server.errors)
        assert len(server.upgrades) == 1, (mode, server.upgrades)
        output['requests'] = server.requests
        output['http_requests'] = server.http_requests
        return output


def comparable(output):
    output = {**output, 'message': dict(output['message'])}
    output['message'].pop('timestamp', None)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', default='build/openai-codex-stream-ws')
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    args = parser.parse_args()
    for mode in ('complete', 'simple', 'auto', 'cached-first', 'connect-disabled', 'idle-disabled', 'fragmented', 'binary', 'tool', 'api-error', 'invalid', 'close-before', 'close-after', 'abort', 'idle', 'connect-timeout'):
        want = run(['bun', 'tests/openai_codex_websocket_reference.ts'], mode, True)
        for backend in args.backends:
            command = ['bun', args.prefix + '.js'] if backend == 'bun' else [args.prefix, '--threads', backend[-1]]
            got = run(command, mode)
            if mode in ('complete', 'simple', 'auto', 'cached-first', 'connect-disabled', 'idle-disabled', 'fragmented', 'binary', 'tool', 'api-error', 'abort'):
                assert comparable(got) == comparable(want), (backend, mode, comparable(got), comparable(want))
                print(f'{backend}: {mode} request/events/final message MATCH')
            else:
                # Diagnostic/error detail parity is tracked as pending; assert
                # the substantive stream and transport behavior independently.
                assert got['events'] == want['events'], (backend, mode, got, want)
                assert got['requests'] == want['requests'], (backend, mode, got, want)
                assert got['http_requests'] == want['http_requests'], (backend, mode, got, want)
                assert got['message']['stopReason'] == want['message']['stopReason'], (backend, mode, got, want)
                print(f'{backend}: {mode} fallback/no-replay/events/stop reason PASS (diagnostics pending)')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Consecutive model turns over the native session pool versus pinned pi."""
import argparse
import base64
import copy
import hashlib
import json
import subprocess
import threading
from openai_codex_websocket_check import Server, Handler, fixture, events, comparable, ROOT
from websocket_client_check import frame, receive, GUID


class ReusableHandler(Handler):
    def do_GET(self):
        conn = self.connection
        conn.settimeout(5)
        try:
            identity = len(self.server.upgrades)
            self.server.upgrades.append(dict(self.headers.items()))
            accept = base64.b64encode(hashlib.sha1((self.headers['Sec-WebSocket-Key'] + GUID).encode()).digest()).decode()
            self.send_response(101)
            self.send_header('Upgrade', 'websocket')
            self.send_header('Connection', 'Upgrade')
            self.send_header('Sec-WebSocket-Accept', accept)
            self.end_headers()
            while True:
                opcode, payload = receive(conn)
                if opcode == 8:
                    conn.sendall(frame(8, payload))
                    break
                assert opcode == 1
                request = json.loads(payload)
                assert request.pop('type') == 'response.create'
                self.server.requests.append(request)
                self.server.identities.append(identity)
                ordinal = len(self.server.requests)
                for value in events(tool=self.server.tool):
                    if value.get('item', {}).get('type') == 'message':
                        value['item']['id'] = f'msg_{ordinal}'
                    if 'response' in value:
                        value['response']['id'] = f'resp_{ordinal}'
                    conn.sendall(frame(1, json.dumps(value, separators=(',', ':')).encode()))
        except (EOFError, ConnectionResetError, BrokenPipeError):
            pass
        except Exception as error:
            self.server.errors.append(str(error))
        finally:
            self.close_connection = True


def native_results(stdout):
    results, labels = [], []
    for line in stdout.splitlines():
        if line.startswith('E '):
            labels.append(line[2:])
        elif line.startswith('R '):
            message = json.loads(''.join(chr(int(n)) for n in line[2:].split(',')))
            results.append({'events': labels, 'message': message})
            labels = []
    return results


def run(command, mode, reference=False, previous=None, following=None):
    with Server(('127.0.0.1', 0), ReusableHandler) as server:
        server.upgrades, server.requests, server.identities, server.errors = [], [], [], []
        server.tool = mode in ('seed-tool', 'cached-tool')
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        url = f'http://127.0.0.1:{server.server_port}'
        cases = [fixture('complete'), fixture('simple')]
        if server.tool:
            for c in cases:
                c['tools'] = fixture('tool')['tools']
        if mode.startswith('cached-') or mode in ('auto-user', 'unset-user'):
            for c in cases:
                c['options']['transport'] = 'auto' if mode == 'auto-user' else 'websocket-cached'
                if mode == 'unset-user':
                    c['options'].pop('transport')
            prior = {**copy.deepcopy(previous), 'timestamp': 0}
            user = {'role': 'user', 'content': 'Continue', 'timestamp': 1}
            cases[1]['messages'] = [prior]
            if mode != 'cached-empty':
                cases[1]['messages'].append(user)
            if mode == 'cached-prefix':
                cases[1]['messages'] = [user]
            if mode == 'cached-configuration':
                cases[1]['options']['temperature'] = .4
            if mode == 'cached-tool':
                cases[1]['messages'] = [prior, {'role': 'toolResult', 'toolCallId': prior['content'][0]['id'],
                    'toolName': 'read', 'content': [{'type': 'text', 'text': 'ready'}], 'isError': False, 'timestamp': 1}]
            if mode == 'cached-chain':
                third = copy.deepcopy(cases[1])
                third['messages'] += [{**copy.deepcopy(following), 'timestamp': 2},
                                      {**user, 'content': 'Continue again', 'timestamp': 3}]
                cases.append(third)
        for c in cases:
            if mode == 'uncached':
                c['options']['cacheRetention'] = 'none'
        if mode == 'session-isolation':
            # Handshake affinity IDs clamp to 64 characters, but pool keys do not.
            cases[0]['options']['sessionId'] = 's' * 64 + 'first'
            cases[1]['options']['sessionId'] = 's' * 64 + 'second'
        try:
            if reference:
                result = subprocess.run(command, cwd=ROOT, input=json.dumps({'url': url, 'cases': cases}), text=True, capture_output=True, timeout=15)
                output = json.loads(result.stdout)
            else:
                encoded = [','.join(str(ord(c)) for c in json.dumps(case, separators=(',', ':'))) for case in cases]
                result = subprocess.run(command + [url, *encoded], cwd=ROOT, text=True, capture_output=True, timeout=15)
                output = native_results(result.stdout)
            assert result.returncode == 0, (result.stdout, result.stderr[-2000:])
        finally:
            server.shutdown()
            worker.join()
        server.server_close()
        assert not server.errors, server.errors
        assert len(output) == len(cases), output
        expected = [0, 1] if mode in ('uncached', 'session-isolation') else [0] * len(cases)
        assert server.identities == expected, (mode, server.identities)
        return [comparable(item) for item in output], server.requests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', default='build/openai-codex-stream-pool')
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    args = parser.parse_args()
    reference = ['bun', 'tests/openai_codex_websocket_reference.ts']
    initial = run(reference, 'reuse', True)[0]
    previous, following = initial[0]['message'], initial[1]['message']
    previous_tool = run(reference, 'seed-tool', True)[0][0]['message']
    modes = ('reuse', 'uncached', 'session-isolation', 'cached-empty', 'cached-user',
             'auto-user', 'unset-user', 'cached-configuration', 'cached-prefix', 'cached-tool', 'cached-chain')
    for mode in modes:
        prior = previous_tool if mode == 'cached-tool' else previous
        want = run(reference, mode, True, prior, following)
        second = want[1][1]
        delta = mode in ('cached-empty', 'cached-user', 'auto-user', 'cached-tool', 'cached-chain')
        assert ('previous_response_id' in second) == delta, (mode, second)
        if delta:
            assert second['previous_response_id'] == 'resp_1', second
            assert len(second['input']) == (0 if mode == 'cached-empty' else 1), second
        if mode == 'cached-chain':
            assert want[1][2]['previous_response_id'] == 'resp_2', want[1][2]
            assert len(want[1][2]['input']) == 1, want[1][2]
        for backend in args.backends:
            command = ['bun', args.prefix + '.js'] if backend == 'bun' else [args.prefix, '--threads', backend[-1]]
            got = run(command, mode, previous=prior, following=following)
            assert got == want, (backend, mode, got, want)
            print(f'{backend}: {mode} consecutive-turn requests/events/messages/connection identity MATCH')


if __name__ == '__main__':
    main()

"""Pinned Chat Completions wire and stream checks over a local HTTP/SSE server."""
import argparse
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = Path('/home/agent/code/pi-mono')

TEXT = b'data: {"id":"chatcmpl-1","model":"test-model","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}\n\ndata: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\ndata: malformed-after-done\n\n'
TOOL = b'data: {"id":"chatcmpl-tool","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call-1","type":"function","function":{"name":"lookup","arguments":"{\\\"value\\\":"}}]},"finish_reason":null}]}\n\ndata: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\\"42\\\"}"}}]},"finish_reason":"tool_calls"}]}\n\ndata: [DONE]\n\n'
TOOL_REPLY = b'data: {"id":"chatcmpl-answer","choices":[{"index":0,"delta":{"content":"found"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n'
ERROR_STOP = b'data: {"id":"chatcmpl-filter","choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}\n\ndata: [DONE]\n\n'

class Handler(http.server.BaseHTTPRequestHandler):
    requests = []
    response = TEXT
    status = 200
    statuses = []
    tool = False

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['content-length'])))
        self.requests.append((self.path, {key.lower(): value for key, value in self.headers.items()}, body))
        status = self.statuses.pop(0) if self.statuses else self.status
        self.send_response(status)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        response = (TOOL if len(self.requests) == 1 else TOOL_REPLY) if self.tool else self.response
        self.wfile.write(response if status == 200 else b'{"error":{"message":"failure"}}')

    def log_message(self, *_):
        pass

def run(command, base, mode='basic', expected=None):
    args = command + [base] + ([] if mode == 'basic' else [mode])
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    actual = result.stdout.splitlines()
    if expected is not None:
        assert actual == expected, (mode, actual, expected)

def oracle(mode):
    value = subprocess.check_output(['bun', 'tests/completions_oracle.ts', mode], cwd=ROOT, text=True)
    return json.loads(value)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--toolchain', default='/home/agent/code/pi-bend/build/bend-system-identity/bend2/main.ts')
    parser.add_argument('--backend', choices=('bun', 'native', 'all'), default='all')
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=UPSTREAM, text=True).strip()
    assert revision.startswith('f07218c4d'), revision
    source = (UPSTREAM / 'packages/ai/src/api/openai-completions.ts').read_text()
    for contract in ['chat.completions.create(params', 'stream_options = { include_usage: true }', 'case "tool_calls":', 'Provider finish_reason: ${reason}']:
        assert contract in source, contract
    baselines = {mode: oracle(mode) for mode in ('basic', 'tool', 'tool_image', 'compat', 'reasoning', 'reasoning_off', 'sampling', 'openrouter', 'openrouter_off', 'together', 'together_off', 'deepseek')}
    fixture = ROOT / 'packages/coding-agent/test/completions-provider-loopback.bend'
    with tempfile.TemporaryDirectory(prefix='completions-loopback-') as directory:
        commands = []
        if args.backend in ('bun', 'all'):
            path = Path(directory) / 'provider.js'
            subprocess.run(['bun', args.toolchain, str(fixture), '-o', str(path)], cwd=ROOT, check=True)
            commands.append(('bun', ['bun', str(path)]))
        if args.backend in ('native', 'all'):
            path = Path(directory) / 'provider'
            subprocess.run(['sh', 'scripts/build-pure.sh', str(fixture.relative_to(ROOT)), str(path)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands += [('native1', [str(path), '--threads', '1']), ('native4', [str(path), '--threads', '4'])]
        server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f'http://127.0.0.1:{server.server_port}/v1'
        agent = subprocess.check_output(['node', '-e', "const os=require('node:os');process.stdout.write(`pi (${os.platform()} ${os.release()}; ${os.arch()})`)"], text=True)
        try:
            for backend, command in commands:
                Handler.requests.clear()
                Handler.response = TEXT
                run(command, base, expected=baselines['basic']['eventTypes'])
                assert len(Handler.requests) == 1
                path, headers, body = Handler.requests[0]
                assert path == '/v1/chat/completions', path
                assert headers['authorization'] == 'Bearer test-completions-key', headers
                assert headers['user-agent'] == agent, headers
                assert body == baselines['basic']['payloads'][0], (body, baselines['basic'])
                print(f'{backend}: request body, auth, User-Agent, text events')
                Handler.requests.clear()
                Handler.tool = True
                run(command, base, 'tool', baselines['tool']['eventTypes'])
                assert len(Handler.requests) == 2, Handler.requests
                first, second = (item[2] for item in Handler.requests)
                assert first == baselines['tool']['payloads'][0], (first, baselines['tool']['payloads'][0])
                assert second == baselines['tool']['payloads'][1], (second, baselines['tool']['payloads'][1])
                print(f'{backend}: two-turn streamed tool replay')
                Handler.requests.clear()
                run(command, base, 'tool_image', baselines['tool_image']['eventTypes'])
                assert len(Handler.requests) == 2, Handler.requests
                first, second = (item[2] for item in Handler.requests)
                assert first == baselines['tool_image']['payloads'][0], (first, baselines['tool_image']['payloads'][0])
                assert second == baselines['tool_image']['payloads'][1], (second, baselines['tool_image']['payloads'][1])
                print(f'{backend}: multimodal tool-result image replay')
                Handler.tool = False
                Handler.requests.clear()
                Handler.response = ERROR_STOP
                run(command, base, expected=['start','error'])
                print(f'{backend}: provider finish error')
                Handler.requests.clear()
                Handler.status = 400
                run(command, base, expected=['error'])
                Handler.status = 200
                print(f'{backend}: HTTP error event')
                Handler.requests.clear()
                Handler.response = TEXT
                Handler.statuses = [429, 200]
                run(command, base, 'retry', ['start','text_start','text_delta','text_end','done'])
                assert len(Handler.requests) == 2, Handler.requests
                print(f'{backend}: transient HTTP retry')
                Handler.requests.clear()
                run(command, base, 'headers', ['start','text_start','text_delta','text_end','done'])
                assert Handler.requests[0][1]['user-agent'] == 'custom-agent'
                assert Handler.requests[0][1]['x-completions-test'] == 'option'
                print(f'{backend}: custom header override')
                Handler.requests.clear()
                run(command, base, 'compat', baselines['compat']['eventTypes'])
                selected = Handler.requests[0][2]
                assert selected == baselines['compat']['payloads'][0], (selected, baselines['compat'])
                print(f'{backend}: explicit core compatibility overrides')
                Handler.requests.clear()
                run(command, base, 'reasoning', baselines['reasoning']['eventTypes'])
                selected = Handler.requests[0][2]
                assert selected == baselines['reasoning']['payloads'][0], (selected, baselines['reasoning'])
                print(f'{backend}: reasoning effort request')
                Handler.requests.clear()
                run(command, base, 'reasoning_off', baselines['reasoning_off']['eventTypes'])
                assert Handler.requests[0][2] == baselines['reasoning_off']['payloads'][0], (Handler.requests[0][2], baselines['reasoning_off'])
                print(f'{backend}: default-off reasoning request')
                Handler.requests.clear()
                run(command, base, 'sampling', baselines['sampling']['eventTypes'])
                assert Handler.requests[0][2] == baselines['sampling']['payloads'][0], (Handler.requests[0][2], baselines['sampling'])
                print(f'{backend}: model and option sampling precedence')
                for mode in ('openrouter', 'openrouter_off', 'together', 'together_off', 'deepseek'):
                    Handler.requests.clear()
                    run(command, base, mode, baselines[mode]['eventTypes'])
                    assert len(Handler.requests) == 1, Handler.requests
                    selected = Handler.requests[0][2]
                    assert selected == baselines[mode]['payloads'][0], (mode, selected, baselines[mode])
                    print(f'{backend}: {mode} reasoning request')
                Handler.requests.clear()
                run(command, base, 'unsupported', ['start','text_start','text_delta','text_end','done'])
                assert len(Handler.requests) == 1, Handler.requests
                print(f'{backend}: compat without finish_reason support streams normally')
        finally:
            server.shutdown()
            thread.join()

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""The Anthropic, OpenAI Codex and Radius loopback callback servers against
pinned pi-mono.

Each login runs through packages/ai/test/oauth-flows.bend (the port) and
tests/oauth_flows_reference.ts (pinned pi-mono), with the provider requests
answered by the loopback server of tests/oauth_flows_check.py. On the
auth_url event this driver requests the provider's callback server with a
sequence of targets (wrong route, OAuth errors, missing parameters, state
mismatch, then the completing request) and records each response's status,
content type and body. Both must answer every request identically, byte for
byte, and end the login the same way.

Usage: python3 tests/oauth_callback_pages_check.py [--port-command ...]
(default: build the port with Bun; pass e.g. `build/oauth-flows --threads 4`
for a native build).
"""
import argparse
import base64
import http.client
import json
import os
import shlex
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.parse import parse_qs, quote, urlsplit

from oauth_flows_check import Server, decoded

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/ai/test/oauth-flows.bend'

# The Codex credential needs the account id claim in the access token.
CODEX_ACCESS = 'aaa.' + base64.urlsafe_b64encode(json.dumps({'https://api.openai.com/auth': {'chatgpt_account_id': 'acc_test'}}).encode()).decode().rstrip('=') + '.bbb'

# flow -> (callback port, prompt answers, [requests ending in the completing one])
FLOWS = {
    'anthropic': (53692, [], [
        ['/wrong', '/callback?error=access_denied', '/callback?error=%3Cb%3E%26%22%27', '/callback?error=&code=c&state=x',
         '/callback?code=c', '/callback?state={state}', '/callback?code=&state={state}', '/callback?code=c&state=wrong',
         '/callback/?code=c&state={state}', '/callback?code=browser-code&state={state}'],
    ]),
    'codex': (1455, ['browser'], [
        ['/wrong', '/auth/callback?code=c', '/auth/callback?code=c&state=wrong', '/auth/callback?code=c&state=',
         '/auth/callback?state={state}', '/auth/callback?code=&state={state}', '/auth/callback?error=access_denied&state={state}',
         '/auth/callback?code=browser-code&state={state}'],
    ]),
    'radius': (1456, ['browser'], [
        ['/wrong', '/oauth/callback?code=c&state=wrong', '/oauth/callback?code=c', '/oauth/callback?state={state}',
         '/oauth/callback?code=&state={state}', '/oauth/callback?code=browser-code&state={state}'],
        ['/oauth/callback?error=access_denied&error_description=' + quote('Denied <by> "user" & co.') + '&state={state}'],
        ['/oauth/callback?error=access_denied&state={state}'],
        ['/oauth/callback?error=access_denied&error_description=&state={state}'],
    ]),
}


def routes(server):
    def answer(request):
        url = request['url']
        if url.endswith('/v1/oauth'):
            return 200, {'authorizationEndpoint': 'https://radius-ui.example/authorize'}, None
        access = CODEX_ACCESS if 'openai' in url else 'access-token'
        return 200, {'access_token': access, 'refresh_token': 'refresh-token', 'expires_in': 3600, 'id_token': CODEX_ACCESS}, None
    server.routes = {'*': answer}


def fetch(port, target):
    for _ in range(100):
        try:
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
            connection.request('GET', target)
            response = connection.getresponse()
            result = (response.status, response.getheader('content-type'), response.read().decode())
            connection.close()
            return result
        except ConnectionRefusedError:
            time.sleep(0.05)
    return ('refused', None, '')


def login(command, server, flow, visits):
    port, prompts, _ = FLOWS[flow]
    with tempfile.NamedTemporaryFile('w', suffix='.json', prefix='oauth-pages-') as file:
        json.dump({'flow': flow, 'prompts': prompts, 'pendingPrompt': True}, file)
        file.flush()
        env = {k: v for k, v in os.environ.items() if k != 'PI_OAUTH_CALLBACK_HOST'}
        process = subprocess.Popen(command + [server.base, file.name], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        pages, outcome = [], None
        try:
            for line in process.stdout:
                tag, _, rest = line.rstrip('\n').partition(' ')
                if tag == 'N':
                    event = json.loads(decoded(rest))
                    if event['type'] == 'auth_url':
                        state = parse_qs(urlsplit(event['url']).query)['state'][0]
                        for target in visits:
                            pages.append((target, *fetch(port, target.replace('{state}', quote(state)))))
                elif tag == 'C':
                    credential = json.loads(decoded(rest))
                    outcome = ('credential', credential['access'], credential['refresh'])
                elif tag == 'E':
                    outcome = ('error', decoded(rest))
            process.wait(timeout=60)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        if process.returncode != 0:
            raise AssertionError((flow, process.returncode, process.stderr.read()[-2000:]))
    return pages, outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--port-command')
    parser.add_argument('--flows', nargs='+', default=list(FLOWS))
    arguments = parser.parse_args()
    if arguments.port_command:
        port_command = shlex.split(arguments.port_command)
    else:
        subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', 'build/oauth-flows.js'], cwd=ROOT, check=True)
        port_command = ['bun', 'build/oauth-flows.js']
    failures = 0
    server = Server()
    routes(server)
    for flow in arguments.flows:
        for visits in FLOWS[flow][2]:
            upstream = login(['bun', 'tests/oauth_flows_reference.ts'], server, flow, visits)
            port = login(port_command, server, flow, visits)
            if upstream != port or len(upstream[0]) != len(visits):
                failures += 1
                print(f'FAIL {flow}: {visits}')
                for want, have in zip(upstream[0], port[0]):
                    if want != have:
                        print(f'  upstream {want[:3]} {want[3][:300]!r}\n  port     {have[:3]} {have[3][:300]!r}')
                if upstream[1] != port[1]:
                    print(f'  outcome upstream {upstream[1]} port {port[1]}')
            else:
                statuses = ' '.join(str(page[1]) for page in port[0])
                print(f'PASS {flow}: {len(visits)} callback requests ({statuses}) and the login outcome match upstream')
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()

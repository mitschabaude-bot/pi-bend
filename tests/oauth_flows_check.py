#!/usr/bin/env python3
"""pi-mono's OAuth flow suites (packages/ai/test/*-oauth.test.ts,
oauth-auth.test.ts) against a loopback server.

Upstream stubs the global fetch per test; here the flows run with a fetch
that rewrites `https://<host><path>` to `<server>/<host><path>`
(packages/ai/test/oauth-flows.bend for the port, tests/oauth_flows_reference.ts
for pinned pi-mono), and the server answers each URL as the test's stub does
and records the requests. Every case runs through both; the upstream
assertions must hold for each, and both must send the same requests and give
the same result.

Adaptation: upstream drives the device-code polling with fake timers; here
the clock is real, so a poll must fall in [expected, expected + 900 ms) after
login starts, and credential expiry is compared to the clock at the response.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import http.server
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from upstream_pin import UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/ai/test/oauth-flows.bend'


def decoded(points):
    return ''.join(chr(int(p)) for p in points.split(',')) if points else ''


class Server:
    """Answers by path (`/<host><path>`): routes map a URL to a function
    (request) -> (status, body, headers); requests are recorded with their
    arrival time."""

    def __init__(self):
        self.routes = {}
        self.requests = []
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def handle_any(self):
                length = int(self.headers.get('content-length', 0) or 0)
                raw = self.rfile.read(length) if length else b''
                url = 'https://' + self.path.lstrip('/')
                parts = urlsplit(url)
                key = f'{parts.scheme}://{parts.netloc}{parts.path}'
                request = dict(method=self.command, url=url, key=key, headers={k.lower(): v for k, v in self.headers.items()}, body=raw.decode('utf-8', 'replace'), at=time.time())
                owner.requests.append(request)
                route = owner.routes.get(key) or owner.routes.get('*')
                if route is None:
                    status, body, headers = 404, {'error': f'Unexpected request: {url}'}, {}
                else:
                    status, body, headers = route(request)
                if status is None:
                    # A transport failure: close without a response.
                    self.close_connection = True
                    self.connection.shutdown(2)
                    return
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                for name, value in (headers or {}).items():
                    self.send_header(name, value)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = do_POST = handle_any

            def log_message(self, *_):
                pass

        class Quiet(http.server.ThreadingHTTPServer):
            def handle_error(self, request, client_address):
                pass  # clients that abort or drop connections are expected

        self.http = Quiet(('127.0.0.1', 0), Handler)
        self.http.daemon_threads = True
        threading.Thread(target=self.http.serve_forever, daemon=True).start()

    @property
    def base(self):
        return f'http://127.0.0.1:{self.http.server_port}'


def form(request):
    return {k: v[0] for k, v in parse_qs(request['body'], keep_blank_values=True).items()}


def reply(body, status=200, headers=None):
    return lambda request: (status, body, headers)


def sequence(*replies):
    queue = list(replies)
    return lambda request: queue.pop(0)(request) if queue else (500, {'error': 'Unexpected extra request'}, None)


class Failed(AssertionError):
    pass


def expect(condition, message):
    if not condition:
        raise Failed(message)


def run(command, server, spec):
    with tempfile.NamedTemporaryFile('w', suffix='.json', prefix='oauth-case-') as file:
        json.dump(spec, file)
        file.flush()
        env = {k: v for k, v in os.environ.items() if not k.startswith('KIMI_')}
        env.update(spec.get('env', {}))
        result = subprocess.run(command + [server.base, file.name], cwd=ROOT, capture_output=True, text=True, timeout=300, env=env)
    if result.returncode != 0:
        raise Failed(f'exit {result.returncode}: {result.stderr[-1500:]}')
    out = dict(events=[], prompts=[], credential=None, auth=None, facts=None, error=None, start=None, browser={}, available=None, stored='<unread>')
    for line in result.stdout.splitlines():
        tag, _, rest = line.partition(' ')
        if tag == 'S':
            seconds, millis = rest.split()
            out['start'] = int(seconds) + int(millis) / 1000
        elif tag == 'N':
            out['events'].append(json.loads(decoded(rest)))
        elif tag == 'P':
            out['prompts'].append(json.loads(decoded(rest)))
        elif tag == 'C':
            out['credential'] = json.loads(decoded(rest))
        elif tag == 'A':
            out['auth'] = json.loads(decoded(rest))
        elif tag == 'D':
            out['facts'] = json.loads(decoded(rest))
        elif tag == 'E':
            out['error'] = decoded(rest)
        elif tag == 'V':
            out['available'] = json.loads(decoded(rest))
        elif tag == 'T':
            out['stored'] = json.loads(decoded(rest))
        elif tag in ('B', 'B2', 'M', 'R'):
            out['browser'][tag] = rest
    return out


def near(actual, expected_seconds, start):
    """A poll time at `expected_seconds` after the login started (real clock)."""
    offset = actual - start
    return expected_seconds - 0.001 <= offset < expected_seconds + 0.9


def expires_near(credential, base_time, lifetime_ms):
    return abs(credential['expires'] - (base_time * 1000 + lifetime_ms)) < 1500


TESTS = []


def test(name):
    def register(function):
        TESTS.append((name, function))
        return function
    return register


def first_difference(want, have, path='$'):
    if isinstance(want, dict) and isinstance(have, dict):
        for key in list(want) + [key for key in have if key not in want]:
            if key not in have or key not in want or want[key] != have[key]:
                return first_difference(want.get(key, '<absent>'), have.get(key, '<absent>'), f'{path}.{key}')
    elif isinstance(want, list) and isinstance(have, list) and want != have:
        for index, (left, right) in enumerate(zip(want, have)):
            if left != right:
                return first_difference(left, right, f'{path}[{index}]')
        return f'{path}: length {len(want)} != {len(have)}'
    return f'{path}: upstream {json.dumps(want)[:500]} != port {json.dumps(have)[:500]}'


# Per-login randomness (the loopback callback's port and path, PKCE values).
RANDOM = [
    (re.compile(r'http(%3A%2F%2F|://)(127\.0\.0\.1|localhost)(%3A|:)\d+(%2F|/)oauth(%2F|/)callback(%2F|/)[0-9a-f-]+'), r'<callback \2>'),
    (re.compile(r'code_challenge=[A-Za-z0-9_-]+'), 'code_challenge=<challenge>'),
    (re.compile(r'"code_verifier":"[A-Za-z0-9_-]+"'), '"code_verifier":"<verifier>"'),
    (re.compile(r'([?&]state=|"state":")[A-Za-z0-9_-]+'), r'\1<state>'),
]


def unrandom(value):
    text = value if isinstance(value, str) else json.dumps(value)
    for pattern, replacement in RANDOM:
        text = pattern.sub(replacement, text)
    return text if isinstance(value, str) else json.loads(text)


def request_views(requests):
    # The runtime's own defaults (Bun's User-Agent, fetch's `Accept: */*`)
    # are not the flow's; headers the flow sets are compared.
    return [dict(method=r['method'], url=r['url'], body=unrandom(r['body']), headers={k: r['headers'].get(k) for k in ('authorization', 'content-type', 'accept', 'x-api-version', 'user-agent') if r['headers'].get(k) is not None and not (k == 'user-agent' and r['headers'][k].startswith('Bun/')) and not (k == 'accept' and r['headers'][k] == '*/*')}) for r in requests]


def normalized(out):
    """Outputs without clock values."""
    def clockless(value):
        credential = dict(value) if isinstance(value, dict) else value
        if credential and 'expires' in credential:
            credential['expires'] = '<clock>' if credential['expires'] < 1e15 else credential['expires']
        return credential
    return unrandom(dict(events=out['events'], prompts=out['prompts'], credential=clockless(out['credential']), auth=out['auth'], facts=out['facts'], error=out['error'], browser=out.get('browser', {}), available=out.get('available'), stored=clockless(out.get('stored'))))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--prefix', default='build/oauth-flows')
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    parser.add_argument('--no-build', action='store_true')
    parser.add_argument('--only')
    arguments = parser.parse_args()
    if not arguments.no_build:
        if 'bun' in arguments.backends:
            subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
        if any(b.startswith('native') for b in arguments.backends):
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)
    commands = {'bun': ['bun', arguments.prefix + '.js'], 'native-1': [arguments.prefix, '--threads', '1'], 'native-4': [arguments.prefix, '--threads', '4']}
    executors = [('upstream', ['bun', 'tests/oauth_flows_reference.ts'])] + [(backend, commands[backend]) for backend in arguments.backends]
    failures = 0
    for name, function in TESTS:
        if arguments.only and arguments.only not in name:
            continue
        results = {}
        problems = []
        for executor, command in executors:
            server = Server()
            try:
                out = function(lambda spec: run(command, server, spec), server)
                results[executor] = [normalized(out) if out else None, request_views(server.requests)]
            except Failed as error:
                problems.append(f'{executor}: {error}')
            finally:
                server.http.shutdown()
        reference = results.get('upstream')
        for executor, value in results.items():
            if executor != 'upstream' and reference and value != reference:
                problems.append(f'{executor} differs from upstream at {first_difference(reference, value)}')
        if problems:
            failures += 1
            print(f'FAIL {name}')
            for problem in problems:
                print(f'  {problem[:2500]}')
        else:
            print(f'PASS {name}')
    sys.exit(1 if failures else 0)


# xai-oauth.test.ts
# -----------------
XAI_CLIENT = 'b1a00492-073a-47ea-816f-4c329264a828'
XAI_DEVICE = 'https://auth.x.ai/oauth2/device/code'
XAI_TOKEN = 'https://auth.x.ai/oauth2/token'


def device_code_response(**overrides):
    return {'device_code': 'device-code', 'user_code': 'ABCD-1234', 'verification_uri': 'https://accounts.x.ai/oauth2/device', 'expires_in': 900, 'interval': 5, **overrides}


def token_response(**overrides):
    body = {'access_token': 'access-token', 'refresh_token': 'refresh-token', 'expires_in': 21_600, 'token_type': 'Bearer', **overrides}
    return {k: v for k, v in body.items() if v is not None}


X = 'xai-oauth.test.ts > xAI OAuth device flow'


@test(f'{X} > uses the device grant, delays polling, and handles pending and slow_down')
def xai_device_grant(execute, server):
    def device(request):
        f = form(request)
        expect(f.get('client_id') == XAI_CLIENT and f.get('scope') == 'openid profile email offline_access grok-cli:access api:access' and f.get('referrer') == 'pi', f)
        return 200, device_code_response(), None

    def token_check(request):
        f = form(request)
        expect(f.get('grant_type') == 'urn:ietf:params:oauth:grant-type:device_code' and f.get('client_id') == XAI_CLIENT and f.get('device_code') == 'device-code', f)
    replies = [(400, {'error': 'authorization_pending'}), (400, {'error': 'slow_down', 'interval': 10}), (200, token_response())]

    def token(request):
        token_check(request)
        status, body = replies.pop(0)
        return status, body, None
    server.routes = {XAI_DEVICE: device, XAI_TOKEN: token}
    out = execute({'flow': 'xai', 'action': 'login'})
    expect(out['events'] == [{'type': 'device_code', 'userCode': 'ABCD-1234', 'verificationUri': 'https://accounts.x.ai/oauth2/device', 'intervalSeconds': 5, 'expiresInSeconds': 900}], out['events'])
    polls = [r['at'] for r in server.requests if r['key'] == XAI_TOKEN]
    expect(len(polls) == 3 and near(polls[0], 5, out['start']) and near(polls[1], 10, out['start']) and near(polls[2], 20, out['start']), [p - out['start'] for p in polls])
    credential = out['credential']
    expect(credential and credential['type'] == 'oauth' and credential['access'] == 'access-token' and credential['refresh'] == 'refresh-token' and expires_near(credential, polls[2], 21_600_000 - 300_000), (credential, out['error']))
    return out


@test(f'{X} > falls back to the default poll interval when the response reports interval 0')
def xai_interval_zero(execute, server):
    server.routes = {XAI_DEVICE: reply(device_code_response(interval=0)), XAI_TOKEN: reply(token_response())}
    out = execute({'flow': 'xai', 'action': 'login'})
    polls = [r['at'] for r in server.requests if r['key'] == XAI_TOKEN]
    expect(out['credential'] and len(polls) == 1 and near(polls[0], 5, out['start']), ([p - out['start'] for p in polls], out['error']))
    return out


@test(f'{X} > prefers verification_uri_complete when the server provides it')
def xai_complete_uri(execute, server):
    server.routes = {XAI_DEVICE: reply(device_code_response(verification_uri_complete='https://accounts.x.ai/oauth2/device?user_code=ABCD-1234')), XAI_TOKEN: reply(token_response())}
    out = execute({'flow': 'xai', 'action': 'login'})
    expect(out['events'] == [{'type': 'device_code', 'userCode': 'ABCD-1234', 'verificationUri': 'https://accounts.x.ai/oauth2/device?user_code=ABCD-1234', 'intervalSeconds': 5, 'expiresInSeconds': 900}], out['events'])
    return out


@test(f'{X} > rejects a non-https verification_uri_complete')
def xai_http_complete(execute, server):
    server.routes = {'*': reply(device_code_response(verification_uri_complete='http://accounts.x.ai/oauth2/device?user_code=ABCD-1234'))}
    out = execute({'flow': 'xai', 'action': 'login'})
    expect(out['error'] and 'Untrusted verification URI' in out['error'], out)
    return out


for uri in ['http://accounts.x.ai/oauth2/device', 'file:///etc/passwd', 'not a url']:
    def xai_untrusted(execute, server, uri=uri):
        server.routes = {'*': reply(device_code_response(verification_uri=uri))}
        out = execute({'flow': 'xai', 'action': 'login'})
        expect(out['error'] and 'Untrusted verification URI' in out['error'], out)
        return out
    test(f'{X} > rejects a non-https verification URI: {uri}')(xai_untrusted)


for error in ['access_denied', 'authorization_denied']:
    def xai_denied(execute, server, error=error):
        server.routes = {'*': sequence(reply(device_code_response(interval=1)), reply({'error': error}, 400))}
        out = execute({'flow': 'xai', 'action': 'login'})
        expect(out['error'] and 'xAI device authorization was denied' in out['error'], out)
        return out
    test(f'{X} > fails when device authorization is denied: {error}')(xai_denied)


@test(f'{X} > cancels while waiting for the first token poll')
def xai_cancel(execute, server):
    server.routes = {'*': reply(device_code_response())}
    out = execute({'flow': 'xai', 'action': 'login', 'abortOnDeviceCode': True})
    expect(out['error'] and 'Login cancelled' in out['error'] and len(server.requests) == 1, (out, len(server.requests)))
    return out


@test(f'{X} > refreshes tokens and preserves an unrotated refresh token')
def xai_refresh(execute, server):
    def token(request):
        f = form(request)
        expect(request['url'] == XAI_TOKEN and f.get('grant_type') == 'refresh_token' and f.get('client_id') == XAI_CLIENT, f)
        if f.get('refresh_token') == 'old-refresh':
            return 200, token_response(access_token='new-access', refresh_token='new-refresh'), None
        expect(f.get('refresh_token') == 'keep-refresh', f)
        return 200, token_response(access_token='newer-access', refresh_token=None), None
    server.routes = {'*': token}
    credential = lambda refresh: {'type': 'oauth', 'access': 'old-access', 'refresh': refresh, 'expires': 0}
    rotated = execute({'flow': 'xai', 'action': 'refresh', 'credential': credential('old-refresh')})
    preserved = execute({'flow': 'xai', 'action': 'refresh', 'credential': credential('keep-refresh')})
    expect(rotated['credential']['type'] == 'oauth' and rotated['credential']['refresh'] == 'new-refresh' and rotated['credential']['access'] == 'new-access', rotated)
    expect(preserved['credential']['refresh'] == 'keep-refresh' and preserved['credential']['access'] == 'newer-access', preserved)
    facts = execute({'flow': 'xai', 'action': 'describe'})
    expect(facts['facts']['name'] == 'xAI (Grok/X subscription)', facts)
    auth = execute({'flow': 'xai', 'action': 'toAuth', 'credential': preserved['credential']})
    expect(auth['auth'] == {'apiKey': 'newer-access'}, auth)
    return dict(events=[], prompts=[], credential=preserved['credential'], auth=auth['auth'], facts=facts['facts'], error=None)


@test(f'{X} > assumes a one-hour lifetime when expires_in is missing')
def xai_default_lifetime(execute, server):
    server.routes = {'*': reply(token_response(expires_in=None))}
    out = execute({'flow': 'xai', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old-access', 'refresh': 'old-refresh', 'expires': 0}})
    expect(out['credential'] and expires_near(out['credential'], server.requests[-1]['at'], 3_600_000 - 300_000), out)
    return out


@test(f'{X} > rejects token responses with missing fields')
def xai_missing_fields(execute, server):
    server.routes = {'*': reply(token_response(access_token=None))}
    out = execute({'flow': 'xai', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old-access', 'refresh': 'old-refresh', 'expires': 0}})
    expect(out['error'] and 'Invalid xAI OAuth response field: access_token' in out['error'], out)
    return out


@test(f'{X} > surfaces the upstream error code and description on refresh failure')
def xai_refresh_failure(execute, server):
    server.routes = {'*': reply({'error': 'invalid_grant', 'error_description': 'refresh token revoked'}, 400)}
    out = execute({'flow': 'xai', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old-access', 'refresh': 'old-refresh', 'expires': 0}})
    expect(out['error'] and 'xAI OAuth token refresh failed (HTTP 400): invalid_grant: refresh token revoked' in out['error'], out)
    return out


# meta-oauth.test.ts
# ------------------
META_CLIENT = '1031625952748946'
META_DEVICE = 'https://auth.meta.com/oidc/device/authorization/'
META_TOKEN = 'https://auth.meta.com/oidc/device/token/'
META_MINT = 'https://api.meta.ai/muse-code/key'
DAY_MS = 24 * 60 * 60 * 1000
M = 'meta-oauth.test.ts > Meta OAuth'


@test(f'{M} > logs in with the device flow and mints a Model API key')
def meta_login(execute, server):
    def device(request):
        expect(request['method'] == 'POST' and form(request).get('client_id') == META_CLIENT, request)
        return 200, {'device_code': 'device-code-123', 'user_code': 'ABCD-1234', 'verification_uri': 'https://auth.meta.com/oauth/device/', 'verification_uri_complete': 'https://auth.meta.com/oauth/device/?code=ABCD-1234', 'interval': 5, 'expires_in': 600}, None
    polls = [(400, {'error': 'authorization_pending'}), (200, {'access_token': 'identity-token', 'token_type': 'Bearer'})]

    def token(request):
        f = form(request)
        expect(f.get('grant_type') == 'urn:ietf:params:oauth:grant-type:device_code' and f.get('client_id') == META_CLIENT and f.get('device_code') == 'device-code-123', f)
        status, body = polls.pop(0)
        return status, body, None

    def mint(request):
        expect(request['method'] == 'POST' and request['headers'].get('authorization') == 'Bearer identity-token', request['headers'])
        return 200, {'api_key': 'LLM|minted-key'}, None
    server.routes = {META_DEVICE: device, META_TOKEN: token, META_MINT: mint}
    out = execute({'flow': 'meta', 'action': 'login'})
    expect(out['events'][0] == {'type': 'device_code', 'userCode': 'ABCD-1234', 'verificationUri': 'https://auth.meta.com/oauth/device/?code=ABCD-1234', 'intervalSeconds': 5, 'expiresInSeconds': 600}, out['events'])
    minted = next(r['at'] for r in server.requests if r['key'] == META_MINT)
    polled = [r['at'] for r in server.requests if r['key'] == META_TOKEN]
    expect(len(polled) == 2 and near(polled[0], 5, out['start']) and near(polled[1], 10, out['start']), [p - out['start'] for p in polled])
    c = out['credential']
    expect(c and c['type'] == 'oauth' and c['refresh'] == 'identity-token' and c['access'] == 'LLM|minted-key' and expires_near(c, minted, DAY_MS), (c, out['error']))
    return out


@test(f'{M} > re-mints the API key from the stored identity token on refresh')
def meta_refresh(execute, server):
    def mint(request):
        expect(request['url'] == META_MINT and request['headers'].get('authorization') == 'Bearer identity-token', request)
        return 200, {'api_key': 'LLM|fresh-key'}, None
    server.routes = {'*': mint}
    out = execute({'flow': 'meta', 'action': 'refresh', 'credential': {'type': 'oauth', 'refresh': 'identity-token', 'access': 'LLM|old-key', 'expires': 1}})
    c = out['credential']
    expect(c and c['refresh'] == 'identity-token' and c['access'] == 'LLM|fresh-key' and expires_near(c, server.requests[-1]['at'], DAY_MS), out)
    return out


@test(f'{M} > reports the setup URL when Meta issues no key')
def meta_setup(execute, server):
    server.routes = {'*': reply({'require_payment': True, 'action_url': 'https://dev.meta.ai/billing'})}
    out = execute({'flow': 'meta', 'action': 'refresh', 'credential': {'type': 'oauth', 'refresh': 'identity-token', 'access': '', 'expires': 1}})
    expect(out['error'] and 'Complete setup at https://dev.meta.ai/billing' in out['error'], out)
    return out


@test(f'{M} > uses the minted key as the request api key')
def meta_to_auth(execute, server):
    out = execute({'flow': 'meta', 'action': 'toAuth', 'credential': {'type': 'oauth', 'refresh': 'identity-token', 'access': 'LLM|key', 'expires': 1}})
    expect(out['auth'] == {'apiKey': 'LLM|key'}, out)
    return out


# kimi-coding-oauth.test.ts
# -------------------------
KIMI_CLIENT = '17e5f671-d194-4dfb-9706-5516cb48c098'
KIMI_HOST = 'https://auth.kimi.com'
K = 'kimi-coding-oauth.test.ts > Kimi Code OAuth'


def kimi_device(**overrides):
    return {'user_code': 'ABCD-1234', 'device_code': 'device-code-123', 'verification_uri': 'https://www.kimi.com/code', 'verification_uri_complete': 'https://www.kimi.com/code?user_code=ABCD-1234', 'interval': 5, 'expires_in': 600, **overrides}


@test(f'{K} > logs in with the device authorization flow')
def kimi_login(execute, server):
    def device(request):
        expect(request['method'] == 'POST' and request['headers'].get('content-type') == 'application/x-www-form-urlencoded' and request['headers'].get('accept') == 'application/json' and form(request).get('client_id') == KIMI_CLIENT, request)
        return 200, kimi_device(), None
    polls = [(400, {'error': 'authorization_pending'}), (200, {'access_token': 'access-token', 'refresh_token': 'refresh-token', 'expires_in': 3600})]

    def token(request):
        f = form(request)
        expect(f.get('grant_type') == 'urn:ietf:params:oauth:grant-type:device_code' and f.get('client_id') == KIMI_CLIENT and f.get('device_code') == 'device-code-123', f)
        status, body = polls.pop(0)
        return status, body, None
    server.routes = {f'{KIMI_HOST}/api/oauth/device_authorization': device, f'{KIMI_HOST}/api/oauth/token': token}
    out = execute({'flow': 'kimi', 'action': 'login'})
    expect(out['events'] == [{'type': 'device_code', 'userCode': 'ABCD-1234', 'verificationUri': 'https://www.kimi.com/code?user_code=ABCD-1234', 'intervalSeconds': 5, 'expiresInSeconds': 600}], out['events'])
    polled = [r['at'] for r in server.requests if r['key'].endswith('/api/oauth/token')]
    expect(len(polled) == 2 and near(polled[0], 5, out['start']) and near(polled[1], 10, out['start']), [p - out['start'] for p in polled])
    c = out['credential']
    expect(c and c['access'] == 'access-token' and c['refresh'] == 'refresh-token' and expires_near(c, polled[1], 3_600_000), (c, out['error']))
    return out


for error, text in [('expired_token', 'expired'), ('access_denied', 'denied')]:
    def kimi_fails(execute, server, error=error, text=text):
        server.routes = {f'{KIMI_HOST}/api/oauth/device_authorization': reply(kimi_device()), f'{KIMI_HOST}/api/oauth/token': reply({'error': error}, 400)}
        out = execute({'flow': 'kimi', 'action': 'login'})
        expect(out['error'] and text in out['error'], out)
        return out
    test(f'{K} > ' + ('fails when the device code expires' if error == 'expired_token' else 'fails when the user denies the login'))(kimi_fails)


@test(f'{K} > honors the KIMI_CODE_OAUTH_HOST override')
def kimi_host(execute, server):
    server.routes = {'https://auth.example.com/api/oauth/device_authorization': reply(kimi_device(interval=1)), 'https://auth.example.com/api/oauth/token': reply({'access_token': 'a', 'refresh_token': 'r', 'expires_in': 60})}
    out = execute({'flow': 'kimi', 'action': 'login', 'env': {'KIMI_CODE_OAUTH_HOST': 'https://auth.example.com/'}})
    expect(out['credential'] and out['credential']['access'] == 'a' and out['credential']['refresh'] == 'r', out)
    expect([r['url'] for r in server.requests] == ['https://auth.example.com/api/oauth/device_authorization', 'https://auth.example.com/api/oauth/token'], [r['url'] for r in server.requests])
    return out


@test(f'{K} > refreshes tokens and returns a Bearer header for requests')
def kimi_refresh(execute, server):
    def token(request):
        f = form(request)
        expect(request['url'] == f'{KIMI_HOST}/api/oauth/token' and f.get('grant_type') == 'refresh_token' and f.get('refresh_token') == 'old-refresh' and f.get('client_id') == KIMI_CLIENT, (request['url'], f))
        return 200, {'access_token': 'new-access', 'refresh_token': 'new-refresh', 'expires_in': 3600}, None
    server.routes = {'*': token}
    before = time.time()
    out = execute({'flow': 'kimi', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old-access', 'refresh': 'old-refresh', 'expires': before * 1000}})
    c = out['credential']
    expect(c and set(c) == {'type', 'access', 'refresh', 'expires'} and c['access'] == 'new-access' and c['refresh'] == 'new-refresh' and c['expires'] >= before * 1000 + 3_600_000, out)
    auth = execute({'flow': 'kimi', 'action': 'toAuth', 'credential': c})
    expect(auth['auth'] == {'headers': {'Authorization': 'Bearer new-access'}}, auth)
    return dict(out, auth=auth['auth'])


@test(f'{K} > retries refresh on 429 and fails unauthorized on invalid_grant')
def kimi_retry(execute, server):
    server.routes = {'*': sequence(reply({'error': 'temporarily_unavailable'}, 429), reply({'access_token': 'a', 'refresh_token': 'r', 'expires_in': 60}))}
    old = {'type': 'oauth', 'access': 'old', 'refresh': 'old', 'expires': 0}
    first = execute({'flow': 'kimi', 'action': 'refresh', 'credential': old})
    expect(first['credential'] and first['credential']['access'] == 'a' and len(server.requests) == 2, (first, len(server.requests)))
    expect(server.requests[1]['at'] - server.requests[0]['at'] >= 0.99, server.requests[1]['at'] - server.requests[0]['at'])
    server.routes = {'*': reply({'error': 'invalid_grant'}, 400)}
    second = execute({'flow': 'kimi', 'action': 'refresh', 'credential': old})
    expect(second['error'] and 'unauthorized' in second['error'], second)
    return dict(first, error=second['error'])


# github-copilot-oauth.test.ts
# ----------------------------
COPILOT_TOKEN = 'tid=test;exp=9999999999;proxy-ep=proxy.individual.githubcopilot.com;'
COPILOT_MODELS = 'https://api.individual.githubcopilot.com/models'
G = 'github-copilot-oauth.test.ts > GitHub Copilot OAuth device flow'
_COPILOT_IDS = []


def copilot_model_id(index):
    if not _COPILOT_IDS:
        script = f"import {{ githubCopilotProvider }} from {json.dumps(str(UPSTREAM / 'packages/ai/src/providers/github-copilot.ts'))}; console.log(JSON.stringify(githubCopilotProvider().getModels().map((m) => m.id)));"
        _COPILOT_IDS.extend(json.loads(subprocess.run(['bun', '-e', script], capture_output=True, text=True, check=True).stdout))
    return _COPILOT_IDS[index]


def login_routes(models, policy=None):
    def route(request):
        url = request['url']
        if url.endswith('/login/device/code'):
            return 200, {'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': 'https://github.com/login/device', 'interval': 1, 'expires_in': 900}, None
        if url.endswith('/login/oauth/access_token'):
            return 200, {'access_token': 'ghu_refresh_token'}, None
        if '/copilot_internal/v2/token' in url:
            return 200, {'token': COPILOT_TOKEN, 'expires_at': 9999999999}, None
        if url == COPILOT_MODELS:
            return models(request)
        if url.startswith(COPILOT_MODELS + '/') and url.endswith('/policy'):
            expect(policy is not None, f'Unexpected policy request: {url}')
            return policy(url[len(COPILOT_MODELS) + 1:-len('/policy')])
        return 404, {'error': f'Unexpected fetch URL: {url}'}, None
    return {'*': route}


def copilot_refresh(execute, server, data, proxy_host='proxy.individual.githubcopilot.com'):
    access = f'tid=test;exp=9999999999;proxy-ep={proxy_host};'
    models_url = 'https://' + proxy_host.replace('proxy.', 'api.', 1) + '/models'

    def route(request):
        if '/copilot_internal/v2/token' in request['url']:
            return 200, {'token': access, 'expires_at': 9999999999}, None
        if request['url'] == models_url:
            expect(request['headers'].get('authorization') == f'Bearer {access}', request['headers'])
            return 200, {'data': data}, None
        return 404, {'error': 'Unexpected fetch URL: ' + request['url']}, None
    server.routes = {'*': route}
    return execute({'flow': 'copilot', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old-access-token', 'refresh': 'ghu_refresh_token', 'expires': 0}})


def entry(id, picker, state=None, tools=True):
    item = {'id': id, 'model_picker_enabled': picker, 'capabilities': {'supports': {'tool_calls': tools}}}
    if state:
        item['policy'] = {'state': state}
    return item


# The refreshed credential goes into an InMemoryCredentialStore of a Models
# collection holding githubCopilotProvider(); getAvailable applies the
# provider's filterModels.
def copilot_available(execute, credential):
    out = execute({'flow': 'copilot', 'action': 'available', 'credential': credential})
    expect(out['error'] is None, out)
    return out['available']


@test(f'{G} > filters models to the authenticated account picker catalog')
def copilot_picker(execute, server):
    ids = [copilot_model_id(i) for i in range(3)]
    out = copilot_refresh(execute, server, [entry(ids[0], True), entry(ids[1], True, 'disabled'), entry(ids[2], False, 'enabled')])
    expect(out['credential'] and out['credential'].get('availableModelIds') == [ids[0]], out)
    available = copilot_available(execute, out['credential'])
    expect(available == [ids[0]], available)
    return dict(out, available=available)


@test(f'{G} > falls back to explicitly enabled policy models when the picker catalog is empty')
def copilot_fallback(execute, server):
    enabled = copilot_model_id(0)
    out = copilot_refresh(execute, server, [entry(enabled, False, 'enabled'), entry('policy-disabled-model', False, 'disabled'), entry('unconfigured-model', False), entry('tool-incapable-model', False, 'enabled', False)])
    expect(out['credential'] and out['credential'].get('availableModelIds') == [enabled], out)
    available = copilot_available(execute, out['credential'])
    expect(available == [enabled], available)
    return dict(out, available=available)


@test(f'{G} > does not fall back to policy models for non-Individual accounts')
def copilot_business(execute, server):
    out = copilot_refresh(execute, server, [entry('gpt-4.1', False, 'enabled')], 'proxy.business.githubcopilot.com')
    expect(out['credential'] and out['credential'].get('availableModelIds') == [], out)
    return out


@test(f'{G} > does not retry model catalog throttling during credential refresh')
def copilot_no_retry(execute, server):
    count = []

    def route(request):
        if '/copilot_internal/v2/token' in request['url']:
            return 200, {'token': COPILOT_TOKEN, 'expires_at': 9999999999}, None
        count.append(1)
        return 429, {'error': 'too many requests'}, {'Retry-After': '0'}
    server.routes = {'*': route}
    out = execute({'flow': 'copilot', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old-access-token', 'refresh': 'ghu_refresh_token', 'expires': 0}})
    expect(out['error'] and '429' in out['error'] and len(count) == 1, (out, len(count)))
    return out


@test(f'{G} > reports device-code details through onDeviceCode')
def copilot_device(execute, server):
    server.routes = login_routes(lambda r: (200, {'data': []}, None), lambda id: (200, b'', None))
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect({'type': 'device_code', 'userCode': 'ABCD-EFGH', 'verificationUri': 'https://github.com/login/device', 'intervalSeconds': 1, 'expiresInSeconds': 900} in out['events'] and out['credential'], out)
    return out


@test(f'{G} > updates only known, tool-capable, unconfigured account model policies')
def copilot_policies(execute, server):
    ids = [copilot_model_id(i) for i in range(3)]
    catalog_requests, policies = [], []

    def models(request):
        catalog_requests.append(1)
        return 200, {'data': [entry(ids[0], True, 'enabled'), entry(ids[1], True, 'unconfigured'), entry('remote-only-model', True, 'unconfigured'), entry(ids[2], True, 'unconfigured', False)]}, None

    def policy(id):
        policies.append(id)
        return 200, b'', None
    server.routes = login_routes(models, policy)
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect(out['credential'] and len(catalog_requests) == 1 and policies == [ids[1]], (out, catalog_requests, policies))
    return out


@test(f'{G} > retries a throttled policy update after Retry-After')
def copilot_policy_retry(execute, server):
    id = copilot_model_id(0)
    attempts = []

    def policy(model):
        attempts.append(time.time())
        return (429, {'error': 'too many requests'}, {'Retry-After': '1'}) if len(attempts) == 1 else (200, b'', None)
    server.routes = login_routes(lambda r: (200, {'data': [{'id': id, 'model_picker_enabled': True, 'policy': {'state': 'unconfigured'}}]}, None), policy)
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect(out['credential'] and len(attempts) == 2 and 0.999 <= attempts[1] - attempts[0] < 1.9, (out, [a - attempts[0] for a in attempts]))
    return out


@test(f'{G} > continues policy updates after a transport failure')
def copilot_transport(execute, server):
    ids = [copilot_model_id(0), copilot_model_id(1)]
    seen = []

    def policy(model):
        seen.append(model)
        if len(seen) == 1:
            return None, None, None
        return 200, b'', None
    server.routes = login_routes(lambda r: (200, {'data': [{'id': i, 'model_picker_enabled': True, 'policy': {'state': 'unconfigured'}} for i in ids]}, None), policy)
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect(out['credential'] and seen == ids, (out, seen))
    return out


# Upstream logs in through Models.login over an InMemoryCredentialStore and
# reads the store afterwards.
@test(f'{G} > stops policy updates and persists authentication when the retry delay exceeds the login budget')
def copilot_budget(execute, server):
    ids = [copilot_model_id(0), copilot_model_id(1)]
    seen = []

    def policy(model):
        seen.append(model)
        return 429, {'error': 'too many requests'}, {'Retry-After': '5'}
    server.routes = login_routes(lambda r: (200, {'data': [{'id': i, 'model_picker_enabled': True, 'policy': {'state': 'unconfigured'}} for i in ids]}, None), policy)
    out = execute({'flow': 'copilot', 'action': 'modelsLogin', 'prompts': ['']})
    expect(out['credential'] and out['credential']['type'] == 'oauth' and out['credential']['access'] == COPILOT_TOKEN and seen == [ids[0]], (out, seen))
    expect(out['stored'] == out['credential'], (out['stored'], out['credential']))
    return out


@test(f'{G} > rejects a non-http(s) verification_uri before it reaches onDeviceCode')
def copilot_untrusted(execute, server):
    server.routes = {'*': reply({'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': '$(id>/tmp/pwned)', 'interval': 1, 'expires_in': 900})}
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect(out['error'] and 'Untrusted verification_uri' in out['error'] and not out['events'], out)
    return out


@test(f'{G} > normalizes verification_uri before it reaches onDeviceCode')
def copilot_normalized(execute, server):
    raw = 'https://github.com/login/\x1b]8;;evil'
    normalized_uri = subprocess.run(['bun', '-e', f'console.log(new URL({json.dumps(raw)}).href)'], capture_output=True, text=True, check=True).stdout.strip()
    routes = login_routes(lambda r: (200, {'data': []}, None), lambda id: (200, b'', None))['*']

    def route(request):
        if request['url'].endswith('/login/device/code'):
            return 200, {'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': raw, 'interval': 1, 'expires_in': 900}, None
        return routes(request)
    server.routes = {'*': route}
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect(normalized_uri != raw and out['events'] and out['events'][0].get('verificationUri') == normalized_uri, (normalized_uri, out))
    return out


@test(f'{G} > waits before polling and increases the interval after slow_down')
def copilot_slow_down(execute, server):
    replies = [{'error': 'authorization_pending', 'error_description': 'pending'}, {'error': 'slow_down', 'error_description': 'slow down', 'interval': 7}, {'access_token': 'ghu_refresh_token'}]
    polls = []
    routes = login_routes(lambda r: (200, {'data': []}, None), lambda id: (200, b'', None))['*']

    def route(request):
        url = request['url']
        if url.endswith('/login/device/code'):
            expect(request['method'] == 'POST' and request['headers'].get('accept') == 'application/json' and request['headers'].get('content-type', '').startswith('application/x-www-form-urlencoded') and 'client_id=' in request['body'] and 'scope=read%3Auser' in request['body'], request)
            return 200, {'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': 'https://github.com/login/device', 'interval': 5, 'expires_in': 900}, None
        if url.endswith('/login/oauth/access_token'):
            polls.append(request['at'])
            expect('client_id=' in request['body'] and 'device_code=device-code' in request['body'] and 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code' in request['body'], request['body'])
            return 200, replies.pop(0), None
        return routes(request)
    server.routes = {'*': route}
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect(out['credential'] and len(polls) == 3 and near(polls[0], 5, out['start']) and near(polls[1], 10, out['start']) and near(polls[2], 17, out['start']), ([p - out['start'] for p in polls], out['error']))
    return out


@test(f'{G} > times out after repeated slow_down responses')
def copilot_timeout(execute, server):
    replies = [{'error': 'slow_down', 'error_description': 'slow down'}, {'error': 'slow_down', 'error_description': 'still too fast'}, {'error': 'authorization_pending', 'error_description': 'pending'}]
    polls = []

    def route(request):
        if request['url'].endswith('/login/device/code'):
            return 200, {'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': 'https://github.com/login/device', 'interval': 5, 'expires_in': 25}, None
        polls.append(request['at'])
        return 200, replies.pop(0), None
    server.routes = {'*': route}
    out = execute({'flow': 'copilot', 'action': 'login', 'prompts': ['']})
    expect(out['error'] and re.search('Device flow timed out after one or more slow_down responses', out['error']) and len(polls) == 2 and near(polls[0], 5, out['start']) and near(polls[1], 15, out['start']), (out, [p - out['start'] for p in polls]))
    return out


# openrouter-oauth.test.ts
# ------------------------
# The browser is the driver's: on the auth_url event it GETs the loopback
# callback with the test's code. Upstream's never-settling prompt is
# `pendingPrompt`; its "allows only one token exchange" holds the exchange
# open in the stub, here the server holds it for 1.5 s and the second
# callback arrives after 0.5 s.
OR_TOKEN = 'https://openrouter.ai/api/v1/auth/keys'
O = 'openrouter-oauth.test.ts > OpenRouter OAuth'


def openrouter_key(key, captured=None, delay=0):
    def route(request):
        if captured is not None:
            captured.append(json.loads(request['body']))
        time.sleep(delay)
        return 200, {'key': key}, None
    return route


def token_requests(server):
    return [r for r in server.requests if r['key'] == OR_TOKEN]


def b64url(data):
    import base64
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


@test(f'{O} > runs PKCE on a one-shot loopback callback and exchanges the code for a permanent API key')
def openrouter_pkce(execute, server):
    import hashlib
    bodies = []
    server.routes = {OR_TOKEN: openrouter_key('sk-or-test', bodies)}
    out = execute({'flow': 'openrouter', 'callbackCode': 'authorization-code', 'pendingPrompt': True})
    expect(out['credential'] == {'type': 'oauth', 'access': 'sk-or-test', 'refresh': '', 'expires': 9007199254740991}, out)
    expect(out['browser'].get('B') == '200' and out['browser'].get('M') == 'true', out['browser'])
    urls = [e['url'] for e in out['events'] if e['type'] == 'auth_url']
    expect(len(urls) == 1, out['events'])
    authorize = urlsplit(urls[0])
    query = {k: v[0] for k, v in parse_qs(authorize.query).items()}
    expect(f'{authorize.scheme}://{authorize.netloc}' == 'https://openrouter.ai' and authorize.path == '/auth' and query.get('code_challenge_method') == 'S256', urls[0])
    callback = urlsplit(query.get('callback_url', ''))
    expect(callback.hostname == '127.0.0.1' and re.fullmatch(r'/oauth/callback/[0-9a-f-]+', callback.path), query)
    expect(len(bodies) == 1 and bodies[0].get('code') == 'authorization-code' and bodies[0].get('code_challenge_method') == 'S256', bodies)
    verifier = bodies[0].get('code_verifier')
    expect(isinstance(verifier, str) and query.get('code_challenge') == b64url(hashlib.sha256(verifier.encode()).digest()), (verifier, query))
    expect(len(token_requests(server)) == 1, server.requests)
    return out


@test(f'{O} > reports token exchange failures through both the callback page and login')
def openrouter_exchange_failure(execute, server):
    server.routes = {OR_TOKEN: reply({'error': {'message': 'invalid code'}}, 403)}
    out = execute({'flow': 'openrouter', 'callbackCode': 'bad-code', 'pendingPrompt': True})
    expect('OpenRouter OAuth key exchange failed (HTTP 403): invalid code' in (out['error'] or ''), out)
    expect(out['browser'].get('B') == '502', out['browser'])
    return out


@test(f'{O} > allows only one token exchange for a callback')
def openrouter_one_exchange(execute, server):
    server.routes = {OR_TOKEN: openrouter_key('sk-or-test', delay=1.5)}
    out = execute({'flow': 'openrouter', 'callbackCode': 'authorization-code', 'pendingPrompt': True, 'secondCallbackMs': 500})
    expect(out['browser'].get('B2') == '409' and out['browser'].get('B') == '200', out['browser'])
    expect(len(token_requests(server)) == 1, server.requests)
    expect((out['credential'] or {}).get('access') == 'sk-or-test', out)
    return out


@test(f'{O} > rejects a successful response that does not contain a key')
def openrouter_no_key(execute, server):
    server.routes = {OR_TOKEN: reply({'user_id': 'user-1'})}
    out = execute({'flow': 'openrouter', 'callbackCode': 'code-without-key', 'pendingPrompt': True})
    expect('OpenRouter OAuth response carries no "key"' in (out['error'] or ''), out)
    expect(out['browser'].get('B') == '502', out['browser'])
    return out


@test(f'{O} > mints a key from a pasted redirect URL when the loopback callback never arrives')
def openrouter_pasted(execute, server):
    bodies = []
    server.routes = {OR_TOKEN: openrouter_key('sk-or-manual', bodies)}
    out = execute({'flow': 'openrouter', 'prompts': ['{callback}?code=manual-code']})
    expect(out['credential'] == {'type': 'oauth', 'access': 'sk-or-manual', 'refresh': '', 'expires': 9007199254740991}, out)
    expect(len(bodies) == 1 and bodies[0].get('code') == 'manual-code' and bodies[0].get('code_challenge_method') == 'S256', bodies)
    expect(len(token_requests(server)) == 1, server.requests)
    return out


@test(f'{O} > accepts a bare authorization code from the manual prompt')
def openrouter_bare(execute, server):
    bodies = []
    server.routes = {OR_TOKEN: openrouter_key('sk-or-manual', bodies)}
    out = execute({'flow': 'openrouter', 'prompts': ['  manual-code  ']})
    expect((out['credential'] or {}).get('access') == 'sk-or-manual' and len(bodies) == 1 and bodies[0].get('code') == 'manual-code', (out, bodies))
    return out


@test(f'{O} > fails login when the manual prompt is cancelled')
def openrouter_prompt_cancelled(execute, server):
    server.routes = {OR_TOKEN: reply({'key': 'sk-or-unexpected'})}
    out = execute({'flow': 'openrouter', 'promptError': 'Login cancelled'})
    expect('Login cancelled' in (out['error'] or ''), out)
    expect(not token_requests(server), server.requests)
    return out


@test(f'{O} > rejects empty manual input without exchanging a code')
def openrouter_empty_input(execute, server):
    server.routes = {OR_TOKEN: reply({'key': 'sk-or-unexpected'})}
    out = execute({'flow': 'openrouter', 'prompts': ['   ']})
    expect('Missing authorization code' in (out['error'] or ''), out)
    expect(not token_requests(server), server.requests)
    return out


@test(f'{O} > closes the pending callback when login is cancelled')
def openrouter_cancelled(execute, server):
    out = execute({'flow': 'openrouter', 'abortOnAuthUrl': True, 'pendingPrompt': True})
    expect('Login cancelled' in (out['error'] or ''), out)
    expect(any(e['type'] == 'auth_url' for e in out['events']) and out['browser'].get('R') == 'refused', out)
    return out


@test(f'{O} > rejects before opening a callback server when login is already cancelled')
def openrouter_pre_cancelled(execute, server):
    out = execute({'flow': 'openrouter', 'preAborted': True, 'prompts': ['']})
    expect('Login cancelled' in (out['error'] or '') and out['events'] == [], out)
    return out


@test(f'{O} > uses the configured OAuth callback host')
def openrouter_callback_host(execute, server):
    out = execute({'flow': 'openrouter', 'abortOnAuthUrl': True, 'pendingPrompt': True, 'env': {'PI_OAUTH_CALLBACK_HOST': 'localhost'}})
    expect('Login cancelled' in (out['error'] or ''), out)
    urls = [e['url'] for e in out['events'] if e['type'] == 'auth_url']
    callback = urlsplit(parse_qs(urlsplit(urls[0]).query).get('callback_url', [''])[0]) if urls else None
    expect(callback is not None and callback.hostname == 'localhost', out['events'])
    return out


# anthropic-oauth.test.ts
# -----------------------
ANTHROPIC_TOKEN = 'https://platform.claude.com/v1/oauth/token'
A = 'anthropic-oauth.test.ts > Anthropic OAuth'


@test(f'{A} > keeps the localhost redirect_uri for manual callback login')
def anthropic_manual_redirect(execute, server):
    def token(request):
        body = json.loads(request['body'])
        expect(request['method'] == 'POST' and body.get('grant_type') == 'authorization_code' and body.get('code') == 'manual-code' and body.get('redirect_uri') == 'http://localhost:53692/callback', body)
        return 200, {'access_token': 'access-token', 'refresh_token': 'refresh-token', 'expires_in': 3600}, None
    server.routes = {ANTHROPIC_TOKEN: token}
    out = execute({'flow': 'anthropic', 'prompts': ['{redirect_uri}?code=manual-code&state={state}']})
    credential = out['credential'] or {}
    expect(credential.get('access') == 'access-token' and credential.get('refresh') == 'refresh-token', out)
    expect(len(server.requests) == 1, server.requests)
    return out


@test(f'{A} > omits scope from refresh token requests')
def anthropic_refresh_scope(execute, server):
    def token(request):
        body = json.loads(request['body'])
        expect(request['method'] == 'POST' and body.get('grant_type') == 'refresh_token' and body.get('client_id') and body.get('refresh_token') == 'refresh-token' and 'scope' not in body, body)
        return 200, {'access_token': 'new-access-token', 'refresh_token': 'new-refresh-token', 'expires_in': 3600}, None
    server.routes = {ANTHROPIC_TOKEN: token}
    out = execute({'flow': 'anthropic', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old-access-token', 'refresh': 'refresh-token', 'expires': 0}})
    credential = out['credential'] or {}
    expect(credential.get('access') == 'new-access-token' and credential.get('refresh') == 'new-refresh-token', out)
    expect(len(server.requests) == 1, server.requests)
    return out


@test(f'{A} > anthropicOAuth.login resolves through the manual_code prompt and aborts it after settling')
def anthropic_manual_prompt(execute, server):
    server.routes = {ANTHROPIC_TOKEN: reply({'access_token': 'access', 'refresh_token': 'refresh', 'expires_in': 3600})}
    out = execute({'flow': 'anthropic', 'prompts': ['the-code'], 'watchPromptSignal': True})
    credential = out['credential'] or {}
    expect(credential.get('type') == 'oauth' and credential.get('access') == 'access', out)
    expect(any(e['type'] == 'auth_url' for e in out['events']) and any(p['type'] == 'manual_code' for p in out['prompts']), out)
    expect(out['browser'].get('M') == 'true', out['browser'])
    return out


# oauth-auth.test.ts
# ------------------
# "keeps the extension OAuth barrel free of built-in flow implementations"
# checks src/oauth.ts, a type-only entry point for JavaScript extensions,
# which the native port does not have (docs/scope-decisions.md). The
# "Models.getAuth" half runs in packages/ai/test/oauth-auth.bend.
OA = 'oauth-auth.test.ts > OAuthAuth adapters'


def combined(outs):
    return dict(events=[], prompts=[], credential=None, auth=None, error=None, start=None, browser={}, facts=[(o['facts'], o['auth'], o['credential'], o['error']) for o in outs])


@test(f'{OA} > identifies only subscription-backed OAuth flows as subscriptions')
def oauth_subscriptions(execute, server):
    outs = [execute({'flow': flow, 'action': 'describe'}) for flow in ('anthropic', 'codex', 'copilot', 'kimi', 'xai', 'openrouter')]
    flags = [o['facts']['isSubscription'] for o in outs]
    expect(flags[:5] == [True] * 5 and flags[5] is not True, flags)
    return combined(outs)


def to_auth(execute, flow, credential):
    return execute({'flow': flow, 'action': 'toAuth', 'credential': credential})


@test(f'{OA} > anthropic toAuth derives the api key from the access token')
def oauth_anthropic_to_auth(execute, server):
    out = to_auth(execute, 'anthropic', {'type': 'oauth', 'access': 'token', 'refresh': 'r', 'expires': 0})
    expect(out['auth'] == {'apiKey': 'token'}, out)
    return out


@test(f'{OA} > openai-codex toAuth derives the api key from the access token')
def oauth_codex_to_auth(execute, server):
    out = to_auth(execute, 'codex', {'type': 'oauth', 'access': 'token', 'refresh': 'r', 'expires': 0})
    expect(out['auth'] == {'apiKey': 'token'}, out)
    return out


@test(f'{OA} > openrouter derives the api key and keeps the permanent credential on refresh')
def oauth_openrouter_permanent(execute, server):
    credential = {'type': 'oauth', 'access': 'token', 'refresh': '', 'expires': 9007199254740991}
    auth = to_auth(execute, 'openrouter', credential)
    refreshed = execute({'flow': 'openrouter', 'action': 'refresh', 'credential': credential})
    expect(auth['auth'] == {'apiKey': 'token'} and refreshed['credential'] == credential, (auth, refreshed))
    expect(not server.requests, server.requests)
    return combined([auth, refreshed])


@test(f'{OA} > xAI toAuth derives the api key from the access token')
def oauth_xai_to_auth(execute, server):
    out = to_auth(execute, 'xai', {'type': 'oauth', 'access': 'token', 'refresh': 'r', 'expires': 0})
    expect(out['auth'] == {'apiKey': 'token'}, out)
    return out


@test(f'{OA} > github-copilot toAuth derives baseUrl from the token proxy endpoint')
def oauth_copilot_proxy(execute, server):
    access = 'tid=abc;exp=123;proxy-ep=proxy.enterprise.example;rest'
    out = to_auth(execute, 'copilot', {'type': 'oauth', 'access': access, 'refresh': 'r', 'expires': 0})
    expect(out['auth'] == {'apiKey': access, 'baseUrl': 'https://api.enterprise.example'}, out)
    return out


@test(f'{OA} > github-copilot toAuth falls back to the enterprise domain, then the individual endpoint')
def oauth_copilot_fallbacks(execute, server):
    enterprise = to_auth(execute, 'copilot', {'type': 'oauth', 'access': 'no-proxy-ep', 'refresh': 'r', 'expires': 0, 'enterpriseUrl': 'https://company.ghe.com'})
    individual = to_auth(execute, 'copilot', {'type': 'oauth', 'access': 'no-proxy-ep', 'refresh': 'r', 'expires': 0})
    expect((enterprise['auth'] or {}).get('baseUrl') == 'https://copilot-api.company.ghe.com', enterprise)
    expect((individual['auth'] or {}).get('baseUrl') == 'https://api.individual.githubcopilot.com', individual)
    return combined([enterprise, individual])


@test(f'{OA} > anthropic refresh exchanges the refresh token and returns a typed credential')
def oauth_anthropic_refresh(execute, server):
    server.routes = {'*': reply({'access_token': 'new-access', 'refresh_token': 'new-refresh', 'expires_in': 3600})}
    out = execute({'flow': 'anthropic', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old', 'refresh': 'old-r', 'expires': 0}})
    credential = out['credential'] or {}
    expect(credential.get('type') == 'oauth' and credential.get('access') == 'new-access' and credential.get('refresh') == 'new-refresh' and credential.get('expires', 0) > out['start'] * 1000, out)
    return out


@test(f'{OA} > github-copilot refresh preserves the enterprise domain')
def oauth_copilot_enterprise_refresh(execute, server):
    def route(request):
        if urlsplit(request['url']).path.endswith('/models'):
            return 200, {'data': []}, None
        return 200, {'token': 'new-token', 'expires_at': 9999999999}, None
    server.routes = {'*': route}
    out = execute({'flow': 'copilot', 'action': 'refresh', 'credential': {'type': 'oauth', 'access': 'old', 'refresh': 'gh-token', 'expires': 0, 'enterpriseUrl': 'company.ghe.com'}})
    credential = out['credential'] or {}
    expect(credential.get('access') == 'new-token' and credential.get('enterpriseUrl') == 'company.ghe.com', out)
    expect(server.requests and 'api.company.ghe.com' in server.requests[0]['url'], [r['url'] for r in server.requests])
    return out


if __name__ == '__main__':
    main()

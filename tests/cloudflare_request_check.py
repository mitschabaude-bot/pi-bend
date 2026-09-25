"""Cloudflare requests versus upstream ModelRuntime streaming, no network.

The reference runs the pinned upstream ModelRuntime (in-memory credentials,
no models.json) with the real SDKs and a capturing fetch; the Bend side,
tests/cloudflare-request.bend, resolves the model's auth through the Bend
model runtime, materializes the endpoint through the provider's streams and
streams through the api's provider with a capturing fetch. Each case runs in
its own process on both sides with the same environment, so ambient
CLOUDFLARE_* values reach both auth contexts. Compared: the request URL, the
auth, session and protocol headers (SDK platform headers and the User-Agent
are the SDKs' own and are covered by the per-API differentials) and the JSON
body; a case without a request compares only that both failed.
Runs the JavaScript lane; pass --native with a native build of the fixture.
"""
import argparse, json, os, subprocess
from pathlib import Path
from upstream_pin import PIN
from bend_toolchain import BEND

ROOT = Path(__file__).resolve().parents[1]
PI_MONO = Path(os.environ.get('PI_MONO', ROOT.parent / 'pi-mono'))
ENTRY = 'tests/cloudflare-request.bend'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/cloudflare-request')
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--native', action='store_true')
arguments = parser.parse_args()
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=PI_MONO, text=True).strip() == PIN

GATEWAY, WORKERS = 'cloudflare-ai-gateway', 'cloudflare-workers-ai'
KIMI = '@cf/moonshotai/kimi-k2.6'
FULL = dict(type='api_key', key='test-token', env=dict(CLOUDFLARE_ACCOUNT_ID='test-account', CLOUDFLARE_GATEWAY_ID='test-gateway'))
KEY = dict(type='api_key', key='test-token')
AMBIENT = dict(CLOUDFLARE_API_KEY='ambient-token', CLOUDFLARE_ACCOUNT_ID='ambient-account', CLOUDFLARE_GATEWAY_ID='ambient-gateway')
cases = [
    # The three gateway APIs and Workers AI with a stored credential.
    (GATEWAY, 'workers-ai/' + KIMI, 'full', {}),
    (GATEWAY, 'claude-haiku-4.5', 'full', {}),
    (GATEWAY, 'gpt-4.1', 'full', {}),
    (WORKERS, KIMI, 'full', {}),
    # A stored key with ambient account and gateway ids.
    (GATEWAY, 'workers-ai/' + KIMI, 'key', AMBIENT),
    (GATEWAY, 'claude-haiku-4.5', 'key', AMBIENT),
    (WORKERS, KIMI, 'key', AMBIENT),
    # Stored credential values win over ambient ones.
    (GATEWAY, 'gpt-4.1', 'full', AMBIENT),
    # Ambient auth only (source CLOUDFLARE_API_KEY).
    (GATEWAY, 'gpt-4.1', 'none', AMBIENT),
    (WORKERS, KIMI, 'none', AMBIENT),
    # A gateway without a gateway id is not configured.
    (GATEWAY, 'workers-ai/' + KIMI, 'key', dict(CLOUDFLARE_ACCOUNT_ID='ambient-account')),
    (GATEWAY, 'gpt-4.1', 'none', {}),
]
COMPARED = ['authorization', 'x-api-key', 'cf-aig-authorization', 'session_id', 'x-client-request-id', 'x-session-affinity', 'x-session-id', 'anthropic-version', 'anthropic-beta', 'anthropic-dangerous-direct-browser-access', 'content-type', 'accept']
CREDENTIALS = dict(full=FULL, key=KEY, none=None)
clean = {k: v for k, v in os.environ.items() if not (k.startswith('CLOUDFLARE_') or k.endswith('_API_KEY'))}

def summary(captured):
    if 'url' not in captured:
        return 'no request'
    headers = captured['headers']
    return dict(url=captured['url'], headers={name: headers.get(name) for name in COMPARED}, body=json.loads(captured['body']))

def bend_summary(output):
    lines = output.splitlines()
    if not lines or not lines[0].startswith('url '):
        return 'no request'
    headers = {}
    body = None
    for line in lines[1:]:
        if line.startswith('header '):
            name, value = line[len('header '):].split(': ', 1)
            headers[name] = value
        elif line.startswith('body '):
            body = json.loads(line[len('body '):])
    return dict(url=lines[0][len('url '):], headers={name: headers.get(name) for name in COMPARED}, body=body)

if not arguments.no_build:
    subprocess.run([BEND, ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
commands = [('bun', ['bun', arguments.prefix + '.js'])]
if arguments.native:
    commands += [('native-1', [arguments.prefix, '--threads', '1']), ('native-4', [arguments.prefix, '--threads', '4'])]
references = []
for provider, model, credential, ambient in cases:
    case = dict(provider=provider, modelId=model, credential=CREDENTIALS[credential])
    output = subprocess.check_output(['bun', 'tests/cloudflare_request_reference.ts', str(PI_MONO)], input=json.dumps([case]), text=True, cwd=ROOT, env=dict(clean, **ambient))
    references.append(summary(json.loads(output)[0]))
for label, command in commands:
    failures = []
    for (provider, model, credential, ambient), expected in zip(cases, references):
        run = subprocess.run(command + [provider, model, credential], cwd=ROOT, capture_output=True, text=True, timeout=300, env=dict(clean, **ambient))
        assert run.returncode == 0, (label, provider, model, run.stdout, run.stderr)
        actual = bend_summary(run.stdout)
        if actual != expected:
            failures.append((provider, model, credential, ambient, actual, expected))
    for provider, model, credential, ambient, actual, expected in failures:
        print(f'FAIL {label} {provider}/{model} credential={credential} ambient={sorted(ambient)}')
        print('  bend:    ', json.dumps(actual, sort_keys=True))
        print('  upstream:', json.dumps(expected, sort_keys=True))
    assert not failures, f'{len(failures)} of {len(cases)} cases differ'
    requests = sum(value != 'no request' for value in references)
    print(f'{label}: {len(cases)} Cloudflare request comparisons PASS ({requests} requests, {len(cases) - requests} unconfigured)', flush=True)

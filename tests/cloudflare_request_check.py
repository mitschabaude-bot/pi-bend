"""Compare ModelRuntime completion and extension-style resolved-auth requests
with pinned upstream, using capturing fetches and no network. Build the Bend
fixture once and reuse it for every case on native one/four threads.
"""
import argparse, json, os, subprocess
from pathlib import Path
from upstream_pin import PIN, UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
PI_MONO = UPSTREAM
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runner', type=Path, default=ROOT / 'build/cloudflare-request')
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
    url = next((line[4:] for line in lines if line.startswith('url ')), None)
    if url is None:
        return 'no request'
    headers = {}
    body = None
    for line in lines:
        if line.startswith('header '):
            name, value = line[len('header '):].split(': ', 1)
            headers[name] = value
        elif line.startswith('body '):
            body = json.loads(line[len('body '):])
    return dict(url=url, headers={name: headers.get(name) for name in COMPARED}, body=body)

references = []
for kind in ('runtime', 'resolved'):
    for provider, model, credential, ambient in cases:
        case = dict(provider=provider, modelId=model, credential=CREDENTIALS[credential], kind=kind)
        output = subprocess.check_output(['bun', 'tests/cloudflare_request_reference.ts', str(PI_MONO)], input=json.dumps([case]), text=True, cwd=ROOT, env=dict(clean, **ambient))
        data = json.loads(output)[0]
        references.append((kind, provider, model, credential, ambient, summary(data), data.get('resolvedAuth')))
for threads in (1, 4):
    failures = []
    for kind, provider, model, credential, ambient, expected, auth in references:
        run = subprocess.run([str(arguments.runner.resolve()), provider, model, credential, kind], cwd=ROOT, capture_output=True, text=True, timeout=300, env=dict(clean, **ambient, BEND_THREADS=str(threads)))
        assert run.returncode == 0, (threads, provider, model, run.stdout, run.stderr)
        actual = bend_summary(run.stdout)
        if actual != expected:
            failures.append((kind, provider, model, credential, ambient, actual, expected))
        if kind == 'resolved' and expected != 'no request':
            headers = {}
            for line in run.stdout.splitlines():
                if line.startswith('authheader '):
                    name, value = line[len('authheader '):].split(': ', 1)
                    headers[name] = None if value == 'null' else value
            expected_headers = {name.lower(): value for name, value in (auth.get('headers') or {}).items()}
            assert auth['ok'] and headers == expected_headers, (threads, provider, headers, expected_headers)
    for kind, provider, model, credential, ambient, actual, expected in failures:
        print(f'FAIL native{threads} {kind} {provider}/{model} credential={credential} ambient={sorted(ambient)}')
        print('  bend:    ', json.dumps(actual, sort_keys=True))
        print('  upstream:', json.dumps(expected, sort_keys=True))
    assert not failures, f'{len(failures)} of {len(references)} cases differ'
    requests = sum(row[5] != 'no request' for row in references)
    print(f'native{threads}: {len(references)} Cloudflare request comparisons PASS ({requests} requests, {len(references) - requests} unconfigured)', flush=True)

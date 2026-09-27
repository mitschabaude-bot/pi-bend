#!/usr/bin/env python3
"""pi-mono packages/ai/test/node-http-proxy.test.ts over the native
resolveHttpProxyUrlForTarget (packages/ai/src/utils/node-http-proxy.bend).

Upstream sets process.env per test; here each resolution runs
packages/ai/test/node-http-proxy.bend in a process whose environment carries
exactly the test's proxy variables. Every resolution must give the upstream
expectation and match pinned pi-mono's function under the same environment
(tests/node_http_proxy_reference.ts). Further differential rows cover the
parsing edges of NO_PROXY entries, ALL_PROXY, scheme-less proxies and invalid
proxy URLs.
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from upstream_pin import UPSTREAM  # noqa: F401  (exports PI_MONO)

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/ai/test/node-http-proxy.bend'
PROXY_KEYS = ['HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'no_proxy', 'all_proxy',
              'npm_config_http_proxy', 'npm_config_https_proxy', 'npm_config_proxy', 'npm_config_no_proxy']
UNSUPPORTED = 'Unsupported proxy protocol. SOCKS and PAC proxy URLs are not supported; use an HTTP or HTTPS proxy URL.'
BEDROCK = 'https://bedrock-runtime.us-east-1.amazonaws.com'
PROXY = 'url http://proxy.example:8080/'

T = 'node-http-proxy.test.ts > node HTTP proxy resolution'
# (test name, process env, [(target, scoped env or None, expectation)]); an
# expectation None is compared with upstream only, a string starting with
# "error-prefix " must prefix the error.
TESTS = [
    (f'{T} > respects NO_PROXY exclusions', {'HTTPS_PROXY': 'http://proxy.example:8080', 'NO_PROXY': 'bedrock-runtime.us-east-1.amazonaws.com'},
     [(BEDROCK, None, 'none')]),
    (f'{T} > resolves HTTP and HTTPS proxy URLs', {'HTTPS_PROXY': 'http://proxy.example:8080'},
     [(BEDROCK, None, PROXY)]),
    (f'{T} > prefers scoped proxy env aliases before process env aliases', {'https_proxy': 'http://process-proxy.example:8080'},
     [(BEDROCK, {'HTTPS_PROXY': 'http://scoped-proxy.example:8080'}, 'url http://scoped-proxy.example:8080/')]),
    (f'{T} > rejects SOCKS and PAC proxy URLs explicitly', {'HTTPS_PROXY': 'socks5://proxy.example:1080'},
     [(BEDROCK, None, 'error-prefix error ' + UNSUPPORTED)]),
    (f'{T} > handles subdomain wildcards, IPv6, and ports in NO_PROXY',
     {'HTTPS_PROXY': 'http://proxy.example:8080', 'NO_PROXY': 'example.com, .wildcard.org, *.star.net, ::1, [2001:db8::1], 127.0.0.1:8080'},
     [('https://example.com', None, 'none'), ('https://api.example.com', None, 'none'), ('https://wildcard.org', None, 'none'),
      ('https://api.wildcard.org', None, 'none'), ('https://star.net', None, 'none'), ('https://api.star.net', None, 'none'),
      ('https://notexample.com', None, PROXY), ('https://[::1]:80', None, 'none'), ('https://[2001:db8::1]', None, 'none'),
      ('https://127.0.0.1:8080', None, 'none'), ('https://127.0.0.1:3000', None, PROXY)]),
    # Differential rows beyond the upstream suite.
    ('differential > ALL_PROXY, scheme-less values and http targets', {'ALL_PROXY': 'proxy.example:3128', 'http_proxy': 'http://lower.example:1'},
     [('https://api.example.com', None, None), ('http://api.example.com', None, None), ('ws://api.example.com', None, None),
      ('https://api.example.com', {'all_proxy': 'https://scoped.example'}, None), ('not a url', None, None)]),
    ('differential > NO_PROXY entry parsing edges', {'HTTPS_PROXY': 'http://proxy.example:8080', 'HTTP_PROXY': 'http://proxy.example:8080',
                                                     'NO_PROXY': ' [::2]:443 ,host.example:0,port.example:+8443,neg.example:-1, *, bad:port, a:b:c , .'},
     [('https://[::2]', None, None), ('https://[::2]:444', None, None), ('https://host.example:9', None, None), ('https://port.example:8443', None, None),
      ('https://port.example', None, None), ('https://neg.example', None, None), ('https://bad', None, None), ('https://a:b:c', None, None),
      ('http://other.example', None, None), ('https://EXAMPLE.org', {'no_proxy': 'Example.ORG'}, None)]),
    ('differential > NO_PROXY star and invalid proxy URLs', {'HTTPS_PROXY': 'http://[bad', 'NO_PROXY': ''},
     [('https://api.example.com', None, None), ('https://api.example.com', {'NO_PROXY': '*'}, None), ('https://api.example.com', {'https_proxy': 'ftp://proxy.example'}, None)]),
]


def run(command, target, scoped, env):
    arguments = [target] + ([json.dumps(scoped)] if scoped is not None else [])
    result = subprocess.run(command + arguments, cwd=ROOT, capture_output=True, text=True, timeout=120, env=env)
    if result.returncode != 0:
        return f'exit {result.returncode}: {result.stderr[-500:]}'
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--prefix', default='build/node-http-proxy')
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    parser.add_argument('--no-build', action='store_true')
    arguments = parser.parse_args()
    if not arguments.no_build:
        if 'bun' in arguments.backends:
            subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
        if any(b.startswith('native') for b in arguments.backends):
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)
    commands = {'bun': ['bun', arguments.prefix + '.js'], 'native-1': [arguments.prefix, '--threads', '1'], 'native-4': [arguments.prefix, '--threads', '4']}
    base = {k: v for k, v in os.environ.items() if k not in PROXY_KEYS}
    failures = 0
    for name, process_env, rows in TESTS:
        env = {**base, **process_env}
        problems = []
        for target, scoped, expected in rows:
            upstream = run(['bun', 'tests/node_http_proxy_reference.ts'], target, scoped, env)
            if expected is not None and not (upstream.startswith(expected[len('error-prefix '):]) if expected.startswith('error-prefix ') else upstream == expected):
                problems.append(f'upstream {target}: {upstream!r} is not {expected!r}')
            for backend in arguments.backends:
                port = run(commands[backend], target, scoped, env)
                if port != upstream:
                    problems.append(f'{backend} {target} {scoped}: {port!r} != upstream {upstream!r}')
        if problems:
            failures += 1
            print(f'FAIL {name}')
            for problem in problems:
                print(f'  {problem}')
        else:
            print(f'PASS {name}')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()

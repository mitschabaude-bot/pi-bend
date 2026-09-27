#!/usr/bin/env python3
"""Native fetch through HTTP proxies (packages/runtime/src/http-proxy.bend)
against pinned pi-mono's configureHttpDispatcher (undici EnvHttpProxyAgent with
proxyTunnel: true).

A loopback CONNECT proxy records each tunnel request and pipes it to loopback
origins (a keep-alive HTTP server and a TLS 1.3 server); every case runs
tests/http-proxy.bend (Bun, native one/four threads) and
tests/http_proxy_reference.mts (Node) with the same proxy variables. Results
and the CONNECT requests the proxy saw must agree; header order is compared
too. Node accepts the test certificate through NODE_TLS_REJECT_UNAUTHORIZED=0;
the native fetch pins it.
"""
import argparse
import os
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

from tls13_handshake_check import server_context, encode
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from upstream_pin import UPSTREAM  # noqa: F401  (exports PI_MONO)

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'tests/http-proxy.bend'
PROXY_KEYS = ['HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'no_proxy', 'all_proxy']


def read_head(stream):
    data = bytearray()
    while b'\r\n\r\n' not in data:
        part = stream.recv(4096)
        if not part:
            return None, bytes(data)
        data.extend(part)
    head, _, rest = bytes(data).partition(b'\r\n\r\n')
    return head.decode('latin-1'), rest


def pipe(source, target):
    try:
        while True:
            part = source.recv(65536)
            if not part:
                break
            target.sendall(part)
    except OSError:
        pass
    finally:
        try:
            target.shutdown(socket.SHUT_WR)
        except OSError:
            pass


class Server:
    def __init__(self, handler):
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(16)
        self.port = self.listener.getsockname()[1]
        self.handler = handler
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while True:
            try:
                peer, _ = self.listener.accept()
            except OSError:
                return
            threading.Thread(target=self.handler, args=(peer,), daemon=True).start()

    def close(self):
        self.listener.close()


class Origin:
    """Answers every request on a connection with `hello <path>` (keep-alive)."""

    def __init__(self, context=None):
        self.context = context
        self.requests = []
        self.server = Server(self.handle)

    def handle(self, peer):
        try:
            stream = self.context.wrap_socket(peer, server_side=True) if self.context else peer
        except (ssl.SSLError, OSError):
            peer.close()
            return
        with stream:
            while True:
                head, _ = read_head(stream)
                if head is None:
                    return
                line = head.split('\r\n')[0]
                self.requests.append(line)
                body = f'hello {line.split(" ")[1]}'.encode()
                stream.sendall(b'HTTP/1.1 200 OK\r\ncontent-length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)


class Proxy:
    def __init__(self, origins, refuse=False):
        self.origins = origins
        self.refuse = refuse
        self.connects = []
        self.server = Server(self.handle)

    def handle(self, peer):
        head, rest = read_head(peer)
        if head is None:
            peer.close()
            return
        lines = head.split('\r\n')
        headers = [tuple(part.strip() for part in line.split(':', 1)) for line in lines[1:]]
        self.connects.append((lines[0], [(name.lower(), value) for name, value in headers]))
        if self.refuse:
            peer.sendall(b'HTTP/1.1 407 Proxy Authentication Required\r\ncontent-length: 0\r\nconnection: close\r\n\r\n')
            peer.close()
            return
        method, target, _ = lines[0].split(' ')
        host, _, port = target.rpartition(':')
        upstream = socket.create_connection(('127.0.0.1', self.origins.get(host.strip('[]'), int(port))))
        peer.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
        if rest:
            upstream.sendall(rest)
        threading.Thread(target=pipe, args=(upstream, peer), daemon=True).start()
        pipe(peer, upstream)


def run_case(command, env):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240, env=env)
    if result.returncode != 0:
        return [f'exit {result.returncode}: {result.stderr[-800:]}']
    return result.stdout.strip().split('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--prefix', default='build/http-proxy')
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    parser.add_argument('--no-build', action='store_true')
    arguments = parser.parse_args()
    if not arguments.no_build:
        if 'bun' in arguments.backends:
            subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
        if any(b.startswith('native') for b in arguments.backends):
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)
    commands = {'bun': ['bun', arguments.prefix + '.js'], 'native-1': [arguments.prefix, '--threads', '1'], 'native-4': [arguments.prefix, '--threads', '4']}
    failures = 0
    with tempfile.TemporaryDirectory(prefix='pi-http-proxy-') as temporary:
        directory = Path(temporary)
        context, _ = server_context(directory, 'ecdsa')
        certificate = x509.load_pem_x509_certificate((directory / 'certificate.pem').read_bytes()).public_bytes(serialization.Encoding.DER)
        resolver, hosts = directory / 'resolv.conf', directory / 'hosts'
        resolver.write_text('nameserver 127.0.0.1\n')
        plain, secure = Origin(), Origin(context)
        # slow.test's first address has a full accept queue, so a connection
        # attempt to it hangs; its second address is the TLS origin.
        hosts.write_text('127.0.0.1 localhost\n127.0.0.1 fast.test\n127.0.0.2 slow.test\n127.0.0.1 slow.test\n')
        origins = {'plain.test': plain.server.port, 'secure.test': secure.server.port}
        base = {k: v for k, v in os.environ.items() if k not in PROXY_KEYS}
        P, S = plain.server.port, secure.server.port

        def case(name, variables, urls, refuse=False, expect=None, native_only=False, compare_count=True, setting=None):
            nonlocal failures
            proxy = Proxy(origins, refuse)
            url = f'http://127.0.0.1:{proxy.server.port}'
            values = {k: v.replace('{proxy}', url).replace('{proxyhost}', url[len('http://'):]) for k, v in variables.items()}
            configured = '-' if setting is None else setting.replace('{proxy}', url)
            env = {**base, **values}
            problems = []
            reference = None
            if not native_only:
                start = len(proxy.connects)
                reference = (run_case(['node', 'tests/http_proxy_reference.mts', configured] + urls, {**env, 'NODE_TLS_REJECT_UNAUTHORIZED': '0'}), proxy.connects[start:])
                if expect and not expect(*reference):
                    problems.append(f'upstream does not meet the expectation: {reference}')
            for backend in arguments.backends:
                start = len(proxy.connects)
                args = [encode(certificate), str(resolver), str(hosts), configured] + urls
                lines = run_case(commands[backend] + args, env)
                observed = (lines, proxy.connects[start:])
                if expect and not expect(*observed):
                    problems.append(f'{backend} does not meet the expectation: {observed}')
                if reference is not None and not compare_count:
                    observed, compared = (observed[0], observed[1][:1]), (reference[0], reference[1][:1])
                else:
                    compared = reference
                if reference is not None and observed != compared:
                    problems.append(f'{backend} differs from upstream:\n    upstream {compared}\n    port     {observed}')
            proxy.server.close()
            if problems:
                failures += 1
                print(f'FAIL {name}')
                for problem in problems:
                    print(f'  {problem}')
            else:
                print(f'PASS {name}')

        hello = lambda *paths: lambda lines, connects: lines == [f'status 200 hello {p}' for p in paths]
        case('http origin through HTTP_PROXY', {'HTTP_PROXY': '{proxy}'},
             [f'http://plain.test:{P}/a'], expect=lambda lines, connects: hello('/a')(lines, connects) and len(connects) == 1)
        # undici starts the second request before the first connection is
        # released and opens a second tunnel; the native pool reuses the idle
        # tunnel. Both requests' results and tunnel requests are compared.
        case('two requests through one proxy', {'HTTP_PROXY': '{proxy}'},
             [f'http://plain.test:{P}/a', f'http://plain.test:{P}/b'], compare_count=False,
             expect=lambda lines, connects: hello('/a', '/b')(lines, connects) and 1 <= len(connects) <= 2 and all(c == connects[0] for c in connects))
        case('https origin through HTTPS_PROXY (TLS inside the tunnel)', {'HTTPS_PROXY': '{proxy}'},
             [f'https://secure.test:{S}/s'], expect=lambda lines, connects: hello('/s')(lines, connects) and len(connects) == 1)
        case('https origin falls back to HTTP_PROXY', {'HTTP_PROXY': '{proxy}'},
             [f'https://secure.test:{S}/f'], expect=lambda lines, connects: hello('/f')(lines, connects) and len(connects) == 1)
        case('lowercase variables win over uppercase ones', {'http_proxy': '{proxy}', 'HTTP_PROXY': 'http://127.0.0.1:9'},
             [f'http://plain.test:{P}/l'], expect=lambda lines, connects: hello('/l')(lines, connects) and len(connects) == 1)
        case('NO_PROXY reaches the origin directly', {'HTTP_PROXY': '{proxy}', 'NO_PROXY': 'example.com, 127.0.0.1'},
             [f'http://127.0.0.1:{P}/direct'], expect=lambda lines, connects: hello('/direct')(lines, connects) and connects == [])
        case('NO_PROXY with a port only excludes that port', {'HTTP_PROXY': '{proxy}', 'NO_PROXY': 'plain.test:1'},
             [f'http://plain.test:{P}/p'], expect=lambda lines, connects: hello('/p')(lines, connects) and len(connects) == 1)
        case('proxy credentials become proxy-authorization', {'HTTP_PROXY': 'http://user:p%40ss@{proxyhost}'},
             [f'http://plain.test:{P}/auth'], expect=lambda lines, connects: hello('/auth')(lines, connects) and ('proxy-authorization', 'Basic dXNlcjpwQHNz') in connects[0][1])
        case('a refused tunnel fails the request', {'HTTP_PROXY': '{proxy}'}, [f'http://plain.test:{P}/r'], refuse=True,
             expect=lambda lines, connects: lines == ['error Proxy response (407) !== 200 when HTTP Tunneling'])
        # coding-agent http-dispatcher.test.ts, observed through the requests.
        D = 'http-dispatcher.test.ts > '
        case(D + 'http proxy settings > applies httpProxy to HTTP_PROXY and HTTPS_PROXY', {},
             [f'http://plain.test:{P}/setting', f'https://secure.test:{S}/setting'], setting='  {proxy}  ', compare_count=False,
             expect=lambda lines, connects: lines == ['status 200 hello /setting'] * 2 and len(connects) == 2)
        case(D + 'http proxy settings > does not override existing proxy env vars', {'HTTP_PROXY': '{proxy}', 'HTTPS_PROXY': '{proxy}'},
             [f'http://plain.test:{P}/env', f'https://secure.test:{S}/env'], setting='http://127.0.0.1:9', compare_count=False,
             expect=lambda lines, connects: lines == ['status 200 hello /env'] * 2 and len(connects) == 2)
        case(D + 'http proxy settings > ignores empty values', {}, [f'http://127.0.0.1:{P}/empty'], setting='   ',
             expect=lambda lines, connects: lines == ['status 200 hello /empty'] and connects == [])
        case(D + 'http dispatcher > tunnels proxied HTTP origins', {'HTTP_PROXY': '{proxy}'},
             [f'http://127.0.0.1:{P}/v1/chat/completions'] * 2, compare_count=False,
             expect=lambda lines, connects: lines == ['status 200 hello /v1/chat/completions'] * 2 and connects and connects[0][0] == f'CONNECT 127.0.0.1:{P} HTTP/1.1')
        case('https:// proxy URLs are rejected natively (TLS to the proxy is not supported)', {'HTTPS_PROXY': 'https://127.0.0.1:1'},
             [f'https://secure.test:{S}/x'], native_only=True,
             expect=lambda lines, connects: lines == ['config HTTPS proxies are not supported; use an http:// proxy URL'])
        # http-dispatcher.test.ts > http dispatcher > "allows two seconds for
        # HTTPS connection attempts without changing the Node default".
        # Upstream spies on undici's connect options; here the coding agent's
        # options are observed through timing: the hanging first address of
        # slow.test is abandoned after two seconds (measured from the reply
        # to fast.test, a single-address host fetched just before). There is
        # no process-wide default to leave unchanged natively.
        queue = socket.socket()
        queue.bind(('127.0.0.2', S))
        queue.listen(0)
        filler = []
        for _ in range(4):
            client = socket.socket()
            client.setblocking(False)
            client.connect_ex(('127.0.0.2', S))
            filler.append(client)
        name = D + 'http dispatcher > allows two seconds for HTTPS connection attempts without changing the Node default'
        problems = []
        for backend in arguments.backends:
            env = {k: v for k, v in base.items() if k not in PROXY_KEYS}
            process = subprocess.Popen(commands[backend] + [encode(certificate), str(resolver), str(hosts), '-', f'https://fast.test:{S}/fast', f'https://slow.test:{S}/attempt'], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
            first = process.stdout.readline().strip()
            fast = time.monotonic()
            second = process.stdout.readline().strip()
            elapsed = time.monotonic() - fast
            process.communicate(timeout=60)
            if first != 'status 200 hello /fast' or second != 'status 200 hello /attempt' or not 1.9 <= elapsed <= 3.5:
                problems.append(f'{backend}: {first!r} then {second!r} after {elapsed:.2f} s')
        for client in filler:
            client.close()
        queue.close()
        if problems:
            failures += 1
            print(f'FAIL {name}')
            for problem in problems:
                print(f'  {problem}')
        else:
            print(f'PASS {name}')
        plain.server.close()
        secure.server.close()
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()

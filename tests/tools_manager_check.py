"""tools-manager: management downloads, archive installation, lookup and offline mode.

PI_BEND_DOWNLOAD_LIVE=1 also downloads the latest rg release from GitHub.
"""
import argparse
import base64
import http.server
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['native-1', 'native-4'])
p.add_argument('--prefix', type=Path, default=ROOT / 'build/tools-manager')
a = p.parse_args()

hits = {}
PAYLOAD = bytes(range(256)) * 300


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, body=b'', headers=()):
        self.send_response(code)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        hits[self.path] = hits.get(self.path, 0) + 1
        count = hits[self.path]
        if self.path == '/file':
            self.reply(200, PAYLOAD)
        elif self.path == '/redirect':
            self.reply(302, headers=[('Location', '/relative')])
        elif self.path == '/relative':
            self.reply(301, headers=[('Location', f'http://127.0.0.1:{port}/file')])
        elif self.path == '/loop':
            self.reply(302, headers=[('Location', '/loop')])
        elif self.path == '/flaky':
            self.reply(503 if count <= 2 else 200, b'flaky' if count <= 2 else PAYLOAD)
        elif self.path == '/unavailable':
            self.reply(503, b'down')
        elif self.path == '/teapot':
            self.reply(429 if count == 1 else 418, b'later')
        else:
            self.reply(404, b'missing')


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
port = server.server_address[1]
threading.Thread(target=server.serve_forever, daemon=True).start()


def decode(line):
    kind, _, value = line.partition(':')
    return kind, base64.b64decode(value).decode() if value else ''


def archive(path, members):
    with tarfile.open(path, 'w:gz') as tar:
        for name, data in members:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(data))


for backend in a.backends:
    command = [str(a.prefix), '--threads', backend[-1]]
    checks = 0

    def run(*args, env=None):
        global checks
        result = subprocess.run(command + list(args), capture_output=True, text=True, timeout=180, env={**os.environ, **(env or {})})
        assert result.returncode == 0 and not result.stderr, (backend, args, result.stdout[-500:], result.stderr[-1000:])
        checks += 1
        return [decode(line) for line in result.stdout.splitlines()]

    with tempfile.TemporaryDirectory(prefix='bend-tools-manager-') as tmp:
        base = Path(tmp)
        # Downloads: plain body, relative and absolute redirects, the redirect
        # limit, retried transient statuses and a final failing status.
        hits.clear()
        dest = base / 'plain'
        assert run('download', f'http://127.0.0.1:{port}/file', str(dest)) == [('ok', '')]
        assert dest.read_bytes() == PAYLOAD
        dest = base / 'redirected'
        assert run('download', f'http://127.0.0.1:{port}/redirect', str(dest)) == [('ok', '')]
        assert dest.read_bytes() == PAYLOAD
        assert run('download', f'http://127.0.0.1:{port}/loop', str(base / 'loop')) == [('error', 'fetch failed: redirect count exceeded')]
        assert hits['/loop'] == 3 * 21, hits  # every attempt follows 20 redirects
        dest = base / 'flaky'
        assert run('download', f'http://127.0.0.1:{port}/flaky', str(dest)) == [('ok', '')]
        assert dest.read_bytes() == PAYLOAD and hits['/flaky'] == 3
        url = f'http://127.0.0.1:{port}/unavailable'
        assert run('download', url, str(base / 'down')) == [('error', f'Download failed with HTTP 503: {url}')]
        assert hits['/unavailable'] == 3 and not (base / 'down').exists()
        url = f'http://127.0.0.1:{port}/teapot'
        assert run('download', url, str(base / 'teapot')) == [('error', f'Download failed with HTTP 418: {url}')]
        assert hits['/teapot'] == 2
        url = f'http://127.0.0.1:{port}/absent'
        assert run('download', url, str(base / 'absent')) == [('error', f'Download failed with HTTP 404: {url}')]
        assert hits['/absent'] == 1
        # Installation: versioned and root layouts, a nested binary, a missing
        # binary and a corrupt archive. The archive and the extraction
        # directory are removed in every case; the binary becomes executable.
        asset = 'ripgrep-15.0.0-x86_64-unknown-linux-musl.tar.gz'
        for layout, members in [('versioned', [('ripgrep-15.0.0-x86_64-unknown-linux-musl/rg', b'#!/bin/sh\necho versioned\n'), ('ripgrep-15.0.0-x86_64-unknown-linux-musl/doc/rg', b'decoy')]),
                                ('root', [('rg', b'#!/bin/sh\necho root\n')]),
                                ('nested', [('other/deeper/rg', b'#!/bin/sh\necho nested\n'), ('other/README', b'x')])]:
            bindir = base / layout
            bindir.mkdir()
            archive(bindir / asset, members)
            extract = bindir / 'extract_tmp_rg_1'
            target = bindir / 'rg'
            assert run('install', str(bindir / asset), str(extract), asset, 'rg', str(target)) == [('installed', str(target))]
            assert subprocess.check_output([str(target)], text=True).strip() == layout
            assert target.stat().st_mode & 0o777 == 0o755
            assert sorted(os.listdir(bindir)) == ['rg'], os.listdir(bindir)
        bindir = base / 'empty'
        bindir.mkdir()
        archive(bindir / asset, [('ripgrep/README', b'no binary')])
        extract = bindir / 'extract_tmp_rg_2'
        assert run('install', str(bindir / asset), str(extract), asset, 'rg', str(bindir / 'rg')) == [('error', f'Binary not found in archive: expected rg under {extract}')]
        assert os.listdir(bindir) == []
        (bindir / asset).write_bytes(b'not gzip')
        [(kind, message)] = run('install', str(bindir / asset), str(extract), asset, 'rg', str(bindir / 'rg'))
        assert kind == 'error' and message.startswith(f'Failed to extract {asset}: tar: '), message
        assert os.listdir(bindir) == []
        # Lookup: the bin directory first, then PATH; offline mode skips the
        # download with upstream's warning.
        bindir = base / 'bin'
        bindir.mkdir()
        (bindir / 'rg').write_text('#!/bin/sh\n')
        assert run('ensure', str(bindir), 'rg') == [('path', str(bindir / 'rg'))]
        path = base / 'path'
        path.mkdir()
        (path / 'fdfind').write_text('#!/bin/sh\necho fd 10\n')
        (path / 'fdfind').chmod(0o755)
        assert run('ensure', str(bindir), 'fd', env={'PATH': str(path)}) == [('path', 'fdfind')]
        assert run('ensure', str(bindir), 'fd', env={'PATH': str(base / 'nowhere'), 'PI_OFFLINE': 'Yes'}) == [('warning', 'fd not found. Offline mode enabled, skipping download.'), ('none', '')]
        assert run('ensure', str(bindir), 'fd', env={'PATH': str(base / 'nowhere'), 'PI_OFFLINE': '0'}) == [('info', 'fd not found. Downloading...'), ('warning', 'Failed to download fd: fetch failed: no network transport'), ('none', '')]
        # Live: the latest rg release from GitHub through the CLI's transport.
        # Only one worker meets upstream's 10 s version-check budget (BEND-033).
        if os.environ.get('PI_BEND_DOWNLOAD_LIVE') == '1' and backend == 'native-1':
            bindir = base / 'live'
            bundle = os.environ.get('SSL_CERT_FILE', '/etc/ssl/certs/ca-certificates.crt')
            # PATH offers tar and gzip for the extraction but no rg.
            tools = base / 'tar-only'
            tools.mkdir()
            for name in ['tar', 'gzip']:
                (tools / name).symlink_to(shutil.which(name))
            lines = run('live', str(bindir), 'rg', bundle, env={'PATH': str(tools)})
            assert lines[0] == ('info', 'ripgrep not found. Downloading...') and lines[1] == ('info', f'ripgrep installed to {bindir / "rg"}') and lines[2] == ('path', str(bindir / 'rg')), lines
            assert subprocess.check_output([str(bindir / 'rg'), '--version'], text=True).startswith('ripgrep ')
            assert os.listdir(bindir) == ['rg'], os.listdir(bindir)
    print(f'{backend}: {checks} tools-manager scenarios passed', flush=True)
server.shutdown()

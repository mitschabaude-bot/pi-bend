"""Actual Fetch outcomes for a peer responding before it drains the upload.

The Bend checker separately proves socket backpressure and descriptor cleanup;
this oracle checks public HTTP outcomes, not exact upload bytes or timing.
"""
import concurrent.futures
import json
import socket
import subprocess

with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    listener.bind(('127.0.0.1', 0))
    listener.listen()
    listener.settimeout(15)

    def serve():
        for mode in range(5):
            with listener.accept()[0] as peer:
                peer.settimeout(15)
                head = bytearray()
                while not head.endswith(b'\r\n\r\n'):
                    part = peer.recv(1)
                    assert part, head
                    head.extend(part)
                response = b'HTTP/1.1 413 Content Too Large\r\nConnection: close\r\n'
                payloads = [b'Content-Length: 3\r\n\r\nabc',
                            b'Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n',
                            b'\r\nabc',
                            b'Content-Length: 3\r\n\r\na',
                            b'Content-Length: 3\r\n\r\n']
                peer.sendall(response + payloads[mode])
                if mode in [2, 3]:
                    peer.shutdown(socket.SHUT_WR)
                try:
                    while peer.recv(65536):
                        pass
                except ConnectionResetError:
                    pass

    future = pool.submit(serve)
    code = r'''
const base = process.argv[1];
const body = new Uint8Array(8 * 1024 * 1024);
for (let mode = 0; mode < 5; mode++) {
  const controller = new AbortController();
  const response = await fetch(base, {method: 'POST', body, signal: controller.signal});
  let result;
  if (mode === 4) {
    await response.body.cancel();
    result = 'early';
  } else {
    const reader = response.body.getReader();
    let text = '';
    try {
      for (;;) {
        const {value, done} = await reader.read();
        if (done) break;
        text += new TextDecoder().decode(value);
      }
      result = {text, end: 'eof'};
    } catch {
      result = {text, end: 'error'};
    }
  }
  console.log(JSON.stringify({status: response.status, result, aborted: controller.signal.aborted}));
}
'''
    result = subprocess.run(['node', '--input-type=module', '-e', code,
                             f'http://127.0.0.1:{listener.getsockname()[1]}/'],
                            text=True, capture_output=True, timeout=30)
    future.result(timeout=3)
    assert result.returncode == 0, (result.stdout, result.stderr)
    rows = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(rows) == 5, rows
    for mode, row in enumerate(rows):
        expected = ({'text': 'abc', 'end': 'eof'} if mode < 3 else
                    {'text': 'a', 'end': 'error'} if mode == 3 else 'early')
        assert row == {'status': 413, 'result': expected, 'aborted': False}, row
    print('Node Fetch: early 413 fixed/chunked/EOF, truncation and consumer cancellation PASS')

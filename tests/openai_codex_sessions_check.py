#!/usr/bin/env python3
"""Owned Codex session pool against real WebSocket connections.

Check reuse after disposing/aborting the previous request signal, account
isolation, expiry and cancellation of a new request on a reused connection.
"""
import argparse
import base64
import hashlib
from pathlib import Path
import socketserver
import subprocess
import threading
from websocket_client_check import frame, receive, GUID

ROOT = Path(__file__).resolve().parents[1]


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(5)
        try:
            header = b''
            while not header.endswith(b'\r\n\r\n'):
                byte = conn.recv(1)
                if not byte:
                    raise EOFError
                header += byte
            fields = dict(line.split(':',1) for line in header.decode().split('\r\n')[1:] if ':' in line)
            accept = base64.b64encode(hashlib.sha1((fields['sec-websocket-key'].strip()+GUID).encode()).digest()).decode()
            conn.sendall(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n').encode())
            with self.server.lock:
                self.server.connections += 1
                identity = self.server.connections
            while True:
                opcode, payload = receive(conn)
                assert opcode == 1, opcode
                with self.server.lock:
                    self.server.requests.append((identity,payload.decode()))
                if self.server.mode == 'cancel' and payload == b'second':
                    continue
                conn.sendall(frame(1,payload))
        except (EOFError,ConnectionResetError,BrokenPipeError):
            pass
        except Exception as error:
            self.server.errors.append(str(error))


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = False
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix',default='build/openai-codex-sessions')
    parser.add_argument('--backends',nargs='+',choices=['bun','native-1','native-4'],default=['bun'])
    args = parser.parse_args()
    for backend in args.backends:
        command = ['bun',args.prefix+'.js'] if backend == 'bun' else [args.prefix,'--threads',backend[-1]]
        for mode in ('reuse','account','expired','age','busy','replacement','cancel'):
            with Server(('127.0.0.1',0),Handler) as server:
                server.mode,server.connections,server.requests,server.errors,server.lock = mode,0,[],[],threading.Lock()
                worker = threading.Thread(target=server.serve_forever)
                worker.start()
                try:
                    result = subprocess.run(command+[f'ws://127.0.0.1:{server.server_address[1]}/responses',mode],cwd=ROOT,text=True,capture_output=True,timeout=15)
                    assert result.returncode == 0,(mode,result.stdout,result.stderr[-1500:])
                finally:
                    server.shutdown()
                    worker.join()
                server.server_close()
                assert not server.errors,(mode,server.errors)
                expected = 1 if mode in ('reuse','cancel') else 2
                assert server.connections == expected,(mode,server.requests)
                assert [payload for _,payload in server.requests] == (['first','second','third'] if mode in ('busy','replacement') else ['first','second']),server.requests
                if mode == 'busy':
                    assert [identity for identity,_ in server.requests] == [1,2,1],server.requests
                if mode == 'replacement':
                    assert [identity for identity,_ in server.requests] == [1,2,2],server.requests
                lines = result.stdout.splitlines()
                assert lines[:2] == ['text|first','fresh'],lines
                assert lines[-1] == ('reused' if expected == 1 or mode in ('busy','replacement') else 'fresh'),lines
                assert lines[2].startswith('error|') if mode == 'cancel' else lines[2] == 'text|second',lines
                print(f'{backend}: {mode} connection identity/request-signal isolation/cleanup PASS')


if __name__ == '__main__':
    main()

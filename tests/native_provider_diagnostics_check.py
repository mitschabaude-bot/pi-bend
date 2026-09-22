"""Local HTTPS failure categories; diagnostics must not change ordinary output.

Usage: python3 tests/native_provider_diagnostics_check.py BINARY --threads 1
The runner accepts the four-tool fixture's usual five positional arguments.
"""
import sys,pathlib,subprocess,socket,tempfile,os,json,struct
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0,str(pathlib.Path('tests').resolve()))
from fetch_https_check import trusted_context
from native_agent_check import response, completion
from cryptography import x509
from cryptography.hazmat.primitives import serialization
command=sys.argv[1:]
cases=[('json',b'data: {"PRIVATE_SENTINEL":\n\n','processing.read.sse.invalid-json',False),('schema',b'data: {"type":"response.output_text.delta","delta":7}\n\n','processing.read.responses.event-schema',False),('terminal',b'data: {"type":"response.created","response":{"id":"test"}}\n\n','processing.responses.missing-terminal',False),('truncated',b'data: {"type":"response.created","response":{"id":"test"}}\n\n',None,True)]
for label,body,category,truncated in cases:
 for enabled in [None,'0','1']:
  with tempfile.TemporaryDirectory(prefix='pi-diagnostic-') as folder,ThreadPoolExecutor(max_workers=1) as pool:
   path=pathlib.Path(folder);ctx,der=trusted_context(path,'localhost');trust=path/'root.pem';trust.write_bytes(x509.load_der_x509_certificate(der).public_bytes(serialization.Encoding.PEM))
   with socket.socket() as listener:
    listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(40)
    def serve():
     connection,_=listener.accept()
     with ctx.wrap_socket(connection,server_side=True) as peer:
      data=b''
      while b'\r\n\r\n' not in data:data+=peer.recv(65536)
      head,payload=data.split(b'\r\n\r\n',1);length=int(next(line.split(b':',1)[1] for line in head.split(b'\r\n') if line.lower().startswith(b'content-length:')))
      while len(payload)<length:payload+=peer.recv(65536)
      peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: '+str(len(body)+(100 if truncated else 0)).encode()+b'\r\nConnection: close\r\n\r\n'+body)
    future=pool.submit(serve)
    env={**os.environ,'OPENAI_API_KEY':'PRIVATE_KEY_SENTINEL','PI_BEND_RETRY_REQUESTS':'0'}
    env.pop('PI_BEND_PROVIDER_DIAGNOSTICS',None)
    if enabled is not None:env['PI_BEND_PROVIDER_DIAGNOSTICS']=enabled
    run=subprocess.run(command+[str(trust),'fixture-model',f'https://localhost:{listener.getsockname()[1]}/v1','test',str(path)],env=env,text=True,capture_output=True,timeout=60)
    future.result(timeout=10)
    assert run.returncode!=0,(label,run.stdout,run.stderr)
    diagnostics=[line for line in run.stdout.splitlines() if line.startswith('provider-diagnostic|')]
    if enabled is None:
     assert not diagnostics,(label,diagnostics)
     baseline=(run.returncode,run.stdout.splitlines(),run.stderr)
    elif enabled=='0':
     assert not diagnostics,(label,diagnostics)
     assert (run.returncode,run.stdout.splitlines(),run.stderr)==baseline
    else:
     assert (run.returncode,[line for line in run.stdout.splitlines() if not line.startswith('provider-diagnostic|')],run.stderr)==baseline
     assert diagnostics,(label,run.stdout,run.stderr)
     assert all('PRIVATE' not in line for line in diagnostics),diagnostics
     if category:assert 'provider-diagnostic|primary|'+category in diagnostics,(label,diagnostics)
     print(label,diagnostics,flush=True)
print('PASS opt-in/disabled local HTTPS failures and diagnostic redaction')


def read_request(peer):
    wire = b''
    while b'\r\n\r\n' not in wire:
        data = peer.recv(65536)
        assert data, 'closed before request headers'
        wire += data
    head, body = wire.split(b'\r\n\r\n', 1)
    length = int(next(line.split(b':', 1)[1] for line in head.split(b'\r\n')
                      if line.lower().startswith(b'content-length:')))
    while len(body) < length:
        data = peer.recv(65536)
        assert data, 'closed before request body'
        wire += data
        body += data
    assert len(body) == length
    assert head.startswith(b'POST /v1/responses HTTP/1.1\r\n')
    return wire, json.loads(body)


# The failed initial attempt sends no response bytes, so retrying cannot replay
# an already-emitted tool call. The separate post-tool request checks the history.
for enabled in [None, '0', '1']:
    with tempfile.TemporaryDirectory(prefix='pi-retry-') as folder, ThreadPoolExecutor(max_workers=1) as pool:
        path = pathlib.Path(folder)
        ctx, der = trusted_context(path, 'localhost')
        trust = path / 'root.pem'
        trust.write_bytes(x509.load_der_x509_certificate(der).public_bytes(serialization.Encoding.PEM))
        target = path / 'once.txt'
        requests = []
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            listener.settimeout(40)

            def retry_peer():
                raw, _ = listener.accept()
                raw.settimeout(30)
                with ctx.wrap_socket(raw, server_side=True) as peer:
                    requests.append(read_request(peer))
                    # Real TCP RST, after the complete request and before headers;
                    # skip TLS close_notify instead of sending a truncated response.
                    peer.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
                if enabled != '1':
                    return
                raw, _ = listener.accept()
                raw.settimeout(30)
                with ctx.wrap_socket(raw, server_side=True) as peer:
                    requests.append(read_request(peer))
                    assert requests[0][0] == requests[1][0], 'retry did not replay the exact request'
                    value = requests[1][1]
                    assert [tool['name'] for tool in value['tools']] == ['write', 'edit', 'read', 'bash']
                    assert not any(item.get('type') in ['function_call', 'function_call_output'] for item in value['input'])
                    encoded = json.dumps({'path': 'once.txt', 'content': 'executed once\n'}, separators=(',', ':'))
                    item = {'type': 'function_call', 'id': 'fc-once', 'call_id': 'call-once', 'name': 'write', 'arguments': ''}
                    response(peer, [
                        {'type': 'response.created', 'response': {'id': 'resp-retry'}},
                        {'type': 'response.output_item.added', 'output_index': 0, 'item': item},
                        {'type': 'response.function_call_arguments.delta', 'output_index': 0, 'delta': encoded},
                        {'type': 'response.function_call_arguments.done', 'output_index': 0, 'arguments': encoded},
                        {'type': 'response.output_item.done', 'output_index': 0, 'item': {**item, 'arguments': encoded}},
                        completion('resp-retry')])
                raw, _ = listener.accept()
                raw.settimeout(30)
                with ctx.wrap_socket(raw, server_side=True) as peer:
                    requests.append(read_request(peer))
                    value = requests[2][1]
                    calls = [item for item in value['input'] if item.get('type') == 'function_call']
                    outputs = [item for item in value['input'] if item.get('type') == 'function_call_output']
                    assert len(calls) == len(outputs) == 1, value['input']
                    assert calls[0]['call_id'] == outputs[0]['call_id'] == 'call-once'
                    assert outputs[0]['output'] == 'Successfully wrote to once.txt'
                    assert target.read_text() == 'executed once\n'
                    item = {'type': 'message', 'id': 'msg-final', 'role': 'assistant', 'content': []}
                    response(peer, [
                        {'type': 'response.created', 'response': {'id': 'resp-final'}},
                        {'type': 'response.output_item.added', 'output_index': 0, 'item': item},
                        {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'retry complete'},
                        {'type': 'response.output_item.done', 'output_index': 0, 'item': {**item, 'content': [{'type': 'output_text', 'text': 'retry complete'}]}},
                        completion('resp-final')])

            future = pool.submit(retry_peer)
            env = {**os.environ, 'OPENAI_API_KEY': 'PRIVATE_KEY_SENTINEL', 'PI_BEND_PROVIDER_DIAGNOSTICS': '1'}
            env.pop('PI_BEND_RETRY_REQUESTS', None)
            if enabled is not None:
                env['PI_BEND_RETRY_REQUESTS'] = enabled
            run = subprocess.run(command + [str(trust), 'fixture-model', f'https://localhost:{listener.getsockname()[1]}/v1', 'test', str(path)],
                                 env=env, text=True, capture_output=True, timeout=60)
            future.result(timeout=10)
            lines = run.stdout.splitlines()
            if enabled == '1':
                assert run.returncode == 0 and not run.stderr, (run.stdout, run.stderr)
                assert len(requests) == 3  # two initial attempts plus one post-tool continuation
                assert 'executions write=1 edit=0 read=0 bash=0' in lines, lines
                assert lines.count('event tool_execution_start') == lines.count('event tool_execution_end') == 1, lines
                assert 'answer retry complete' in lines, lines
                assert not any(line.startswith('provider-diagnostic|') for line in lines), lines
            else:
                assert run.returncode != 0 and len(requests) == 1, (run.stdout, run.stderr)
                assert 'executions write=0 edit=0 read=0 bash=0' in lines and not target.exists(), lines
                assert not any('tool_execution_' in line for line in lines), lines
                assert 'provider-diagnostic|primary|request.headers.socket.os.104' in lines, lines
            # No extra request may be queued after the host retires its loop.
            listener.settimeout(.1)
            try:
                unexpected, _ = listener.accept()
            except TimeoutError:
                pass
            else:
                unexpected.close()
                raise AssertionError('unexpected duplicate request')
        print(f'retry={enabled!r}: {len(requests)} total requests, exact replay and tool count PASS', flush=True)
print('PASS default/disabled request failure and opt-in reset recovery without duplicate tool execution')

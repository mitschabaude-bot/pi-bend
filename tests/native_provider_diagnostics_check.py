"""Local HTTPS failure categories; diagnostics must not change ordinary output.

Usage: python3 tests/native_provider_diagnostics_check.py BINARY --threads 1
The runner accepts the four-tool fixture's usual five positional arguments.
"""
import sys,pathlib,subprocess,socket,tempfile,os,json
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0,str(pathlib.Path('tests').resolve()))
from fetch_https_check import trusted_context
from cryptography import x509
from cryptography.hazmat.primitives import serialization
command=sys.argv[1:]
cases=[('json',b'data: {"PRIVATE_SENTINEL":\n\n','processing.read.sse.invalid-json',False),('schema',b'data: {"type":"response.output_text.delta","delta":7}\n\n','processing.read.responses.event-schema',False),('terminal',b'data: {"type":"response.created","response":{"id":"test"}}\n\n','processing.responses.missing-terminal',False),('truncated',b'data: {"type":"response.created","response":{"id":"test"}}\n\n',None,True)]
for label,body,category,truncated in cases:
 for enabled in ['0','1']:
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
    run=subprocess.run(command+[str(trust),'fixture-model',f'https://localhost:{listener.getsockname()[1]}/v1','test',str(path)],env={**os.environ,'OPENAI_API_KEY':'PRIVATE_KEY_SENTINEL','PI_BEND_PROVIDER_DIAGNOSTICS':enabled},text=True,capture_output=True,timeout=60)
    future.result(timeout=10)
    assert run.returncode!=0,(label,run.stdout,run.stderr)
    diagnostics=[line for line in run.stdout.splitlines() if line.startswith('provider-diagnostic|')]
    if enabled=='0':
     assert not diagnostics,(label,diagnostics)
     baseline=(run.returncode,run.stdout.splitlines(),run.stderr)
    else:
     assert (run.returncode,[line for line in run.stdout.splitlines() if not line.startswith('provider-diagnostic|')],run.stderr)==baseline
     assert diagnostics,(label,run.stdout,run.stderr)
     assert all('PRIVATE' not in line for line in diagnostics),diagnostics
     if category:assert 'provider-diagnostic|primary|'+category in diagnostics,(label,diagnostics)
     print(label,diagnostics,flush=True)
print('PASS opt-in/disabled local HTTPS failures and diagnostic redaction')

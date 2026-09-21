"""Composed native acquisition/retries and canonical session against pinned pi."""
import argparse, hashlib, json, re, socket, subprocess, threading, time
from pathlib import Path
from scoped_session_audit import prepare
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix',type=Path,default=ROOT/'build/openai-native-session')
parser.add_argument('--backends',nargs='+',choices=['native-1','native-4','bun'],default=['native-1','native-4','bun'])
parser.add_argument('--audit',action='store_true')
parser.add_argument('--prepare-audit',action='store_true')
args=parser.parse_args();prefix=args.prefix.resolve()
compiler=ROOT/'build/bend-profiles/dns-transport-teles/bend2'
if args.prepare_audit:
    prepare(prefix,compiler,any(b.startswith('native-') for b in args.backends))
    raise SystemExit(0)
program=Path(str(prefix)+('-audit' if args.audit else ''))
created={'type':'response.created','response':{'id':'resp-test'}}
item={'type':'message','id':'msg-test','role':'assistant','content':[]}
added={'type':'response.output_item.added','output_index':0,'item':item}
delta={'type':'response.output_text.delta','output_index':0,'delta':'hé🙂'}
ended={'type':'response.output_item.done','output_index':0,'item':{**item,'content':[{'type':'output_text','text':'hé🙂'}]}}
completed={'type':'response.completed','response':{'id':'resp-final','status':'completed','usage':{'input_tokens':20,'output_tokens':5,'total_tokens':25,'input_tokens_details':{'cached_tokens':3,'cache_write_tokens':2}}}}
incomplete={'type':'response.incomplete','response':{'id':'resp-final','status':'incomplete','incomplete_details':{'reason':'max_output_tokens'}}}
failed={'type':'response.failed','response':{'status':'failed','error':{'code':'failed','message':'failed'}}}
normal=[created,added,delta,ended,completed];partial=[created,added,delta]
cases=[]
for supplied in [False,True]:
    for mode,events,statuses in [(0,normal,[200]),(2,normal,[]),(3,normal,[200]),(9,partial,[200]),(10,partial,[200]),(16,partial+[failed],[200]),(18,partial+[incomplete],[200]),(20,normal,[503,200]),(21,normal,[503,503,503]),(22,normal,[]),(23,normal,[] if supplied else [200])]:
        cases.append(dict(mode=mode,events=events,statuses=statuses,supplied=supplied,slow=False))
    cases.append(dict(mode=0,events=normal,statuses=[200],supplied=supplied,slow=True))
oracle=[dict(c, mode=2 if c['mode']==22 else c['mode'], sdkStatusError=True, abortCallerOnIteratorClose=False, preaborted=c['mode']==23 and c['supplied']) for c in cases]
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith('46c9de402')
reference=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/openai_provider_driver_reference.mts'],cwd=ROOT,input=json.dumps(oracle),text=True))
frame=lambda event:('data: '+json.dumps(event,ensure_ascii=False,separators=(',',':'))+'\n\n').encode()
runs=[]
for backend,command in [('native-1',[str(program),'--threads','1']),('native-4',[str(program),'--threads','4']),('bun',[str(Path.home()/'.bun/bin/bun'),str(program)+'.js'])]:
    if backend not in args.backends:continue
    for case,original in zip(cases,reference['results'],strict=True):
        assert original['unhandled'] is None
        trace=[line for line in original['trace'] if not line.startswith('emit:') and line!='close']
        wanted=trace+[f"run:{original['error'] or 'ok'}:cleanup:none:delivery:none"]+original['retained']+[original['final']]+['caller:'+('aborted' if case['mode']==23 else 'live')]
        if case['mode']==22:
            # Approved strict options validation precedes hooks. Reuse the
            # oracle's initial failed message shape, with the validation cause.
            old=','.join(str(ord(c)) for c in 'payload');new=','.join(str(ord(c)) for c in 'invalid retry options')
            wanted=[line.replace('run:payload:', 'run:invalid retry options:').replace(':error:'+old, ':error:'+new) for line in wanted if not line.startswith('payload:')]
        errors=[];peers=[];requests=[];stop=threading.Event()
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(.1)
            def serve():
                try:
                    while not stop.is_set():
                        try:peer,_=listener.accept()
                        except socket.timeout:continue
                        with peer:
                            peer.settimeout(10);data=b''
                            while b'\r\n\r\n' not in data:
                                chunk=peer.recv(4096);assert chunk;data+=chunk
                            head,body=data.split(b'\r\n\r\n',1)
                            assert head.startswith(b'POST /v1/responses HTTP/1.1\r\n'),head
                            headers=dict(line.lower().split(b':',1) for line in head.split(b'\r\n')[1:])
                            size=int(headers[b'content-length'])
                            while len(body)<size:
                                chunk=peer.recv(4096);assert chunk;body+=chunk
                            assert body==b'7' and headers[b'authorization'].strip()==b'bearer fixture-key',(head,body)
                            index=len(requests);requests.append(body.decode());assert index<len(case['statuses']),'extra request'
                            status=case['statuses'][index]
                            if status==200:
                                response=b''.join(map(frame,case['events']))+(b'data: {\n\n' if case['mode']==10 else b'data: [DONE]\n\n')
                                content_type='text/event-stream'
                            else:response=b'{"error":{"message":"original"}}';content_type='application/json'
                            peer.sendall(f'HTTP/1.1 {status} Response\r\nContent-Type: {content_type}\r\nContent-Length: {len(response)}\r\nx-response: ok\r\n\r\n'.encode())
                            if case['slow']:time.sleep(1.15)
                            peer.sendall(response)
                            peer.shutdown(socket.SHUT_WR)
                            try:assert peer.recv(4096)==b'';peers.append('eof')
                            except ConnectionResetError:peers.append('reset')
                except BaseException as error:errors.append(repr(error))
            thread=threading.Thread(target=serve);thread.start()
            try:result=subprocess.run(command+[str(case['mode']),str(listener.getsockname()[1]),'yes' if case['supplied'] else 'no'],cwd=ROOT,capture_output=True,text=True,timeout=30)
            finally:stop.set();thread.join(timeout=12)
        assert not thread.is_alive() and not errors and len(peers)==len(case['statuses']),(backend,case,errors,peers)
        assert result.returncode==0,(backend,case,result)
        assert sorted(result.stderr.splitlines())==(['AUDIT 0 0 0','TIMERS 0 0'] if args.audit else []),(backend,case,result.stderr)
        actual=result.stdout.splitlines()
        if actual!=wanted:
            Path(str(prefix)+'-mismatch.json').write_text(json.dumps(dict(backend=backend,case=case,actual=actual,wanted=wanted),indent=2)+'\n')
        assert actual==wanted,(backend,case['mode'],case['supplied'],actual,wanted)
        runs.append(dict(backend=backend,audited=args.audit,case=case,trace=actual,requests=requests,peers=peers))
    print(backend,len(cases),'composed native session cases PASS',flush=True)
pending=[ROOT/'tests/openai-native-session.bend'];seen=set()
while pending:
    path=pending.pop().resolve()
    if path in seen:continue
    seen.add(path);pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
seen.update([ROOT/'tests/scoped_session_audit.py',ROOT/'tests/channel_audit.py',Path(__file__).resolve(),ROOT/'tests/openai_provider_driver_reference.mts',ROOT/'tests/responses_stream_reference.mts'])
upstream=ROOT.parent/'pi-mono/packages/ai/src'
seen.update(upstream/n for n in ['api/openai-responses.ts','api/openai-responses-shared.ts','api/constrained-sampling.ts','models.ts','utils/json-parse.ts','utils/headers.ts','utils/error-body.ts','utils/provider-retry.ts'])
deps=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules')
for dependency in ['openai','partial-json']:
    seen.add(deps/dependency/'package.json')
    seen.update((deps/dependency).rglob('*.js'))
programs=[Path(str(program)+suffix) for suffix in ['', '.c', '.js'] if Path(str(program)+suffix).exists()]
record=dict(program_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in programs},scope='Composed cleartext native session: actual envelope/hooks/retry/request/body/session. Supplied and owned parents, retained snapshots, final result, peer closure. Native channel/parked-IO/socket (fd 0..4095), Bun channel/live-IO/waiting-IO and both timer/waiter audits when enabled. Finite cases, not a universal resource proof.',reference_commit=reference_commit,sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},runs=runs)
Path(str(program)+'-'+','.join(args.backends)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')

"""Scoped HTTP/SSE session traces against the pinned pi provider lifecycle.

This fixture begins at HTTP dispatch: preparation/hooks/retries are validated
separately, so only their explicit oracle log lines are omitted here.
"""
import argparse,hashlib,json,re,socket,subprocess,threading,time
from pathlib import Path
from channel_audit import instrument
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix',type=Path,default=ROOT/'build/openai-scoped-session')
parser.add_argument('--backends',nargs='+',choices=['native-1','native-4','bun'],default=['native-1','native-4','bun'])
parser.add_argument('--audit',action='store_true',help='Run resource-instrumented programs')
parser.add_argument('--prepare-audit',action='store_true',help='Emit instrumented sources and exit; compile native source separately')
args=parser.parse_args();prefix=args.prefix.resolve()
BEND=ROOT/'build/bend-profiles/dns-transport-teles/bend2'
if args.prepare_audit:
    if any(b.startswith('native-') for b in args.backends):
        c=Path(str(prefix)+'.c').read_text()
        c+=r'''
    static void __attribute__((destructor)) scoped_session_audit(void) {
      unsigned channels=0,sockets=0,live=0,waiting=0;
      for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
      for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
      for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
      fprintf(stderr,"AUDIT %u %u %u\nTIMERS %u %u\n",channels,io_park.head!=NULL,sockets,live,waiting);
    }
    '''
        Path(str(prefix)+'-audit.c').write_text(c)
    js=instrument(Path(str(prefix)+'.js').read_text())
    original=(BEND/'effs/timer.js').read_text()
    needle='  return io_tup(row, row);'
    assert js.count(original)==1 and original.count(needle)==1
    js=js.replace(original,original.replace(needle,'  scopedTimerRows.push(row);\n'+needle))
    js="const scopedTimerRows=[];process.on('exit',()=>console.error('TIMERS',scopedTimerRows.filter(x=>x.state!==3).length,scopedTimerRows.filter(x=>x.waiter!==null).length));\n"+js
    Path(str(prefix)+'-audit.js').write_text(js)
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
cases=[dict(mode=m,statuses=[200],events=e,name=n,slow=False) for m,e,n in [(0,normal,'normal'),(9,partial,'missing-terminal'),(10,partial,'invalid-json'),(16,partial+[failed],'provider-failure'),(18,partial+[incomplete],'length-limit')]]
cases.append(dict(mode=0,statuses=[200],events=normal,name='past-header-deadline',slow=True))
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith('46c9de402')
reference=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/openai_provider_driver_reference.mts'],input=json.dumps(cases),cwd=ROOT,text=True))
frame=lambda e:('data: '+json.dumps(e,ensure_ascii=False,separators=(',',':'))+'\n\n').encode()
runs=[]
for backend,command in [('native-1',[str(program),'--threads','1']),('native-4',[str(program),'--threads','4']),('bun',[str(Path.home()/'.bun/bin/bun'),str(program)+'.js'])]:
    if backend not in args.backends:continue
    for case,original in zip(cases,reference['results'],strict=True):
        assert original['unhandled'] is None
        omitted=('payload:','request:','response:model:','emit:')
        trace=[line for line in original['trace'] if not line.startswith(omitted) and line!='close']
        wanted=trace+[f"run:{original['error'] or 'ok'}:cleanup:none:delivery:none"]+original['retained']+[original['final']]
        errors=[];peers=[]
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(10)
            def serve():
                try:
                    with listener.accept()[0] as peer:
                        peer.settimeout(10);request=b''
                        while b'\r\n\r\n' not in request:
                            part=peer.recv(4096);assert part,'truncated request';request+=part
                        assert request.startswith(b'GET /sse HTTP/1.1\r\n'),request
                        body=b''.join(map(frame,case['events']))+(b'data: {\n\n' if case['mode']==10 else b'data: [DONE]\n\n')
                        header=f'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {len(body)}\r\n\r\n'.encode()
                        peer.sendall(header)
                        if case['slow']:time.sleep(1.15)
                        peer.sendall(body);peer.shutdown(socket.SHUT_WR)
                        try:assert peer.recv(4096)==b'';peers.append('eof')
                        except ConnectionResetError:peers.append('reset')
                except BaseException as error:errors.append(repr(error))
            thread=threading.Thread(target=serve);thread.start()
            try:result=subprocess.run(command+[str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=20)
            finally:thread.join(timeout=12)
            assert not thread.is_alive() and not errors and len(peers)==1,(backend,case['name'],errors,peers)
        assert result.returncode==0,(backend,case['name'],result)
        assert sorted(result.stderr.splitlines())==(['AUDIT 0 0 0','TIMERS 0 0'] if args.audit else []),(backend,case['name'],result.stderr)
        actual=result.stdout.splitlines()
        assert actual==wanted,(backend,case['name'],actual,wanted)
        runs.append(dict(backend=backend,audited=args.audit,case=case['name'],peer=peers[0],trace=actual))
    print(backend,len(cases),'scoped session reference cases PASS',flush=True)
pending=[ROOT/'tests/openai-scoped-session.bend'];seen=set()
while pending:
    p=pending.pop().resolve()
    if p in seen:continue
    seen.add(p);pending.extend(p.parent/n for n in re.findall(r'^import (\.[^\s]+)',p.read_text(),re.M))
seen.update([ROOT/'tests/channel_audit.py',Path(__file__).resolve(),ROOT/'tests/openai_provider_driver_reference.mts',ROOT/'tests/responses_stream_reference.mts'])
upstream=ROOT.parent/'pi-mono/packages/ai/src'
seen.update(upstream/n for n in ['api/openai-responses.ts','api/openai-responses-shared.ts','api/constrained-sampling.ts','models.ts','utils/json-parse.ts','utils/headers.ts','utils/error-body.ts','utils/provider-retry.ts'])
partial=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/partial-json')
seen.update(partial.rglob('*.js'));seen.add(partial/'package.json')
programs=[Path(str(program)+suffix) for suffix in ['', '.c', '.js'] if Path(str(program)+suffix).exists()]
record=dict(program_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in programs},scope='Scoped HTTP/SSE acquisition and production session eventstream lifecycle against pinned pi. Exact retained snapshots, final result, failures and peer closure; Optional native live-channel/parked-IO/socket (fd 0..4095) audit; Bun explicit-channel/live-IO/waiting-IO audit; both audit live timers and timer waiters. Finite cases, not a universal resource proof.',reference_commit=reference_commit,sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},runs=runs)
Path(str(program)+'-'+','.join(args.backends)+'-session-result.json').write_text(json.dumps(record,indent=2)+'\n')

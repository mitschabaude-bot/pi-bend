"""The OpenAI Responses provider end to end against the pinned pi wrapper.

Builds tests/openai-responses.bend, scripts a loopback HTTP server per case and
compares every printed line (hooks, run outcome, retained events, final message,
cancellation) with the pinned upstream wrapper driven by the same events.
Requests, retries, bodies and peer closure are asserted by the server.
"""
import argparse,hashlib,json,os,re,socket,struct,subprocess,tempfile,threading,time
from pathlib import Path
from scoped_session_audit import prepare
from upstream_pin import PIN
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix',type=Path,default=ROOT/'build/openai-responses')
parser.add_argument('--backends',nargs='+',choices=['native-1','native-4','bun'],default=['native-1','native-4','bun'])
parser.add_argument('--no-build',action='store_true')
parser.add_argument('--audit',action='store_true')
parser.add_argument('--prepare-audit',action='store_true')
args=parser.parse_args();prefix=args.prefix.resolve()
toolchain=ROOT/'build/bend-native-toolchain/bend2'
compiler=toolchain/'main.ts'
bun=Path.home()/'.bun/bin/bun'
if args.prepare_audit:
    prepare(prefix,toolchain,any(b.startswith('native-') for b in args.backends))
    raise SystemExit(0)
program=Path(str(prefix)+('-audit' if args.audit else ''))
# The installed toolchain carries the layout cap (BEND-010 resolution).
capped=compiler
if not args.no_build and not args.audit:
    for suffix,limit,tool in [('c','16',capped if capped.is_file() else compiler),('js','8',compiler)]:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib',limit,'--stats',f'{prefix}-{suffix}-build.json','--',str(bun),str(tool),'tests/openai-responses.bend','-o',f'{prefix}.{suffix}'],cwd=ROOT,check=True,env={**os.environ,'BEND_LAY_MAX':'32'})
    subprocess.run(['clang','-fbracket-depth=2048','-std=c11','-O1',f'{prefix}.c','-lpthread','-lm','-o',str(prefix)],cwd=ROOT,check=True)

def bits(n):b=struct.pack('>d',n);return f"{int.from_bytes(b[:4],'big')},{int.from_bytes(b[4:],'big')}"
def scalars(s):return ','.join(str(ord(c)) for c in s)
created={'type':'response.created','response':{'id':'resp-test'}}
item={'type':'message','id':'msg-test','role':'assistant','content':[]}
added={'type':'response.output_item.added','output_index':0,'item':item}
delta={'type':'response.output_text.delta','output_index':0,'delta':'hé🙂'}
ended={'type':'response.output_item.done','output_index':0,'item':{**item,'content':[{'type':'output_text','text':'hé🙂'}]}}
completed={'type':'response.completed','response':{'id':'resp-final','status':'completed','usage':{'input_tokens':20,'output_tokens':5,'total_tokens':25,'input_tokens_details':{'cached_tokens':3,'cache_write_tokens':2}}}}
incomplete={'type':'response.incomplete','response':{'id':'resp-final','status':'incomplete','incomplete_details':{'reason':'max_output_tokens'}}}
failed={'type':'response.failed','response':{'status':'failed','error':{'code':'failed','message':'failed'}}}
tool_item={'type':'custom_tool_call','id':'ct','call_id':'call','name':'tool','input':''}
tool_events=[created,{'type':'response.output_item.added','output_index':0,'item':tool_item},{'type':'response.custom_tool_call_input.delta','output_index':0,'delta':'al'},{'type':'response.custom_tool_call_input.done','output_index':0,'input':'alpha'},{'type':'response.output_item.done','output_index':0,'item':{**tool_item,'input':'alpha'}},{'type':'response.completed','response':{'id':'r','status':'completed'}}]
normal=[created,added,delta,ended,completed];partial=[created,added,delta]
def tiered(response_tier):
    terminal=json.loads(json.dumps(completed))
    if response_tier is not None:terminal['response']['service_tier']=response_tier
    return normal[:-1]+[terminal]
# mode: fixture behaviour; oracle: the upstream wrapper's injected mode;
# statuses: scripted HTTP responses; placeholder: an error text the oracle
# cannot produce, substituted from the native run line under `accept`.
cases=[]
def add(mode,events,statuses,oracle=None,supplied=(False,True),**extra):
    for s in supplied:cases.append(dict(mode=mode,events=events,statuses=statuses,oracle=mode if oracle is None else oracle,supplied=s,slow=False,**extra))
add(0,normal,[200])
add(1,tool_events,[200],oracle=0)
add(2,normal,[])
add(3,normal,[200])
add(9,partial,[200])
add(10,partial,[200],placeholder='json',accept='Invalid SSE JSON: ')
add(14,normal,[200]);add(15,normal,[200])
add(16,partial+[failed],[200]);add(18,partial+[incomplete],[200])
add(20,normal,[503,200]);add(21,normal,[503,503,503])
add(22,normal,[],oracle=2,placeholder='payload',accept='maxRetries must be a non-negative integer within the native natural-number range')
add(23,normal,[200],supplied=(False,));add(23,normal,[],supplied=(True,),preaborted=True)
for mode,tier,response_tier,model_id in [(24,'flex',None,'test'),(25,'priority',None,'test'),(26,'priority',None,'gpt-5.5'),(27,'flex','priority','test'),(28,'priority','flex','test')]:
    add(mode,tiered(response_tier),[200],serviceTier=tier,modelId=model_id)
add(30,[],[],oracle=0,apiKey='')
add(31,normal,[],oracle=0,placeholder='configuration',accept='')
add(32,[],[200],oracle=10,placeholder='json',accept='Invalid SSE JSON: ')
add(33,normal,[200])
add(34,normal,[200],oracle=0);
for c in cases:
    if c['mode']==34:c['slow']=True
def oracle(name,value):return json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/'+name],cwd=ROOT,input=json.dumps(value),text=True))
model=dict(id='test',name='Test',api='openai-responses',provider='openai',baseUrl='http://127.0.0.1/v1',reasoning=False,input=['text'],cost=dict(input=1000000,output=2000000,cacheRead=3000000,cacheWrite=4000000),contextWindow=128000,maxTokens=4096,compat=dict(supportsOpenAIGrammarTools=True))
tool=dict(name='tool',description='A tool',parameters=dict(type='object',properties=dict(program=dict(type='string')),required=['program']),constrainedSampling=dict(type='grammar',variants=dict(openai_lark='start: /[a-z]+/')))
messages=[dict(role='system',content='initial',toolsAdded=[tool],timestamp=1),dict(role='user',content='hello',timestamp=1)]
prepared=oracle('responses_prepare_reference.mts',[dict(model={**model,'id':c.get('modelId','test')},messages=messages,options=dict(apiKey=c.get('apiKey','fixture-key'),env={},**({'serviceTier':c['serviceTier']} if 'serviceTier' in c else {}))) for c in cases])
grammar=oracle('openai_provider_grammar_reference.mts',dict(model=model,events=tool_events,grammar=prepared[1]['grammar']))
assert prepared[1]['grammar']=={'tool':'program'} and grammar['content'][0]['arguments']=={'program':'alpha'},(prepared[1],grammar)
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith(PIN[:9])
def oracle_case(c,p):
    value=dict(mode=c['oracle'],events=[] if c['mode']==32 else c['events'],statuses=c['statuses'],supplied=c['supplied'],defaultPricing=True,sdkStatusError=True,abortCallerOnIteratorClose=False,preaborted=c.get('preaborted',False),structuredPayload=True,params=p.get('payload'),serviceTier=c.get('serviceTier'),modelId=c.get('modelId'),grammar=p.get('grammar',{}))
    if 'error' in p:value['preparationError']=p['error']
    if c['mode']==31:value['requestError']=c['placeholder']
    return value
reference=oracle('openai_provider_driver_reference.mts',[oracle_case(c,p) for c,p in zip(cases,prepared,strict=True)])['results']
frame=lambda event:('data: '+json.dumps(event,ensure_ascii=False,separators=(',',':'))+'\n\n').encode()
def canonical(line):
    if line.startswith('payload:') and line.endswith(':model'):return 'payload:'+json.dumps(json.loads(line[8:-6]),sort_keys=True,separators=(',',':'))+':model'
    return line
# Native retry entropy, sleeps and the transport are real; the oracle's
# injected `random`, `sleep` and `request:` effects and its emit/close
# bookkeeping are not printed by the fixture.
def wanted_lines(c,r,native_error):
    trace=[l for l in r['trace'] if not (l.startswith(('emit:','sleep ','request:')) or l in ('close','random'))]
    lines=trace+(['dependencies:closed'] if c['mode']!=33 else [])+[f"run:{r['error'] or 'ok'}:cleanup:none"]+r['retained']+[r['final']]
    lines.append('tool:tool:'+json.dumps(grammar['content'][0]['arguments'],separators=(',',':')) if c['mode']==1 else 'tool:none')
    lines+=['timestamp:'+bits(123.0),'payload:7:model','response:model:'+bits(200.0).replace(',',':')+':ok','originals:alive','caller:'+('aborted' if c.get('preaborted') else 'live')]
    if 'placeholder' in c:
        lines=[l.replace(':'+c['placeholder']+':',':'+native_error+':').replace(':error:'+scalars(c['placeholder']),':error:'+scalars(native_error)) for l in lines]
    return list(map(canonical,lines))
runs=[]
fixture=tempfile.TemporaryDirectory(prefix='pi-bend-openai-responses-')
root=Path(fixture.name)
(root/'resolver').write_text('nameserver 127.0.0.1\noptions ndots:1 timeout:1 attempts:1\n')
(root/'hosts').write_text('127.0.0.1 fixture.invalid\n')
(root/'bad-resolver').write_text('options ndots:bad\n')
environment={**os.environ,'RES_OPTIONS':'','LOCALDOMAIN':'','PI_BEND_FILE_TEST_ROOT':str(root)}
for backend in args.backends:
    command=[str(bun),str(program)+'.js'] if backend=='bun' else [str(program),'--threads',backend.split('-')[1]]
    for c,p,r in zip(cases,prepared,reference,strict=True):
        assert r['unhandled'] is None,(c,r)
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
                            assert headers[b'authorization'].strip()==b'bearer fixture-key',(head,body)
                            assert json.loads(body)==(9 if c['mode']==14 else None if c['mode']==15 else p['payload']),(body,p)
                            index=len(requests);requests.append(body.decode());assert index<len(c['statuses']),'extra request'
                            status=c['statuses'][index]
                            if status==200:
                                response=b''.join(map(frame,c['events']))+(b'data: {\n\n' if c['mode']==10 else b'data: {broken\n\n' if c['mode']==32 else b'data: [DONE]\n\n')
                                content_type='text/event-stream'
                            else:response=b'{"error":{"message":"original"}}';content_type='application/json'
                            peer.sendall(f'HTTP/1.1 {status} Response\r\nContent-Type: {content_type}\r\nContent-Length: {len(response)}\r\nx-response: ok\r\n\r\n'.encode())
                            if c['slow']:time.sleep(1.15)
                            peer.sendall(response)
                            peer.shutdown(socket.SHUT_WR)
                            try:assert peer.recv(4096)==b'';peers.append('eof')
                            except ConnectionResetError:peers.append('reset')
                except BaseException as error:errors.append(repr(error))
            thread=threading.Thread(target=serve);thread.start()
            resolver=root/('bad-resolver' if c['mode']==31 else 'resolver')
            started=time.time()*1000
            try:result=subprocess.run(command+[str(c['mode']),str(listener.getsockname()[1]),'yes' if c['supplied'] else 'no',str(resolver),str(root/'hosts')],cwd=ROOT,env=environment,capture_output=True,text=True,timeout=60)
            finally:stop.set();thread.join(timeout=12)
        ended=time.time()*1000
        assert not thread.is_alive() and not errors and len(peers)==len(c['statuses']),(backend,c,errors,peers)
        assert result.returncode==0,(backend,c,result)
        assert sorted(result.stderr.splitlines())==(['AUDIT 0 0 0','TIMERS 0 0'] if args.audit else []),(backend,c,result.stderr)
        actual=list(map(canonical,result.stdout.splitlines()))
        native_error=None
        if 'placeholder' in c:
            run_line=next(l for l in actual if l.startswith('run:'))
            native_error=run_line[len('run:'):-len(':cleanup:none')]
            assert native_error.startswith(c['accept']) and native_error!='ok',(c,run_line)
        wanted=wanted_lines(c,r,native_error)
        if c['mode']==33:
            stamp=next(l for l in actual if l.startswith('timestamp:'))
            high,low=map(int,stamp[len('timestamp:'):].split(','));value=struct.unpack('>d',high.to_bytes(4,'big')+low.to_bytes(4,'big'))[0]
            assert started-1<=value<=ended+1,(started,value,ended)
            wanted=[stamp if l.startswith('timestamp:') else l for l in wanted]
        if actual!=wanted:Path(str(prefix)+'-mismatch.json').write_text(json.dumps(dict(backend=backend,case=c,actual=actual,wanted=wanted),indent=2)+'\n')
        assert actual==wanted,(backend,c['mode'],c['supplied'],actual,wanted)
        runs.append(dict(backend=backend,audited=args.audit,case=c,trace=actual,requests=requests,peers=peers))
    print(backend,len(cases),'OpenAI Responses provider cases PASS',flush=True)
fixture.cleanup()
pending=[ROOT/'tests/openai-responses.bend'];seen=set()
while pending:
    path=pending.pop().resolve()
    if path in seen:continue
    seen.add(path);pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
seen.update([Path(__file__).resolve(),ROOT/'tests/scoped_session_audit.py',ROOT/'tests/channel_audit.py',ROOT/'tests/openai_provider_driver_reference.mts',ROOT/'tests/openai_provider_grammar_reference.mts',ROOT/'tests/responses_prepare_reference.mts',ROOT/'tests/responses_stream_reference.mts'])
seen.update((ROOT.parent/'pi-mono/packages/ai/src').rglob('*.ts'))
deps=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules')
for dependency in ['openai','partial-json']:
    seen.add(deps/dependency/'package.json');seen.update((deps/dependency).rglob('*.js'))
programs=[Path(str(program)+suffix) for suffix in ['','.c','.js'] if Path(str(program)+suffix).exists()]
record=dict(scope=__doc__,reference_commit=reference_commit,prepared=prepared,grammar=grammar,program_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in programs},sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},runs=runs)
Path(str(program)+'-'+','.join(args.backends)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')

"""System-owned provider sessions with real preparation, grammar, hooks and failure cleanup."""
import argparse,ast,hashlib,json,re,socket,subprocess,threading,os,tempfile
from pathlib import Path
from scoped_session_audit import prepare
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--prefix',type=Path,default=ROOT/'build/openai-system-provider')
p.add_argument('--backends',nargs='+',choices=['bun','native-1','native-4'],default=['bun'])
p.add_argument('--audit',action='store_true');p.add_argument('--prepare-audit',action='store_true')
a=p.parse_args();prefix=a.prefix.resolve();program=Path(str(prefix)+('-audit' if a.audit else ''))
if a.prepare_audit:
    native=any(b.startswith('native') for b in a.backends)
    prepare(prefix,ROOT/'build/bend-profiles/dns-transport-teles/bend2',native)
    tree=ast.parse((ROOT/'tests/resolver_file_check.py').read_text())
    audit=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='audit' for t in n.targets))
    if native:
        path=Path(str(prefix)+'-audit.c');path.write_text(path.read_text()+audit)
    path=Path(str(prefix)+'-audit.js')
    path.write_text("""import {readdirSync as auditList,readlinkSync as auditLink} from 'node:fs';
process.on('exit',()=>{let live=0;const root=process.env.PI_BEND_FILE_TEST_ROOT;
for(const fd of auditList('/proc/self/fd')) {try {const target=auditLink('/proc/self/fd/'+fd);if(target===root||target.startsWith(root+'/'))live++;}catch{}}
console.error('FILES '+live);});
"""+path.read_text())
    raise SystemExit
model=dict(id='test',name='Test',api='openai-responses',provider='openai',baseUrl='http://127.0.0.1/v1',reasoning=False,input=['text'],cost=dict(input=1000000,output=2000000,cacheRead=3000000,cacheWrite=4000000),contextWindow=128000,maxTokens=4096,compat=dict(supportsOpenAIGrammarTools=True))
tool=dict(name='tool',description='A tool',parameters=dict(type='object',properties=dict(program=dict(type='string')),required=['program']),constrainedSampling=dict(type='grammar',variants=dict(openai_lark='start: /[a-z]+/')))
messages=[dict(role='system',content='initial',toolsAdded=[tool],timestamp=1),dict(role='user',content='hello',timestamp=1)]
def oracle(name,value):return json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/'+name],cwd=ROOT,input=json.dumps(value),text=True))
prepared=oracle('responses_prepare_reference.mts',[dict(model=model,messages=messages,options=dict(apiKey='fixture-key',env={}))])[0]
assert prepared['grammar']=={'tool':'program'},prepared
item=dict(type='custom_tool_call',id='ct',call_id='call',name='tool',input='')
def event(kind,**kw):return dict(type='response.'+kind,**kw)
events=[event('created',response=dict(id='r')),event('output_item.added',output_index=0,item=item),event('custom_tool_call_input.delta',output_index=0,delta='al'),event('custom_tool_call_input.done',output_index=0,input='alpha'),event('output_item.done',output_index=0,item={**item,'input':'alpha'}),event('completed',response=dict(id='r',status='completed'))]
reference=oracle('openai_provider_grammar_reference.mts',dict(model=model,events=events,grammar=prepared['grammar']))
assert len(reference['content'])==1 and reference['content'][0]['arguments']=={'program':'alpha'},reference
missing_grammar=oracle('openai_provider_grammar_reference.mts',dict(model=model,events=events,grammar={}))
assert missing_grammar['content'][0]['arguments']!=reference['content'][0]['arguments']
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit=='46c9de402bddf46b03c3b9f46487b777aaa41861'
runs=[]
fixture=tempfile.TemporaryDirectory(prefix='pi-bend-system-provider-')
root=Path(fixture.name)
(root/'resolver').write_text('nameserver 127.0.0.1\noptions ndots:1 timeout:1 attempts:1\n')
(root/'hosts').write_text('127.0.0.1 fixture.invalid\n')
(root/'bad-resolver').write_text('options ndots:bad\n')
os.mkfifo(root/'blocked')
environment={**os.environ,'RES_OPTIONS':'','LOCALDOMAIN':'','PI_BEND_FILE_TEST_ROOT':str(root)}
for backend in a.backends:
    command=[str(Path.home()/'.bun/bin/bun'),str(program)+'.js'] if backend=='bun' else [str(program),'--threads',backend.split('-')[1]]
    for mode in [0,14,15,2,3,22,30,31,32]:
        for supplied in [False,True]:
            expected_request=mode not in [2,22,30,31];errors=[];bodies=[];closed=[];stop=threading.Event()
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(.1)
                def serve():
                    try:
                        while not stop.is_set():
                            try:peer,_=listener.accept()
                            except socket.timeout:continue
                            with peer:
                                peer.settimeout(10);raw=b''
                                while b'\r\n\r\n' not in raw:
                                    chunk=peer.recv(4096);assert chunk;raw+=chunk
                                head,body=raw.split(b'\r\n\r\n',1)
                                assert head.startswith(b'POST /v1/responses HTTP/1.1\r\n')
                                headers=dict(x.lower().split(b':',1) for x in head.split(b'\r\n')[1:]);size=int(headers[b'content-length'])
                                while len(body)<size:
                                    chunk=peer.recv(4096);assert chunk;body+=chunk
                                value=json.loads(body);bodies.append(value)
                                assert value==(9 if mode==14 else None if mode==15 else prepared['payload']),value
                                assert headers[b'authorization'].strip()==b'bearer fixture-key'
                                response=b'data: {broken\n\n' if mode==32 else ''.join('data: '+json.dumps(e)+'\n\n' for e in events).encode()+b'data: [DONE]\n\n'
                                peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nx-response: ok\r\nContent-Length: '+str(len(response)).encode()+b'\r\n\r\n'+response);peer.shutdown(socket.SHUT_WR)
                                try:assert peer.recv(4096)==b'';closed.append('eof')
                                except ConnectionResetError:closed.append('reset')
                    except BaseException as e:errors.append(repr(e))
                thread=threading.Thread(target=serve);thread.start()
                resolver=root/('blocked' if mode in [2,22,30] else 'bad-resolver' if mode==31 else 'resolver')
                hosts=root/('blocked' if mode in [2,22,30,31] else 'hosts')
                try:run=subprocess.run(command+[str(mode),str(listener.getsockname()[1]),'yes' if supplied else 'no',str(resolver),str(hosts)],cwd=ROOT,env=environment,capture_output=True,text=True,timeout=30)
                finally:stop.set();thread.join(12)
            assert not thread.is_alive() and not errors,(backend,mode,errors)
            assert len(bodies)==int(expected_request) and len(closed)==len(bodies),(mode,bodies,closed)
            assert run.returncode==0,(mode,run)
            assert sorted(run.stderr.splitlines())==(['AUDIT 0 0 0','FILES 0','TIMERS 0 0'] if a.audit else []),run.stderr
            lines=run.stdout.splitlines();assert lines[-4:]==['payload:7:model','response:model:1080623104:0:ok','originals:alive','caller:live'],lines
            if mode in [0,14,15]:
                assert 'tool:tool:'+json.dumps(reference['content'][0]['arguments'],separators=(',',':')) in lines,lines
                assert 'run:ok:cleanup:none:delivery:none' in lines,lines
                assert [x[6:] for x in lines if x.startswith('event:')]==['start']+reference['events']+['done'],lines
            else:assert 'tool:none' in lines and any(x.startswith('run:') and not x.startswith('run:ok:') for x in lines),lines
            assert len([x for x in lines if x.startswith('payload:')])==(1 if mode in [22,30] else 2),lines
            assert len([x for x in lines if x.startswith('response:')])==(2 if expected_request else 1),lines
            assert lines.count('dependencies:closed')==1 and lines.index('dependencies:closed')<next(i for i,x in enumerate(lines) if x.startswith('run:')),lines
            if mode==31:assert 'run:system configuration:cleanup:none:delivery:none' in lines,lines
            if mode==32:assert 'run:json:cleanup:none:delivery:none' in lines and lines.count('diagnostic')==1 and lines.count('abort-hook')==1,lines
            runs.append(dict(backend=backend,audited=a.audit,mode=mode,supplied=supplied,trace=lines,requests=bodies,closed=closed))
    print(backend,'18 system provider cases PASS',flush=True)
fixture.cleanup()
pending=[ROOT/'tests/openai-system-provider.bend'];seen=set()
while pending:
    path=pending.pop().resolve()
    if path in seen:continue
    seen.add(path);pending.extend(path.parent/n for n in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
seen.update([Path(__file__).resolve(),ROOT/'tests/openai_provider_grammar_reference.mts',ROOT/'tests/responses_stream_reference.mts',ROOT/'tests/responses_prepare_reference.mts',ROOT/'tests/scoped_session_audit.py',ROOT/'tests/channel_audit.py',ROOT/'tests/resolver_file_check.py'])
seen.update((ROOT.parent/'pi-mono/packages/ai/src').rglob('*.ts'))
dependency=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/partial-json')
seen.add(dependency/'package.json');seen.update(dependency.rglob('*.js'))
record=dict(reference_commit=reference_commit,scope=__doc__,sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)},prepared=prepared,reference=reference,missing_grammar_control=missing_grammar,runs=runs,program_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [program,Path(str(program)+'.c'),Path(str(program)+'.js')] if p.exists()})
Path(str(program)+'-'+','.join(a.backends)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')

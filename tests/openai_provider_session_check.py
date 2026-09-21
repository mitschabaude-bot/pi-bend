"""Owned asynchronous Responses session over HTTP/SSE and canonical stream consumers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import threading
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--worktree', type=Path, default=ROOT)
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--prefix', type=Path, default=Path('build/openai-provider-session'))
parser.add_argument('--backends', nargs='+', choices=['native-1','native-4','bun'], default=['native-1','native-4','bun'])
args = parser.parse_args()
WORK = args.worktree.resolve()
BEND = Path(os.environ.get('BEND', ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts')).resolve()
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'tests/openai-provider-session.bend'
prefix = WORK / args.prefix
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '32',
                            '--stats', f'{prefix}-{backend}-build.json', '--', str(BEND), SOURCE, '-o', f'{prefix}.{backend}'],
                           cwd=WORK, check=True, stdout=log, stderr=subprocess.STDOUT)

if any(b.startswith('native') for b in args.backends):
    c = Path(f'{prefix}.c').read_text()
    Path(f'{prefix}-audit.c').write_text(c + r'''
    static void __attribute__((destructor)) openai_http_reader_audit(void) {
      unsigned channels=0,sockets=0;
      for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
      for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
      fprintf(stderr,"AUDIT %u %u %u\n",channels,io_park.head!=NULL,sockets);
    }
    ''')
Path(f'{prefix}-audit.js').write_text(instrument(Path(f'{prefix}.js').read_text()))
# Production and audit compilation are independent; inspect both exits.
compilers = [subprocess.Popen(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{prefix}{suffix}.c',
                              '-lpthread', '-lm', '-o', str(prefix) + suffix], cwd=WORK)
             for suffix in (['', '-audit'] if any(b.startswith('native') for b in args.backends) else [])]
compile_exits = [process.wait() for process in compilers]
assert all(code == 0 for code in compile_exits), compile_exits

def frame(value):
    return ('data: '+json.dumps(value,ensure_ascii=False,separators=(',',':'))+'\n\n').encode()
created={'type':'response.created','response':{'id':'resp-test'}}
item={'type':'message','id':'msg-test','role':'assistant','content':[]}
added={'type':'response.output_item.added','output_index':0,'item':item}
delta={'type':'response.output_text.delta','output_index':0,'delta':'hé🙂'}
ended={'type':'response.output_item.done','output_index':0,'item':{**item,'content':[{'type':'output_text','text':'hé🙂'}]}}
completed={'type':'response.completed','response':{'id':'resp-final','status':'completed','usage':{'input_tokens':20,'output_tokens':5,'total_tokens':25,'input_tokens_details':{'cached_tokens':3,'cache_write_tokens':2}}}}
incomplete={'type':'response.incomplete','response':{'id':'resp-final','status':'incomplete','incomplete_details':{'reason':'max_output_tokens'}}}
failed={'type':'response.failed','response':{'status':'failed','error':{'code':'failed','message':'failed'}}}
normal=[created,added,delta,ended,completed]
partial=[created,added,delta]
cases=[]
for mode in [0,1,2,3,8,9,10,11,12,13,14,15,16,17,18]:
    statuses=[] if mode==2 else [400] if mode==1 else [429,429,429] if mode==13 else [429,200] if mode==14 else [200]
    events=partial if mode in [7,9,10] else partial+[failed] if mode in [11,16] else partial+[incomplete] if mode==18 else normal
    cases.append({'mode':mode,'statuses':statuses,'events':events})
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith('46c9de402')
reference=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning',str(ROOT/'tests/openai_provider_driver_reference.mts')],input=json.dumps(cases),cwd=ROOT,text=True))
assert len(reference['results'])==len(cases)
runs=[]
for audited in [False,True]:
    suffix='-audit' if audited else ''
    for backend,command in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[BUN,str(prefix)+suffix+'.js'])]:
        if backend not in args.backends:continue
        for case,original in zip(cases,reference['results'],strict=True):
            mode=case['mode'];trace=[line for line in original['trace'] if not line.startswith('emit:') and line!='close'];retained=list(original['retained']);adaptations=[]
            if mode==3:
                trace.append('release');adaptations.append('Retire unread acquired response when the response hook fails.')
            assert original['unhandled'] is None
            cleanup='cleanup' if mode in [11,12] else 'none'
            error=original['error'] or 'ok'
            if mode in [11,12]:adaptations.append('Inject cleanup failure after actual retirement; retain it separately from the primary cause.')
            wanted=trace+[f'run:{error}:cleanup:{cleanup}:delivery:none']+retained+[original['final']]
            errors,peers=[],[]
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(15)
                def serve():
                    try:
                        for status in case['statuses']:
                            with listener.accept()[0] as peer:
                                peer.settimeout(15);request=b''
                                while b'\r\n\r\n' not in request:
                                    part=peer.recv(4096)
                                    if not part:raise AssertionError('request truncated')
                                    request+=part
                                head,body=request.split(b'\r\n\r\n',1)
                                assert head.startswith(b'POST /responses HTTP/1.1\r\n'),head
                                fields=dict(line.lower().split(b': ',1) for line in head.split(b'\r\n')[1:])
                                assert fields[b'content-type']==b'application/json'
                                length=int(fields[b'content-length'])
                                while len(body)<length:
                                    part=peer.recv(4096)
                                    if not part:raise AssertionError('request body truncated')
                                    body+=part
                                assert len(body)==length
                                payload=b''.join(map(frame,case['events']))+(b'data: {\n\n' if mode==10 else b'data: [DONE]\n\n') if 200<=status<300 else b'bad'
                                wire=f'HTTP/1.1 {status} Fixture\r\nContent-Type: text/event-stream\r\nx-response: ok\r\nContent-Length: {len(payload)}\r\n\r\n'.encode()+payload
                                peer.sendall(wire);peer.shutdown(socket.SHUT_WR)
                                try:
                                    assert peer.recv(4096)==b'';closure='eof'
                                except ConnectionResetError:closure='reset'
                                peers.append({'payload':body.decode(),'closure':closure})
                    except BaseException as error:errors.append(repr(error))
                thread=threading.Thread(target=serve);thread.start()
                try:
                    result=subprocess.run(command+[str(listener.getsockname()[1]),str(mode)],cwd=WORK,text=True,capture_output=True,timeout=45,check=True)
                finally:thread.join(timeout=17)
                assert not thread.is_alive() and not errors and [p['payload'] for p in peers]==original['sent'],(backend,mode,errors,peers,original['sent'])
            actual=result.stdout.splitlines()
            if actual!=wanted:
                (ROOT/'build/openai-provider-session-mismatch.json').write_text(json.dumps({'backend':backend,'mode':mode,'actual':actual,'expected':wanted},indent=2)+'\n')
            assert actual==wanted,(backend,mode,actual,wanted)
            assert result.stderr==('AUDIT 0 0 0\n' if audited else ''),(backend,mode,result.stderr)
            runs.append({'backend':backend,'audited':audited,'mode':mode,'peers':peers,'passed':True,'adaptations':adaptations})
        print(backend,'audit' if audited else 'production',len(cases),'owned provider session cases PASS',flush=True)

pending,visited=[WORK/SOURCE],set()
while pending:
    path=pending.pop().resolve()
    if path in visited:continue
    visited.add(path)
    pending += [path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.MULTILINE)]
base=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
changed={'packages/ai/src/api/openai-responses-session.bend',SOURCE}
for path in visited:
    name=str(path.relative_to(WORK));expected=(ROOT/name).read_bytes() if name in changed else subprocess.check_output(['git','show',base+':'+name],cwd=ROOT)
    assert path.read_bytes()==expected,name
record={
 'scope':'Owned asynchronous Responses session composes the canonical driver/hooks/retries, real HTTP/SSE processing and concurrent canonical stream consumers. Actual pinned wrapper/processor oracle, explicit cleanup adaptations, nonfailing canonical publication. Test-selected string presentation of typed internal causes; no complete serialized provider/auth/TLS/TUI claim.',
 'reference_commit':reference_commit,'reference':reference,
 'validated_checkout':{'base_commit':base,'changed_files':sorted(changed),'pending_form_drafts_included':False},
 'runs':runs,
 'source_sha256':{str(path.relative_to(WORK)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
 'harness_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),ROOT/'tests/channel_audit.py',ROOT/'tests/openai_provider_driver_reference.mts',ROOT/'tests/responses_stream_reference.mts']},
 'program_sha256':{suffix:hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in (['', '.c','.js','-audit','-audit.c','-audit.js'] if any(b.startswith('native') for b in args.backends) else ['.js','-audit.js'])},
 'compiler_command':str(BEND),
 'compiler_sha256':{name:hashlib.sha256((BEND.parent/name).read_bytes()).hexdigest() for name in ['main.ts','bend.ts','comp.ts','base.bend']},
 'builds':{backend:json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c','js'] if (backend=='js' and 'bun' in args.backends) or (backend=='c' and any(b.startswith('native') for b in args.backends))},
}
Path(str(prefix)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')

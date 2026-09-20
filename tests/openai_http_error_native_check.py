"""Native HTTP error-body consumption composed with typed OpenAI diagnostics."""
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
args = parser.parse_args()
WORK = args.worktree.resolve()
BEND = Path(os.environ.get('BEND', ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts')).resolve()
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'tests/openai-http-error-native.bend'
prefix = WORK / 'build/openai-http-error-native'
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '24',
                            '--stats', f'{prefix}-{backend}-build.json', '--', str(BEND), SOURCE, '-o', f'{prefix}.{backend}'],
                           cwd=WORK, check=True, stdout=log, stderr=subprocess.STDOUT)

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
for suffix in ['', '-audit']:
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{prefix}{suffix}.c',
                    '-lpthread', '-lm', '-o', str(prefix) + suffix], cwd=WORK, check=True)



def scalars(text): return ','.join(str(ord(c)) for c in text)
def wire(status,payload,headers=b'',extra=0):
    return f'HTTP/1.1 {status} Fixture\r\nContent-Length: {len(payload)+extra}\r\n'.encode()+headers+b'\r\n'+payload

def compact(value):return json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()
normal=[
 ('gateway-string',403,'openai',compact({'error':'blocked by gateway WAF'})),
 ('structured',400,'openai',compact({'error':{'message':'invalid tools','code':'bad','param':'tools','type':'invalid_request_error'}})),
 ('openrouter-extra',403,'openrouter',compact({'error':{'message':'Provider returned error','code':403,'metadata':{'raw':'upstream WAF blocked policy XYZ'}}})),
 ('html',403,'openai',b'<html>gateway blocked</html>'),
 ('unicode',400,'openai',compact({'error':{'message':'é🙂'}})),
 ('rate-limit',429,'openai',compact({'error':{'message':'retry later','code':'rate_limit'}})),
 ('server-error',500,'openai',compact({'error':{'message':'server unavailable'}})),
 ('bom',401,'openai',b'\xef\xbb\xbf'+compact({'error':{'message':'authentication failed'}})),
]
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith('46c9de402')
reference=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning',str(ROOT/'tests/openai_http_error_reference.mts')],input=json.dumps([dict(status=status,provider=provider,id='native-id',raw=payload.decode('utf-8-sig')) for _,status,provider,payload in normal]),cwd=ROOT,text=True))
cases=[]
for (name,status,provider,payload),trace in zip(normal,reference['results'],strict=True):
    cases.append((name,provider,10000,wire(status,payload,b'x-request-id: native-id\r\n'),trace[1:]))
payload=normal[4][-1]
chunked=b'HTTP/1.1 400 Bad\r\nTransfer-Encoding: chunked\r\nx-request-id: native-id\r\n\r\n'+b''.join(b'1\r\n'+bytes([x])+b'\r\n' for x in payload)+b'0\r\n\r\n'
cases.append(('chunked-unicode','openai',10000,chunked,reference['results'][4][1:]))
cases += [
 ('success','openai',0,wire(200,b'ok'),['accepted:200','text:111,107']),
 ('no-content','openai',0,b'HTTP/1.1 204 No Content\r\n\r\n',['accepted:204','text:']),
 ('invalid-utf8','openai',100,wire(500,b'\xc0\xaf'),['read-error:500:utf8']),
 ('truncated','openai',100,wire(500,b'a',extra=10),['read-error:500:transport']),
 ('limit','openai',1,wire(429,b'long'),['read-error:429:limit']),
 ('unrecognized-json','openai',100,wire(500,b'{"message":"gateway"}'),['kind:InternalServerError','status:500','request-id:none','code:none','param:none','type:none','message:'+scalars('500 gateway'),'format:'+scalars('OpenAI API error (500): {"message":"gateway"}')]),
]
runs=[]
for audited in [False,True]:
    suffix='-audit' if audited else ''
    for backend,command in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[BUN,str(prefix)+suffix+'.js'])]:
        for name,provider,limit,response,wanted in cases:
            errors,peers=[],[]
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(10)
                def serve():
                    try:
                        with listener.accept()[0] as peer:
                            peer.settimeout(10);request=b''
                            while b'\r\n\r\n' not in request:
                                part=peer.recv(4096)
                                if not part: raise AssertionError('request truncated')
                                request+=part
                            assert request.startswith(b'GET /error HTTP/1.1\r\n'),request
                            peer.sendall(response);peer.shutdown(socket.SHUT_WR)
                            assert peer.recv(4096)==b''
                            peers.append('closed')
                    except BaseException as error: errors.append(repr(error))
                thread=threading.Thread(target=serve);thread.start()
                try:
                    result=subprocess.run(command+[str(listener.getsockname()[1]),provider,str(limit)],cwd=WORK,text=True,capture_output=True,timeout=30,check=True)
                finally: thread.join(timeout=12)
                assert not thread.is_alive() and not errors and peers==['closed'],(backend,name,errors,peers)
            assert result.stdout.splitlines()==wanted,(backend,name,result.stdout,wanted)
            assert result.stderr==('AUDIT 0 0 0\n' if audited else ''),(backend,name,result.stderr)
            runs.append({'backend':backend,'audited':audited,'case':name,'peers':peers,'passed':True})
        print(backend,'audit' if audited else 'production',len(cases),'OpenAI HTTP error cases PASS',flush=True)

pending,visited=[WORK/SOURCE],set()
while pending:
    path=pending.pop().resolve()
    if path in visited:continue
    visited.add(path)
    pending += [path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.MULTILINE)]
base=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
new_files={'packages/ai/src/api/openai-http-error.bend','packages/ai/src/utils/error-body.bend','packages/ai/test/openai-http-error.bend','packages/runtime/src/text-unit-budget.bend',SOURCE}
for path in visited:
    name=str(path.relative_to(WORK))
    expected_source=(ROOT/name).read_bytes() if name in new_files else subprocess.check_output(['git','show',base+':'+name],cwd=ROOT)
    assert path.read_bytes()==expected_source,name
record={
 'scope':'Real native HTTP error diagnostic consumption composed with typed OpenAI APIError and existing pi normalization. Fifteen cases, SDK/pi oracle for ordinary errors, native/Bun resource audits and peer-observed retirement. No authenticated request/provider stream or full coding agent.',
 'reference_commit':reference_commit,'reference':reference,
 'validated_checkout':{'base_commit':base,'new_files':sorted(new_files),'pending_form_drafts_included':False},
 'runs':runs,
 'source_sha256':{str(path.relative_to(WORK)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
 'harness_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),ROOT/'tests/channel_audit.py',ROOT/'tests/openai_http_error_reference.mts']},
 'program_sha256':{suffix:hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c','.js','-audit','-audit.c','-audit.js']},
 'compiler_command':str(BEND),
 'compiler_sha256':{name:hashlib.sha256((BEND.parent/name).read_bytes()).hexdigest() for name in ['main.ts','bend.ts','comp.ts','base.bend']},
 'builds':{backend:json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c','js']},
}
(ROOT/'build/openai-http-error-native-results.json').write_text(json.dumps(record,indent=2)+'\n')

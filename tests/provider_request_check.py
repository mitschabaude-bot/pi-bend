"""Provider payload/response hooks around the native HTTP retry boundary."""
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
SOURCE = 'tests/provider-request.bend'
prefix = WORK / 'build/provider-request'
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


def response(status=200, extra=()):
    return {'status':status,'headers':[['x-response','ok'],*extra]}
cases=[
 {'mode':0,'responses':[response()]},
 {'mode':1,'responses':[response()]},
 {'mode':2,'responses':[response(429),response(429),response()]},
 {'mode':3,'responses':[response()]},
 {'mode':4,'responses':[]},
 {'mode':5,'responses':[response()]},
 {'mode':6,'responses':[response()]},
 {'mode':7,'responses':[response(429),response(429),response(429)]},
 {'mode':8,'responses':[response()]},
 {'mode':9,'responses':[response()]},
 {'mode':10,'responses':[response()]},
 {'mode':11,'responses':[response(201,[['x-response','extra']])]},
 {'mode':12,'responses':[response(400)]},
 {'mode':13,'responses':[response(500),response()]},
]
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith('46c9de402')
reference=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning',str(ROOT/'tests/provider_request_reference.mts')],input=json.dumps(cases),cwd=ROOT,text=True))
assert len(reference['results'])==len(cases)
runs=[]
for audited in [False,True]:
    suffix='-audit' if audited else ''
    for backend,command in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[BUN,str(prefix)+suffix+'.js'])]:
        for case,original in zip(cases,reference['results'],strict=True):
            mode=case['mode'];wanted=list(original['trace']);outcome=original['outcome']
            if outcome=='success':wanted+=['accepted','text:111,107']
            elif outcome=='payload':wanted+=['failed:payload:payload']
            elif outcome=='request':wanted+=['provider original']
            else:wanted+=['release','failed:response:response:'+('cleanup' if mode==6 else 'ok')]
            errors,peers=[],[]
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(10)
                def serve():
                    try:
                        for response in case['responses']:
                            with listener.accept()[0] as peer:
                                peer.settimeout(10);request=b''
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
                                payload=b'ok' if 200<=response['status']<300 else b'bad'
                                wire=f"HTTP/1.1 {response['status']} Fixture\r\nContent-Length: {len(payload)}\r\n".encode()+b''.join(f'{k}: {v}\r\n'.encode() for k,v in response['headers'])+b'\r\n'+payload
                                peer.sendall(wire);peer.shutdown(socket.SHUT_WR)
                                assert peer.recv(4096)==b''
                                peers.append(body.decode())
                    except BaseException as error:errors.append(repr(error))
                thread=threading.Thread(target=serve);thread.start()
                try:
                    result=subprocess.run(command+[str(listener.getsockname()[1]),str(mode)],cwd=WORK,text=True,capture_output=True,timeout=30,check=True)
                finally:thread.join(timeout=12)
                assert not thread.is_alive() and not errors and peers==original['sent'],(backend,mode,errors,peers,original['sent'])
            assert result.stdout.splitlines()==wanted,(backend,mode,result.stdout,wanted)
            assert result.stderr==('AUDIT 0 0 0\n' if audited else ''),(backend,mode,result.stderr)
            runs.append({'backend':backend,'audited':audited,'mode':mode,'peers':peers,'passed':True})
        print(backend,'audit' if audited else 'production',len(cases),'provider request cases PASS',flush=True)

pending,visited=[WORK/SOURCE],set()
while pending:
    path=pending.pop().resolve()
    if path in visited:continue
    visited.add(path)
    pending += [path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.MULTILINE)]
base=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
new_files={'packages/ai/src/utils/provider-request.bend','packages/ai/src/utils/provider-response-view.bend',SOURCE}
for path in visited:
    name=str(path.relative_to(WORK))
    expected_source=(ROOT/name).read_bytes() if name in new_files else subprocess.check_output(['git','show',base+':'+name],cwd=ROOT)
    assert path.read_bytes()==expected_source,name
record={
 'scope':'Canonical payload/response hooks surrounding the existing affine retry loop with real HTTP uploads and owned response handoff. Exact pinned pi request-stage and retry traces plus explicit native body-retirement/result markers. Hook-failure owner retirement and cleanup reporting improve the upstream unconsumed-stream path. No complete provider stream/authentication/TUI claim.',
 'reference_commit':reference_commit,'reference':reference,
 'validated_checkout':{'base_commit':base,'new_files':sorted(new_files),'pending_form_drafts_included':False},
 'runs':runs,
 'source_sha256':{str(path.relative_to(WORK)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
 'harness_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),ROOT/'tests/channel_audit.py',ROOT/'tests/provider_request_reference.mts']},
 'program_sha256':{suffix:hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c','.js','-audit','-audit.c','-audit.js']},
 'compiler_command':str(BEND),
 'compiler_sha256':{name:hashlib.sha256((BEND.parent/name).read_bytes()).hexdigest() for name in ['main.ts','bend.ts','comp.ts','base.bend']},
 'builds':{backend:json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c','js']},
}
(ROOT/'build/provider-request-results.json').write_text(json.dumps(record,indent=2)+'\n')

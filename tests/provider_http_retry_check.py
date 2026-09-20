"""Native HTTP status handling composed with affine retries and response consumption."""
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
SOURCE = 'tests/provider-http-retry.bend'
prefix = WORK / 'build/provider-http-retry'
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
def sleep(ms):
    import struct
    high,low=struct.unpack('>II',struct.pack('>d',ms))
    return f'sleep {high}:{low}'
def wire(status, body=b'', headers=b'', extra=0):
    return f'HTTP/1.1 {status} Fixture\r\nContent-Length: {len(body)+extra}\r\n'.encode()+headers+b'\r\n'+body
ok=wire(200,b'ok')
accepted=['request','accepted:200','text:'+scalars('ok')]
def diagnostic(status,text): return ['request',f'diagnostic:{status}:'+scalars(text)]
backoff=['random',sleep(500)]
cases=[
 ('success', [ok], 2, 0, accepted),
 ('success-ignores-retry', [wire(200,b'ok',b'x-should-retry: true\r\n')],2,0,accepted),
 ('429-then-success',[wire(429,b'busy'),ok],2,100,diagnostic(429,'busy')+backoff+accepted),
 ('500-then-success',[wire(500,b'busy'),ok],2,100,diagnostic(500,'busy')+backoff+accepted),
 ('400-terminal',[wire(400,b'bad')],2,100,diagnostic(400,'bad')+['failed:status']),
 ('400-forced',[wire(400,b'bad',b'x-should-retry: true\r\n'),ok],2,100,diagnostic(400,'bad')+backoff+accepted),
 ('500-disabled',[wire(500,b'bad',b'x-should-retry: false\r\n')],2,100,diagnostic(500,'bad')+['failed:status']),
 ('exhausted',[wire(429,b'a'),wire(429,b'b')],1,100,diagnostic(429,'a')+backoff+diagnostic(429,'b')+['failed:status']),
 ('retry-ms',[wire(429,b'',b'retry-after-ms: 25\r\n'),ok],1,100,diagnostic(429,'')+[sleep(25)]+accepted),
 ('retry-seconds',[wire(429,b'',b'retry-after: 2\r\n'),ok],1,100,diagnostic(429,'')+[sleep(2000)]+accepted),
 ('no-content',[b'HTTP/1.1 204 No Content\r\n\r\n'],1,0,['request','accepted:204','text:']),
 ('invalid-diagnostic',[wire(429,b'\xc0\xaf')],2,100,['request','diagnostic-error:429:utf8','failed:diagnostic-or-transport']),
 ('limited-diagnostic',[wire(429,b'long')],2,1,['request','diagnostic-error:429:limit','failed:diagnostic-or-transport']),
 ('truncated-diagnostic',[wire(429,b'a',extra=10)],2,100,['request','diagnostic-error:429:transport','failed:diagnostic-or-transport']),
 ('successful-truncation',[wire(200,b'a',extra=10)],2,0,['request','accepted:200','error:transport']),
]
# Compare ordinary HTTP statuses/body reads with the actual SDK and pi loop.
# Malformed-body cases deliberately retain typed failures instead of SDK strings.
reference_cases=[]
for name,responses,retries,limit,wanted in cases[:11]:
    items=[]
    for response in responses:
        head,body=response.split(b'\r\n\r\n',1)
        lines=head.decode().split('\r\n')
        items.append({'status':int(lines[0].split()[1]),'body':body.hex(),
                      'headers':[line.split(': ',1) for line in lines[1:]]})
    reference_cases.append({'name':name,'responses':items,'retries':retries})
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith('46c9de402')
reference=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning',str(ROOT/'tests/provider_http_retry_reference.mts')],input=json.dumps(reference_cases),cwd=ROOT,text=True))
for case,observed in zip(cases[:11],reference['results'],strict=True):
    assert observed=={'name':case[0],'trace':case[-1]},(case[0],observed,case[-1])

runs=[]
for audited in [False,True]:
    suffix='-audit' if audited else ''
    for backend,command in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[BUN,str(prefix)+suffix+'.js'])]:
        for name,responses,retries,limit,wanted in cases:
            errors,peers=[],[]
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(10)
                def serve():
                    try:
                        for response in responses:
                            with listener.accept()[0] as peer:
                                peer.settimeout(10);request=b''
                                while b'\r\n\r\n' not in request:
                                    part=peer.recv(4096)
                                    if not part: raise AssertionError('request truncated')
                                    request+=part
                                assert request.startswith(b'GET /retry HTTP/1.1\r\n'),request
                                peer.sendall(response)
                                peer.shutdown(socket.SHUT_WR)
                                # Finish this owner before accepting the next attempt.
                                assert peer.recv(4096)==b''
                                peers.append('closed')
                    except BaseException as error: errors.append(repr(error))
                thread=threading.Thread(target=serve);thread.start()
                try:
                    result=subprocess.run(command+[str(listener.getsockname()[1]),str(retries),str(limit)],cwd=WORK,text=True,capture_output=True,timeout=30,check=True)
                finally: thread.join(timeout=12)
                assert not thread.is_alive() and not errors and peers==['closed']*len(responses),(backend,name,errors,peers)
            assert result.stdout.splitlines()==wanted,(backend,name,result.stdout,wanted)
            assert result.stderr==('AUDIT 0 0 0\n' if audited else ''),(backend,name,result.stderr)
            runs.append({'backend':backend,'audited':audited,'case':name,'requests':len(responses),'peers':peers,'passed':True})
        print(backend,'audit' if audited else 'production',len(cases),'HTTP retry cases PASS',flush=True)

pending,visited=[WORK/SOURCE],set()
while pending:
    path=pending.pop().resolve()
    if path in visited:continue
    visited.add(path)
    pending += [path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.MULTILINE)]
base=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
new_files={'packages/ai/src/utils/provider-http-response.bend',SOURCE}
for path in visited:
    name=str(path.relative_to(WORK))
    expected_source=(ROOT/name).read_bytes() if name in new_files else subprocess.check_output(['git','show',base+':'+name],cwd=ROOT)
    assert path.read_bytes()==expected_source,name
record={
 'scope':'Real native HTTP requests, owned status adapter, existing affine retry loop and successful text consumption. Fifteen fixed IO contracts, peer-observed close per attempt and process-exit resource audits. Diagnostic read failures use a fixture-supplied terminal policy; complete provider error normalization and real retry timer scheduling are outside this test.',
 'reference_commit':reference_commit,
 'reference':reference,
 'validated_checkout':{'base_commit':base,'new_files':sorted(new_files),'pending_form_drafts_included':False},
 'runs':runs,
 'source_sha256':{str(path.relative_to(WORK)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
 'harness_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),ROOT/'tests/channel_audit.py',ROOT/'tests/provider_http_retry_reference.mts']},
 'program_sha256':{suffix:hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c','.js','-audit','-audit.c','-audit.js']},
 'compiler_command':str(BEND),
 'compiler_sha256':{name:hashlib.sha256((BEND.parent/name).read_bytes()).hexdigest() for name in ['main.ts','bend.ts','comp.ts','base.bend']},
 'builds':{backend:json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c','js']},
}
(ROOT/'build/provider-http-retry-results.json').write_text(json.dumps(record,indent=2)+'\n')

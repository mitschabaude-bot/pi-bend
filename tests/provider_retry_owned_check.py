"""Affine retry-result transfer through real TCP sockets, with pi effect-trace oracle."""
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
SOURCE = 'tests/provider-retry-owned.bend'
prefix = WORK / 'build/provider-retry-owned'
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '16',
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

reference_commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()
assert reference_commit.startswith('46c9de402'), reference_commit
original = json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/provider_retry_reference.mts'],cwd=ROOT,text=True))
assert len(original)==12
cases=[]
for mode, trace in enumerate(original):
    lines=trace.splitlines(); requests=lines.count('request'); successful=lines[-1]=='done ok'
    expected=[]; count=0
    for line in lines:
        expected.append(line)
        if line=='request':
            count+=1
            expected.append('acquired' if successful and count==requests else 'attempt-close')
    cases.append((mode,requests,successful,expected))
runs = []
for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for backend, command in [
        ('native-1', [str(prefix) + suffix, '--threads', '1']),
        ('native-4', [str(prefix) + suffix, '--threads', '4']),
        ('bun', [BUN, str(prefix) + suffix + '.js']),
    ]:
        for mode, requests, successful, wanted in cases:
            errors, peers = [], []
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0)); listener.listen(); listener.settimeout(10)
                def serve():
                    try:
                        for _ in range(requests):
                            with listener.accept()[0] as peer:
                                peer.settimeout(10); data=b''
                                while True:
                                    part=peer.recv(4096)
                                    if not part: break
                                    data+=part
                                peers.append(data.decode())
                    except BaseException as error:
                        errors.append(repr(error))
                thread=threading.Thread(target=serve); thread.start()
                try:
                    result=subprocess.run(command+[str(listener.getsockname()[1]),str(mode)],cwd=WORK,text=True,capture_output=True,check=True,timeout=20)
                finally:
                    thread.join(timeout=12)
                expected_peers=['']*requests
                if successful: expected_peers[-1]='owned'
                assert not thread.is_alive() and not errors and peers==expected_peers,(backend,mode,errors,peers,expected_peers)
            assert result.stdout.splitlines()==wanted,(backend,mode,result.stdout,wanted)
            assert result.stderr == ('AUDIT 0 0 0\n' if audited else ''), (backend, mode, result.stderr)
            runs.append({'backend':backend,'audited':audited,'mode':mode,'requests':requests,'peers':peers,'passed':True})
        print(backend,'audited' if audited else 'production',len(cases),'affine socket retry cases PASS',flush=True)

pending, visited = [WORK / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=WORK, text=True).strip()
new_files = {'packages/ai/src/utils/provider-retry.bend', SOURCE}
for path in visited:
    name = str(path.relative_to(WORK))
    reference = (ROOT / name).read_bytes() if name in new_files else subprocess.check_output(['git', 'show', base + ':' + name], cwd=WORK)
    assert path.read_bytes() == reference, name
record = {
    'scope': 'Shared retry loop transfers an affine real socket only on success; failing attempts close their sockets before retry. Twelve pi-source effect traces plus explicit acquisition/close markers, native/Bun resource audits and peer-observed payload/EOF. This is retry ownership evidence, not HTTP status policy integration.',
    'reference_commit': reference_commit,
    'original_traces': original,
    'validated_checkout': {'base_commit': base, 'new_files': sorted(new_files), 'pending_form_drafts_included': False},
    'runs': runs,
    'source_sha256': {str(path.relative_to(WORK)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'harness_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__), ROOT / 'tests/channel_audit.py', ROOT / 'tests/provider_retry_reference.mts']},
    'program_sha256': {suffix: hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']},
    'compiler_command': str(BEND),
    'compiler_sha256': {name: hashlib.sha256((BEND.parent / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/provider-retry-owned-results.json').write_text(json.dumps(record, indent=2) + '\n')

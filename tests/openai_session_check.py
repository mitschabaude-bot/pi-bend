"""Gated async session ownership; assertions execute in Bend."""
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
SOURCE = 'packages/ai/test/openai-responses-session.bend'
prefix = WORK / 'build/openai-session'
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '8',
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

runs=[]
for audited in [False,True]:
    suffix='-audit' if audited else ''
    for backend,command in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[BUN,str(prefix)+suffix+'.js'])]:
        result=subprocess.run(command,cwd=WORK,text=True,capture_output=True,check=True,timeout=45)
        assert result.stdout.splitlines()==[f'PASS session {mode}' for mode in range(7)],(backend,result.stdout,result.stderr)
        assert result.stderr==('AUDIT 0 0 0\n' if audited else ''),(backend,result.stderr)
        runs.append({'backend':backend,'audited':audited,'scenarios':7,'passed':True})
        print(backend,'audit' if audited else 'production','7 session scenarios PASS',flush=True)
pending,visited=[WORK/SOURCE],set()
while pending:
    path=pending.pop().resolve()
    if path in visited:continue
    visited.add(path)
    pending += [path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.MULTILINE)]
record={
 'scope':'Bend assertions with a gated acquisition and affine channel-backed body. Nonblocking start, repeatable wait/result observation, immutable retained events, typed primary/cleanup/cancellation errors, single body retirement, borrowed callback survival and disposal of a running producer. Native1/4 and Bun production/audit; 42 scenario executions in six process runs. No exhaustive IO/scheduler theorem.',
 'runs':runs,
 'source_sha256':{str(path.relative_to(WORK)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
 'harness_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),ROOT/'tests/channel_audit.py']},
 'program_sha256':{suffix:hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c','.js','-audit','-audit.c','-audit.js']},
 'compiler_command':str(BEND),
 'compiler_sha256':{name:hashlib.sha256((BEND.parent/name).read_bytes()).hexdigest() for name in ['main.ts','bend.ts','comp.ts','base.bend']},
 'builds':{backend:json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c','js']},
}
(ROOT/'build/openai-session-results.json').write_text(json.dumps(record,indent=2)+'\n')

"""Exercise dynamic error formatting through driver outcomes and delivery failure."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--worktree', type=Path, default=ROOT)
parser.add_argument('--session', action='store_true')
config = parser.parse_args()
work = config.worktree.resolve()
compiler = ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts'
prefix = work / ('build/openai-session-renderer-context' if config.session else 'build/openai-renderer-context')
prefix.parent.mkdir(parents=True, exist_ok=True)
source = 'tests/openai-session-renderer-context.bend' if config.session else 'tests/openai-renderer-context.bend'
case_count = 4 if config.session else 7

def expected(provider):
    if config.session:
        return "PASS session renderer context and cleanup\n"
    lines = []
    for mode in range(7):
        lines.append(f'case:{mode}')
        cause = {1:'request', 2:'processing', 3:'cleanup', 4:'start', 6:'processing'}.get(mode)
        text = f'{provider}: {cause}' if cause else 'none'
        if mode != 1:
            lines.append('start')
        if mode == 4:
            lines.append('release')
        lines.append(('error:' if cause else 'done:') + text)
        final = f'{provider}: delivery' if mode == 5 else text
        lines.append('close:' + final)
        lines.append(f"result:{final}:{'cleanup' if mode == 3 else 'none'}:{'delivery' if mode in (5,6) else 'none'}")
    return '\n'.join(lines) + '\n'

pending = [work/source]
closure = set()
while pending:
    path = pending.pop().resolve()
    if path in closure:
        continue
    closure.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
sources = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(closure)}
for backend in ('c','js'):
    with Path(str(prefix)+'.'+backend+'.log').open('w') as log:
        subprocess.run([str(compiler),source,'-o',str(prefix)+'.'+backend],cwd=work,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
Path(str(prefix)+'-audit.c').write_text(Path(str(prefix)+'.c').read_text()+r'''
static void __attribute__((destructor)) renderer_audit(void) {
  unsigned channels=0;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u\n",channels,io_park.head!=NULL);
}
''')
Path(str(prefix)+'-audit.js').write_text(instrument(Path(str(prefix)+'.js').read_text()))
runs=[]
for suffix in ('','-audit'):
    subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',str(prefix)+suffix+'.c','-lpthread','-lm','-o',str(prefix)+suffix],check=True,timeout=120)
    for backend,command in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[str(Path.home()/'.bun/bin/bun'),str(prefix)+suffix+'.js'])]:
        for provider in ('openai','custom provider','本地🙂'):
            result=subprocess.run(command+[provider],cwd=work,capture_output=True,text=True,check=True,timeout=15)
            audit=('AUDIT 0 0 0\n' if backend=='bun' else 'AUDIT 0 0\n') if suffix else ''
            assert result.stdout==expected(provider) and result.stderr==audit,(backend,provider,result)
            runs.append(dict(backend=backend,audited=bool(suffix),provider=provider,cases=case_count,trace=result.stdout.splitlines()))
        print(backend,suffix or 'plain',str(case_count * 3)+' renderer-context cases PASS',flush=True)
assert sources=={name:hashlib.sha256(Path(name).read_bytes()).hexdigest() for name in sources}
record=dict(scope=('Four session outcomes with three runtime renderer contexts and gated dependency retirement; repeated wait/dispose and zero residual callbacks/IO. ' if config.session else 'Seven driver outcomes with three runtime renderer contexts; acquisition, processing, cleanup, start-delivery and terminal-delivery errors, primary failure preservation and final settlement. ')+'Plain/audited native one/four threads and Bun. No full-provider or universal IO proof claim.',session=config.session,worktree=str(work),sources=sources,harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),audit_helper_sha256=hashlib.sha256((ROOT/'tests/channel_audit.py').read_bytes()).hexdigest(),programs={str(prefix)+s:hashlib.sha256(Path(str(prefix)+s).read_bytes()).hexdigest() for s in ('','.c','.js','-audit','-audit.c','-audit.js')},runs=runs)
Path(str(prefix)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')

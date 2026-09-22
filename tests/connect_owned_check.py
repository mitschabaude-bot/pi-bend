"""Owned connect lifetimes, including cancellation of actual parked loopback waits.

Uses a saturated local listen queue, verified with a nonblocking control probe.
Disposable effect instrumentation audits native rows/FDs/waiters and JS owners.
No external traffic, compiler installation or scheduler modification occurs.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import select
import shutil
import socket
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
parser.add_argument('--production',action='store_true',help='Use unchanged effects without exit-audit instrumentation')
parser.add_argument('--races',action='store_true',help='Audit competing cancellers, cohorts and stale slot reuse')
args=parser.parse_args();candidate=args.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
negative=subprocess.run([str(bun),str(candidate/'main.ts'),'tests/connect-owner-copy.bend'],cwd=ROOT,capture_output=True,text=True)
assert negative.returncode!=0 and 'expected : Data' in negative.stdout+negative.stderr and 'observed : Type' in negative.stdout+negative.stderr,negative
native_audit=r'''
static void __attribute__((destructor)) connect_probe_report(void) {
  u32 live=0, fds=0, waiters=0;
  for (u32 i=0;i<connect_len;++i) {
    live += connect_rows[i].live;
    fds += connect_rows[i].fd >= 0;
    waiters += connect_rows[i].waiter != NULL;
  }
  fprintf(stderr,"audit:%u:%u:%u:%u:%u\n",live,fds,waiters,connect_len,connect_probe_parked);
}
'''
js_audit=r'''
process.on('exit',()=>console.error('audit:'+[
  connect_probe_rows.filter(x=>x.state!==3).length,
  connect_probe_rows.filter(x=>x.fd>=0).length,
  connect_probe_rows.filter(x=>x.waiter!==null).length,
  connect_probe_rows.length,connect_probe_parked].join(':')));
'''
results=[]
with tempfile.TemporaryDirectory(prefix='connect-owned-',dir=ROOT/'build') as directory:
    folder=Path(directory);compiler=folder/'bend2';shutil.copytree(candidate,compiler)
    if not args.production:
        effect=compiler/'effs/connect.c';source=effect.read_text();assert source.count('if (activation) {')==1
        effect.write_text('static u32 connect_probe_parked;\n'+source.replace('if (activation) {','if (activation) { connect_probe_parked += 1;')+native_audit)
        effect=compiler/'effs/connect.js';source=effect.read_text();assert source.count('return io_done(io_tup(row, row));')==1 and source.count('io.waits.splice(index, 1);')==1
        effect.write_text('const connect_probe_rows=[]; let connect_probe_parked=0;\n'+source.replace('return io_done(io_tup(row, row));','connect_probe_rows.push(row); return io_done(io_tup(row, row));').replace('io.waits.splice(index, 1);','io.waits.splice(index, 1); connect_probe_parked += 1;')+js_audit)
    for suffix in ['c','js']:
        subprocess.run([str(bun),str(compiler/'main.ts'),('tests/connect-races.bend' if args.races else 'tests/connect-owned.bend'),'-o',str(folder/f'probe.{suffix}')],cwd=ROOT,check=True,capture_output=True,timeout=120)
    subprocess.run(['clang','-fbracket-depth=2048','-std=c11','-O1',str(folder/'probe.c'),'-lpthread','-lm','-o',str(folder/'probe')],check=True,timeout=120)
    def run(label,command,mode,family,port):
        result=subprocess.run([*command,mode,str(family),str(port)],cwd=ROOT,capture_output=True,text=True,timeout=15)
        assert result.returncode==0,(label,mode,family,result.stdout,result.stderr)
        expected='connected' if mode=='success' else 'closed' if mode=='close' else f'cancelled:{errno.ECANCELED}'
        iterations = (256 if mode=='cohort' else 4) if args.races else 32
        assert result.stdout.splitlines()==[expected]*iterations,(label,mode,result.stdout)
        live=fds=waiters=slots=parked=None
        if args.production:
            assert not result.stderr,(label,mode,result.stderr)
        else:
            parts=result.stderr.strip().split(':');assert parts[0]=='audit' and len(parts)==6,result.stderr
            live,fds,waiters,slots,parked=map(int,parts[1:]);assert (live,fds,waiters)==(0,0,0),(label,mode,parts)
            if mode=='race': assert 0<=parked<=iterations,(label,mode,parts)
            else: assert parked==(iterations if mode in ['parked','cohort'] else 0),(label,mode,'not the intended cancellation path',parts)
            if label.startswith('native'):assert slots==(64 if mode=='cohort' else 1),(label,mode,'registry did not reuse retired slots',slots)
        results.append({'backend':label,'mode':mode,'family':family,'iterations':iterations,'live_owners':live,'owned_fds':fds,'waiters':waiters,'registry_slots_or_js_total_owners':slots,'parked_cancellations':parked})
    for label,command in [('native 1',[str(folder/'probe'),'--threads','1']),('native 4',[str(folder/'probe'),'--threads','4']),('Bun',[str(bun),str(folder/'probe.js')])]:
        for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
            if not args.races:
                with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                    listener.bind((host,0));listener.listen(16);listener.settimeout(15)
                    def serve():
                        for _ in range(32):
                            with listener.accept()[0] as peer:
                                peer.settimeout(10);assert peer.recv(1)==b'x';peer.sendall(b'y');assert peer.recv(1)==b''
                    future=pool.submit(serve);run(label,command,'success',number,listener.getsockname()[1]);future.result(timeout=20)
            for mode in (['race','cohort','reuse'] if args.races else ['before','parked','close']):
                with socket.socket(family,socket.SOCK_STREAM) as listener,socket.socket(family,socket.SOCK_STREAM) as filler,socket.socket(family,socket.SOCK_STREAM) as probe:
                    listener.bind((host,0));listener.listen(0)
                    filler.settimeout(2);filler.connect(listener.getsockname())
                    probe.setblocking(False)
                    assert probe.connect_ex(listener.getsockname())==errno.EINPROGRESS
                    assert not select.select([],[probe],[],.05)[1], 'local control connect did not remain pending'
                    probe.close()
                    run(label,command,mode,number,listener.getsockname()[1])
        print(label+(': IPv4/IPv6 concurrent cancellers, cohorts and slot reuse PASS' if args.races else ': IPv4/IPv6 completion, pre-wait/parked cancellation and retirement PASS'),flush=True)
report={'scope':__doc__,'audited':not args.production,'mode':'concurrent cancellation/cohort/reuse' if args.races else 'core lifetime','owner_copy_rejected':True,'cases':results,'sha256':{name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','effs/connect.c','effs/connect.js']}}
(ROOT/('build/connect-'+('races' if args.races else 'owned')+('-production' if args.production else '')+'-result.json')).write_text(json.dumps(report,indent=2)+'\n')

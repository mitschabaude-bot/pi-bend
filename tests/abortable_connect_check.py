"""AbortSignal composition with owned IPv4/IPv6 attempts on local peers.

Audited copies count primitive calls, parked cancellations, attempts and channels.
Production mode uses unchanged generated programs. Finite Linux checks only.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import select
import shlex
import socket
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
parser.add_argument('--no-build',action='store_true')
parser.add_argument('--production',action='store_true')
args=parser.parse_args();candidate=args.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
launcher=ROOT/'build/abortable-connect-compiler';launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(bun))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_build:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--limit-gib','16','--stats','build/abortable-connect-native-build.json','--','sh','scripts/build-pure.sh','tests/abortable-connect.bend','build/abortable-connect'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/abortable-connect-js-build.json','--',str(launcher),'tests/abortable-connect.bend','-o','build/abortable-connect.js'],cwd=ROOT,check=True)
results=[]
with tempfile.TemporaryDirectory(prefix='abortable-connect-',dir=ROOT/'build') as directory:
    folder=Path(directory);binary=ROOT/'build/abortable-connect';javascript=ROOT/'build/abortable-connect.js'
    if not args.production:
        original=(candidate/'effs/connect.c').read_text();generated=(ROOT/'build/abortable-connect.c').read_text();assert original in generated
        effect='static u32 probe_calls,probe_created,probe_parked;\n'+original
        for family in ['ipv4','ipv6']:
            needle=f'Term connect_{family}_run(Env e, Term* fields, IoWork* work) {{';assert effect.count(needle)==1;effect=effect.replace(needle,needle+' probe_calls++;')
        effect=effect.replace('row->gen += 1;','probe_created++; row->gen += 1;').replace('if (activation) {','if (activation) { probe_parked++;')
        audit=r'''
static void __attribute__((destructor)) abort_connect_audit(void) {
 u32 live=0,fds=0,waiters=0,channels=0;
 for(u32 i=0;i<connect_len;i++){live+=connect_rows[i].live;fds+=connect_rows[i].fd>=0;waiters+=connect_rows[i].waiter!=NULL;}
 for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
 fprintf(stderr,"audit:%u:%u:%u:%u:%u:%u:%u\n",probe_calls,probe_created,probe_parked,live,fds,waiters,channels);
}
'''
        source=folder/'audit.c';source.write_text(generated.replace(original,effect)+audit);binary=folder/'audit'
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-fbracket-depth=2048','-std=c11','-O1',str(source),'-lpthread','-lm','-o',str(binary)],check=True,timeout=120)
        generated=javascript.read_text();original=(candidate/'effs/connect.js').read_text();assert original in generated
        effect='const probeRows=[]; let probeCalls=0,probeParked=0;\n'+original
        for needle in ['function connect_ipv4(word, port) {','function connect_ipv6(a, b, c, d, port, scope) {']:
            assert effect.count(needle)==1;effect=effect.replace(needle,needle+' probeCalls++;')
        effect=effect.replace('return io_done(io_tup(row, row));','probeRows.push(row); return io_done(io_tup(row, row));').replace('io.waits.splice(index, 1);','io.waits.splice(index, 1); probeParked++;')
        effect+="\nprocess.on('exit',()=>console.error('audit:'+ [probeCalls,probeRows.length,probeParked,probeRows.filter(x=>x.state!==3).length,probeRows.filter(x=>x.fd>=0).length,probeRows.filter(x=>x.waiter!==null).length,probeChannels.filter(x=>!x.shut).length].join(':')));\n"
        channel=(candidate/'effs/chan_new.js').read_text();assert channel in generated
        changed=channel.replace('  return { room: Number(room), ring: [], wait: [], shut: false };','  const row={ room: Number(room), ring: [], wait: [], shut: false }; probeChannels.push(row); return row;');assert changed!=channel
        javascript=folder/'audit.js';javascript.write_text('const probeChannels=[];\n'+generated.replace(original,effect).replace(channel,changed))
    def run(label,command,mode,family,port,code=0):
        result=subprocess.run([*command,mode,str(family),str(port),str(code)],cwd=ROOT,capture_output=True,text=True,timeout=20)
        assert result.returncode==0 and result.stdout=='PASS abortable connect\n',(label,mode,result)
        values=None
        if args.production:assert not result.stderr,(label,mode,result.stderr)
        else:
            parts=result.stderr.strip().split(':');assert parts[0]=='audit' and len(parts)==8,result.stderr
            calls,created,parked,live,fds,waiters,channels=map(int,parts[1:]);values=dict(calls=calls,created=created,parked=parked,live=live,fds=fds,waiters=waiters,channels=channels)
            assert live==fds==waiters==channels==0,(label,mode,values)
            if mode in ['pre','default']:assert calls==created==parked==0,values
            elif mode=='cancel':assert 1<=parked<=created<=calls<=32,values
            elif mode=='late':assert calls==created==1 and parked==0,values
            elif mode=='success':assert calls==created==16 and parked==0,values
            else:
                assert calls==16 and parked==0,values
                if port>65535:assert created==0,values
        results.append({'backend':label,'mode':mode,'family':family,'port':port,'expected_error':code,'audit':values})
    for label,command in [('native 1',[str(binary),'--threads','1']),('native 4',[str(binary),'--threads','4']),('Bun',[str(bun),str(javascript)])]:
        for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
            for mode,count in [('success',16),('late',1)]:
                with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                    listener.bind((host,0));listener.listen(16);listener.settimeout(15)
                    def serve():
                        for _ in range(count):
                            with listener.accept()[0] as peer:peer.settimeout(10);assert peer.recv(1)==b''
                    future=pool.submit(serve);run(label,command,mode,number,listener.getsockname()[1]);future.result(timeout=20)
            with socket.socket(family,socket.SOCK_STREAM) as closed:
                closed.bind((host,0));port=closed.getsockname()[1]
                run(label,command,'error',number,port,errno.ECONNREFUSED)
                run(label,command,'error',number,65536,errno.EINVAL)
                run(label,command,'pre',number,port)
                run(label,command,'default',number,port)
            with socket.socket(family,socket.SOCK_STREAM) as listener,socket.socket(family,socket.SOCK_STREAM) as filler,socket.socket(family,socket.SOCK_STREAM) as probe:
                listener.bind((host,0));listener.listen(0);filler.settimeout(2);filler.connect(listener.getsockname())
                probe.setblocking(False);assert probe.connect_ex(listener.getsockname())==errno.EINPROGRESS;assert not select.select([],[probe],[],.05)[1];probe.close()
                run(label,command,'cancel',number,listener.getsockname()[1])
        print(label+': AbortSignal connect composition PASS',flush=True)
report={'scope':__doc__,'audited':not args.production,'cases':results,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'packages/runtime/src/socket.bend',ROOT/'tests/abortable-connect.bend',candidate/'comp.ts',candidate/'base.bend',candidate/'effs/connect.c',candidate/'effs/connect.js',ROOT/'build/abortable-connect',ROOT/'build/abortable-connect.js']}}
(ROOT/('build/abortable-connect-production-result.json' if args.production else 'build/abortable-connect-result.json')).write_text(json.dumps(report,indent=2)+'\n')

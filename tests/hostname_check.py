"""Additive hostname effect: actual OS result, fault injection, emission and compile controls."""
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import socket
import statistics
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BUN=Path.home()/'.bun/bin/bun'
BASE=TOOLCHAIN
CANDIDATE=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/hostname-{suffix}-build.json','--',str(BUN),str(CANDIDATE/'main.ts'),'tests/hostname.bend','-o',f'build/hostname.{suffix}'],cwd=ROOT,check=True)
clang=['clang','-std=c11','-fbracket-depth=2048','-O1','build/hostname.c','-lpthread','-lm']
subprocess.run([*clang,'-o','build/hostname'],cwd=ROOT,check=True)
subprocess.run([*clang,'tests/hostname-effect-shim.c','-Wl,--wrap=uname','-o','build/hostname-shim'],cwd=ROOT,check=True)
js_shim='''const hostTestOs = require("node:os");
hostTestOs.hostname = () => {
  const value = process.env.PI_BEND_HOSTNAME_ERROR;
  if (value === "unknown") throw new Error("test failure");
  if (value !== undefined) {
    const code = -Number(value);
    if (process.env.PI_BEND_HOSTNAME_NESTED) throw {info:{errno:code}};
    throw {errno:code};
  }
  return process.env.PI_BEND_HOSTNAME_VALUE;
};
'''
(ROOT/'build/hostname-shim.js').write_text(js_shim+(ROOT/'build/hostname.js').read_text())
checks=[]
for backend,real,shim in [('native 1',['build/hostname','--threads','1'],['build/hostname-shim','--threads','1']),('native 4',['build/hostname','--threads','4'],['build/hostname-shim','--threads','4']),('Bun',[str(BUN),'build/hostname.js'],[str(BUN),'build/hostname-shim.js'])]:
    env={k:v for k,v in os.environ.items() if not k.startswith('PI_BEND_HOSTNAME_')}
    env['HOSTNAME']='not-the-kernel-hostname.invalid'
    run=subprocess.run(real,cwd=ROOT,env=env,capture_output=True,text=True,timeout=10)
    assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==['name:'+socket.gethostname()]*3,(backend,'system mismatch')
    names=['','node','host.example.test','.','x'*64,'tést.域']
    for name in names:
        run=subprocess.run(shim,cwd=ROOT,env={**env,'PI_BEND_HOSTNAME_VALUE':name},capture_output=True,text=True,timeout=10)
        assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==['name:'+name]*3,(backend,name,run)
    for code in [1,5,13,22,38]:
        for nested in ([False,True] if backend=='Bun' else [False]):
            current={**env,'PI_BEND_HOSTNAME_ERROR':str(code)}
            if nested:current['PI_BEND_HOSTNAME_NESTED']='1'
            run=subprocess.run(shim,cwd=ROOT,env=current,capture_output=True,text=True,timeout=10)
            assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==['error:'+str(code)]*3,(backend,code,run)
    if backend=='Bun':
        for code in ['unknown','0']:
            run=subprocess.run(shim,cwd=ROOT,env={**env,'PI_BEND_HOSTNAME_ERROR':code},capture_output=True,text=True,timeout=10)
            assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==['error:5']*3,(code,run)
    checks.append(dict(backend=backend,system_hostname_matched=True,HOSTNAME_environment_ignored=True,mocked_names=names,error_codes=[1,5,13,22,38],calls_per_case=3))
    print(backend+': hostname effect PASS',flush=True)

controls=[]
for fixture in ['tests/hostname-control.bend','tests/static-sum-layout.bend']:
    samples=[];digests={}
    for suffix in ['c','js']:
        emitted=[]
        for label,compiler in [('base',BASE),('candidate',CANDIDATE)]:
            target=ROOT/f'build/hostname-control-{label}.{suffix}'
            subprocess.run([str(BUN),str(compiler/'main.ts'),fixture,'-o',str(target)],cwd=ROOT,check=True,capture_output=True)
            emitted.append(target.read_bytes())
        assert emitted[0]==emitted[1],(fixture,suffix,'unused effect changed output')
        digests[suffix]=hashlib.sha256(emitted[0]).hexdigest()
    for pair in range(20):
        current={}
        order=[('base',BASE),('candidate',CANDIDATE)]
        if pair%2:order.reverse()
        for label,compiler in order:
            stats=ROOT/'build/hostname-time.txt'
            target=ROOT/'build/hostname-control-benchmark.c'
            result=subprocess.run(['/usr/bin/time','-f','%e %M','-o',str(stats),str(BUN),str(compiler/'main.ts'),fixture,'-o',str(target)],cwd=ROOT,capture_output=True,text=True,timeout=20)
            assert result.returncode==0 and not result.stderr,(fixture,label,result)
            assert hashlib.sha256(target.read_bytes()).hexdigest()==digests['c']
            seconds,rss=stats.read_text().split();current[label]=dict(seconds=float(seconds),peak_rss_kib=int(rss))
        samples.append(current)
    medians={label:{key:statistics.median(row[label][key] for row in samples) for key in ['seconds','peak_rss_kib']} for label in ['base','candidate']}
    controls.append(dict(fixture=fixture,emission_sha256=digests,pairs=samples,medians=medians))
    print(fixture+': identical C/JS; 20 paired compile measurements complete',flush=True)
paths=['patches/experimental/hostname/base.bend','patches/experimental/hostname/get_hostname.c','patches/experimental/hostname/get_hostname.js','scripts/prepare-hostname-candidate.py','tests/hostname.bend','tests/hostname-effect-shim.c','tests/hostname-control.bend','tests/hostname_check.py']
r=dict(scope=__doc__,checks=checks,compile_controls=controls,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},compiler_sha256={label:{name:hashlib.sha256((compiler/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']} for label,compiler in [('base',BASE),('candidate',CANDIDATE)]},builds={suffix:json.loads((ROOT/f'build/hostname-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/hostname-result.json').write_text(json.dumps(r,indent=2)+'\n')

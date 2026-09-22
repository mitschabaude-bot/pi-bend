"""OS interface index: native/Bun effects, injected errors, resolver integration and controls."""
import ctypes
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
for fixture in ['interface-index','resolver-interface']:
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/{fixture}-{suffix}-build.json','--',str(BUN),str(CANDIDATE/'main.ts'),f'tests/{fixture}.bend','-o',f'build/{fixture}.{suffix}'],cwd=ROOT,check=True)
    subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',f'build/{fixture}.c','-lpthread','-lm','-o',f'build/{fixture}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-O1','build/interface-index.c','tests/interface-index-shim.c','-Wl,--wrap=if_nametoindex','-lpthread','-lm','-o','build/interface-index-shim'],cwd=ROOT,check=True)
js_shim='''const interfaceTestFFI = require("bun:ffi");
const interfaceTestErrno = new Int32Array(1);
let interfaceTestLoads = 0;
const interfaceTestDlopen = interfaceTestFFI.dlopen;
interfaceTestFFI.dlopen = (path, symbols) => {
  if (!symbols.if_nametoindex) return interfaceTestDlopen(path, symbols);
  if (++interfaceTestLoads !== 1) throw new Error("library loaded twice");
  if (process.env.PI_BEND_IF_THROW) throw {errno: -Number(process.env.PI_BEND_IF_THROW)};
  return {symbols: {
    __errno_location: () => interfaceTestFFI.ptr(interfaceTestErrno),
    if_nametoindex: pointer => {
      if (String(new interfaceTestFFI.CString(pointer)) !== process.env.PI_BEND_IF_NAME) {
        interfaceTestErrno[0] = 22; return 0;
      }
      if (process.env.PI_BEND_IF_ERROR !== undefined) {
        interfaceTestErrno[0] = Number(process.env.PI_BEND_IF_ERROR); return 0;
      }
      return Number(process.env.PI_BEND_IF_INDEX);
    }
  }};
};
'''
(ROOT/'build/interface-index-shim.js').write_text(js_shim+(ROOT/'build/interface-index.js').read_text())
libc=ctypes.CDLL(None,use_errno=True)
lookup=libc.if_nametoindex;lookup.argtypes=[ctypes.c_char_p];lookup.restype=ctypes.c_uint
names=[name for _,name in socket.if_nameindex()]+['','missing-if-xyz','.','/','x'*16,'x'*1000,'tést.域']
def expected(name):
    ctypes.set_errno(0);index=lookup(name.encode())
    return f'index:{index}' if index else f'error:{ctypes.get_errno() or 5}:message'
want=[expected(name) for name in names]+['error:22:message']
checks=[]
def check(command,args,expected,env=None):
    result=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,text=True,timeout=20)
    assert result.returncode==0 and not result.stderr and result.stdout.splitlines()==expected,(command,args[:3],result,expected[:3])
for backend,real,shim,resolver in [('native 1',['build/interface-index','--threads','1'],['build/interface-index-shim','--threads','1'],['build/resolver-interface','--threads','1']),('native 4',['build/interface-index','--threads','4'],['build/interface-index-shim','--threads','4'],['build/resolver-interface','--threads','4']),('Bun',[str(BUN),'build/interface-index.js'],[str(BUN),'build/interface-index-shim.js'],[str(BUN),'build/resolver-interface.js'])]:
    env={k:v for k,v in os.environ.items() if not k.startswith('PI_BEND_IF_')}
    check(real,names,want,env)
    repeated=['lo','missing-if-xyz']*1000
    check(real,repeated,[expected(name) for name in repeated]+['error:22:message'],env)
    for name in ['','test-if','tést.域']:
        for index in [1,7,4294967295]:
            check(shim,[name,name],[f'index:{index}']*2+['error:22:message'],{**env,'PI_BEND_IF_NAME':name,'PI_BEND_IF_INDEX':str(index)})
        for code in [0,1,5,12,19,24]:
            check(shim,[name,name],[f'error:{code or 5}:message']*2+['error:22:message'],{**env,'PI_BEND_IF_NAME':name,'PI_BEND_IF_ERROR':str(code)})
    if backend=='Bun':
        # One call exercises initialization failure; NUL rejection runs before FFI.
        for code in [5,12]:
            check(shim,['lo'],[f'error:{code}:message','error:22:message'],{**env,'PI_BEND_IF_THROW':str(code)})
    loopback=socket.if_nametoindex('lo')
    addresses=['127.1','::1','fe80::1','fe80::1%lo','ff01::1%lo','ff02::1%lo','ff11::1%lo','::1%lo','ff05::1%lo','fe80::1%missing-if-xyz','fe80::1%0','::1%4294967295','fe80::1%4294967296','bad']
    errors=expected('missing-if-xyz').split(':')[1]
    overflow_error=expected('4294967296').split(':')[1]
    results=['v4:none','0:none','0:none',f'{loopback}:none',f'{loopback}:none',f'{loopback}:none',f'{loopback}:none','0:invalid','0:invalid',f'0:error:{errors}','0:none','4294967295:none',f'0:error:{overflow_error}','bad-address']
    check(resolver,addresses,results,env)
    checks.append(dict(backend=backend,os_cases=len(names),repeated_calls=len(repeated),injected_cases=27,resolver_cases=len(addresses),embedded_nul_rejected=True))
    print(backend+': interface primitive and resolver integration PASS',flush=True)
controls=[]
for fixture in ['tests/hostname-control.bend','tests/static-sum-layout.bend']:
    samples=[];digests={}
    for suffix in ['c','js']:
        emitted=[]
        for label,compiler in [('base',BASE),('candidate',CANDIDATE)]:
            target=ROOT/f'build/interface-index-control-{label}.{suffix}'
            subprocess.run([str(BUN),str(compiler/'main.ts'),fixture,'-o',str(target)],cwd=ROOT,check=True,capture_output=True)
            emitted.append(target.read_bytes())
        assert emitted[0]==emitted[1],(fixture,suffix,'unused effect changed output')
        digests[suffix]=hashlib.sha256(emitted[0]).hexdigest()
    for pair in range(20):
        current={}
        order=[('base',BASE),('candidate',CANDIDATE)]
        if pair%2:order.reverse()
        for label,compiler in order:
            stats=ROOT/'build/interface-index-time.txt'
            target=ROOT/'build/interface-index-control-benchmark.c'
            result=subprocess.run(['/usr/bin/time','-f','%e %M','-o',str(stats),str(BUN),str(compiler/'main.ts'),fixture,'-o',str(target)],cwd=ROOT,capture_output=True,text=True,timeout=20)
            assert result.returncode==0 and not result.stderr,(fixture,label,result)
            assert hashlib.sha256(target.read_bytes()).hexdigest()==digests['c']
            seconds,rss=stats.read_text().split();current[label]=dict(seconds=float(seconds),peak_rss_kib=int(rss))
        samples.append(current)
    medians={label:{key:statistics.median(row[label][key] for row in samples) for key in ['seconds','peak_rss_kib']} for label in ['base','candidate']}
    controls.append(dict(fixture=fixture,emission_sha256=digests,pairs=samples,medians=medians))
    print(fixture+': identical C/JS; 20 paired compile measurements complete',flush=True)
paths=['patches/experimental/interface-index/base.bend','patches/experimental/interface-index/interface_index.c','patches/experimental/interface-index/interface_index.js','scripts/prepare-interface-index-candidate.py','packages/runtime/src/network-interface.bend','packages/runtime/src/dns-resolver.bend','tests/interface-index.bend','tests/interface-index-shim.c','tests/resolver-interface.bend','tests/interface_index_check.py']
r=dict(scope=__doc__,checks=checks,compile_controls=controls,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={label:{name:hashlib.sha256((compiler/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']} for label,compiler in [('base',BASE),('candidate',CANDIDATE)]},builds={fixture:{suffix:json.loads((ROOT/f'build/{fixture}-{suffix}-build.json').read_text()) for suffix in ['c','js']} for fixture in ['interface-index','resolver-interface']})
(ROOT/'build/interface-index-result.json').write_text(json.dumps(r,indent=2)+'\n')

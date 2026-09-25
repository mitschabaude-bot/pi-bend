#!/usr/bin/env python3
import itertools,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
fixtures=[dict(initial=a,later=b,fail=f) for a,b,f in itertools.product(range(4),range(4),[False,True])]
result=subprocess.run(['node','--experimental-strip-types','tests/agent_hooks_reference.mts'],cwd=root,input=json.dumps(fixtures),text=True,capture_output=True,check=True)
expected=json.loads(result.stdout)
assert len(expected)==len(fixtures)
lines=['import Base','import ../packages/agent/test/agent-hooks.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for f,value in zip(fixtures,expected):lines.append(f'    T.scenario({f["initial"]}, {f["later"]}, {"True{}" if f["fail"] else "False{}"}, {json.dumps(value)})')
lines.append('    IO.print("PASS 32 Agent preparation-hook capture/precedence/signal source scenarios")')
(root/'build').mkdir(exist_ok=True)
(root/'build/agent-hooks-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','build/agent-hooks-check.bend','build/agent-hooks-check'],cwd=root,check=True)
for threads in [1,4]:subprocess.run(['build/agent-hooks-check','--threads',str(threads)],cwd=root,check=True,timeout=120)

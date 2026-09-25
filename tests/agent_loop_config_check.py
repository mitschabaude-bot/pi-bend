#!/usr/bin/env python3
import itertools,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
fixtures=[dict(skip=s,steering=a,follow=b,thinking=t) for s,a,b,t in itertools.product([False,True],range(2),range(2),range(3))]
result=subprocess.run(['node','--experimental-strip-types','tests/agent_loop_config_reference.mts'],cwd=root,input=json.dumps(fixtures),text=True,capture_output=True,check=True)
expected=json.loads(result.stdout)
assert len(expected)==len(fixtures)
lines=['import Base','import ../packages/agent/test/agent-loop-config.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for f,value in zip(fixtures,expected):lines.append(f'    T.scenario({"True{}" if f["skip"] else "False{}"}, {f["steering"]}, {f["follow"]}, {f["thinking"]}, {json.dumps(value)})')
lines.append('    IO.print("PASS 24 Agent loop configuration and live queue source scenarios")')
(root/'build').mkdir(exist_ok=True)
(root/'build/agent-loop-config-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','build/agent-loop-config-check.bend','build/agent-loop-config-check'],cwd=root,check=True)
for threads in [1,4]:subprocess.run(['build/agent-loop-config-check','--threads',str(threads)],cwd=root,check=True,timeout=120)

"""Real child processes: byte streaming, post-exit idle grace and cleanup."""
import argparse
import base64
from pathlib import Path
import subprocess
import time

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--prefix',type=Path,default=Path('build/child-process'))
a=p.parse_args()
for threads in [1,4]:
    def run(command,mode='normal'):
        started=time.monotonic()
        result=subprocess.run([str(a.prefix.resolve()),'--threads',str(threads),mode,command],
                              capture_output=True,text=True,timeout=8)
        elapsed=time.monotonic()-started
        assert result.returncode==0 and not result.stderr,(result.stdout,result.stderr)
        lines=result.stdout.splitlines()
        assert lines[0]=='stdin ok' and lines[-1]=='close ok',lines[-5:]
        output=b''.join(base64.b64decode(line[5:],validate=True) for line in lines if line.startswith('data '))
        status=next(line[7:] for line in lines if line.startswith('status '))
        errors=[line for line in lines if line.startswith('error ')]
        return output,status,errors,elapsed
    output,status,errors,_=run('printf hello; printf world >&2; exit 7')
    assert sorted(output)==sorted(b'helloworld') and status=='exit:7' and not errors
    assert run('true')[:3]==(b'','exit:0',[])
    assert run("printf '\\000\\377\\303\\251'")[:3]==(b'\0\xff\xc3\xa9','exit:0',[])
    output,status,errors,_=run('head -c 131072 /dev/zero & head -c 131072 /dev/zero >&2 & wait')
    assert output==bytes(262144) and status=='exit:0' and not errors
    output,status,errors,elapsed=run('(sleep 0.7) & exit 0')
    assert output==b'' and status=='exit:0' and not errors and .07<=elapsed<.6,elapsed
    # Output continues well beyond 100ms after the leader exits. Every chunk
    # must extend the grace period, including activity on stderr only.
    for target in ['', '>&2']:
        command=f'(i=0; while [ "$i" -lt 8 ]; do printf x {target}; i=$((i+1)); sleep 0.04; done; sleep 0.5) & exit 0'
        output,status,errors,elapsed=run(command)
        assert output==b'x'*8 and status=='exit:0' and not errors,(output,status,errors)
        assert .30<=elapsed<.75,elapsed
    output,status,errors,_=run('kill -TERM $$')
    assert output==b'' and status=='signal:15' and not errors
    output,status,errors,elapsed=run('printf trigger; sleep 5','fail')
    assert output==b'trigger' and status=='signal:9' and errors==['error output:0:consumer failed'],(output,status,errors)
    assert elapsed<1,elapsed
    for _ in range(20):
        output,status,errors,_=run('(printf tail; sleep 0.15) & exit 0')
        assert output==b'tail' and status=='exit:0' and not errors,(output,status,errors)
    # Reuse one Bend runtime: leaked pipe descriptors accumulate across runs.
    repeated=subprocess.run([str(a.prefix.resolve()),'--threads',str(threads),'normal',
        'ls /proc/$PPID/fd | wc -l','40'],capture_output=True,text=True,timeout=15)
    assert repeated.returncode==0 and not repeated.stderr,(repeated.stdout,repeated.stderr)
    lines=repeated.stdout.splitlines()
    assert lines.count('close ok')==40 and lines.count('status exit:0')==40,lines[-10:]
    counts=[int(base64.b64decode(line[5:])) for line in lines if line.startswith('data ')]
    assert len(counts)==40 and len(set(counts))==1 and counts[0]<20,counts
    print(f'native-{threads}: 29 process-draining/idle/consumer-failure scenarios and 40 same-runtime FD checks PASS',flush=True)

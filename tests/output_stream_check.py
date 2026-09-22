"""Output publisher throttling, reentry, retirement and checked spill cleanup."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from output_accumulator_fault_check import hooks
ROOT=Path(__file__).resolve().parents[1]
EXPECTED=['throttle:ok','reentry:ok','slow:ok','silent:ok','concurrent:ok','concurrent-observed:ok','empty:ok','incomplete:ok']

def main():
    p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');p.add_argument('--repeat',type=int,default=5);args=p.parse_args()
    hosted=args.runner.endswith('.js');runner=['bun',args.runner] if hosted else [args.runner,'--threads',args.threads]
    for _ in range(args.repeat):
        result=subprocess.run(runner,text=True,capture_output=True,timeout=30)
        assert result.returncode==0 and result.stdout.splitlines()==EXPECTED and not result.stderr,(result.returncode,result.stdout,result.stderr)
    with tempfile.TemporaryDirectory() as tmp:
        base=Path(tmp);c,js=hooks();(base/'fault.c').write_text(c);(base/'fault.cjs').write_text(js)
        subprocess.run(['cc','-shared','-fPIC','-O2',str(base/'fault.c'),'-ldl','-o',str(base/'fault.so')],check=True)
        for fault,expected in [('1',['ok','close:5']),('2',['ok','close:4']),('3',['write:28','write-close:28:5'])]:
            command=runner.copy();env=dict(os.environ,TMPDIR=tmp,BEND_FAULT_PATH=tmp+'/pi-bend-output-test-',BEND_FAULT=fault)
            if hosted:command[1:1]=['--preload',str(base/'fault.cjs')]
            else:env['LD_PRELOAD']=str(base/'fault.so')
            result=subprocess.run([*command,'fault'],text=True,capture_output=True,env=env,timeout=30)
            assert result.returncode==0 and result.stdout.splitlines()==expected,(result.stdout,result.stderr)
            assert result.stderr=='audit:1:0\n',result.stderr
            paths=list(base.glob('pi-bend-output-test-*'));assert len(paths)==1
            assert paths[0].read_bytes()==(b'' if fault=='3' else b'abc');paths[0].unlink()
        env=dict(os.environ,TMPDIR=tmp+'/missing')
        result=subprocess.run([*runner,'fault'],text=True,capture_output=True,env=env,timeout=30)
        assert result.returncode==0 and result.stdout.splitlines()==['open:2','open:2'],(result.stdout,result.stderr)
    print(f'{args.repeat} passes of8 lifecycle scenarios; checked close/dual failure/open failure audits passed')
if __name__=='__main__':main()

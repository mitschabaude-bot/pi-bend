"""Checked spill retirement and error preservation using existing OS fault hooks."""
import argparse
import ast
import os
from pathlib import Path
import subprocess
import tempfile
from output_accumulator_check import parsed
ROOT=Path(__file__).resolve().parents[1]

def hooks():
    source=ast.parse((ROOT/'tests/filesystem_write_check.py').read_text())
    values={node.targets[0].id:ast.literal_eval(node.value) for node in source.body if isinstance(node,ast.Assign) and isinstance(node.targets[0],ast.Name) and node.targets[0].id in ('C','JS')}
    c=values['C'].replace('!strcmp(path,wanted)','!strncmp(path,wanted,strlen(wanted))')
    js=values['JS'].replace('String(path) === process.env.BEND_FAULT_PATH','String(path).startsWith(process.env.BEND_FAULT_PATH)')
    return c,js

def main():
    p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');args=p.parse_args()
    hosted=args.runner.endswith('.js');runner=['bun',args.runner] if hosted else [args.runner,'--threads',args.threads]
    with tempfile.TemporaryDirectory() as tmp:
        c,js=hooks();base=Path(tmp);(base/'fault.c').write_text(c);(base/'fault.cjs').write_text(js)
        subprocess.run(['cc','-shared','-fPIC','-O2',str(base/'fault.c'),'-ldl','-o',str(base/'fault.so')],check=True)
        for fault,wanted in [('1',['ok','close:5','ok','ok']),('2',['ok','close:4','ok','ok']),('3',['write:28','write-close:28:5','ok','ok'])]:
            env=dict(os.environ,TMPDIR=tmp,BEND_THREADS=args.threads,BEND_FAULT_PATH=tmp+'/pi-bend-output-test-',BEND_FAULT=fault)
            command=runner.copy()
            if hosted:command[1:1]=['--preload',str(base/'fault.cjs')]
            else:env['LD_PRELOAD']=str(base/'fault.so')
            result=subprocess.run([*command,'1:1:616263;c;c'],text=True,capture_output=True,env=env,timeout=30)
            assert result.returncode==0,(result.stdout,result.stderr)
            assert result.stderr=='audit:1:0\n',result.stderr
            output=[parsed(x) for x in result.stdout.splitlines() if x!='end']
            assert [s['status'] for s,_ in output]==wanted,output
            assert all(s['truncation']['totalBytes']==3 and s['last']==3 for s,_ in output),output
            path=Path(output[0][1]);assert path.read_bytes()==(b'' if fault=='3' else b'abc');path.unlink()
        env=dict(os.environ,TMPDIR=tmp+'/absent',BEND_THREADS=args.threads)
        result=subprocess.check_output([*runner,'1:1:616263;s;f;c;c'],text=True,env=env)
        output=[parsed(x)[0] for x in result.splitlines() if x!='end']
        assert [s['status'] for s in output]==['open:2','open:2','open:2','ok','ok','ok'],output
        assert all(not s['path'] and s['truncation']['totalBytes']==3 for s in output)
        env['TMPDIR']=tmp
        result=subprocess.check_output([*runner,'5:20:61;c;62;f','5:20:61;x;62;f;f;63'],text=True,env=env)
        cases=result.split('end\n');first=[parsed(x)[0] for x in cases[0].splitlines()];second=[parsed(x)[0] for x in cases[1].splitlines()]
        assert [s['status'] for s in first]==['ok','ok','closed','closed','ok'],first
        assert [s['status'] for s in second]==['ok','invalid:256','ok','ok','ok','finished','ok'],second
        assert second[-1]['truncation']['content']=='ab'
    print('write/close dual failures, close-once/no-leaks, sticky open error, lifecycle and invalid bytes passed')
if __name__=='__main__':main()

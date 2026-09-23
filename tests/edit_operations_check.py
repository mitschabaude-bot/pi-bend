"""Injected edit operations, cancellation precedence and shared queue ownership."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--bun-only',action='store_true')
p.add_argument('--native-only',action='store_true')
args=p.parse_args()
commands=[] if args.native_only else [('Bun',['bun',str(ROOT/'build/edit-operations.js')])]
if not args.bun_only: commands.extend([(f'native{i}',[os.environ.get('EDIT_OPERATIONS_BINARY',str(ROOT/'build/edit-operations')),'--threads',str(i)]) for i in [1,4]])
with tempfile.TemporaryDirectory(prefix='bend-edit-operations-') as directory:
    root=Path(directory)
    for name,command in commands:
        path=root/'file.txt'
        alias=root/'alias.txt'
        if not alias.exists(): alias.symlink_to(path)
        def run(*arguments):
            result=subprocess.run(command+list(map(str,arguments)),capture_output=True,text=True,timeout=60)
            assert result.returncode==0 and not result.stderr,(name,arguments,result.returncode,result.stderr)
            return result.stdout.strip()
        for mode,order in [('before',''),('access-abort','A'),('access-failure','A'),('read-abort','AR'),('read-failure','AR'),('write-abort','ARW'),('write-failure','ARW'),('success','ARW')]:
            assert run(mode,path)==order,(name,mode)
        for other in [path,alias]:
            path.write_text('hello world\n')
            assert run('parallel',path,other)=='ok'
            assert path.read_text()=='bye there\n'
            path.write_text('hello')
            assert run('retained',path,other)=='ok'
            assert path.read_text()=='last'
        print(f'{name}: operation order, abort/error precedence, concurrent edits and edit/write queue retention PASS',flush=True)

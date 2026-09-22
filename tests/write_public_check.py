"""Invoke the real AgentTool returned by createWriteTool, with owned callbacks."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('backends',nargs='*')
parser.add_argument('--prefix',default='build/write-public')
args=parser.parse_args()
prefix=ROOT/args.prefix
for backend,command in [('bun',['bun',str(prefix)+'.js']),
                        ('native-1',[str(prefix),'--threads','1']),
                        ('native-4',[str(prefix),'--threads','4'])]:
    if args.backends and backend not in args.backends:continue
    with tempfile.TemporaryDirectory(prefix='bend-public-write-') as folder:
        root=Path(folder)
        home=root/'home'
        work=root/'work'
        home.mkdir();work.mkdir()
        def run(path,content):
            result=subprocess.run(command+[str(work),str(home),path,content],cwd=root,
                                  capture_output=True,text=True,timeout=40)
            assert result.returncode==0 and not result.stderr,(backend,path,result)
            return result.stdout.rstrip('\n')
        for path,target in [('nested/é😀.txt',work/'nested/é😀.txt'),
                            ('@tilde\u202ffile',work/'tilde file'),
                            ('~/new/deep.txt',home/'new/deep.txt'),
                            ('@~/second',home/'second'),
                            ((root/'url name').as_uri(),root/'url name'),
                            (str(root/'absolute'),root/'absolute')]:
            assert run(path,'Hello 漢字\n')=='Successfully wrote to '+path
            assert target.read_text()=='Hello 漢字\n'
            assert run(path,'short')=='Successfully wrote to '+path
            assert target.read_text()=='short'
        for path in ['file://remote/forbidden',root.as_uri()+'/bad%',root.as_uri()+'/bad%ED%A0%80',root.as_uri()+'/a%2fb']:
            assert run(path,'never written')=='path error'
    print(f'{backend}: public write metadata, exact results, normalized paths and file contents PASS',flush=True)

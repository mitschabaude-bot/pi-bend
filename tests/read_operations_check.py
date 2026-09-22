"""Read callback ordering, borrowed lifetime, cancellation, context and image notes."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('backends', nargs='*')
parser.add_argument('--prefix', default='build/read-operations')
args = parser.parse_args()
prefix = ROOT/args.prefix
text = {'content': [['text','alpha\nbeta']], 'truncated':False}
note = '[Current model does not support images. The image will be omitted from this request.]'
image = lambda suffix: {'content':[['text','Read image file [image/gif]'+suffix],['image','AQID','image/gif']], 'truncated':False}
access = 'access:/tmp/read-test/file;'
expected = {
    'text':(text, access+'read;'),
    'image':(image('\nresized'), access+'mime;read;image;'),
    'empty-mime':(text, access+'mime;read;'),
    'pre-abort':({'error':'Operation aborted'}, ''),
    'fail-access:/tmp/read-test/file':({'error':'access:/tmp/read-test/file failure'}, access),
    'fail-mime':({'error':'mime failure'}, access+'mime;'),
    'fail-read':({'error':'read failure'}, access+'mime;read;'),
    'fail-image':({'error':'image failure'}, access+'mime;read;image;'),
    'abort-access:/tmp/read-test/file':({'error':'Operation aborted'}, access),
    'abort-read':({'error':'Operation aborted'}, access+'mime;read;image;'),
}
for backend, command in [('bun',['bun',str(prefix)+'.js']),
                         ('native-1',[str(prefix),'--threads','1']),
                         ('native-4',[str(prefix),'--threads','4'])]:
    if args.backends and backend not in args.backends:
        continue
    run = subprocess.run(command,capture_output=True,text=True,timeout=60)
    assert run.returncode == 0 and not run.stderr, (backend,run.returncode,run.stderr)
    lines = run.stdout.splitlines()
    assert lines[-1] == 'gated read settled before cancellation returned', lines[-1]
    values = [json.loads(line) for line in lines[:-1]]
    assert len(values) == len(expected)*2
    for index,(name,(result,trace)) in enumerate(expected.items()):
        assert values[index*2] == [name,result,trace], (backend,name,values[index*2])
        actual = values[index*2+1]
        context = text if name in ['text','empty-mime'] else result if name in ['fail-mime','fail-read','fail-image'] else image('\n'+note)
        assert actual[:2] == [name+'-context',context], (backend,name,actual)
        assert 'access:/tmp/override/file;' in actual[2], (backend,name,actual)
    print(f'{backend}: callback order/errors, borrowed ownership, cancellation, cwd/model context and gated settlement PASS',flush=True)

"""Public read AgentTool: real files, paths, typed arguments and injected image processing."""
from upstream_pin import UPSTREAM
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('backends', nargs='*')
parser.add_argument('--prefix', default='build/read-public')
args = parser.parse_args()
prefix = ROOT/args.prefix
reference = UPSTREAM / 'packages/coding-agent/src/core/tools'
source = (reference/'read.ts').read_text()
body = source[source.index('function getNonVisionImageNote'):source.index('export function createReadTool(cwd')]
oracle = ROOT/'build/read-tool-oracle.ts'
oracle.write_text(
    'import {access,readFile} from "node:fs/promises";\n'
    'import {constants} from "node:fs";\n'
    'import {resolveReadPathAsync} from '+json.dumps(str(reference/'path-utils.ts'))+';\n'
    'import {detectSupportedImageMimeTypeFromFile} from '+json.dumps(str(reference.parent.parent/'utils/mime.ts'))+';\n'
    'import {truncateHead,DEFAULT_MAX_BYTES,DEFAULT_MAX_LINES,formatSize} from '+json.dumps(str(reference/'truncate.ts'))+';\n'
    + r"""
const readSchema = {}, readRenderers = {};
const readToolSystemPromptContribution = {snippet:'Read file contents',guidelines:[]};
const defaultReadOperations = {readFile,access:path=>access(path,constants.R_OK),detectImageMimeType:detectSupportedImageMimeTypeFromFile};
const mode = process.argv[3];
async function processImage(buffer,mime,{autoResizeImages}) {
  if(mode==='unsupported') return {ok:false,message:'Unsupported test image'};
  if(mode==='failed') throw new Error('processor failure');
  return {ok:true,data:'AQID',mimeType:'image/png',hints:autoResizeImages?['resized']:[]};
}
""" + body + r"""
const tool = createReadToolDefinition(process.argv[2],{autoResizeImages:mode!=='noresize'});
for(const value of process.argv.slice(4)) {
  try {
    const result = await tool.execute('test',JSON.parse(value));
    console.log(JSON.stringify({content:result.content.map(x=>x.type==='text'?['text',x.text]:['image',x.data,x.mimeType]),truncated:!!result.details}));
  } catch(e) { console.log(JSON.stringify({error:e.message})); }
}
""")
for backend, command in [('bun', ['bun', str(prefix)+'.js']),
                         ('native-1', [str(prefix), '--threads', '1']),
                         ('native-4', [str(prefix), '--threads', '4'])]:
    if args.backends and backend not in args.backends:
        continue
    with tempfile.TemporaryDirectory(prefix='bend-read-public-') as folder:
        root = Path(folder)
        home, cwd = root/'home', root/'work'
        home.mkdir(); cwd.mkdir()
        def run(inputs, mode='default'):
            result = subprocess.run(command+[str(cwd), str(home), mode, *map(json.dumps, inputs)], capture_output=True, text=True, timeout=60)
            assert result.returncode == 0 and not result.stderr, (backend, result.returncode, result.stderr)
            return [json.loads(line) for line in result.stdout.splitlines()]
        def text(value, truncated=False):
            return {'content': [['text', value]], 'truncated': truncated}
        sample = cwd/'file.txt'
        sample.write_bytes(b'one\ntwo\nthree\n')
        cases = [{'path':'file.txt'}, {'path':'file.txt','offset':2,'limit':1},
                 {'path':'file.txt','offset':0}, {'path':'file.txt','limit':0},
                 {'path':'file.txt','offset':5}]
        assert run(cases) == [text('one\ntwo\nthree\n'), text('two\n\n[2 more lines in file. Use offset=3 to continue.]'),
                             text('one\ntwo\nthree\n'), text('\n\n[4 more lines in file. Use offset=1 to continue.]'),
                             {'error':'Offset 5 is beyond end of file (4 lines total)'}]
        upstream = [json.loads(line) for line in subprocess.check_output(['bun',str(oracle),str(cwd),'default',*map(json.dumps,cases)],text=True).splitlines()]
        assert run(cases) == upstream
        bad = [{'path':'file.txt' ,key:value} for key in ['offset','limit'] for value in [-1,1.5,None,'1',2**49]]
        bad += [{}, {'path':1}, [], {'path':'file.txt','limit':True}]
        assert all('input is invalid' in value['error'] for value in run(bad))
        paths = [('~/home.txt',home/'home.txt'), ('@wide\u202fspace',cwd/'wide space'),
                 ('screen 1 AM.png',cwd/'screen 1\u202fAM.png'), ('screen 1 pm.png',cwd/'screen 1\u202fpm.png'),
                 ('café.txt',cwd/'cafe\u0301.txt'), ("Capture d'écran",cwd/'Capture d’écran'),
                 ("quote's.txt",cwd/'quote’s.txt'), ((root/'url name').as_uri(),root/'url name')]
        for given, actual in paths:
            actual.write_text('path result')
        assert run([{'path':given} for given,_ in paths]) == [text('path result')]*len(paths)
        # Existing exact names win over all alternative filename spellings.
        (cwd/'café.txt').write_text('exact')
        assert run([{'path':'café.txt'}]) == [text('exact')]
        (cwd/'empty').write_bytes(b'')
        (cwd/'bom').write_bytes(b'\xef\xbb\xbftext')
        (cwd/'invalid').write_bytes(b'a\xffb')
        assert run([{'path':'empty'},{'path':'bom'},{'path':'invalid'}]) == [text(''),text('\ufefftext'),{'error':'File contains invalid UTF-8'}]
        errors = run([{'path':'missing'}, {'path':'.'}, {'path':'file://remote/forbidden'}])
        assert errors[0]['error'].startswith('Error 2:') and errors[1]['error'].startswith('Error 21:')
        assert errors[2] == {'error':'Invalid file path'}
        (cwd/'many').write_text('line\n'*2005)
        result = run([{'path':'many'}])[0]
        assert result['truncated'] and result['content'][0][1].endswith('[Showing lines 1-2000 of 2006. Use offset=2001 to continue.]')
        (cwd/'image').write_bytes(b'GIF89a')
        assert run([{'path':'image'}]) == [text('Read image file [image/gif]\n[Image omitted: could not be resized below the inline image size limit.]')]
        assert run([{'path':'image'}], 'processed') == [{'content':[['text','Read image file [image/png]\nresized'],['image','AQID','image/png']], 'truncated':False}]
        assert run([{'path':'image'}], 'noresize') == [{'content':[['text','Read image file [image/png]'],['image','AQID','image/png']], 'truncated':False}]
        assert run([{'path':'image'}], 'unsupported') == [text('Read image file [image/gif]\nUnsupported test image')]
        assert run([{'path':'image'}], 'failed') == [{'error':'processor failure'}]
        for mode in ['processed','noresize','unsupported','failed']:
            upstream = [json.loads(line) for line in subprocess.check_output(['bun',str(oracle),str(cwd),mode,json.dumps({'path':'image'})],text=True).splitlines()]
            assert run([{'path':'image'}],mode) == upstream
    print(f'{backend}: public read files/paths/arguments/truncation and typed image processing PASS', flush=True)

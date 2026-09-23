"""Public edit factory, disk bytes and exact pinned rendering behavior."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--bun-only',action='store_true')
p.add_argument('--native-only',action='store_true')
p.add_argument('--diff-package',type=Path,default=ROOT/'build/package')
args=p.parse_args()
cases=[
 ('basic',b'hello world\n',[('world','there')]),
 ('large file',b'a'*200000+b'\nneedle\n',[('needle','updated')]),
 ('CRLF',b'one\r\ntwo\r\n',[('two','TWO')]),
 ('BOM',b'\xef\xbb\xbfone\r\ntwo\r\n',[('two','TWO')]),
 ('original snapshot',b'foo\nbar\n',[('foo\n','foo bar\n'),('bar\n','BAR\n')]),
 ('disjoint',b'alpha\nbeta\ngamma\n',[('gamma','GAMMA'),('alpha','ALPHA')]),
 ('fuzzy untouched',b'keep  \nfirst target  \nafter\n',[('first target\nafter','FIRST\nAFTER')]),
 ('Unicode','ＡＢＣ１２３\ncafe\u0301\n'.encode(),[('ABC123\ncafé\n','XYZ789\ncoffee\n')]),
 ('not found',b'hello',[('missing','x')]),
 ('duplicate',b'foo foo',[('foo','bar')]),
 ('overlap',b'one\ntwo\nthree\n',[('one\ntwo','a'),('two\nthree','b')]),
 ('atomic failure',b'alpha\nbeta\n',[('alpha','ALPHA'),('missing','x')]),
 ('no change',b'hello',[('hello','hello')]),
 ('empty needle',b'hello',[('','x')]),
 ('legacy',b'hello',[('hello','bye')]),
 ('legacy appended',b'one\ntwo\n',[('one','ONE'),('two','TWO')]),
]
def unpoints(s): return ''.join(chr(int(x)) for x in s.split(',')) if s else ''
with tempfile.TemporaryDirectory(prefix='bend-edit-') as directory:
    root=Path(directory)
    source=Path(os.environ.get('PI_MONO','/home/agent/code/pi-mono'))/'packages/coding-agent/src/core/tools/edit-diff.ts'
    original=source.read_text()
    assert hashlib.sha256(original.encode()).hexdigest()=='f85a9809eb44b9828236050cf38a8e45933e5cfd583a186e9a0e55a664dd3e8d', 'Unexpected edit-diff.ts revision'
    assert json.loads((args.diff_package/'package.json').read_text())['version']=='8.0.4'
    code=re.sub(r'^import .*;\n','',original.split('export interface EditDiffResult')[0],flags=re.M)
    driver=root/'oracle.ts'
    driver.write_text('import * as Diff from '+json.dumps(str(args.diff_package.resolve()/'libesm/index.js'))+';\n'+code+'''
const rows=await Bun.file(process.argv[2]).json();
console.log(JSON.stringify(rows.map(([name,text,edits])=>{try {
 const bom=text.startsWith('\\ufeff')?'\\ufeff':'';
 const content=bom?text.slice(1):text;
 const ending=detectLineEnding(content);
 const {baseContent,newContent}=applyEditsToNormalizedContent(normalizeToLF(content),edits,'file.txt');
 const rendered=generateDiffString(baseContent,newContent);
 return {disk:bom+restoreLineEndings(newContent,ending),text:`Successfully replaced ${edits.length} block(s) in file.txt.`,diff:rendered.diff,patch:generateUnifiedPatch('file.txt',baseContent,newContent),first:rendered.firstChangedLine??null};
 }catch(error){return {error:error.message}}})));
''')
    data=root/'cases.json'
    data.write_text(json.dumps([[name,raw.decode(),[dict(oldText=a,newText=b) for a,b in pairs]] for name,raw,pairs in cases]))
    expected=json.loads(subprocess.check_output(['bun',str(driver),str(data)],text=True))
    commands=[] if args.native_only else [('Bun',['bun',str(ROOT/'build/edit-public.js')])]
    if not args.bun_only: commands.extend([(f'native{i}',[os.environ.get('EDIT_PUBLIC_BINARY',str(ROOT/'build/edit-public')),'--threads',str(i)]) for i in [1,4]])
    for backend,command in commands:
        def run(arguments):
            result=subprocess.run(command+[str(root),json.dumps(arguments)],capture_output=True,text=True,timeout=60)
            assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr[:2000])
            fields=result.stdout.strip().split('|')
            if fields[0]=='error': return {'error':unpoints(fields[1])}
            return dict(zip(['text','diff','patch'],map(unpoints,fields[1:4])),first=None if fields[4]=='none' else int(fields[4]))
        path=root/'file.txt'
        for (name,raw,pairs),oracle in zip(cases,expected):
            path.write_bytes(raw)
            edits=[dict(oldText=a,newText=b) for a,b in pairs]
            arguments=dict(path='file.txt',edits=edits)
            if name=='legacy': arguments=dict(path='file.txt',**edits[0])
            if name=='legacy appended': arguments=dict(path='file.txt',edits=edits[:-1],**edits[-1])
            actual=run(arguments)
            assert actual=={k:v for k,v in oracle.items() if k!='disk'},(backend,name,actual,oracle)
            assert path.read_bytes()==(oracle['disk'].encode() if 'disk' in oracle else raw),(backend,name)
        for arguments in [dict(path='file.txt',edits=[]),dict(path='file.txt',edits='[{"oldText":"hello","newText":"bye"}]'),dict(path='file.txt',edits=dict(oldText='hello',newText='bye')),dict(path='file.txt',oldText='hello'),dict(path=1,edits=[]),dict(path='file.txt',edits=[dict(oldText=1,newText='bye')])]:
            path.write_bytes(b'hello')
            assert 'error' in run(arguments),(backend,arguments)
            assert path.read_bytes()==b'hello'
        path.write_bytes(b'hello\xff')
        assert run(dict(path='file.txt',edits=[dict(oldText='hello',newText='bye')]))=={'error':'File contains invalid UTF-8'}
        assert path.read_bytes()==b'hello\xff'
        path.unlink()
        assert run(dict(path='file.txt',edits=[dict(oldText='a',newText='b')]))=={'error':'Could not edit file: file.txt. Error code: ENOENT.'}
        path.write_bytes(b'a');path.chmod(0o400)
        assert run(dict(path='file.txt',edits=[dict(oldText='a',newText='b')]))=={'error':'Could not edit file: file.txt. Error code: EACCES.'}
        path.chmod(0o600)
        print(f'{backend}: public factory, exact results/patches, BOM/CRLF, atomic errors, legacy and strict inputs PASS',flush=True)

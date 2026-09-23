"""Public grep over rg against an rg-driven oracle of upstream's formatting and injected operation contracts."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
# Process spawning is native-only; the Bun lane has no process primitive.
p.add_argument('backends',nargs='*',default=['native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/grep-public')
p.add_argument('--rg',default=shutil.which('rg'))
a=p.parse_args()
RG=str(Path(a.rg).resolve())
print(subprocess.check_output([RG,'--version'],text=True).splitlines()[0],flush=True)

def clipped(text):
    size=0
    for i,c in enumerate(text):
        size+=2 if ord(c)>0xffff else 1
        if size>500:return text[:i]+'... [truncated]',True
    return text,False

for backend in a.backends:
    command=[str(a.prefix),'--threads',backend[-1]]
    checks=0
    with tempfile.TemporaryDirectory(prefix='bend-grep-public-',dir='/var/tmp') as tmp:
        base=Path(tmp);home=base/'home';home.mkdir();root=base/'work';root.mkdir();xdg=home/'.config';xdg.mkdir()
        # The tool finds rg in the agent's bin directory. The rg configuration
        # sorts by path so that rg's parallel output order is reproducible.
        bindir=home/'.pi/agent/bin';bindir.mkdir(parents=True);(bindir/'rg').symlink_to(RG)
        rgrc=base/'rgrc';rgrc.write_text('--sort=path\n')
        env={**os.environ,'HOME':str(home),'XDG_CONFIG_HOME':str(xdg),'RIPGREP_CONFIG_PATH':str(rgrc)}
        env.pop('PI_CODING_AGENT_DIR',None)
        def write(path,text):
            path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
            if isinstance(text,bytes):path.write_bytes(text)
            else:path.write_text(text)
        def run(args,mode='native',entries=':native',cwd=None,extra_env=None):
            global checks
            result=subprocess.run(command+[mode,str(cwd or root),str(home),json.dumps(args),entries],cwd=root,env={**env,**(extra_env or {})},text=True,capture_output=True,timeout=90)
            assert result.returncode==0 and not result.stderr,(backend,mode,result.returncode,result.stdout[-500:],result.stderr[-1000:])
            value={};trace=[]
            for line in result.stdout.splitlines():
                kind,text=line.split(':',1)
                if kind in ['isDirectory','readFile']:trace.append((kind,base64.b64decode(text).decode()))
                elif kind=='details':value[kind]=text
                else:value[kind]=base64.b64decode(text).decode()
            checks+=1
            return value,trace
        def oracle(args):
            search=Path(args.get('path') or root)
            if not search.is_absolute():search=root/search
            flags=[RG,'--json','--line-number','--color=never','--hidden']
            if args.get('ignoreCase'):flags+=['--ignore-case']
            if args.get('literal'):flags+=['--fixed-strings']
            if args.get('glob'):flags+=['--glob',args['glob']]
            result=subprocess.run(flags+['--',args['pattern'],str(search)],cwd=root,env=env,capture_output=True)
            maximum=max(1,args.get('limit',100))
            events=[event['data'] for line in result.stdout.decode('utf-8','replace').splitlines() if line.strip() and (event:=json.loads(line))['type']=='match'][:maximum]
            reached=len(events)>=maximum
            if not reached and result.returncode not in (0,1):
                return {'error':result.stderr.decode('utf-8','replace').strip() or f'ripgrep exited with code {result.returncode}'}
            if not events:return {'text':'No matches found','details':'none'}
            lines=[];line_cut=False;context=max(0,args.get('context',0))
            for event in events:
                if 'text' not in event['path']:continue
                path=event['path']['text'];number=event['line_number']
                relative=os.path.relpath(path,search) if search.is_dir() else ''
                display=relative if relative and relative!='.' and not relative.startswith('..') else os.path.basename(path)
                if not context and 'text' in event['lines']:
                    text=event['lines']['text'].replace('\r\n','\n').replace('\r','').removesuffix('\n')
                    text,cut=clipped(text);line_cut|=cut;lines.append(f'{display}:{number}: {text}')
                else:
                    # Node's readFile(path, 'utf-8'): replacement, BOM kept.
                    content=Path(path).read_bytes().decode('utf-8','replace').replace('\r\n','\n').replace('\r','\n').split('\n')
                    for index in range(max(1,number-context),min(len(content),number+context)+1):
                        text,cut=clipped(content[index-1]);line_cut|=cut
                        sep=':' if index==number else '-'
                        lines.append(f'{display}{sep}{index}{sep} {text}')
            text='\n'.join(lines);assert len(text.encode())<=51200,'byte-cap cases have explicit assertions'
            notices=[]
            if reached:notices.append(f'{maximum} matches limit reached. Use limit={maximum*2} for more, or refine pattern')
            if line_cut:notices.append('Some lines truncated to 500 chars. Use read tool to see full lines')
            if notices:text+='\n\n['+'. '.join(notices)+']'
            return {'text':text,'details':f'{maximum if reached else "none"}|none|{"True" if line_cut else "none"}' if notices else 'none'}
        def compare(args):
            value,_=run(args);expected=oracle(args);assert value==expected,(backend,args,expected,value)
            return value

        # tools.test.ts: should include filename when searching a single file.
        file=root/'test.txt';write(file,'first line\nneedle here\nlast line\n')
        assert compare({'pattern':'needle','path':str(file)})['text']=='test.txt:2: needle here'
        # Original global limit/context assertion: second match excluded.
        write(file,'before\nneedle first\nafter\nneedle second\nlast\n')
        value=compare({'pattern':'needle','path':str(file),'limit':1,'context':1})
        assert value['text']=='test.txt-1- before\ntest.txt:2: needle first\ntest.txt-3- after\n\n[1 matches limit reached. Use limit=2 for more, or refine pattern]'
        # Original flag-like pattern assertion: no command execution.
        sentinel=root/'must-not-exist'
        payload=root/'payload.sh';write(payload,f'#!/bin/sh\necho executed > {sentinel}\ncat "$1"\n');payload.chmod(0o755)
        assert compare({'pattern':f'--pre={payload}','path':str(file)})['text']=='No matches found'
        assert not sentinel.exists()
        override=root/'override';write(override/'hit.txt','context hit\n')
        value,_=run({'pattern':'context'},mode='context',cwd=override)
        assert value['text']=='hit.txt:1: context hit'

        samples=root/'samples'
        write(samples/'a.txt','alpha\nBETA\nαβγ\né😀\nword words\n\nlast')
        write(samples/'b.ts','alpha\r\nbeta\rbeta\n[a-z]+\n--help\n')
        write(samples/'.hidden','alpha\n');write(samples/'nested'/'c.ts','alpha\nalpha\n')
        for pattern in ['', '^alpha$', r'\Aalpha', r'alpha\z', '(?i)beta', r'\p{Greek}+', 'é.', r'\bword\b', r'(alpha|beta)+', '--help', r'(?-u)\xC3\xA9', '(?R)^alpha$', r'[^\n]', r'[a\n]', r'[\n-a]', r'[\n--\n]']:
            compare({'pattern':pattern,'path':str(samples)})
        for context in [0,1,2,10]:compare({'pattern':'alpha','path':str(samples),'context':context})
        for maximum in [0,1,2,4,100]:compare({'pattern':'alpha','path':str(samples),'limit':maximum})
        for args in [{'pattern':'beta','ignoreCase':True},{'pattern':'[a-z]+','literal':True},{'pattern':'é😀','literal':True},{'pattern':'ALPHA','ignoreCase':True,'literal':True}]:compare({**args,'path':str(samples)})
        for glob in ['*.ts','**/*.ts','!*.ts','samples/*.ts','/samples/*.ts','samples/nested/*','*','!*','*.TXT']:
            compare({'pattern':'alpha','path':str(samples),'glob':glob})

        outside=root/'outside';write(outside/'.gitignore','ignored.txt\n');write(outside/'ignored.txt','hit\n');write(outside/'.fdignore','fd.txt\n');write(outside/'fd.txt','hit\n')
        write(outside/'.ignore','ordinary.txt\n');write(outside/'ordinary.txt','hit\n');write(outside/'.rgignore','rg.txt\n');write(outside/'rg.txt','hit\n')
        write(xdg/'fd/ignore','fd-global.txt\n');write(outside/'fd-global.txt','hit\n')
        compare({'pattern':'hit','path':str(outside),'glob':'*.txt'})
        compare({'pattern':'hit','path':str(outside)})
        (outside/'.git').mkdir();compare({'pattern':'hit','path':str(outside)})
        write(outside/'.rgignore','!ordinary.txt\nrg.txt\n');compare({'pattern':'hit','path':str(outside)})
        write(outside/'.git/info/exclude','excluded.txt\n');write(outside/'excluded.txt','hit\n');compare({'pattern':'hit','path':str(outside)})
        write(outside/'.gitignore','ignored/\n*.secret\n');write(outside/'ignored'/'child.txt','hit\n');write(outside/'file.secret','hit\n')
        compare({'pattern':'hit','path':str(outside),'glob':'*.txt'})
        compare({'pattern':'hit','path':str(outside),'glob':'*'})
        compare({'pattern':'hit','path':str(outside/'ignored')})
        # Global Git rules apply only inside repositories; nested repositories
        # stop inherited Git rules but still inherit ordinary ignore files.
        write(xdg/'git/ignore','global.txt\n');write(outside/'global.txt','hit\n')
        compare({'pattern':'hit','path':str(outside)})
        detached=root/'detached';write(detached/'global.txt','hit\n')
        compare({'pattern':'hit','path':str(detached)})
        nested=outside/'nested';(nested/'.git').mkdir(parents=True)
        write(outside/'.gitignore','parent.txt\n');write(nested/'parent.txt','hit\n')
        write(outside/'.ignore','ordinary.txt\n');write(nested/'ordinary.txt','hit\n')
        write(nested/'global.txt','hit\n');compare({'pattern':'hit','path':str(outside)})
        compare({'pattern':'hit','path':str(nested)})
        excludes=home/'custom-excludes';write(excludes,'custom.txt\n')
        write(home/'.gitconfig',f'[core]\n  excludesFile = {excludes}\n')
        write(outside/'custom.txt','hit\n');compare({'pattern':'hit','path':str(outside)})
        quoted=home/'custom excludes';write(quoted,'custom.txt\n')
        write(home/'.gitconfig',f'[core]\n excludesFile = "{quoted}"\n')
        compare({'pattern':'hit','path':str(outside)})
        (home/'.gitconfig').unlink()
        (outside/'link').symlink_to(samples,target_is_directory=True)
        (outside/'linked.txt').symlink_to(samples/'a.txt')
        os.mkfifo(outside/'fifo');compare({'pattern':'alpha','path':str(outside)})
        compare({'pattern':'alpha','path':str(outside/'linked.txt')})

        # Context callbacks remain authoritative, are cached once per file,
        # and are never called for zero-context output.
        for context in [0,1]:
            args={'pattern':'needle','path':str(file),'context':context}
            value,trace=run(args,mode='injected',entries='A\ncustom one\nC\ncustom two\nE\n')
            assert trace[0]==('isDirectory',str(file)) and sum(k=='readFile' for k,_ in trace)==context
            if context:assert 'custom one' in value['text'] and 'custom two' in value['text']
            else:assert value==oracle(args)
        value,trace=run({'pattern':'needle','path':str(file),'context':1},mode='read-error')
        assert value['text']=='test.txt:2: (unable to read file)\ntest.txt:4: (unable to read file)' and len(trace)==2
        value,trace=run({'pattern':'needle','path':str(file),'context':1},mode='preabort')
        assert value=={'error':'Operation aborted'} and not trace,(value,trace)
        # Upstream listens for an abort only once rg has started, and formats
        # the output after rg exits without checking again: an abort during
        # isDirectory or a context read leaves the search to finish.
        for mode in ['abort-isDirectory','abort-readFile']:
            value,trace=run({'pattern':'needle','path':str(file),'context':1},mode=mode,entries='A\ncustom one\nC\ncustom two\nE\n')
            assert 'custom one' in value['text'] and [k for k,_ in trace]==['isDirectory','readFile'],(mode,value,trace)
        for mode in ['missing','directory-error']:
            value,_=run({'pattern':'needle','path':str(file)},mode=mode);assert value=={'error':f'Path not found: {file}'}
        value,trace=run({'pattern':'needle','path':str(file)},mode='reuse',entries='caller-owned');assert trace[-1]==('readFile','/virtual')
        value,_=run({'pattern':'needle','path':'absent'});assert value=={'error':f'Path not found: {root / "absent"}'}
        for invalid in [{}, {'pattern':4},{'pattern':'a','limit':-1},{'pattern':'a','limit':1.5},{'pattern':'a','context':-1},{'pattern':'a','ignoreCase':'yes'},{'pattern':'a','literal':1},{'pattern':'a','glob':5}]:
            value,trace=run(invalid,mode='injected');assert 'input is invalid' in value['error'] and not trace
        # rg's own failures surface as its stderr.
        denied=root/'denied';write(denied/'file','needle\n');denied.chmod(0)
        try:
            value,_=run({'pattern':'needle','path':str(denied)});assert value==oracle({'pattern':'needle','path':str(denied)}) and 'denied' in value['error'].lower(),value
        finally:denied.chmod(0o700)
        for target in [file,samples]:
            value,_=run({'pattern':'needle','path':str(target),'glob':'['});assert value==oracle({'pattern':'needle','path':str(target),'glob':'['}) and 'glob' in value['error']
        compare({'pattern':'needle','path':str(file),'glob':'!*.txt'})
        for pattern in ['[','(?=a)',r'foo\nbar',r'[\n]',r'\x0a']:
            value=compare({'pattern':pattern,'path':str(file)});assert 'regex' in value['error'],value
        compare({'pattern':'foo\nbar','literal':True,'path':str(file)})
        # rg transcodes UTF-16 by its BOM; context lines are reread as UTF-8,
        # as upstream does.
        for encoding,bom in [('utf-8',b'\xef\xbb\xbf'),('utf-16le',b'\xff\xfe'),('utf-16be',b'\xfe\xff')]:
            encoded=root/f'{encoding}.txt';write(encoded,bom+'before\nneedle 😀\nafter\n'.encode(encoding))
            for context in [0,1]:compare({'pattern':'needle','path':str(encoded),'context':context})
        # Invalid UTF-8 lines reach the tool as bytes; the file is read instead.
        for raw in [b'needle\n\xff',b'needle\xc3',b'\xff\xfea',b'x\xffneedle\n']:
            broken=root/'broken';write(broken,raw)
            for context in [0,1]:compare({'pattern':'needle','path':str(broken),'context':context})
        binary=root/'binary'
        for raw in [b'needle\0text\n',b'needle\n'+b'x'*70000+b'\0',b'\xff\xfe'+ 'needle\0text\n'.encode('utf-16le'),b'needle\n'+b'x'*70000+b'\xff']:
            write(binary,raw);compare({'pattern':'needle','path':str(binary),'limit':1});compare({'pattern':'needle','path':str(root)})
        long=root/'long';write(long,'x'*100000+'needle\n'+'😀'*400+'needle\n')
        compare({'pattern':'needle','path':str(long)})
        large=root/'large';write(large,('needle '+'a'*490+'\n')*200)
        value,_=run({'pattern':'needle','path':str(large),'limit':200})
        assert '50.0KB limit reached' in value['text'] and value['details'].startswith('200|True:')
        assert value['text'].endswith('for more, or refine pattern. 50.0KB limit reached]')
        value,_=run({'pattern':'needle','path':str(file),'limit':1},mode='repeat')
        before,after=map(int,value['fds'].split(':'));assert before==after and before<100
        # rg blocks reading a FIFO without a writer until the abort kills it.
        slow=root/'slow';os.mkfifo(slow)
        value,_=run({'pattern':'absent-pattern','path':str(slow)},mode='abort-native');assert value=={'error':'Operation aborted'},value
        slow.unlink()
    print(f'{backend}: {checks} public grep scenarios passed',flush=True)

"""Public find over fd against an fd-driven oracle of upstream's output and injected operation contracts."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
# Process spawning is native-only; the Bun lane has no process primitive.
p.add_argument('backends',nargs='*',default=['native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/find-public')
p.add_argument('--fd',type=Path,default=Path.home()/'.pi/agent/bin/fd')
a=p.parse_args()
FD=str(a.fd.resolve())
print(subprocess.check_output([FD,'--version'],text=True).strip(),flush=True)

def clean(path):
    return str(path)

for backend in a.backends:
    command=[str(a.prefix),'--threads',backend[-1]]
    checks=0
    with tempfile.TemporaryDirectory(prefix='bend-find-public-',dir='/var/tmp') as tmp:
        base=Path(tmp); home=base/'home'; home.mkdir(); root=base/'work'; root.mkdir(); xdg=home/'.config'; xdg.mkdir()
        # The tool finds fd in the agent's bin directory.
        bindir=home/'.pi/agent/bin';bindir.mkdir(parents=True);(bindir/'fd').symlink_to(FD)
        env={**os.environ,'HOME':str(home),'XDG_CONFIG_HOME':str(xdg)}
        env.pop('PI_CODING_AGENT_DIR',None)
        def run(mode='native',pattern='**',path='none',limit='none',entries='',cwd=None):
            global checks
            result=subprocess.run(command+[mode,str(cwd or root),str(home),"pattern:"+pattern,str(path),str(limit),entries],cwd=root,env=env,text=True,capture_output=True,timeout=60)
            assert result.returncode==0 and not result.stderr,(backend,mode,result.returncode,result.stdout[-500:],result.stderr)
            value={};trace=[]
            for line in result.stdout.splitlines():
                kind,text=line.split(':',1)
                if kind in ['exists','glob']:trace.append((kind,base64.b64decode(text).decode()))
                elif kind=='details':value[kind]=text
                else:value[kind]=base64.b64decode(text).decode()
            checks+=1
            return value,trace
        def write(path,text=''):
            path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
        def relativize(line,search):
            value=os.path.relpath(line,search) if line.startswith('/') else line
            value='' if value=='.' else value
            return value+'/' if line.endswith('/') and not value.endswith('/') else value
        # upstream find.ts over the same fd: readline lines, trimmed and
        # relativized, with its notices (outputs stay below the byte cap).
        def oracle(pattern,path=root,limit=1000):
            args=[FD,'--glob','--color=never','--hidden']
            if not any(os.path.exists(parent/'.git') for parent in [path,*path.parents]):args+=['--no-require-git']
            args+=['--max-results',str(limit)]
            if '/' in pattern:
                args+=['--full-path']
                if not pattern.startswith(('/', '**/')) and pattern!='**':pattern='**/'+pattern
            result=subprocess.run(args+['--',pattern,str(path)],cwd=root,env=env,capture_output=True)
            lines=re.split(r'\r\n|\n|\r',result.stdout.decode('utf-8','replace'))
            if lines and lines[-1]=='':lines.pop()
            output='\n'.join(lines)
            if result.returncode!=0 and not output:
                return {'error':result.stderr.decode('utf-8','replace').strip() or f'fd exited with code {result.returncode}'}
            if not output:return {'text':'No files found matching pattern','details':'none'}
            found=[relativize(line.strip(),path) for line in lines if line.strip()]
            text='\n'.join(found)
            if len(found)>=limit:
                text+=f'\n\n[{limit} results limit reached. Use limit={limit*2} for more, or refine pattern]'
                return {'text':text,'details':f'{limit}|none'}
            return {'text':text,'details':'none'}
        def listing(value):
            body,_,notice=value['text'].partition('\n\n[')
            return sorted([] if body=='No files found matching pattern' else body.split('\n')),notice
        # fd's parallel traversal orders its output freely, so listings compare
        # as sets; notices and details compare exactly.
        def compare(pattern,path=root,limit=None):
            value,trace=run('native',pattern,str(path),'none' if limit is None else limit)
            want=oracle(pattern,path,1000 if limit is None else limit)
            assert not trace,(trace)
            if 'error' in want:assert value==want,(backend,pattern,path,value,want)
            elif want['details']=='none':assert listing(value)==listing(want) and value['details']=='none',(backend,pattern,path,value,want)
            else:
                # Which results a capped traversal reaches first is fd's choice.
                everything=set(listing(oracle(pattern,path,10**6))[0])
                assert len(listing(value)[0])==len(listing(want)[0]) and set(listing(value)[0])<=everything and listing(value)[1]==listing(want)[1] and value['details']==want['details'],(backend,pattern,path,value,want)
            return (listing(value)[0] if 'text' in value else None),value
        native=compare

        # Original tools.test.ts: hidden files, .gitignore, parse errors,
        # flag-like patterns and dynamic ctx.cwd.
        write(root/'.secret/hidden.txt');write(root/'visible.txt');write(root/'ignored.txt')
        write(root/'.gitignore','ignored.txt\n')
        actual,_=compare('**/*.txt');assert actual==['.secret/hidden.txt','visible.txt']
        _,value=compare('[');assert 'error' in value
        assert native('--help')[0]==[]
        write(root/'ctx-cwd-find.txt');value,_=run('context','ctx-cwd-find.txt');assert value['text']=='ctx-cwd-find.txt',value
        (root/'.gitignore').unlink()
        # #3302 path globs: slash matching includes the full absolute candidate.
        write(root/'some/parent/child/file.ext');write(root/'some/parent/child/test.spec.ts');write(root/'src/foo/bar/example.spec.ts')
        for pattern in ['*.spec.ts','some/parent/child/**','**/parent/child/*','src/**/*.spec.ts',str(root/'src')+'/**/*.ts','**/src/**','src/*/*.ts','src/**/bar/?.spec.ts']:
            actual,_=compare(pattern)
            if pattern=='*.spec.ts':assert sorted(actual)==['some/parent/child/test.spec.ts','src/foo/bar/example.spec.ts']
            elif pattern in ['some/parent/child/**','**/parent/child/*']:assert {'some/parent/child/file.ext','some/parent/child/test.spec.ts'} <= set(actual)
            elif pattern=='src/**/*.spec.ts':assert actual==['src/foo/bar/example.spec.ts']
        # #3303 scoped nested rules, with and without a repository boundary.
        scoped=root/'scoped';write(scoped/'a/.gitignore','ignored.txt\n')
        for name in ['a/ignored.txt','a/kept.txt','b/ignored.txt','b/kept.txt','root.txt']:write(scoped/name)
        actual,_=compare('**/*.txt',scoped);assert sorted(actual)==['a/kept.txt','b/ignored.txt','b/kept.txt','root.txt']
        write(scoped/'a/deep/.gitignore','secret.txt\n')
        for name in ['a/ignored.txt','a/kept.txt','a/deep/ignored.txt','a/deep/secret.txt','a/deep/kept.txt','b/ignored.txt','b/kept.txt','root.txt']:write(scoped/name)
        actual,_=compare('**/*.txt',scoped);assert sorted(actual)==['a/deep/kept.txt','a/kept.txt','b/ignored.txt','b/kept.txt','root.txt']
        repo=root/'repo';(repo/'.git').mkdir(parents=True)
        write(repo/'.gitignore','*.txt\n!keep.txt\nblocked/\n');write(repo/'drop.txt');write(repo/'keep.txt');write(repo/'blocked/keep.txt')
        write(repo/'nested/.gitignore','nested.txt\n');(repo/'nested/.git').mkdir()
        write(repo/'nested/outer.txt');write(repo/'nested/nested.txt');write(repo/'nested/keep.txt')
        actual,_=compare('*.txt',repo);assert 'nested/outer.txt' in actual and 'drop.txt' not in actual
        compare('*.txt',repo/'nested')
        outside=root/'outside';write(outside/'.gitignore','*.txt\n');write(outside/'nested/.gitignore','!keep.txt\n');(outside/'nested/.git').mkdir()
        write(outside/'nested/outer.txt');write(outside/'nested/keep.txt');actual,_=compare('*.txt',outside);assert actual==['nested/keep.txt'],actual
        compare('*.txt',repo/'blocked')  # Explicit roots bypass ancestor pruning.
        # Source priorities, ancestor sources, directory pruning and no hard
        # node_modules/.git exclusions in the native default.
        priority=root/'priority';(priority/'.git').mkdir(parents=True)
        write(priority/'.gitignore','*.txt\n');write(priority/'.ignore','!one.txt\n!three.txt\n');write(priority/'.fdignore','one.txt\n!two.txt\n')
        for name in ['one.txt','two.txt','three.txt','four.txt','deep/one.txt','deep/two.txt','deep/three.txt']:write(priority/name)
        compare('*.txt',priority);compare('*.txt',priority/'deep')
        write(priority/'deep/.gitignore','!four.txt\n');write(priority/'deep/four.txt');compare('*.txt',priority)
        write(priority/'.git/info/exclude','*.bin\n');write(priority/'hidden.bin');compare('*.bin',priority)
        write(root/'node_modules/dependency.js');write(repo/'.git/metadata.js');compare('*.js',root)
        # Symlink entries are emitted, never followed. FIFO/device-like entries
        # are inspected by metadata and never opened.
        links=root/'links';links.mkdir();(links/'dir').mkdir();write(links/'dir/child')
        (links/'link').symlink_to('dir');(links/'broken').symlink_to('missing');(links/'cycle').symlink_to('cycle');os.mkfifo(links/'fifo')
        compare('*',links)
        blocked=root/'unreadable';write(blocked/'x');blocked.chmod(0)
        try:
            compare('x',blocked)
            compare('x',root)
        finally:
            blocked.chmod(0o700)
        value,_=run(path=root/'visible.txt');assert 'not a directory' in value['error']
        # Basename smart case, classes, braces and recursive paths.
        cases=root/'patterns'
        for name in ['Alpha.TS','alpha.ts','beta.ts','delta.json','sub/abc.ts','sub/deep/a.ts','.hidden.ts','literal[1].ts','--help']:write(cases/name)
        for pattern in ['*.ts','*.TS','[ab]*.ts','[!A-Z]*.ts','{alpha,beta}.ts','**/*.{ts,json}','sub/**/*.ts','sub/*/*.ts','literal[[]1].ts','--help','']:
            compare(pattern,cases)
        # Global Git and fd ignore sources. Reset each source between cases.
        globaldir=root/'global';write(globaldir/'one.tmp');write(globaldir/'two.tmp');write(globaldir/'three.tmp')
        write(xdg/'git/ignore','one.tmp\n');compare('*.tmp',globaldir)
        write(xdg/'fd/ignore','two.tmp\n');compare('*.tmp',globaldir)
        write(home/'custom-ignore','three.tmp\n');write(home/'.gitconfig','[core]\n excludesFile = '+str(home/'custom-ignore')+'\n');compare('*.tmp',globaldir)
        (home/'.gitconfig').unlink();write(xdg/'git/config','[core]\n excludesfile = '+str(home/'custom-ignore')+'\n');compare('*.tmp',globaldir)
        (xdg/'git/config').unlink();(xdg/'git/ignore').unlink();(xdg/'fd/ignore').unlink()
        # Global anchored patterns follow fd's process-relative path semantics.
        write(globaldir/'sub/a.tmp');write(xdg/'git/ignore','/sub/a.tmp\n')
        compare('*.tmp',globaldir)
        (xdg/'git/ignore').unlink()
        # Linked worktree .git and commondir, without requiring a HEAD file.
        worktree=root/'worktree';worktree.mkdir();metadata=base/'git-metadata';(metadata/'worktrees/w').mkdir(parents=True)
        write(worktree/'.git','gitdir: '+str(metadata/'worktrees/w')+'\n')
        write(metadata/'worktrees/w/commondir',str(metadata)+'\n')
        write(metadata/'info/exclude','excluded.txt\n');write(worktree/'excluded.txt');write(worktree/'kept.txt')
        compare('*.txt',worktree)

        # Relative gitdir/commondir, quoted and malformed Git configuration and
        # malformed ignore files are fd's to interpret.
        write(worktree/'.git','gitdir: ../../git-metadata/worktrees/w\n')
        write(metadata/'worktrees/w/commondir','../..\n')
        compare('*.txt',worktree)
        write(home/'ignore with spaces','one.tmp\n')
        write(home/'.gitconfig','[core]\nexcludesFile = "'+str(home/'ignore with spaces')+'"\n')
        compare('*.tmp',globaldir)
        write(home/'.gitconfig','[core]\nexcludesFile = "unfinished\n')
        compare('**',globaldir)
        (home/'.gitconfig').unlink()
        invalid=root/'invalid';write(invalid/'kept.txt');(invalid/'.gitignore').write_bytes(b'\xff')
        compare('**',invalid)

        # POSIX #6104 path normalization, retaining literal backslashes.
        for search,path,want in [('/', '/home/user/file.txt','home/user/file.txt'),('/', '/home/user/project/','home/user/project/'),('/home/user','/home/user/file\\','file\\'),('/workspace/project','/tmp/results/file.txt','../../tmp/results/file.txt'),('/workspace/project','/tmp/results/dir/','../../tmp/results/dir/'),('/a','/a2/x','../a2/x'),('/a','relative/','relative/')]:
            value,_=run('relative',path=path,cwd=search);assert value=={'relative':want},(backend,value,want)
        value,trace=run('injected',cwd='/',entries='/home/user/project/\n/home/user/project/file.txt')
        assert value=={'text':'home/user/project/\nhome/user/project/file.txt','details':'none'} and trace==[('exists','/'),('glob','**|/|1000')]
        # Injected operations preserve their order and result count, including
        # over-limit results; they receive exact ignore/limit options.
        for maximum,entries,text,details in [(2,'z\na','z\na\n\n[2 results limit reached]','2|none'),(1,'z\na','z\na\n\n[1 results limit reached]','1|none'),(0,'a','a\n\n[0 results limit reached]','0|none'),(0,'','No files found matching pattern','none')]:
            value,trace=run('injected',cwd='/virtual',limit=maximum,entries=entries);assert value=={'text':text,'details':details};assert trace[-1]==('glob',f'**|/virtual|{maximum}')
        for mode,error,n in [('missing','Path not found: /virtual',1),('exists-error','exists failed',1),('glob-error','glob failed',2),('preabort','Operation aborted',0),('abort-exists','Operation aborted',1),('abort-glob','Operation aborted',2)]:
            value,trace=run(mode,cwd='/virtual',entries='a');assert value=={'error':error} and len(trace)==n,(backend,mode,value,trace)
        value,trace=run('reuse',cwd='/virtual',entries='a');assert value['text']=='a' and trace[-1]==('exists','/virtual')
        for limit in ['bad','-1','1.5','nan','inf','281474976710656']:
            value,trace=run('injected',limit=limit);assert 'input is invalid' in value['error'] and not trace
        # Exact and exceeded result caps; zero is unlimited per fd.
        many=root/'many'
        for i in range(1001):write(many/f'{i:04d}.txt')
        for maximum,count in [(1,1),(1000,1000),(1001,1001),(1002,1001)]:
            lines,value=compare('*.txt',many,maximum);assert len(lines)==count
        compare('*.txt',many,0)
        # readline splits a name at a newline and the tool trims each line, as
        # upstream does.
        odd=root/'odd';odd.mkdir();write(odd/' leading ');write(odd/'new\nline')
        compare('*',odd)
        unicode=root/'unicode';write(unicode/'é');write(unicode/'É');write(unicode/'😀')
        for pattern in ['?','é','É']:compare(pattern,unicode)
        malformed=root/'malformed';write(malformed/'.gitignore','[\n');write(malformed/'a')
        compare('**',malformed)
        # Byte cap and UTF-8 character boundaries; injected and fd notices
        # differ exactly as the upstream tool's two branches do.
        long=root/'long'
        for i in range(300):write(long/(f'{i:03d}-'+'é'*100))
        value,_=run('native','*',str(long),300);assert value['text'].endswith('for more, or refine pattern. 50.0KB limit reached]')
        assert value['details'].startswith('300|True:300:')
    print(f'{backend}: {checks} public find scenarios passed against the fd-driven oracle')

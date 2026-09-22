"""Native public find against fd 10.3.0 and injected operation contracts."""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backends',nargs='*',default=['bun','native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/find-public')
p.add_argument('--fd',type=Path,default=Path.home()/'.pi/agent/bin/fd')
a=p.parse_args()
assert subprocess.check_output([str(a.fd),'--version'],text=True).strip()=='fd 10.3.0'

for backend in a.backends:
    command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
    checks=0
    with tempfile.TemporaryDirectory(prefix='bend-find-public-',dir='/var/tmp') as tmp:
        base=Path(tmp); home=base/'home'; home.mkdir(); root=base/'work'; root.mkdir(); xdg=home/'.config'; xdg.mkdir()
        env={**os.environ,'HOME':str(home),'XDG_CONFIG_HOME':str(xdg)}
        def run(mode='native',pattern='**',path='none',limit='none',entries='',cwd=None):
            global checks
            result=subprocess.run(command+[mode,str(cwd or root),str(home),"pattern:"+pattern,str(path),str(limit),entries],env=env,text=True,capture_output=True,timeout=60)
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
        def oracle(pattern,path=root,limit=1000):
            args=[str(a.fd),'--glob','--color=never','--hidden','--print0','--max-results',str(limit)]
            if not any(os.path.exists(parent/'.git') for parent in [path,*path.parents]):args+=['--no-require-git']
            if '/' in pattern:
                args+=['--full-path']
                if not pattern.startswith(('/', '**/')):pattern='**/'+pattern
            result=subprocess.run(args+['--',pattern,str(path)],env=env,capture_output=True,check=True)
            return [os.path.relpath(name.decode(),path)+('/' if name.endswith(b'/') else '') for name in result.stdout.split(b'\0') if name]
        def native(pattern,path=root,limit='none',mode='native'):
            value,trace=run(mode,pattern,str(path),limit)
            assert not trace and 'text' in value,(backend,pattern,value,trace)
            text=value['text'].split('\n\n[')[0]
            return ([] if text=='No files found matching pattern' else text.split('\n')),value
        def compare(pattern,path=root):
            actual,value=native(pattern,path)
            want=oracle(pattern,path)
            assert sorted(actual)==sorted(want),(backend,pattern,path,actual,want)
            return actual,value

        # Original tools.test.ts: hidden files, .gitignore, parse errors,
        # flag-like patterns and dynamic ctx.cwd.
        write(root/'.secret/hidden.txt');write(root/'visible.txt');write(root/'ignored.txt')
        write(root/'.gitignore','ignored.txt\n')
        actual,_=compare('**/*.txt');assert actual==['.secret/hidden.txt','visible.txt']
        value,_=run(pattern='[');assert value=={'error':'Error parsing glob pattern'}
        assert native('--help')[0]==[]
        write(root/'ctx-cwd-find.txt');actual,_=native('ctx-cwd-find.txt',mode='context');assert actual==['ctx-cwd-find.txt']
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

        # Correct lexical gitdir/commondir resolution is checked independently
        # of the older ignore crate's relative-path bugs.
        write(worktree/'.git','gitdir: ../../git-metadata/worktrees/w\n')
        write(metadata/'worktrees/w/commondir','../..\n')
        assert native('*.txt',worktree)[0]==['kept.txt']
        # Valid quoted configuration paths retain spaces; malformed values and
        # invalid UTF-8 fail explicitly instead of disappearing into fallbacks.
        write(home/'ignore with spaces','one.tmp\n')
        write(home/'.gitconfig','[core]\nexcludesFile = "'+str(home/'ignore with spaces')+'"\n')
        assert native('*.tmp',globaldir)[0]==['sub/a.tmp','three.tmp','two.tmp']
        write(home/'.gitconfig','[core]\nexcludesFile = "unfinished\n')
        value,_=run(path=globaldir);assert 'invalid Git configuration' in value['error']
        (home/'.gitconfig').unlink()
        invalid=root/'invalid';write(invalid/'kept.txt');(invalid/'.gitignore').write_bytes(b'\xff')
        value,_=run(path=invalid);assert 'invalid UTF-8' in value['error']
        (invalid/'.gitignore').unlink();os.mkfifo(invalid/'.gitignore')
        assert native('*.txt',invalid)[0]==['kept.txt']

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
        for maximum,count in [(1,1),(1000,1000),(1001,1001),(1002,1001),(0,1001)]:
            lines,value=native('*.txt',many,maximum);assert len(lines)==count and lines==sorted(lines)
            reached=count>=maximum
            assert (value['details']!='none')==reached
            if reached:assert value['text'].endswith(f'[{maximum} results limit reached. Use limit={maximum*2} for more, or refine pattern]')
        # Native paths preserve whitespace/newlines; fd's line-reader transport
        # cannot represent these faithfully. No splitting/trimming in Bend IO.
        odd=root/'odd';odd.mkdir();write(odd/' leading ');write(odd/'new\nline')
        value,_=run(pattern='*',path=odd);assert value=={'text':' leading \nnew\nline','details':'none'}
        # Scalar Unicode policy and explicit malformed rejection.
        unicode=root/'unicode';write(unicode/'é');write(unicode/'É');write(unicode/'😀')
        assert native('?',unicode)[0]==['É','é','😀']
        assert native('é',unicode)[0]==['É','é']
        assert native('É',unicode)[0]==['É']
        malformed=root/'malformed';write(malformed/'.gitignore','[\n');write(malformed/'a')
        value,_=run(path=malformed);assert 'invalid' in value['error'].lower() or 'pattern' in value['error'].lower()
        # Byte cap and UTF-8 character boundaries; injected and native notices
        # intentionally differ exactly as the upstream tool's two branches do.
        long=root/'long'
        for i in range(300):write(long/(f'{i:03d}-'+'é'*100))
        lines,value=native('*',long,300);assert len(lines)<300 and value['text'].endswith('for more, or refine pattern. 50.0KB limit reached]')
        assert value['details'].startswith('300|True:300:')
    print(f'{backend}: {checks} public find scenarios passed, including pinned fd directory comparisons')

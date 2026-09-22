#!/usr/bin/env python3
"""Differential native gitignore checks against pi's pinned ignore@7.0.8."""
import argparse
import itertools
import json
from pathlib import Path
import random
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--reference', default='build/ignore-reference/package/index.js')
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command
if command[:1] == ['--']: command = command[1:]
assert command, 'supply compiled fixture command'
rng = random.Random(7341)
patterns = [r'a\/b',r'foo\\ ',r'foo\\\ ',r'foo\  ',r'foo \ ', 'foo', '/foo', 'foo/', '/foo/', '*.md', '**/*.md', 'a/**/b', 'a/**', 'a/**/', '**', '*', 'a?c', '[ab].md', '[!a-c]*', '#comment', r'\#hash', r'\!bang', 'foo ', r'foo\ ', 'file\t', 'FOO', 'a/b', 'a/*/b', '!keep.md', r'a\*', '***', 'a/**/**/b']
paths = ['foo', 'foo/', 'a/foo', 'a/foo/', 'foo/x', 'foo/x/y', 'a/b', 'a/x/b', 'a/x/y/b/', 'a/', 'a/x', 'a/x/', 'a/x/y', '.md', 'note.md', 'a/note.md', 'b.md', 'c.md', 'd.md', '#hash', '!bang', 'foo ', 'file\t', 'FOO', 'abc', 'a*']
cases = [(True,[pattern],path) for pattern,path in itertools.product(patterns,paths)]
for rules in [['*','!keep.md'],['foo/','!foo/x'],['foo/','!foo/','foo/*','!foo/keep'],['*.md','!a/*.md'],['**','!a/','!a/b'],['a/**','!a/'],['foo','!FOO']]:
    cases.extend((mode,rules,path) for mode,path in itertools.product([False,True],paths+['keep.md','foo/keep']))
for _ in range(600):
    rules = rng.choices(patterns,k=rng.randrange(1,7))
    rules = [('!' if rng.randrange(5)==0 else '')+p for p in rules]
    cases.append((bool(rng.randrange(2)),rules,rng.choice(paths)))
# Exercise the complete ASCII POSIX class alphabet, including slash-spanning
# ranges and literal leading bracket members.
classes = [f'[[:{name}:]]' for name in ['alnum','alpha','blank','cntrl','digit','graph','lower','print','punct','space','upper','xdigit']]
classes += ['[]a]', '[!]]', '[^a]', '[/-0]', '[a[]', r'[\]]', r'[\-]', '[A-z]', '[a-cx-z]']
for pattern in classes:
    for mode in [False,True]:
        for code in range(1,128):
            if code in [31,47] or code == 46: continue
            cases.append((mode,[pattern],chr(code)))
for _ in range(2500):
    pattern = ''.join(rng.choices(['a','b','*','?','/','[ab]','[!a]','**'],k=rng.randrange(1,12)))
    path = '/'.join(''.join(rng.choices('ab.',k=rng.randrange(1,5))) for _ in range(rng.randrange(1,5)))
    if any(part in ['.','..'] for part in path.split('/')): continue
    cases.append((bool(rng.randrange(2)),[pattern],path+('/' if rng.randrange(2) else '')))
oracle = '''const ignore=require(process.argv[1]);let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.stringify(JSON.parse(s).map(([ignoreCase,rules,path])=>{const r=ignore({ignoreCase}).add(rules).test(path);return r.ignored?'ignored':r.unignored?'unignored':'included'}))));'''
expected = json.loads(subprocess.check_output(['node','-e',oracle,str(Path(args.reference).resolve())],input=json.dumps(cases),text=True))
# ignore@7.0.8's pinWildcards optimisation overconstrains earlier stars.
# These three discovered cases agree with Git itself; do not reproduce the bug.
git_corrections = {
    ('****b/****b/','bb/ab.b/b/b'),
    ('/*******[ab]/a**','ba.b/a./a.a/...a'),
    ('*?b**a','aa/a/a..a/a.ba'),
}
import tempfile
with tempfile.TemporaryDirectory(prefix='bend-ignore-oracle-') as folder:
    subprocess.run(['git','init','--quiet',folder],check=True)
    for pattern,path in sorted(git_corrections):
        Path(folder,'.gitignore').write_text(pattern+'\n')
        result = subprocess.run(['git','-c','core.ignoreCase=false','check-ignore','--no-index','--stdin'],cwd=folder,input=path+'\n',text=True,capture_output=True)
        assert result.returncode == 0, (pattern,path,result.stderr)
for index,(mode,rules,path) in enumerate(cases):
    if not mode and len(rules)==1 and (rules[0],path) in git_corrections:
        assert expected[index]=='included'
        expected[index]='ignored'
failures=[]
for start in range(0,len(cases),80):
    group = cases[start:start+80]
    encoded = ['\x1f'.join(['1' if mode else '0',path,*rules]) for mode,rules,path in group]
    actual = subprocess.check_output(command+encoded,text=True).splitlines()
    assert len(actual)==len(group),(len(actual),len(group))
    failures.extend((case,want,got) for case,want,got in zip(group,expected[start:start+80],actual) if want!=got)
if failures:
    from collections import Counter
    print(Counter(tuple(case[1]) for case,_,_ in failures))
for failure in failures[:20]: print(repr(failure))
assert not failures, f'{len(failures)} / {len(cases)} mismatches'
print(f'{len(cases)} ordered-rule/path differential comparisons passed')

def native(mode, rules, path):
    encoded = '\x1f'.join(['1' if mode else '0',path,*rules])
    return subprocess.check_output(command+[encoded],text=True).strip()

for path in ['', '/', './a', '../a', '.', '..', 'a//b', 'a/../b', 'a/./b']:
    assert native(False,['*'],path)=='invalid-path',repr(path)
for pattern in ['[', '[]', '[z-a]', 'abc\\', '[[:unknown:]]']:
    assert native(False,[pattern],'value')=='invalid-pattern',repr(pattern)
for mode,rules,path,want in [
    (False,['x'*30000],'x'*30000,'ignored'),
    (False,['x'*30000],'x'*29999+'y','included'),
    (False,['*'],'x'*30000,'ignored'),
    (False,['*a'*300+'b'],'a'*300,'included'),
    (False,['zzz'],'/'.join(['a']*1000),'included'),
]:
    assert native(mode,rules,path)==want,(len(rules[0]),len(path),want)
print('14 strict malformed-input rejections and 5 long/adversarial cases passed')

# Scalar simple folding, deliberately broader than legacy RegExp /i.
for pattern,path,want in [
    ('É','é','ignored'), ('σ','ς','ignored'), ('K','k','ignored'),
    ('ſ','s','ignored'), ('ẞ','ß','ignored'), ('𐐀','𐐨','ignored'),
    ('[A-Z]','K','ignored'), ('[!A-Z]','K','included'),
    ('[Σ]','ς','ignored'), ('[!Σ]','ς','included'),
    ('[𐐀-𐐧]','𐐨','ignored'), ('?','😀','ignored'),
    ('İ','i','included'), ('ı','i','included'), ('ß','ss','included'),
]:
    assert native(True,[pattern],path)==want,(pattern,path,want)
for pattern,path in [('É','é'),('K','k'),('𐐀','𐐨'),('[A-Z]','K')]:
    assert native(False,[pattern],path)=='included',(pattern,path)
print('19 Unicode scalar literal/class/width comparisons passed')

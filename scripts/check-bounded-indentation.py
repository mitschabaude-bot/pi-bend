"""Validate benchmark C and fresh JS for the isolated indentation candidate.

Usage: python3 scripts/check-bounded-indentation.py CANDIDATE_BEND2 BENCHMARK_JSON
Run benchmark-bounded-indentation.py with strategy slice first and pass its output.
"""
import hashlib
import itertools
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1]).resolve()
benchmark_path=Path(sys.argv[2])
baseline=Path.home()/'.bend/current/bend2'
bun=Path.home()/'.bun/bin/bun'
benchmark=json.loads(benchmark_path.read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
for variant,compiler in [('baseline',baseline),('candidate',candidate)]:
    assert digest(compiler/'comp.ts')==benchmark['compiler_sha256'][variant]
for source in benchmark['fixtures']:
    stem=Path(source).stem
    arguments=[]
    if stem=='typed-do-shadow':expected=['PASS typed do binding']*5
    elif stem=='utf8-runner':
        arguments=['b','b65','b240,159,152,128','b239,187,191,65','b255','b226,130','d240|159|152|128','e65,128512']
        expected=['','65','128512','65','65533','65533','|||128512|','65,240,159,152,128']
    else:
        names=re.findall(r'case "([^"]+)":', (root/source).read_text())
        arguments=list(dict.fromkeys(names+['','unknown','response.','é','😀']+[word[:i] for word in names for i in range(len(word))]+[word+'x' for word in names]+[word[:i]+'X'+word[i+1:] for word in names for i in range(len(word))]))
        expected=[str(names.index(word)+1) if word in names else '0' for word in arguments]
    paths={}
    evidence={}
    for variant,compiler in [('baseline',baseline),('candidate',candidate)]:
        folder=root/'build/indent-correctness'/stem/variant
        folder.mkdir(parents=True,exist_ok=True)
        original=root/'build/indent-benchmark-slice'/stem/(variant+'.c')
        assert digest(original)==benchmark['fixtures'][source]['generated_c'][variant]['sha256']
        shutil.copyfile(original,folder/'program.c')
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', sys.executable,str(root/'scripts/run-rss-guarded.py'),'--','clang','-O1','-std=c11','-fbracket-depth=2048','program.c','-o','program','-lpthread','-lm'],cwd=folder,check=True)
        for threads in [1,4]:
            actual=subprocess.check_output([str(folder/'program'),'--threads',str(threads),*arguments],text=True,timeout=60).splitlines()
            assert actual==expected,(stem,variant,threads,actual[:10],expected[:10])
        subprocess.run([str(bun),str(compiler/'main.ts'),source,'-o',str(folder/'program.js')],cwd=root,check=True,stdout=subprocess.DEVNULL,timeout=120)
        actual=subprocess.check_output([str(bun),str(folder/'program.js'),*arguments],text=True,timeout=60).splitlines()
        assert actual==expected,(stem,variant,'JS',actual[:10],expected[:10])
        paths[variant]=folder
        evidence[variant]={'binary_sha256':digest(folder/'program'),'js_sha256':digest(folder/'program.js')}
    assert evidence['baseline']['binary_sha256']==evidence['candidate']['binary_sha256'],(stem,'binary changed')
    changed=0
    with (paths['baseline']/'program.js').open('rb') as before,(paths['candidate']/'program.js').open('rb') as after:
        for left,right in itertools.zip_longest(before,after):
            assert left is not None and right is not None
            assert left.lstrip(b' ')==right.lstrip(b' '),(stem,'JS tokens changed')
            changed+=left!=right
    print(stem,'PASS',len(expected),'assertions per runtime;',changed,'JS indentation lines changed',flush=True)

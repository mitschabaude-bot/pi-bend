"""Differential path-glob behavior against globset 0.4.16 and fd smart case."""
import argparse
import itertools
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backends',nargs='*',default=['bun','native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/path-glob')
p.add_argument('--oracle',type=Path,default=ROOT/'build/path-glob-oracle/target/release/path-glob-oracle')
a=p.parse_args()
patterns=['','*','?','**','**/','a/**','a/**/','a/**/b','**/b','a*b','a?b','[a-z]','[^a-z]','[!a]','[]]','[-a]','[a-]',r'[\]',r'\*','a{b,c}d','{,a}','{}','{a,}','{a,b}{c,d}','{a/b,c}/**','{**,a}','a/**,b','a**/b','***','***/b','**/**/b','a/**/**','a/{b,c}/**','{**/a,b}','[A-Z]*','[a-z]*','[!A-Z]*','foo.[a-zA-Z]']
random.seed(173)
for _ in range(200):
    patterns.append(''.join(random.choices(['a','b','A','/','*','?','**','[ab]','[!b]','{a,b}'],k=random.randrange(1,7))))
texts=['','a','b','A','B','ab','aa','abc','abd','acd','ad','ac','bc','bd','/','a/','a/b','a/x/b','a/x/y/b','a/b/','/a/b','a/x/y','a,','a/b,b','a,b','a/bb','d','c','ab/c','a.b',']','-','\\','*']
texts += [''.join(chars) for size in range(1,4) for chars in itertools.product('ab/',repeat=size)]
cases=list(itertools.product(dict.fromkeys(patterns),dict.fromkeys(texts)))
reference=subprocess.run([str(a.oracle)],input=json.dumps(cases),text=True,capture_output=True,check=True).stdout.splitlines()
assert len(reference)==len(cases)
# These malformed cases are explicitly rejected, including unmatched closing
# braces globset currently discards. They are not malformed compiler tests.
invalid=['[','[a','[z-a]','[!]','[a\\','a\\','{a','a}','{a,{b,c}}']
# Native strings use Unicode scalar matching/folding instead of UTF-8 bytes.
unicode=[('?', 'é',True),('?', '😀',True),('é','É',True),('É','é',False),('σ','ς',True),('[a-z]','K',True),('[!a-z]','K',False),('𐐨','𐐀',True),('𐐀','𐐨',False)]
for backend in a.backends:
    command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
    def run(batch):
        result=subprocess.run(command+[part for case in batch for part in case],text=True,capture_output=True,timeout=60)
        assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr)
        return result.stdout.splitlines()
    actual=[]
    for start in range(0,len(cases),300): actual+=run(cases[start:start+300])
    differences=[(case,want,got) for case,want,got in zip(cases,reference,actual) if want!=got]
    assert not differences,(backend,len(differences),differences[:25])
    assert run([(pattern,'text') for pattern in invalid])==['error']*len(invalid)
    assert run([(pattern,text) for pattern,text,_ in unicode])==[str(value).lower() for _,_,value in unicode]
    # Branches must stay linear in program size; expanding these would produce
    # 2**40 alternatives. Long text verifies bounded native/Bun machine stack.
    assert run([('{a,b}'*40,'a'*40),('a'*20000,'a'*20000),('**/end','a/'*10000+'end')])==['true']*3
    print(f'{backend}: {len(cases)} pinned globset/fd comparisons, {len(invalid)} malformed, {len(unicode)} native Unicode and 3 long/branch checks passed')

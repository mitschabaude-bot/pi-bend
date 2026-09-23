"""Pinned pi edit matching/application comparisons; no filesystem or rendering claims."""
import json
import os
from pathlib import Path
import random
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
rows=[]
def add(name,kind,*args): rows.append((name,[kind,*args]))
def edit(name,content,*pairs): add(name,'e',content,[dict(oldText=a,newText=b) for a,b in pairs])
# Meaningful assertions from pi-mono/packages/coding-agent/test/tools.test.ts.
edit('should replace text in file','hello world',('world','testing'))
edit('should fail if text not found','hello',('missing','testing'))
edit('should fail if text appears multiple times','foo foo',('foo','bar'))
edit('should match edits against the original file, not incrementally','foo\nbar\n',('foo\n','foo bar\n'),('bar\n','BAR\n'))
edit('should replace multiple disjoint regions in one call','alpha\nbeta\ngamma\n',('gamma\n','GAMMA\n'),('alpha\n','ALPHA\n'))
edit('should fail when multi-edit regions overlap','one\ntwo\nthree\n',('one\ntwo\n','ONE\nTWO\n'),('two\nthree\n','TWO\nTHREE\n'))
edit('should not partially apply edits when one edit fails','alpha\nbeta\n',('alpha\n','ALPHA\n'),('missing\n','MISSING\n'))
edit('should match text with trailing whitespace stripped','line one   \nline two  \nline three\n',('line one\nline two\n','replaced\n'))
edit('should match fullwidth punctuation in Chinese text','你好，世界\n你好（世界）\n',('你好,世界\n你好(世界)\n','你好，pi\n你好(pi)\n'))
edit('should match compatibility-equivalent Unicode forms','ＡＢＣ１２３\ncafe\u0301\n',('ABC123\ncafé\n','XYZ789\ncoffee\n'))
edit('should match smart single quotes to ASCII quotes','console.log(‘hello’);\n',("console.log('hello');","console.log('world');"))
edit('should match smart double quotes to ASCII quotes','const msg = “Hello World”;\n',('const msg = "Hello World";','const msg = "Goodbye";'))
edit('should match Unicode dashes to ASCII hyphen','range: 1–5\nbreak—here\n',('range: 1-5\nbreak-here','range: 10-50\nbreak--here'))
edit('should match non-breaking space to regular space','hello\u00a0world\n',('hello world','hello universe'))
edit('should prefer exact match over fuzzy match',"const x = 'exact';\nconst y = 'other';\n",("const x = 'exact';","const x = 'changed';"))
edit('should detect duplicates after fuzzy normalization','hello world   \nhello world\n',('hello world','replaced'))
edit('should support fuzzy matching in multi-edit mode','console.log(‘hello’);\nhello\u00a0world\n',("console.log('hello');\n","console.log('world');\n"),('hello world\n','hello universe\n'))
edit('should preserve the correct occurrence when fuzzy replacement equals a nearby line','replace me   \nafter   \n',('replace me\n','after\n'))
edit('should preserve untouched lines and produce an applicable patch for fuzzy multi-edits','keep before  \nfirst target  \nfirst after\nkeep middle   \nsecond target  \nsecond after\nkeep after  \n',('first target\nfirst after','FIRST\nFIRST2'),('second target\nsecond after','SECOND\nSECOND2'))
edit('normalize edit line endings','first\nsecond\nthird\n',('second\r\n','REPLACED\r\n'))
edit('no change','hello',('hello','hello'))
edit('empty edit list','hello')
edit('empty old text precedence','hello',('missing','x'),('','y'))
edit('no final newline','old',('old','new'))
edit('astral offsets','😀before\ntarget\n😀after',('target','new'))
edit('multiple replacements same fuzzy line','α—one—two\nuntouched  \n',('α-one','α-ONE'),('two','TWO'))
edit('exact and fuzzy shared base','ＡＢＣ\nleft—right\n',('ＡＢＣ','abc'),('left-right','new'))
edit('adjacent edits','abcd',('ab','x'),('cd','y'))
for content in ['', '\r', '\n', '\r\n', 'a\nb\r\nc', 'a\r\nb\nc', 'a\rb\r\n', '😀\r\n']:
    for ending in ['\n','\r\n']: add('line ending policy','l',content,ending)
for source in ['', 'ＡＢＣ１２３', 'cafe\u0301', 'x\ufeff\n', 'x\u0085\n', 'a\u2028b\u2029', '“smart”\u00a0‘quotes’  \n', '‐‑‒–—―−', '😀\t \n']:
    add('fuzzy normalization','f',source)
for content,needle in [('😀a “x”','"x"'),('both x and “x”','x'),('text','absent'),('text',''),('a  \nb','a\nb')]:
    add('fuzzy offsets','m',content,needle)
add('line count rejection','p','a\nb\n','a\n',[])
add('outside range rejection','p','abc','abc',[dict(matchIndex=3,matchLength=0,newText='x')])
add('empty content range rejection','p','','',[dict(matchIndex=0,matchLength=0,newText='x')])
add('end outside range rejection','p','abc','abc',[dict(matchIndex=1,matchLength=3,newText='x')])
add('duplicate normalized line placement','p','same  \nsame   \nsame \n','same\nsame\nsame\n',[dict(matchIndex=5,matchLength=5,newText='changed\n')])
rng=random.Random(4107)
alphabet=['a','b',' ','\t','é','😀','—','“','Ａ','\u00a0','\u0301']
for n in range(300):
    content='\n'.join(''.join(rng.choices(alphabet,k=rng.randrange(1,15))) for _ in range(rng.randrange(1,6)))
    if rng.choice([True,False]): content+='\n'
    a=rng.randrange(len(content)); b=rng.randrange(a+1,len(content)+1)
    old=content[a:b]
    if not old.strip(): continue # Explicitly covered below under the accepted policy.
    edit(f'generated original-snapshot {n}',content,(old,rng.choice(['changed','😀\n',''])))
    add(f'generated fuzzy normalization {n}','f',content)
for n in range(120):
    original=''.join(f'line{i}: {rng.choice(["Ａ", "B", "😀"])}   \n' for i in range(rng.randrange(2,9)))
    base=original.replace('Ａ','A').replace('   \n','\n')
    positions=sorted(rng.sample(range(len(base)),rng.randrange(1,min(6,len(base)))))
    changes=[]
    for i,pos in enumerate(positions):
        limit=positions[i+1] if i+1<len(positions) else len(base)
        changes.append(dict(matchIndex=pos,matchLength=rng.randrange(0,limit-pos+1),newText=rng.choice(['X','\n','😀',''])))
    rng.shuffle(changes)
    add(f'generated preservation {n}','p',original,base,changes)

def points(s): return ','.join(map(str,map(ord,s)))
def wire(row):
    kind,*args=row
    if kind=='e': return '|'.join([kind,points(args[0]),*[points(e[k]) for e in args[1] for k in ['oldText','newText']]])
    if kind=='p': return '|'.join([kind,points(args[0]),points(args[1]),*[str(e[k]) if k!='newText' else points(e[k]) for e in args[2] for k in ['matchIndex','matchLength','newText']]])
    return '|'.join([kind,*map(points,args)])
oracle=subprocess.run(['node','--disable-warning=ExperimentalWarning','tests/edit_diff_reference.ts'],cwd=ROOT,input=json.dumps([r for _,r in rows]),capture_output=True,text=True,check=True)
expected=oracle.stdout.splitlines()
assert len(expected)==len(rows),(oracle.stderr,len(expected),len(rows))
# Authorized deviations: no accidental empty fuzzy needle / split('') counting.
policy=[(['m','abc','   '],'missing|'+points('abc')),
        (['e','a b',[dict(oldText=' ',newText='_')]],'ok|'+points('a b')+'|'+points('a_b')),
        (['e','abc',[dict(oldText='   ',newText='x')]],'error|Could not find the exact text in file.txt. The old text must match exactly including all whitespace and newlines.')]
policy.append((['e','a',[dict(oldText=' ',newText='x')]],'error|Could not find the exact text in file.txt. The old text must match exactly including all whitespace and newlines.'))
rows.extend(('empty fuzzy needle policy',row) for row,_ in policy)
expected.extend(value for _,value in policy)
binary=os.environ.get('EDIT_DIFF_BINARY','build/edit-diff')
commands=[] if '--native-only' in sys.argv else [('Bun',['bun','build/edit-diff.js'])]
if '--bun-only' not in sys.argv:
    commands += [('native1',[binary,'--threads','1']),('native4',[binary,'--threads','4'])]
for name,cmd in commands:
    for start in range(0,len(rows),80):
        batch=rows[start:start+80]
        p=subprocess.run(cmd+[wire(row) for _,row in batch],cwd=ROOT,capture_output=True,text=True,timeout=90)
        assert p.returncode==0 and not p.stderr,(name,p.returncode,p.stderr[:1500])
        got=p.stdout.splitlines()
        assert len(got)==len(batch),(name,start,len(got),len(batch))
        for i,(actual,wanted) in enumerate(zip(got,expected[start:start+80])):
            assert actual==wanted,(name,start+i,rows[start+i],actual,wanted)
    print(f'{name}: {len(rows)} edit matching/application and line-preservation assertions PASS',flush=True)

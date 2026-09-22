#!/usr/bin/env python3
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--upstream',default='../pi-mono');p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command[1:] if a.command[:1]==['--'] else a.command
root=pathlib.Path(__file__).resolve().parent.parent
reference=json.loads(subprocess.check_output(['bun','tests/frontmatter_reference.ts',str(pathlib.Path(a.upstream).resolve())],text=True,cwd=root))
reference['cases'] += [
 {'name':'strict fence line', 'source':'---suffix\nname: test\n---\nBody', 'expected':{'ok':True,'frontmatter':{},'body':'---suffix\nname: test\n---\nBody'}},
 {'name':'reject nonmapping frontmatter', 'source':'---\n[one, two]\n---\nBody', 'expected':{'ok':False}},
]
failures=[]
for group,prefix in [('cases',[]),('yaml',['--yaml'])]:
 for start in range(0,len(reference[group]),20):
  batch=reference[group][start:start+20]
  result=subprocess.run(command+prefix+[case['source'] for case in batch],capture_output=True,text=True,check=True,timeout=120)
  lines=result.stdout.splitlines();assert len(lines)==len(batch),(start,result.stdout,result.stderr)
  for case,line in zip(batch,lines):
   actual=json.loads(line);expected=case['expected']
   if case.get('name') == 'throws on invalid YAML frontmatter':
    assert 'at line 1, column 10' in actual.get('error',''), actual
   if actual['ok'] != expected['ok'] or expected['ok'] and actual != expected:
    failures.append({'source':case['source'],'expected':expected,'actual':actual})
if failures:
 (root/'build/frontmatter-mismatches.json').write_text(json.dumps(failures,ensure_ascii=False,indent=2))
 print(json.dumps(failures[:15],ensure_ascii=False,indent=2));raise SystemExit(f'{len(failures)} mismatches of {sum(len(reference[k]) for k in ["cases","yaml"])}')
print(f"PASS {len(reference['names'])} named frontmatter cases, {len(reference['cases'])} frontmatter outputs, {len(reference['yaml'])} YAML comparisons")

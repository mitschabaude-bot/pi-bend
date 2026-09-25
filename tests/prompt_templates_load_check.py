"""Prompt discovery, frontmatter and source attribution against the pinned loader."""
from upstream_pin import UPSTREAM
import argparse,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def wire(value):return ','.join(str(ord(c)) for c in value)
def optional(value):return 'none' if value is None else wire(value)
def row(t):
 s=t['sourceInfo']
 return '|'.join(['template',wire(t['name']),wire(t['description']),optional(t.get('argumentHint')),wire(t['content']),wire(t['filePath']),wire(s['path']),s['source'],s['scope'],s['origin'],optional(s.get('baseDir'))])
def diagnostic(d):return '|'.join(['diagnostic',d['type'],optional(d.get('path')),wire(d['message'])])
def main():
 p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');p.add_argument('--reference',type=Path,default=UPSTREAM / 'packages/coding-agent');a=p.parse_args()
 cmd=['bun',a.runner] if a.runner.endswith('.js') else [a.runner,'--threads',a.threads]
 with tempfile.TemporaryDirectory(prefix='pi-prompt-') as directory:
  root=Path(directory);cwd=root/'project';agent=root/'agent';home=root/'home';extras=root/'extras'
  for d in [cwd/'.pi/prompts',agent/'prompts',home,extras]:d.mkdir(parents=True)
  def put(path,content):path.write_text(content,encoding='utf8');return path
  put(agent/'prompts/same.md','global: $@');put(cwd/'.pi/prompts/same.md','project: $@')
  definitions={
   'pr':('Review PRs from URLs with structured issue and code analysis','<PR-URL>','You are given one or more GitHub PR URLs: $@'),
   'wr':('Finish the current task end-to-end with changelog, commit, and push','[instructions]','Wrap it. Additional instructions: $ARGUMENTS'),
   'cl':('Audit changelog entries before release',None,'Audit changelog entries for all commits since the last release.'),
   'empty-hint':('A command with empty hint','','Do something'),
   'is':('Analyze GitHub issues (bugs or feature requests)','<issue>','Analyze GitHub issue(s): $ARGUMENTS')}
  for name,(description,hint,body) in definitions.items():
   put(extras/(name+'.md'),'---\ndescription: '+description+'\n'+('' if hint is None else 'argument-hint: '+json.dumps(hint)+'\n')+'---\n'+body)
  put(extras/'plain.md','\n \t\n  first description\nsecond\n')
  put(extras/'long.md','a'*61+'\nbody')
  put(extras/'emoji.md','😀'*31+'\nbody')
  put(extras/'empty.md','');put(extras/'bom.md','\ufeff---\r\ndescription: "BOM and CRLF"\r\n---\r\nBody\r\n')
  put(extras/'unknown.md','---\ndescription: "known"\nunknown: [one, 2, true]\n---\nvalue')
  put(extras/'ignored.MD','upper');put(extras/'ignored.txt','other');(extras/'nested').mkdir();put(extras/'nested/ignored.md','nested')
  (extras/'link.md').symlink_to(extras/'pr.md');(extras/'broken.md').symlink_to(extras/'absent');(extras/'directory.md').symlink_to(extras/'nested')
  os.mkfifo(extras/'pipe.md')
  put(extras/'\ue000.md','private character');put(extras/'😀.md','emoji filename')
  def native(paths,defaults=True,config='.pi'):
   command='|'.join(['l',wire(str(cwd)),wire(str(agent)),wire(str(home)),str(int(defaults)),wire(config),*[wire(str(x)) for x in paths]])
   result=subprocess.run([*cmd,'--',command],capture_output=True,text=True,timeout=60)
   assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
   lines=result.stdout.splitlines();assert lines and lines[-1]=='end',lines
   return lines[:-1]
  def reference(paths,defaults=True):
   options=dict(cwd=str(cwd),agentDir=str(agent),promptPaths=[str(x) for x in paths],includeDefaults=defaults)
   path=root/'options.json';path.write_text(json.dumps(options))
   result=json.loads(subprocess.check_output(['bun',str(ROOT/'tests/prompt_templates_reference.ts'),str(a.reference),str(path),'load'],text=True))
   return [row(x) for x in result['templates']]+[diagnostic(x) for x in result['diagnostics']]
  scenarios=[([],True),([extras],False),([extras,agent/'prompts/same.md',extras/'pr.md'],True),(['../extras',root/'missing'],False),([extras/'ignored.MD',extras/'pipe.md',extras/'nested'],False),([extras/'pr.md',extras/'pr.md'],False),([extras.as_uri()],False)]
  count=0
  for paths,defaults in scenarios:
   got=native(paths,defaults);want=reference(paths,defaults)
   assert got==want,(paths,[(g,w) for g,w in zip(got,want) if g!=w],len(got),len(want))
   count+=len(want)
  # Root configuration and home come from the caller, not process globals.
  put(home/'tilde.md','home');assert native(['~/tilde.md'],False)==reference([home/'tilde.md'],False)
  (cwd/'.custom/prompts').mkdir(parents=True);put(cwd/'.custom/prompts/custom.md','custom')
  custom=native([],True,'.custom');assert len(custom)==2 and custom[1].startswith('template|'+wire('custom')+'|'),custom
  # Non-string metadata is ignored, invalid bytes decode with replacement and
  # malformed frontmatter is a warning (upstream b6419322e).
  bad=root/'bad';bad.mkdir()
  put(bad/'description.md','---\ndescription: 42\n---\nbody')
  put(bad/'hint.md','---\nargument-hint: false\n---\nbody')
  put(bad/'yaml.md','---\ndescription: [unterminated\n---\nbody')
  (bad/'bytes.md').write_bytes(b'\xffbody')
  rows=native([bad],False);want=reference([bad],False)
  # The YAML warning's prose is the yaml package's; ours keeps its own wording
  # (docs/upstream-v0.87.1.md), so only its path and location must agree.
  def located(row):
   kind,level,path,message=row.split('|');text=''.join(chr(int(c)) for c in message.split(','))
   return (kind,level,path,text[text.index(' at line '):].split(':')[0])
  assert [r for r in rows if not r.startswith('diagnostic|')]==[r for r in want if not r.startswith('diagnostic|')],(rows,want)
  assert [located(r) for r in rows if r.startswith('diagnostic|')]==[located(r) for r in want if r.startswith('diagnostic|')],(rows,want)
  # loadPromptTemplates - diagnostics: "reports invalid YAML frontmatter and keeps valid siblings" (#9354, v0.87.1),
  # asserted as upstream on both loaders: only the valid template loads, with one warning for the invalid file
  # whose message names line 1, column 14.
  siblings=root/'siblings';siblings.mkdir()
  invalid=put(siblings/'invalid.md','---\ndescription: Broken: unquoted colon\n---\nDo something.\n');put(siblings/'valid.md','Valid prompt content.')
  for rows in [native([siblings],False),reference([siblings],False)]:
   templates=[r for r in rows if r.startswith('template|')];diagnostics=[r.split('|') for r in rows if r.startswith('diagnostic|')]
   assert [t.split('|')[1] for t in templates]==[wire('valid')],rows
   assert len(diagnostics)==1 and diagnostics[0][1]=='warning' and diagnostics[0][2]==wire(str(invalid)),rows
   assert 'line 1, column 14' in ''.join(chr(int(c)) for c in diagnostics[0][3].split(',')),rows
  # A 60-UTF16-unit display budget must not manufacture half a surrogate pair.
  boundary=put(root/'boundary.md','x'*59+'😀end')
  rows=native([boundary],False);assert rows[0].split('|')[2]==wire('x'*59+'...'),rows
  unreadable=put(root/'unreadable.md','private');unreadable.chmod(0)
  try:
   rows=native([unreadable],False);assert rows==reference([unreadable],False) and rows[0].startswith('diagnostic|warning|'),rows
  finally:unreadable.chmod(0o600)
  print(f'{len(scenarios)} pinned discovery scenarios / {count} templates; all five original argument-hint cases, warnings for malformed or unreadable templates, symlinks, nonfiles, config and UTF16 boundary passed')
if __name__=='__main__':main()

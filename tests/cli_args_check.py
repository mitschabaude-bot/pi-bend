"""Pinned named CLI assertions plus complete-result differential comparisons."""
import argparse,json,pathlib,random,subprocess,tempfile
from upstream_pin import PIN
ROOT=pathlib.Path(__file__).resolve().parents[1];UPSTREAM=ROOT.parent/'pi-mono'
p=argparse.ArgumentParser();p.add_argument('--prefix',default='build/cli-args');p.add_argument('backends',nargs='*');a=p.parse_args()
def source(path):return subprocess.check_output(['git','-C',str(UPSTREAM),'show',PIN+':packages/coding-agent/'+path],text=True)
rng=random.Random(54149)
switches=['--help','-h','--version','-v','--continue','-c','--resume','-r','--no-session','--no-tools','-nt','--no-builtin-tools','-nbt','--no-extensions','-ne','--no-skills','-ns','--no-prompt-templates','-np','--no-themes','--no-context-files','-nc','--offline','--verbose','--approve','-a','--no-approve','-na']
strings=['--provider','--model','--api-key','--system-prompt','--append-system-prompt','--name','-n','--session','--session-id','--fork','--session-dir','--export','--extension','-e','--skill','--prompt-template','--theme','--models','--tools','-t','--exclude-tools','-xt']
values=['','abc','--literal value','@path','a,b, ,c,','  spaced  ','β😀','one\ntwo','false']
extra=[[],['--','--model','x','@file','-p','@'],['--print','---\nx:y\n---\nhello'],['--custom=a=b','--custom=','--flag','@file'],['--list-models','@file','--list-models','foo'],['--model','--help'],['--append-system-prompt','a','--append-system-prompt','b'],' \u00a0name\u3000 ','\ufeff\t\n','\u200b']
for _ in range(300):
 argv=[]
 for _ in range(rng.randrange(1,24)):
  choice=rng.randrange(6)
  if choice==0:argv.append(rng.choice(switches))
  elif choice==1:argv.extend([rng.choice(strings),rng.choice(values)])
  elif choice==2:argv.extend(rng.choice([['--mode','rpc'],['--mode','json'],['--thinking','off'],['--thinking','xhigh'],['--thinking','bogus'],['--tui-mode','regular'],['--tui-mode','fullscreen'],['--tui-mode','bogus'],['--use-theme','dark']]))
  elif choice==3:argv.append(rng.choice(['message','@file','--registered=hello','--enabled','-bad']))
  elif choice==4:argv.extend(['--print',rng.choice(['hello','---frontmatter','@attachment'])])
  else:argv.extend(['--list-models',rng.choice(['search','--help','@file'])])
 extra.append(argv)
with tempfile.TemporaryDirectory(prefix='cli-args-reference-') as folder:
 root=pathlib.Path(folder);src=source('src/cli/args.ts');(root/'args.ts').write_text(src[src.index('export type Mode'):src.index('export function printHelp')])
 (root/'args.test.ts').write_text(source('test/args.test.ts'));(root/'extra.json').write_text(json.dumps(extra))
 oracle=json.loads(subprocess.check_output(['bun',str(ROOT/'tests/cli_args_reference.ts'),str(root/'args.ts'),str(root/'args.test.ts'),str(root/'extra.json')],text=True))
 assert len(oracle['names'])>=60,len(oracle['names'])
 for backend in a.backends or ['bun','native-1','native-4']:
  command=['bun',str(ROOT/a.prefix)+'.js'] if backend=='bun' else [str(ROOT/a.prefix),'--threads',backend[-1]]
  def run(inputs):
   output=[]
   for start in range(0,len(inputs),25):
    result=subprocess.run(command+[json.dumps(x,ensure_ascii=False) for x in inputs[start:start+25]],capture_output=True,text=True,check=True,timeout=60)
    assert not result.stderr,result.stderr;output.extend(json.loads(x) for x in result.stdout.splitlines())
   assert len(output)==len(inputs);return output
  records=oracle['records'];actual=run([r['input'] for r in records])
  for got,record in zip(actual,records):assert got==record['expected'],(backend,record['name'],record['input'],got,record['expected'])
  # Approved rejection policy: missing known values are not extension flags.
  missing=[[name] for name in strings]+[['--mode'],['--thinking'],['--tui-mode'],['--use-theme']]
  for case,got in zip(missing,run(missing)):
   assert got['unknownFlags']==[] and len(got['diagnostics'])==1 and got['diagnostics'][0]['type']=='error',(case,got)
  invalid=[['--mode','bad'],['--mode','--help'],['--thinking','--help'],['--tui-mode','--help']]
  for case,got in zip(invalid,run(invalid)):
   assert 'mode' not in got and 'thinking' not in got and 'tuiMode' not in got
   assert got['diagnostics'][0]['type']=='error'
   if case[-1]=='--help':assert got['help'] is True
  print(f'{backend}: {len(oracle["names"])} pinned named tests, {len(records)} full-result comparisons, {len(missing)+len(invalid)} approved rejection checks PASS',flush=True)

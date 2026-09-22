"""Pinned original autocomplete assertions plus explicit native policy/lifetime cases."""
import argparse,base64,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);p.add_argument('--prefix',type=Path,default=ROOT/'build/autocomplete');a=p.parse_args()
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 original=subprocess.run(['node','--disable-warning=ExperimentalWarning',str(ROOT/'tests/autocomplete_original.mts'),json.dumps(command)],cwd=ROOT,text=True,capture_output=True,timeout=180)
 assert original.returncode==0,(backend,original.stdout,original.stderr)
 checks=0
 with tempfile.TemporaryDirectory(prefix='bend-autocomplete-',dir='/var/tmp') as tmp:
  base=Path(tmp);home=base/'home';home.mkdir();root=base/'work';root.mkdir();xdg=home/'.config';xdg.mkdir()
  env={**os.environ,'HOME':str(home),'XDG_CONFIG_HOME':str(xdg)}
  def decode(s):return base64.b64decode(s).decode()
  def invoke(args):
   global checks
   result=subprocess.run(command+list(map(str,args)),env=env,text=True,capture_output=True,timeout=60)
   assert result.returncode==0 and not result.stderr,(backend,args,result.returncode,result.stdout,result.stderr)
   checks+=1;lines=result.stdout.splitlines()
   if lines[0]=='none':return None
   if lines[0].startswith('error:'):return {'error':lines[0][6:]}
   if lines[0].startswith('trigger:'):return lines[0]=='trigger:True'
   if lines[0].startswith('apply:'):
    _,text,line,col=lines[0].split(':');return {'lines':decode(text).split('\n'),'cursorLine':int(line),'cursorCol':int(col)}
   assert lines[0].startswith('prefix:'),lines
   items=[]
   for line in lines[1:]:
    _,value,label,desc=line.split(':');item={'value':decode(value),'label':decode(label)}
    if desc!='none':item['description']=decode(desc[4:])
    items.append(item)
   return {'prefix':decode(lines[0][7:]),'items':items}
  def query(text,mode='suggest',force=False,recursive=True,policy='scalar',cwd=root):return invoke([mode,cwd,home,text,0,len(text),'yes' if force else 'no','yes' if recursive else 'no',policy])
  def values(text,**kw):
   result=query(text,**kw);return [] if result is None else [v['value'] for v in result['items']]
  def write(path,content=''):path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(content)
  write(root/'alpha');write(root/'Zebra');write(root/'beta');(root/'a folder').mkdir()
  assert values('',force=True)==['"a folder/"','Zebra','alpha','beta']
  assert values('',force=True,policy='folded')==['"a folder/"','alpha','beta','Zebra']
  assert values('@',recursive=False)==[]
  assert query('@',mode='aborted') is None
  assert query('/model error',mode='commands')=={'error':'callback'}
  for text,want in [('/model',False),('  /model',False),('/model arg',True),('hey /',True),('',True),('\t/model',False)]:assert invoke(['trigger',text,0,len(text)])==want
  assert invoke(['apply','😀 @a tail',0,4,'@alpha','alpha','@a'])=={'lines':['😀 @alpha  tail'],'cursorLine':0,'cursorCol':9}
  assert invoke(['apply','x\n😀 ./a',1,5,'./alpha','alpha','./a'])=={'lines':['x','😀 ./alpha'],'cursorLine':1,'cursorCol':9}
  assert invoke(['apply','abc',0,2,'x','x','zz'])=={'error':'prefix'}
  assert invoke(['apply','abc',3,0,'x','x',''])=={'error':'cursor'}
  assert invoke(['trigger','abc',0,4])=={'error':'cursor'}
  write(root/'~note');assert values('~n',force=True)==['~note']
  write(home/'from-home');assert values('~/from')==['~/from-home']
  write(root/'[literal].txt');write(root/'back\\slash.txt');write(root/'new\nline.txt');write(root/' leading ')
  assert values('@[')==['@[literal].txt']
  assert values('@back\\')==['@back\\slash.txt']
  assert values('./back\\')==['./back\\slash.txt']
  assert '@new\nline.txt' in values('@new')
  assert '@" leading "' in values('@leading')
  # Follow sibling aliases, but never follow a directory cycle indefinitely.
  write(root/'actual'/'needle.txt');(root/'alias').symlink_to('actual',target_is_directory=True);(root/'actual'/'loop').symlink_to('..',target_is_directory=True)
  assert set(values('@needle'))=={'@actual/needle.txt','@alias/needle.txt'}
  (root/'broken').symlink_to('absent');assert values('@broken')==[]
  os.mkfifo(root/'pipe');assert values('@pipe')==[]
  # fd mode observes .gitignore only in repositories, but .ignore/.fdignore
  # apply anywhere. A negated child cannot resurrect its excluded parent.
  write(root/'.gitignore','outside.txt\n');write(root/'outside.txt');assert values('@outside')==['@outside.txt']
  (root/'.git').mkdir();assert values('@outside')==[]
  write(root/'.fdignore','hidden.txt\nblocked/\n!blocked/kept.txt\n');write(root/'hidden.txt');write(root/'blocked'/'kept.txt')
  assert values('@hidden')==[];assert values('@kept')==[]
  write(root/'.git'/'secret.txt');assert values('@secret')==[]
  write(xdg/'fd'/'ignore','global.txt\n');write(root/'global.txt');assert values('@global')==[]
  # Invalid UTF-8 ignore content is rejected, not silently decoded/reinterpreted.
  (root/'.fdignore').write_bytes(b'\xff');assert query('@')=={'error':'other'}
 print(f'{backend}: 27 actual pinned tests and source comparisons passed; {checks} native-policy checks passed')

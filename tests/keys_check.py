#!/usr/bin/env python3
"""Replay the actual pinned test suite, then compare independent key APIs."""
import argparse,itertools,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ESC='\x1b'
def run(command,arguments):
 p=subprocess.run(command+arguments,cwd=ROOT,text=True,capture_output=True,timeout=60)
 assert p.returncode==0,(p.returncode,p.stderr[-3000:])
 return [json.loads(line) for line in p.stdout.splitlines()]
def batch(command,inputs,size=200):
 result=[]
 for i in range(0,len(inputs),size):result.extend(run(command,[json.dumps(inputs[i:i+size],ensure_ascii=True,separators=(',',':'))])[0])
 return result
def key(base,mask):return ''.join(x+'+' for bit,x in [(1,'shift'),(4,'ctrl'),(2,'alt'),(8,'super')] if mask&bit)+base
def vectors(tables):
 result=[];rng=random.Random(917)
 def add(data,kitty=False,windows=False,targets=()):
  context={'data':data,'kitty':kitty,'windows':windows}
  for method in ['parseKey','decodeKittyPrintable','decodePrintableKey','isKeyRelease','isKeyRepeat']:result.append(dict(context,method=method))
  for target in targets:result.append(dict(context,method='matchesKey',key=target))
 names=['escape','enter','tab','space','backspace','delete','insert','clear','home','end','pageUp','pageDown','up','down','left','right','f1','f12']
 symbols="`-=[]\\;',./!@#$%^&*()_|~{}:<>?" # '+' is an explicitly corrected upstream bug.
 for kitty,windows in itertools.product([False,True],repeat=2):
  for n in range(128):
   candidates=names+([chr(n).lower()] if chr(n).isalnum() and n<127 else [])+list(symbols)
   candidates += [chr(n+96)] if 1<=n<=26 else []
   targets=[key(rng.choice(candidates),rng.randrange(16)) for _ in range(8)]
   targets += ['ctrl+h','ctrl+[','ctrl+_','ctrl+-','shift+a','alt+b']
   add(chr(n),kitty,windows,targets)
   add(ESC+chr(n),kitty,windows,targets)
  for mode,prefix in [('plain',''),('shift','shift+'),('ctrl','ctrl+')]:
   for name,seqs in tables[mode].items():
    for seq in seqs:add(seq,kitty,windows,[prefix+name,name,'alt+'+name,'super+'+name])
 points=[0,8,9,13,27,32,47,48,57,65,69,90,97,99,122,127,196,1089,128512]+list(range(57399,57427))
 # Include locks and unsupported modifier bits independently of the Kitty flag.
 for point,mask in itertools.product(points,[0,1,2,3,4,5,6,7,8,9,12,13,15,16,32,64,128,192,193,196,256]):
  event=rng.choice(['',':1',':2',':3',':4'])
  data=f'{ESC}[{point};{mask+1}{event}u'
  targets=[key(x,mask&15) for x in ['a','c','1','/','enter','backspace','left']]
  add(data,bool(mask%2),False,targets)
  add(f'{ESC}[27;{mask+1};{point}~',False,False,targets)
 for point,shifted,base,mask in itertools.product([49,65,97,47,1089,128512],[65,1057],[99,118,47,49],[0,1,4,5,64,197]):
  targets=[key(x,mask&15) for x in ['a','c','v','1','/']]
  add(f'{ESC}[{point}:{shifted}:{base};{mask+1}:3u',True,False,targets)
  add(f'{ESC}[{point}::{base};{mask+1}u',False,False,targets)
 for final,mask,event in itertools.product('ABCDHF',[0,1,2,4,5,8,15,64,193],['',':2',':3']):
  add(f'{ESC}[1;{mask+1}{event}{final}',targets=[key(n,mask&15) for n in names])
 for num,mask,event in itertools.product([1,2,3,4,5,6,7,8,11,24],[0,1,2,4,5,8,64],['',':2',':3']):
  add(f'{ESC}[{num};{mask+1}{event}~',targets=[key(n,mask&15) for n in names])
 for data in ['',ESC,ESC+'[',ESC+'[97',ESC+'[97;',ESC+'[97;u',ESC+'[97::u',ESC+'[27;5;~','text:3u','::3u','abc:2Fxyz',ESC+'[200~90:62:3F:A5'+ESC+'[201~',ESC+'[97:65:99:3u',ESC+'[3:3~']:
  add(data,targets=['a','ctrl+a','delete'])
 return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--reference',default='/home/agent/code/pi-mono');p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 assert command,'fixture command required'
 oracle=['bun','tests/keys_reference.ts',a.reference]
 originals=run(oracle,['--original'])[0]
 actual=batch(command,[x['input'] for x in originals])
 for original,got in zip(originals,actual):assert original['expected']==got,(original,got)
 print(f'{len(originals)} original assertions in {len(set(x["name"] for x in originals))} named tests passed',flush=True)
 inputs=vectors(run(oracle,['--tables'])[0]);expected=batch(oracle,inputs);actual=batch(command,inputs)
 for data,want,got in zip(inputs,expected,actual):assert want==got,(data,want,got)
 print(f'{len(inputs)} separate parse/match/printable/event source comparisons passed',flush=True)
 # Intentional corrections: '+' is an actual base key, malformed identifiers
 # cannot silently shed unknown/repeated modifiers, and scalars never wrap.
 corrections=[]
 def correction(input,expected):corrections.append((input,expected))
 bases=list('abcdefghijklmnopqrstuvwxyz0123456789`-=[]\\;\',./!@#$%^&*()_+|~{}:<>?')+['escape','enter','tab','space','backspace','delete','insert','clear','home','end','pageUp','pageDown','up','down','left','right']+[f'f{i}' for i in range(1,13)]
 for name,mask in itertools.product(bases,range(16)):
  canonical=key(name,mask)
  correction({'method':'parseKeyId','key':canonical},canonical)
 for mask in range(16):
  correction({'method':'matchesKey','data':f'{ESC}[43;{mask+1}u','key':key('+',mask)},True)
 correction({'method':'matchesKey','data':'+','key':'+'},True)
 for name in ['','ctrl+','ctrl+ctrl+a','meta+a','unknown+ctrl+a','ctrl++a','ctrl+alt+','ctrl+"','++']:
  correction({'method':'parseKeyId','key':name},None)
 for data in [f'{ESC}[55296u',f'{ESC}[57343u',f'{ESC}[1114112u',f'{ESC}[4294967393u',f'{ESC}[97;4294967297u',f'{ESC}[97;0u',f'{ESC}[97u\n',f'{ESC}[27;4294967297;97~',f'{ESC}[97:55296;2u']:
  for method in ['parseKey','decodeKittyPrintable','decodePrintableKey']:
   correction({'method':method,'data':data},None)
 correction({'method':'parseKey','data':f'{ESC}[65583u'},None)
 correction({'method':'parseKey','data':f'{ESC}[65583::99;5u'},'ctrl+c')
 correction({'method':'matchesKey','data':f'{ESC}[65583::99;5u','key':'ctrl+c'},True)
 for (input,want),got in zip(corrections,batch(command,[x[0] for x in corrections])):assert want==got,(input,want,got)
 print(f'{len(corrections)} identifier/Unicode/malformed-boundary checks passed',flush=True)
 # Real pasted input is large and can contain misleading event substrings.
 long='x'*120000+':3u'
 longcases=[({'method':'isKeyRelease','data':long},True),({'method':'isKeyRelease','data':ESC+'[200~'+long+ESC+'[201~'},False),({'method':'isKeyRepeat','data':'x'*120000+':2F'},True),({'method':'parseKey','data':'x'*120000},None)]
 for (input,want),got in zip(longcases,batch(command,[x[0] for x in longcases],1)):assert want==got,(input['method'],want,got)
 print('4 long paste/event scans passed',flush=True)

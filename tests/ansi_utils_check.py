#!/usr/bin/env python3
"""Source-equivalent ANSI behavior, explicit corrections, and long inputs."""
import argparse,itertools,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];E='\x1b'
def run(command,items):
 p=subprocess.run(command+[json.dumps(items,separators=(',',':'),ensure_ascii=False)],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert p.returncode==0,(p.returncode,p.stderr[-2000:])
 return json.loads(p.stdout)
def batch(command,items):
 result=[]
 for i in range(0,len(items),100):result.extend(run(command,items[i:i+100]))
 return result
def corpus():
 rng=random.Random(374);cases=[]
 codes=[E+'['+x+'m' for x in ['','0','1','2','3','4','5','7','8','9','21','22','23','24','25','27','28','29','39','49','31','41','90','107','1;4;31;42','0;4;48;5;255','1;0;2;38;2;0;255;0','38;5;0','48;5;255','38;2;0;0;0','48;2;255;255;255','038;5;002','0048;2;001;002;003']]
 codes += [E+']8;id=x;https://example.test/a'+t for t in ['\x07',E+'\\']]+[E+']8;;'+t for t in ['\x07',E+'\\']]+[E+']0;window\ttitle'+E+'\\',E+'_payload\tdata\x07',E+'[4G',E+'[2K',E+'[H',E+'[2J']
 for c,t in itertools.product(codes,['','abc','a\tb','ำຳ','😀é']):
  value=t+c+t
  cases += [{'method':m,'text':value} for m in ['strip','normalize','background','close']]
  cases.append({'method':'extract','text':value,'position':len(t)})
 for _ in range(400):
  items=[rng.choice(codes) for _ in range(rng.randrange(1,24))];items.insert(rng.randrange(len(items)),None)
  cases.append({'method':'track','items':items})
 for prefix,suffix in itertools.product(codes[:33],codes[:33]):cases.append({'method':'track','items':[prefix,suffix]})
 return cases
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--reference',default='/home/agent/code/pi-mono');p.add_argument('--width-reference',default='build/ansi-reference/node_modules/get-east-asian-width/index.js');p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 oracle=['bun','tests/ansi_utils_reference.ts',a.reference,a.width_reference]
 original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True));actual=batch(command,[x['input'] for x in original]);assert actual==[x['expected'] for x in original]
 print(f'{len(original)} normalization observations from 2 actual named tests passed',flush=True)
 cases=corpus();expected=batch(oracle,cases);actual=batch(command,cases)
 assert len(actual)==len(expected)
 for c,w,g in zip(cases,expected,actual):assert w==g,(c,w,g)
 print(f'{len(cases)} actual-source ANSI/style comparisons passed',flush=True)
 corrections=[]
 def case(method,text,expected,**kw):corrections.append((dict(method=method,text=text,**kw),expected))
 for control in [E+'[?25h',E+'[1;2A',E+'[>7u',E+'[0 q']:
  case('strip','x'+control+'y','xy');case('extract',control,{'code':control,'length':len(control)})
 for text in [E+'[12',E+']unterminated'+E+'[31m',E+'_unterminated',E+'[12😀visible',E+'[1 '+E+'xhello']:
  case('strip',text,text)
 for ending in ['\x07',E+'\\']:
  for prefix in [E+']8;;https://example.test/ำຳ',E+']0;ำຳ']:
   text=prefix+ending+'ำ\tຳ';case('normalize',text,prefix+ending+'ํา   ໍາ')
 seed=E+'[1;4;31;42m';unchanged={'codes':seed,'background':E+'[42m','reset':E+'[24m','active':True}
 for invalid in ['38;2;1;2','48;5;256','38;2;0;256;0','38;7;1','48;2;1;;3','1;48;5;999','4294967296']:
  # Empty RGB channels have ANSI default-zero meaning; only malformed groups reject.
  if invalid=='48;2;1;;3':continue
  corrections.append(({'method':'track','items':[seed,E+'['+invalid+'m']},[unchanged,unchanged]))
 empty={'codes':'','background':'','reset':'','active':False}
 corrections.append(({'method':'track','items':[seed,E+'[;m']},[unchanged,empty]))
 got=batch(command,[x[0] for x in corrections]);assert got==[x[1] for x in corrections],[(i,c,g) for i,(c,g) in enumerate(zip(corrections,got)) if c[1]!=g]
 print(f'{len(corrections)} corrected framing/payload/malformed-style cases passed',flush=True)
 long='x'*100000
 for c,expected in [({'method':'strip','text':long},long),({'method':'normalize','text':long},long),({'method':'strip','text':E+']'+long},E+']'+long),({'method':'extract','text':E+']'+long+'\x07'},{'code':E+']'+long+'\x07','length':100003}),({'method':'strip','text':(E+'[31mX')*10000},'X'*10000)]:assert run(command,[c])==[expected]
 print('5 long plain/control/token scans passed',flush=True)

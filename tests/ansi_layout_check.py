#!/usr/bin/env python3
"""Actual pinned layout assertions and ANSI/Unicode boundary comparisons."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];E='\x1b'
def compressed(value):
 result=dict(value);text=result.get('text','')
 if len(text)>10000:
  for n in range(1,100):
   if len(text)%n==0 and text[:n]*(len(text)//n)==text:
    result['text']=text[:n];result['repeat']=len(text)//n;break
 return result
def run(command,items,compress=False):
 payload=[compressed(v) for v in items] if compress else items
 p=subprocess.run(command+[json.dumps(payload,separators=(',',':'),ensure_ascii=False)],cwd=ROOT,text=True,capture_output=True,timeout=120)
 assert p.returncode==0,(p.returncode,p.stderr[-2000:])
 return json.loads(p.stdout)
def batch(command,items,compress=False):
 result=[]
 for i in range(0,len(items),40):result.extend(run(command,items[i:i+40],compress))
 return result
def corpus():
 rng=random.Random(763);cases=[]
 samples=['','hello world','hello  world   ','a\tb','a\n\r\nb','界界x界','日本語の文章','a\u0301 b','👩\u200d💻👩\u200d💻 xyz','🇦🇧🇨 abc','กำfoo','က္က်က္','a\u00a0b','\x00a','\u065f','\u302e','\u1734']
 styles=['',E+'[31m',E+'[4m',E+'[1;3;48;2;0;255;4m',E+']8;p=x;https://example.com\x07',E+']8;;https://x'+E+'\\']
 for text in samples:
  for style in styles:
   text=style+text+(E+'[0m' if style else '')
   for width in [0,1,2,3,5,8,20]:
    cases.append(dict(method='wrapTextWithAnsi',text=text,width=width))
    for ellipsis in ['', '...', '…','界',E+'[32m..'+E+'[0m']:
     cases.append(dict(method='truncateToWidth',text=text,width=width,ellipsis=ellipsis,pad=rng.choice([True,False])))
    for strict in [True,False]:
     start=rng.randrange(9)
     cases.append(dict(method='sliceWithWidth',text=text,start=start,length=width,strict=strict))
     cases.append(dict(method='extractSegments',text=text,before=start,after=start+rng.randrange(4),length=width,strict=strict))
 for _ in range(500):
  text=''.join(rng.choices(['ab','界','カ','한','ㄅ','ー','々','\u0301','🙂',' ', '\t',E+'[31m',E+'[24m'],k=rng.randrange(15)))
  cases.append(dict(method='wrapTextWithAnsi',text=text,width=rng.randrange(1,12)))
 return cases
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--reference',default='/home/agent/code/pi-mono');p.add_argument('--width-reference',default='build/ansi-reference/node_modules/get-east-asian-width/index.js');p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 oracle=['bun','tests/ansi_layout_reference.ts',a.reference,a.width_reference]
 original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True));calls=original['calls'];actual=batch(command,[c['input'] for c in calls],True)
 assert len(actual)==len(calls)
 for c,g in zip(calls,actual):assert c['expected']==g,(c['name'],c['input'] if len(c['input']['text'])<1000 else '<large>',c['expected'],g)
 print(f'{len(calls)} layout results from {len(set(c["name"] for c in calls))} original named tests passed',flush=True)
 properties=[{'method':'cjkProperties'}];assert run(command,properties)==run(oracle,properties)
 print('All 1,114,112 CJK Script_Extensions values match the pinned source regex digest',flush=True)
 cases=corpus();expected=batch(oracle,cases);actual=batch(command,cases);assert len(actual)==len(expected)
 for c,w,g in zip(cases,expected,actual):assert w==g,(c,w,g)
 print(f'{len(cases)} ANSI/Unicode wrapping, truncation and slicing comparisons passed',flush=True)

 long=[dict(method='wrapTextWithAnsi',text='x',repeat=20000,width=10000),dict(method='wrapTextWithAnsi',text='x ',repeat=10000,width=10000),dict(method='wrapTextWithAnsi',text='a'+'\u0301'*20000+' word'*40,width=20),dict(method='wrapTextWithAnsi',text='x',repeat=100000,width=80),dict(method='wrapTextWithAnsi',text='word ',repeat=10000,width=80),dict(method='sliceWithWidth',text='界x',repeat=100000,start=299990,length=10,strict=True),dict(method='extractSegments',text='x',repeat=200000,before=10,after=199990,length=10,strict=True)]
 assert batch(command,long)==batch(oracle,long)
 print('Seven wide-line/long combining/unbroken-word/wrapping/slicing/overlay scans passed',flush=True)
 corrected=[
  (dict(method='wrapTextWithAnsi',text=E+'[?25lab',width=1),[E+'[?25la','b']),
  (dict(method='truncateToWidth',text=E+'[?25labc',width=2,ellipsis='',pad=False),E+'[?25lab'+E+'[0m'),
  (dict(method='sliceWithWidth',text=E+'[?25labc',start=1,length=1,strict=True),dict(text=E+'[?25lb',width=1)),
  (dict(method='sliceWithWidth',text=E+']bad'+E+'[31m',start=0,length=100,strict=True),dict(text=E+']bad'+E+'[31m',width=8)),
  (dict(method='extractSegments',text=E+'[?25labc',before=1,after=2,length=1,strict=True),dict(before=E+'[?25la',beforeWidth=1,after='c',afterWidth=1)),
 ]
 for case,want in corrected:assert run(command,[case])==[want],(case,want,run(command,[case]))
 print('Five approved control-grammar correction cases passed',flush=True)

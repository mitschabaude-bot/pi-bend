#!/usr/bin/env python3
"""Pinned Pi width assertions, Unicode17 data, RGI sequences and valid text."""
import argparse,importlib.util,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];E='\x1b'
spec=importlib.util.spec_from_file_location('display',ROOT/'scripts/generate-display-unicode.py');data=importlib.util.module_from_spec(spec);spec.loader.exec_module(data)
def run(command,items):
 p=subprocess.run(command+[json.dumps(items,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=120)
 assert p.returncode==0,(p.returncode,p.stderr[-2000:])
 return json.loads(p.stdout)
def batch(command,items):
 result=[]
 for i in range(0,len(items),100):result.extend(run(command,items[i:i+100]))
 return result
def corpus():
 rng=random.Random(531);cases=[];emojis=data.emoji();prefixes=set()
 for points in emojis:
  for n in range(1,len(points)+1):prefixes.add(points[:n])
 for points in sorted(prefixes):
  text=''.join(map(chr,points));cases += [{'method':m,'text':text} for m in ['width','grapheme','emoji']]
 # Near misses must not become emoji through hash collisions or broad heuristics.
 for points in sorted(emojis)[::3]:
  text=''.join(map(chr,points));cases += [{'method':'emoji','text':text+'a'},{'method':'emoji','text':'a'+text}]
 values=data.properties();boundaries={cp for cp in range(1,len(values)) if values[cp]!=values[cp-1]}
 for cp in sorted({n for p in boundaries for n in [p-1,p,p+1] if 0<=n<0x110000 and not 0xd800<=n<=0xdfff}):
  text=chr(cp);cases += [{'method':'width','text':text},{'method':'width','text':'a'+text}]
 marks=[chr(cp) for cp,v in enumerate(values) if v&1];bases=['a','界','ก','ກ','क','က္','ｶ','😀','1','\t','\x00','\u200d']
 for _ in range(1000):
  text=rng.choice(bases)+''.join(rng.choices(marks,k=rng.randrange(6)))
  cases.append({'method':'width','text':text})
 for _ in range(500):
  points=[rng.randrange(0x110000) for _ in range(rng.randrange(12))];text=''.join(chr(p) for p in points if not 0xd800<=p<=0xdfff);cases.append({'method':'width','text':text})
 for text in ['a\u0301','क्ष','🇨🇳','👩\u200d💻','กำ','ກຳ','ｶﾞ','a\tb','\u065f','\u1734','\u302e']:
  for pos in range(len(text)+1):
   decorated=text[:pos]+E+'[31m'+text[pos:]+E+'[0m';cases.append({'method':'width','text':decorated})
 return cases
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--reference',default='/home/agent/code/pi-mono');p.add_argument('--width-reference',default='build/ansi-reference/node_modules/get-east-asian-width/index.js');p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 oracle=['bun','tests/visible_width_reference.ts',a.reference,a.width_reference]
 original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True));calls=original['calls'];actual=batch(command,[c['input'] for c in calls])
 assert len(actual)==len(calls)
 for c,g in zip(calls,actual):assert c['expected']==g,(c,g)
 print(f'{len(calls)} width observations from {len(set(c["name"] for c in calls))} original named tests passed; wrapping/slicing results remain reference-only',flush=True)
 property_case=[{'method':'properties'}];expected=run(oracle,property_case);actual=run(command,property_case);assert actual==expected,(expected,actual)
 print('All 1,114,112 Unicode property/EastAsianWidth/singleton-RGI values match source digest',flush=True)
 cases=corpus();expected=batch(oracle,cases);actual=batch(command,cases);assert len(actual)==len(expected)
 for c,w,g in zip(cases,expected,actual):assert w==g,(c,w,g)
 print(f'{len(cases)} RGI/prefix/property-boundary/mixed-text comparisons passed',flush=True)
 corrected=[({'method':'width','text':'a'+E+'[?25lb'},2),({'method':'width','text':E+'[12😀visible'},12),({'method':'width','text':E+']bad'+E+'[31m'},8)]
 for case,want in corrected:assert run(command,[case])==[want],(case,want,run(command,[case]))
 long=[({'method':'repeat','text':'x','repeat':200000},200000),({'method':'repeat','prefix':'a','text':'\u0301','repeat':100000},1),({'method':'repeat','text':'👩\u200d💻','repeat':10000},20000),({'method':'repeat','text':E+'[31mX'+E+'[0m','repeat':10000},10000)]
 for case,want in long:assert run(command,[case])==[want],(case,want)
 print('3 corrected-control widths and 4 long ASCII/combining/emoji/styled scans passed',flush=True)

#!/usr/bin/env python3
"""Actual Image source, original component assertions and cache/callback behavior."""
from upstream_pin import UPSTREAM
import argparse,json,re,subprocess,random
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(command,values):
 p=subprocess.run(command+[json.dumps(values,ensure_ascii=False,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert p.returncode==0,(p.returncode,p.stderr[-3000:])
 result=json.loads(p.stdout)
 assert isinstance(result,list) and len(result)==len(values),('result count',len(result),len(values))
 return result
def batch(command,values):
 result=[]
 for i in range(0,len(values),8):result+=run(command,values[i:i+8])
 return result
def normalized(value,configured):
 if value['results'] is None:return value
 ids={s['id'] for s in value['results'] if s['id'] is not None}
 if configured is None:
  assert len(ids)<=1,ids
  for identifier in ids:assert 1<=identifier<4294967295,identifier
  for item in value['results']:
   if item['id'] is not None:
    identifier=item['id'];item['id']=42;item['lines']=[re.sub(r'(?<=,)i='+str(identifier)+r'(?=[,;])','i=42',s) for s in item['lines']]
 return value
def corpus():
 dims=lambda w,h:dict(widthPx=w,heightPx=h)
 base=dict(data='AAAA',mime='image/png',home='/test/home',env={'TERM_PROGRAM':'kitty'},cells=dims(10,20),options={'maxWidthCells':10},dimensions=dims(10,100),steps=[{'width':12}])
 a=[base,{**base,'cells':dims(10,10),'dimensions':dims(20,20),'options':{'maxWidthCells':2},'steps':[{'width':4}]},{**base,'env':{},'prefix':'\x1b[33m','suffix':'\x1b[0m','options':{'filename':'/test/home/images/'+'generated-image-with-a-very-long-absolute-path'*4+'.png'},'dimensions':dims(1280,720),'steps':[{'width':40}]}]
 r=random.Random(62)
 for _ in range(100):
  width=r.choice([0,1,2,3,10,20,80]);opts={'filename':'/test/home/界 😀 image.png'}
  if r.randrange(2):opts['imageId']=r.choice([1,42,4294967295])
  if r.randrange(2):opts['maxWidthCells']=r.choice([.5,1,2,3,10,60,100])
  if r.randrange(2):opts['maxHeightCells']=r.choice([.5,1,3,10,20])
  a.append(dict(data='AAAA',mime='image/png',home='/test/home',env={'TERM_PROGRAM':r.choice(['kitty','iterm.app','unknown'])},prefix=r.choice(['','\x1b[33m']),suffix='\x1b[0m',options=opts,dimensions=dims(r.randint(1,1000),r.randint(1,1000)),cells=dims(r.choice([9,10,9.5]),r.choice([16,18,20])),steps=[{'width':width},{'width':width},{'width':width,'invalidate':True},{'width':width+3}]))
 a.append(dict(data='AAAA',mime='unknown',steps=[{'width':40},{'width':40},{'width':50}],options={}))
 a.append(dict(data='AAAA',mime='image/png',dimensions=dims(20,20),env={},steps=[{'width':10},{'width':10,'caps':{'images':'kitty','trueColor':True,'hyperlinks':True}},{'width':10,'invalidate':True},{'width':11,'caps':{'images':'iterm2','trueColor':True,'hyperlinks':True}},{'width':11,'caps':{'images':None,'trueColor':False,'hyperlinks':False}},{'width':11,'invalidate':True}]))
 for program in ['unknown','kitty']:
  a.append(dict(data='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+nmP8AAAAASUVORK5CYII=',mime='image/png',env={'TERM_PROGRAM':program},steps=[{'width':10}]))
 for width in [4294967295,4294967296,5000000002,281474976710655]:
  for program in ['kitty','iterm.app']:
   a.append(dict(data='AAAA',mime='image/png',env={'TERM_PROGRAM':program},dimensions=dims(4294967295,1),options={'imageId':42,'maxWidthCells':10000000000,'maxHeightCells':3},cells=dims(1,1),steps=[{'width':width}]))
 return a
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--upstream',default=str(UPSTREAM));p.add_argument('--width-reference',default='/home/agent/code/pi-bend-tui-ansi/build/ansi-reference/node_modules/get-east-asian-width/index.js');p.add_argument('command',nargs='+');args=p.parse_args()
 oracle=['bun','tests/image_component_reference.ts',args.upstream,args.width_reference];values=corpus();expected=batch(oracle,values);actual=batch(args.command,values)
 for index,(v,want,got) in enumerate(zip(values,expected,actual)):
  configured=v.get('options',{}).get('imageId');assert normalized(got,configured)==normalized(want,configured),(index,v,want,got)
 named=json.loads(subprocess.check_output(oracle+['--named'],cwd=ROOT,text=True));assert len(named['passed'])==3
 for i,case in enumerate(named['cases']):assert normalized({'results':[{'lines':case['lines'],'id':next((int(x) for line in case['lines'] for x in re.findall(r',i=(\d+)',line)),None)}]},None)['results'][0]['lines']==actual[i]['results'][0]['lines']
 print(f'{len(values)} component/caching sequences match source; all3 original Image component assertions pass')

 invalid=[dict(data='AAAA',mime='image/png',dimensions={'widthPx':0,'heightPx':1},steps=[{'width':10}]),dict(data='AAAA',mime='image/png',options={'imageId':0},steps=[{'width':10}]),dict(data='AAAA',mime='image/png',options={'maxWidthCells':0},steps=[{'width':10}]),dict(data='AAAA',mime='image/png',options={'maxHeightCells':-1},steps=[{'width':10}]),dict(data='bad base64',mime='image/png',env={'TERM_PROGRAM':'kitty'},dimensions={'widthPx':10,'heightPx':10},steps=[{'width':10}])]
 for got in batch(args.command,invalid):assert got=={'results':None,'callbacks':0},got
 print('5 malformed image/options cases reject without calling fallback theme')

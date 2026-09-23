#!/usr/bin/env python3
"""Exact pinned terminal-image protocols, environment policy, metadata and sizing."""
import argparse,base64,json,random,re,struct,subprocess
from pathlib import Path
def compress(v):
 v=dict(v);text=v.get('text','')
 match=re.search(r'(.)\1{10000,}',text)
 if match:v.update(text=text[:match.start()],repeated=match[1],repeat=len(match[0]),suffix=text[match.end():])
 return v
ROOT=Path(__file__).resolve().parents[1];E='\x1b';S=E+'\\'
def batch(command,items):
 result=[]
 for i in range(0,len(items),5):
  p=subprocess.run(command+[json.dumps([compress(v) for v in items[i:i+5]],ensure_ascii=False,separators=(',',':'))],cwd=ROOT,capture_output=True,text=True,timeout=90)
  assert p.returncode==0,(p.returncode,p.stderr[-3000:])
  values=json.loads(p.stdout)
  assert isinstance(values,list) and len(values)==len(items[i:i+5]),('result count',len(values),len(items[i:i+5]))
  result+=values
 return result

def cases():
 r=random.Random(925);a=[]
 for text in ['', 'abc',E, E+'_',E+']1337;',E+'_G',E+']1337;File=','a'+E+'_Gb','a'+E+']1337;File=foo','normal\nline',E+'[31m'+E+'_G',E+'_G'+S, 'x'*10000+E+'_G']:
  a.append(dict(method='isImageLine',text=text))
 for size in [0,1,2,3,30,3071,3072,3073,6144,13000]:
  data=base64.b64encode(r.randbytes(size)).decode()
  for options in [{},{'columns':3,'rows':5,'imageId':42,'moveCursor':False},{'imageId':4294967295}]:a.append(dict(method='encodeKitty',data=data,options=options))
  for options in [{},{'width':2,'height':'auto'},{'width':{'unit':'pixels','value':100},'height':{'unit':'percent','value':50},'name':'é界.png','inline':False,'preserveAspectRatio':False}]:a.append(dict(method='encodeITerm2',data=data,options=options))
 envs=[{}, {'TERM':'xterm-kitty'},{'TERM':'screen-256color'}, {'TERM':'tmux-256color'}, {'TMUX':'x'},{'COLORTERM':'truecolor'}, {'COLORTERM':'24bit'}, {'WT_SESSION':'x'}]
 envs += [{'TERM_PROGRAM':p} for p in ['kitty','ghostty','WezTerm','WarpTerminal','iTerm.app','vscode','zed','alacritty','Apple_Terminal','tmux','screen']]
 envs += [{k:'x'} for k in ['KITTY_WINDOW_ID','GHOSTTY_RESOURCES_DIR','WEZTERM_PANE','ITERM_SESSION_ID','CMUX_WORKSPACE_ID','WARP_SESSION_ID','WARP_TERMINAL_SESSION_UUID']]
 envs += [{'TERMINAL_EMULATOR':'JetBrains-JediTerm'},{'TMUX':'x','TERM_PROGRAM':'ghostty','COLORTERM':'truecolor'}]
 for env in envs:
  for platform in ['linux','win32','darwin']:
   for probe in [False,True]:a.append(dict(method='caps',env=env,platform=platform,probe=probe))
 for value in ['0','1','auto','bogus']:
  for key in ['PI_HYPERLINKS','PI_TRUE_COLOR','PI_IMAGE_PROTOCOL']:
   a.append(dict(method='caps',env={'TERM_PROGRAM':'ghostty',key:value}))
 for value in ['kitty','iterm2','none','0','auto']:
  a.append(dict(method='caps',env={'PI_IMAGE_PROTOCOL':value,'TMUX':'x'},probe=True))
 for _ in range(250):
  dimensions=dict(widthPx=r.randint(1,100000),heightPx=r.randint(1,100000));cells=dict(widthPx=r.choice([8,9,10,9.5]),heightPx=r.choice([16,18,20,17.5]));width=r.choice([.5,1,3,80,80.9,150]);height=r.choice([None,.5,1,3,40,80.9]);v=dict(method='size',dimensions=dimensions,cells=cells,width=width)
  if height is not None:v['height']=height
  a.append(v)
  if len(a)%5==0:a.append(dict(method='render',dimensions=dimensions,cells=cells,data='AAAA',env={'TERM_PROGRAM':r.choice(['ghostty','iTerm.app','unknown'])},options={'maxWidthCells':width,'maxHeightCells':height,'imageId':42,'moveCursor':False}))
 meta=dict(imageId=42,columns=3,rows=3,widthPx=100,heightPx=100)
 for text in [E+'_Ga=T,f=100,q=2,C=1,c=3,r=3,i=42;AAAA'+S,'left '+E+'_Ga=T,f=100,q=2,c=3,r=3,i=42,m=1;AAAA'+S+E+'_Gm=0;AAAA'+S+' right',E+'_Ga=T,i=42,p=2,x=1,y=2,z=-1,U=1,Q=1,h=3;AAAA'+S,'unknown','prefix '+E+'_Gi=0,i=42;AAAA'+S]:
  for hidden,visible in [(0,3),(1,1),(2,1),(1,5)]:a.append(dict(method='crop',text=text,hidden=hidden,visible=visible,**meta))
  a.append(dict(method='placement',text=text,**meta))
 for name in [None,'x.png','/tmp/a.png','/tmp/a %?#é界\\x.png','/home/test','/home/test/a.png','/home/tester/a.png','/tmp/a^{}[]`#?%/../b','/tmp/a/.','///tmp/a//','/tmp/a/..']:
  for env in [{},{'TERM_PROGRAM':'ghostty'}]:a.append(dict(method='fallback',mime='image/png',dimensions={'widthPx':100,'heightPx':50},filename=name,home='/home/test',env=env))
 for text,url in [('text','https://example.com'),('', 'https://x'),(E+'[31mred'+E+'[0m','file:///tmp/x')]:a.append(dict(method='hyperlink',text=text,url=url))
 a += [dict(method='delete',imageId=i) for i in [1,42,4294967295]]+[dict(method='deleteAll'),dict(method='deletePlacements')]
 png=b'\x89PNG\r\n\x1a\n'+struct.pack('>I',13)+b'IHDR'+struct.pack('>II',300,70)+b'\x08\x06\0\0\0'+b'\0'*4
 gif=b'GIF89a'+struct.pack('<HH',50,100)+b'\0'*3
 jpeg=b'\xff\xd8\xff\xe0\0\x04ab\xff\xc0\0\x0b\x08\0\x46\x01\x2c\x01\x01\x11\0'
 vp8=b'\0'*3+b'\x9d\x01\x2a'+struct.pack('<HH',200,100)
 webp=b'RIFF'+struct.pack('<I',len(vp8)+12)+b'WEBPVP8 '+struct.pack('<I',len(vp8))+vp8
 for mime,data in [('png',png),('gif',gif),('jpeg',jpeg),('webp',webp)]:a.append(dict(method='dimensions',mime='image/'+mime,data=base64.b64encode(data).decode()))
 a.append(dict(method='dimensions',mime='image/jpeg',data=base64.b64encode(jpeg[:2]+b'\xff\xfe\x00\x05abc'+jpeg[2:]).decode()))
 for marker,precision in [(192,8),(193,8),(193,12),(194,8),(194,12)]:
  payload=bytes([precision,0,70,1,44,2,1,17,0,2,17,1]);header=b'\xff\xd8\xff'+bytes([marker])+struct.pack('>H',len(payload)+2)+payload
  a.append(dict(method='dimensions',mime='image/jpeg',data=base64.b64encode(header).decode()))
 a.extend(dict(method='fallback',mime='image/png',filename='/tmp/a'+chr(code)+'z',env={'TERM_PROGRAM':'kitty'}) for code in range(128))
 for v in a:
  if v.get("options",{}).get("maxHeightCells",1) is None: del v["options"]["maxHeightCells"]
 return a
def boundaries():
 encoded=lambda b:base64.b64encode(b).decode()
 a=[({'method':'encodeKitty','data':'not base64!'},None),({'method':'encodeITerm2','data':'AB=='},None),({'method':'encodeKitty','data':'AAAA','options':{'imageId':0}},None),({'method':'encodeKitty','data':'AAAA','options':{'columns':0}},None),({'method':'hyperlink','text':'visible','url':'https://x\x1b]8;;evil'},None),({'method':'size','dimensions':{'widthPx':0,'heightPx':10},'width':80},None),({'method':'size','dimensions':{'widthPx':10,'heightPx':10},'width':0},None),({'method':'delete','imageId':0},None)]
 jpeg=b'\xff\xd8\xff\xc3\x00\x0b\x10\x00\x46\x01\x2c\x01\x01\x11\x00'
 a.append((dict(method='dimensions',mime='image/jpeg',data=encoded(jpeg)),dict(widthPx=300,heightPx=70)))
 payload=b'\x2f'+struct.pack('<I',299|(69<<14))
 webp=b'RIFF'+struct.pack('<I',18)+b'WEBPVP8L'+struct.pack('<I',5)+payload+b'\0'
 a.append((dict(method='dimensions',mime='image/webp',data=encoded(webp)),dict(widthPx=300,heightPx=70)))
 for mime,data in [('jpeg',b'\xff\xd8\xff\xe0\x00\x01'),('jpeg',jpeg[:-1]),('png',b'\x89PNG'+b'X'*30),('gif',b'GIF88a'+b'X'*10),('webp',webp[:24])]:a.append((dict(method='dimensions',mime='image/'+mime,data=encoded(data)),None))
 a.append((dict(method='size',dimensions={'widthPx':1,'heightPx':4294967295},width=4294967295,cells={'widthPx':1,'heightPx':5e-324}),None))
 meta=dict(imageId=42,columns=3,rows=3,widthPx=100,heightPx=100,text='\x1b_Gi=42;AAAA\x1b\\')
 a.append((dict(method='crop',hidden=3,visible=1,**meta),None));a.append((dict(method='crop',hidden=0,visible=0,**meta),None))
 return a
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('command',nargs='+');p.add_argument('--upstream',default='../pi-mono');args=p.parse_args();items=cases();expected=batch(['bun','tests/terminal_image_reference.ts',args.upstream],items);actual=batch(args.command,items)
 for index,(v,want,got) in enumerate(zip(items,expected,actual)):
  assert got==want,(index,v,want,got)
 print(f'{len(items)} terminal-image reference comparisons passed')
 named=json.loads(subprocess.check_output(['bun','tests/terminal_image_named.ts',args.upstream],cwd=ROOT,text=True));captured=named['calls'];results=batch(args.command,[v['input'] for v in captured])
 for v,got in zip(captured,results):assert got==v['expected'],(v['name'],v['input'],v['expected'],got)
 print(f"{len(captured)} captured results from {len(named['passed'])} original named tests passed; 3 Image component cases pending; historical broken-implementation example excluded")

 strict=boundaries();actual=batch(args.command,[v for v,_ in strict])
 for (v,want),got in zip(strict,actual):assert want==got,(v,want,got)
 print(f'{len(strict)} strict-input and header-correction cases passed')

"""Actual CLI file arguments, compared with pinned Pi and Photon."""
import argparse,base64,json,os,pathlib,re,struct,subprocess,tempfile,zlib
from upstream_pin import PIN, UPSTREAM
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--photon',required=True);p.add_argument('--prefix',default='build/file-processor');p.add_argument('backends',nargs='*');a=p.parse_args()
photon=pathlib.Path(a.photon).resolve();upstream=UPSTREAM;pin=PIN
def source(path):return subprocess.check_output(['git','-C',str(upstream),'show',pin+':packages/coding-agent/'+path],text=True)
def png(w,h):
 def chunk(k,d):return struct.pack('>I',len(d))+k+d+struct.pack('>I',zlib.crc32(k+d))
 rows=b''.join(b'\0'+bytes((x*7+y*11)%256 for x in range(w*4)) for y in range(h))
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
with tempfile.TemporaryDirectory(prefix='file-processor-') as directory:
 root=pathlib.Path(directory);cwd=root/'work';home=root/'home';cwd.mkdir();home.mkdir()
 for name in ['exif-orientation.ts','image-resize-core.ts','image-convert.ts','image-process.ts','mime.ts','text.ts']:
  text=source('src/utils/'+name).replace('import { loadPhoton } from "./photon.ts";','const loadPhoton=async()=>require('+json.dumps(str(photon))+');')
  (root/name).write_text(text)
 wrapper=source('src/utils/image-resize.ts');(root/'image-resize.ts').write_text('export {resizeImageInProcess as resizeImage} from "./image-resize-core.ts";\n'+wrapper[wrapper.index('export function formatDimensionNote'):])
 text=source('src/cli/file-processor.ts')
 text=text.replace('import chalk from "chalk";','const chalk={red:(x:string)=>x};')
 text=text.replace('"../core/tools/path-utils.ts"',json.dumps(str(upstream/'packages/coding-agent/src/core/tools/path-utils.ts')))
 for name in ['image-process','mime','text']:text=text.replace('"../utils/'+name+'.ts"','"./'+name+'.ts"')
 (root/'file-processor.ts').write_text(text)
 oracle=root/'run.ts';oracle.write_text('import {processFileArguments} from "./file-processor.ts"; process.chdir(process.argv[2]); console.log(JSON.stringify(await processFileArguments(process.argv.slice(4),process.argv[3]==="default"?undefined:{autoResizeImages:process.argv[3]==="true"})));')
 for name,data in [('text',b'one\r\ntwo\n'),('empty',b''),('bom',b'\xef\xbb\xbfhello'),('double-bom',b'\xef\xbb\xbf\xef\xbb\xbfhello'),('bom-only',b'\xef\xbb\xbf'),('invalid',b'a\xffb'),('small.png',png(7,9)),('large.png',png(2010,3)),('broken.gif',b'GIF89a')]: (cwd/name).write_bytes(data)
 gif=b'GIF89a'+struct.pack('<HHBBB',1,1,128,0,0)+bytes([20,40,60,255,255,255,44])+struct.pack('<HHHHB',0,0,1,1,0)+bytes([2,2,68,1,0,59]);(cwd/'tiny.gif').write_bytes(gif)
 bmp=b'BM'+struct.pack('<IHHI',58,0,0,54)+struct.pack('<IiiHHIIiiII',40,1,1,1,24,0,4,0,0,0,0)+bytes([0,0,255,0]);(cwd/'opaque-image').write_bytes(bmp)
 jpeg=base64.b64decode(re.search(r'const TINY_JPEG_2X1\s*=\s*"([^"]+)"',source('test/image-processing.test.ts'))[1]);(cwd/'tiny.jpg').write_bytes(jpeg)
 (cwd/'link').symlink_to(cwd/'text')
 pathcases=[('~/home.txt',home/'home.txt'),('@wide\u202fspace',cwd/'wide space'),('screen 1 AM.png',cwd/'screen 1\u202fAM.png'),('café.txt',cwd/'cafe\u0301.txt'),("Capture d'écran",cwd/'Capture d’écran')]
 for i,(_,path) in enumerate(pathcases):path.write_text('path'+str(i))
 requests=[([], 'default'),(['empty'],'default'),(['text','bom','double-bom','bom-only','empty','text'],'default'),(['link','/proc/self/status'],'default')]
 requests += [([value],'default') for value,_ in pathcases]
 requests += [(['small.png','text','tiny.jpg','tiny.gif','opaque-image','broken.gif','large.png','small.png'],mode) for mode in ['default','true','false']]
 env=os.environ.copy();env['HOME']=str(home)
 expected=[]
 for files,mode in requests:
  result=subprocess.run(['bun',str(oracle),str(cwd),mode,*files],env=env,text=True,capture_output=True,check=True,timeout=180);expected.append(json.loads(result.stdout))
 for backend in a.backends or ['bun','native-1','native-4']:
  command=['bun',str(ROOT/a.prefix)+'.js'] if backend=='bun' else [str(ROOT/a.prefix),'--threads',backend[-1]]
  def run(files,mode='default'):
   result=subprocess.run(command+[str(cwd),str(home),mode,*files],text=True,capture_output=True,check=True,timeout=180)
   assert not result.stderr,result.stderr
   return json.loads(result.stdout)
  for i,((files,mode),want) in enumerate(zip(requests,expected)):
   got=run(files,mode);assert got['text']==want['text'],(backend,i,got,want)
   assert len(got['images'])==len(want['images']),(backend,i)
   for j,(left,right) in enumerate(zip(got['images'],want['images'])):
    assert left['mimeType']==right['mimeType'] and left['type']==right['type'],(backend,i,j)
    if left['data']!=right['data']:
     # Independent PNG encoders need pixel equivalence, not identical DEFLATE choices.
     paths=[]
     for n,image in enumerate([left,right]):
      path=root/f'compare-{n}';path.write_bytes(base64.b64decode(image['data']));paths.append(str(path))
     pixels=[json.loads(x) for x in subprocess.check_output(['bun',str(ROOT/'tests/png_reference.cjs'),str(photon),*paths],text=True).splitlines()]
     assert pixels[0]==pixels[1],(backend,i,j)
  omission=run(['broken.gif']);assert omission['images']==[] and 'Image omitted: could not be resized below the inline image size limit.' in omission['text']
  for files,kind,path in [(['missing'],'missing',str(cwd/'missing')),(['.'],'read',str(cwd)),(['invalid'],'encoding',str(cwd/'invalid')),(['file://remote/no'],'path','file://remote/no')]:assert run(files)=={'error':kind,'path':path},(backend,files)
  # Exact spelling wins over all fallback variants; file URLs are accepted natively.
  (cwd/'café.txt').write_text('exact');assert 'exact' in run(['café.txt'])['text'];(cwd/'café.txt').unlink()
  assert run([(cwd/'text').as_uri()])==run(['text'])
  print(f'{backend}: {len(requests)} pinned file-list comparisons plus omission, errors, URL and exact-path precedence PASS',flush=True)

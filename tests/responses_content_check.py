"""Responses user/tool content and composition with shared image preparation."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string,seq
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
def text(value):return dict(type='text',text=value,textSignature='ignored')
blocks=[text(''),text('alpha'),text('\ud800'),text('😀'),dict(type='image',data='AA==',mimeType='image/png'),dict(type='image',data='BB==',mimeType='image/jpeg'),text('(tool image omitted: model does not support images)')]
contents=[[]]+[[b] for b in blocks]+[list(xs) for xs in itertools.product(blocks,repeat=2)]
contents += [[blocks[4],blocks[0],blocks[5],blocks[1]],[text(''),text(''),blocks[4]],[text('\ud800'),blocks[4]]]
cases=[dict(vision=v,user=content,content=content) for content in contents for v in [False,True]]
for user,content,v in itertools.product(['','plain','\ud800','x😀\udfff'],[[],[blocks[4]],[text('a'),text('b')]], [False,True]):cases.append(dict(vision=v,user=user,content=content))
expected=json.loads(subprocess.check_output(['node','tests/responses_content_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def nativeBlocks(content):return seq('T.TextImageText{T.TextContent{'+string(b['text'])+', Some{"ignored"}}}' if b['type']=='text' else 'T.TextImageImage{T.ImageContent{'+string(b['data'])+', '+string(b['mimeType'])+'}}' for b in content)
def user(v):return 'T.UserText{'+string(v)+'}' if isinstance(v,str) else 'T.UserBlocks{'+nativeBlocks(v)+'}'
lines=['import Base','import ../packages/ai/test/api/responses-content.bend as Check','import ../packages/ai/src/types.bend as T']
for i,(c,r) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join(['True{}' if c['vision'] else 'False{}',user(c['user']),nativeBlocks(c['content'])]+[string(r[k]) for k in ['user','output','preparedUser','preparedOutput']]+[f'"Responses content {i}"'])+')']
groups=[]
for start in range(0,len(cases),30):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+30,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} Responses content cases, direct and image-prepared")']
src=BUILD/'responses-content-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'responses-content-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

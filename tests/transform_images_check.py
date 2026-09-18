"""Typed image downgrade compared with the actual pinned transcript transform."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
blocks=[{'type':'image','data':'encoded','mimeType':'image/png'}, {'type':'text','text':'text','textSignature':'signed'}, {'type':'text','text':''}, {'type':'text','text':'(image omitted: model does not support images)','textSignature':'user-signed'}, {'type':'text','text':'(tool image omitted: model does not support images)','textSignature':'tool-signed'}]
cases=[dict(vision=vision,content=list(content)) for size in range(4) for content in itertools.product(blocks,repeat=size) for vision in [False,True]]
expected=json.loads(subprocess.check_output(['node','tests/transform_images_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def content(values):
    output=[]
    for b in values:
        if b['type']=='image':output.append('Ai.TextImageImage{Ai.ImageContent{'+string(b['data'])+', '+string(b['mimeType'])+'}}')
        else:output.append('Ai.TextImageText{Ai.TextContent{'+string(b['text'])+', '+('Some{'+string(b['textSignature'])+'}' if 'textSignature' in b else 'None{}')+'}}')
    return ' <> '.join(output+['Nil{}'])
lines=['import Base','import ../packages/ai/test/api/transform-images.bend as T','import ../packages/ai/src/types.bend as Ai']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    assert result[0]['timestamp']==41 and result[1]['timestamp']==42 and result[1]['details']=='details' and result[1]['isError'] is True
    assert result[2]=={'role':'user','content':'plain','timestamp':43}
    lines += [f'def case{i}() -> IO(Unit):','  T.check('+('True{}' if case['vision'] else 'False{}')+', '+content(case['content'])+', '+content(result[0]['content'])+', '+content(result[1]['content'])+f', "images {i}")']
groups=[]
for start in range(0,len(cases),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} typed transcript image transformations")']
src=BUILD/'transform-images-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'transform-images-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

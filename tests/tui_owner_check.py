"""Check callback driven TuiBase frame commit and core input behavior."""
import hashlib,json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
upstream=root.parent/'pi-mono'
def run(command,*args):
 p=subprocess.run(command+list(args),cwd=root,text=True,capture_output=True,timeout=90)
 assert p.returncode==0,(command,p.stderr[-2000:])
 return p.stdout.rstrip('\n')
source=(upstream/'packages/tui/src/tui.ts').read_bytes()
assert hashlib.sha256(source).hexdigest()=='2ca47c56f4a4f24b8c6a4c9c9f2a06004bfc312d9dbcd0ac1921a2cae32bc675'
assert b'const SEGMENT_RESET = "\\x1b[0m\\x1b]8;;\\x07";' in source
spec=dict(base=['A','B','C'],width=8,height=3,overlays=[dict(id=3,order=1,lines=['OV'],mouse='none',options=dict(width=2,row=0,col=1),visible=True)],events=[],removeLive=False)
oracle=['bun',str(root/'tests/tui_base_reference.ts'),str(upstream),str(root/'build/input-reference/node_modules/get-east-asian-width/index.js')]
composition=json.loads(run(oracle,json.dumps([spec])))[0]
hidden_spec=dict(spec,overlays=[dict(spec['overlays'][0],visible=False)])
hidden_composition=json.loads(run(oracle,json.dumps([hidden_spec])))[0]
assert composition['renders']==[dict(id=3,width=2)]
assert [x['id'] for x in composition['bounds']]==[3]
assert hidden_composition['renders']==[] and hidden_composition['bounds']==[]
reset='\x1b[0m\x1b]8;;\x07'
expected_frame='|'.join(line+reset for line in composition['lines'])+'#3'
expected_hidden='|'.join(line+reset for line in hidden_composition['lines'])+'#'
visibility=json.loads(run(['bun',str(root/'tests/tui_owner_visibility_reference.ts')],str(upstream)))
assert visibility==dict(renderVisible=['V3/8x3'],releaseVisible=['V3/8x3'],inputVisible=['V3/8x3','I3','Q'],renderHidden=['V3/8x3'],inputHidden=['V3/8x3','V3/8x3','V3/8x3','F3-','F1+','I1','Q'],focused='base')
for backend in ['bun','native-1','native-4']:
 command=['bun',str(root/'build/tui-owner.js')] if backend=='bun' else [str(root/'build/tui-owner'),'--threads',backend[-1]]
 parts=run(command).split('\x1e')
 assert len(parts)==11,(backend,parts)
 before,still_old,stage,published,release,press,hidden_still_old,hidden_stage,hidden_published,hidden,journal=parts
 assert before==still_old=='old#9',(backend,before,still_old)
 assert stage==published==expected_frame,(backend,stage,published,expected_frame)
 assert release==expected_frame+':00',(backend,release)
 assert press==expected_frame+':11',(backend,press)
 assert hidden_still_old==expected_frame,(backend,hidden_still_old)
 assert hidden_stage==hidden_published==expected_hidden,(backend,hidden_stage,hidden_published,expected_hidden)
 assert hidden==expected_hidden+':11',(backend,hidden)
 assert journal=='V3/8x3,R1/8,R2/8,R3/2,V3/8x3,V3/8x3,I3,V3/8x3,R1/8,R2/8,V3/8x3,F3-,F1+,I1,',(backend,journal)
 print(f'{backend}: frame commit and input callback sequence passed')
print('visibility snapshots: one caller evaluation before each render/input; source predicate calls pinned separately')

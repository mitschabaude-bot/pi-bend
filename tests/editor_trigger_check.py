"""Editor symbol-completion contexts against the pinned trigger and debounce patterns."""
from upstream_pin import UPSTREAM
import json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
command=sys.argv[1:]
r=random.Random(9746)
alphabet=['a','Z','0','.','@','#','$','"',' ','\t','　',' ','，','。','「','…','—','查','あ','한','𠮷','/',' ']
fixed=['','@','#','@x','a@x','查看@x','查看，@x','查看。#tag','@"a b','@"a b"','x @"a，b','@a b','@a，b','$x','a $x','「@x','@𠮷','　@src/说']
for extra in ['','$','@$-']:
  texts=fixed+[''.join(r.choice(alphabet) for _ in range(r.randrange(12))) for _ in range(400)]
  wanted=json.loads(subprocess.check_output(['bun',str(ROOT/'tests/editor_trigger_reference.ts'),str(UPSTREAM),extra],input=json.dumps(texts),text=True))
  got=subprocess.check_output(command+[extra]+texts,text=True).split()
  assert len(got)==len(texts),(extra,len(got))
  for text,g,w in zip(texts,got,wanted): assert (g=='True')==w['trigger']==w['debounce'],(extra,text,g,w)
print('3 trigger sets x %d texts match both source patterns'%len(texts))

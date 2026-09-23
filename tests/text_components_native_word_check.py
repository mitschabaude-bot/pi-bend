"""Input/SettingsList integration with decoded native ICU rule/CJK/Khmer/Lao assets."""
import argparse,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
E='\x1b'
texts=['ー'*12,'ｰ'*12,'ﾞ'*12,'ﾟ'*12,'hello world','foo.bar / path/to/file','你好世界','東京大学日本語','カタカナ ｶﾞｯﾂ','한국어 문장','ភាសាខ្មែរ','កុំអី','ភាសា\u0301ខ្មែរ','ភាសា\u200dខ្មែរ','helloភាសាខ្មែរ世界 again','😀 café東京 កុំអី','a\u0301b 👩‍💻 foo','日本','ー'*12]
texts += ['ພາສາ','ພາສາລາວ','ສະບາຍດີ','ປະເທດລາວ','ພາສາ\u0301ລາວ','ພາສາ\u200dລາວ','helloພາສາລາວ世界 ភាសាខ្មែរ']
key_sets=[[E+'b']*8,["\x01"]+[E+'f']*8,['\x17']*8,['\x01']+[E+'d']*8,[E+'b','\x17','\x19',E+'f',E+'d','\x19',E+'[45;5u']]
cases=[dict(text=text,keys=keys) for text in texts for keys in key_sets]
fixture=ROOT/'build/text-components-native-word.json'; fixture.write_text(json.dumps(cases,ensure_ascii=False))
oracle=['bun','tests/text_components_native_word_reference.ts','/home/agent/code/pi-mono','build/input-reference/node_modules',str(fixture)]
expected=[json.loads(s) for s in subprocess.check_output(oracle,cwd=ROOT,text=True).splitlines()]
# Missing engines are required typed failures, not fake successful Intl output.
# Insert is allowed, failed movement/deletion preserves both components; cursor
# then returns to start/end so both backward and forward paths are exercised.
for text,language in [('ภาษา','Thai'),('မြန်မာ','Myanmar')]:
 keys=[E+'b','\x17','\x01',E+'f',E+'d','\x05']
 cases.append(dict(text=text,keys=keys))
 def snap(cursor):return dict(input=dict(value=text,cursor=cursor),settings=dict(input=dict(value=text,cursor=cursor),selected='text'))
 failure=dict(input=dict(error='MissingWordEngine:'+language),settings=dict(error='MissingWordEngine:'+language))
 final=snap(len(text))
 expected.append(dict(observations=[final,failure,failure,snap(0),failure,failure,final],finalInput=final['input'],finalSettings=final['settings']))
fixture.write_text(json.dumps(cases,ensure_ascii=False))
for backend in a.backends:
 command=['bun','build/text-components-native-word.js'] if backend=='bun' else ['build/text-components-native-word','--threads',backend[-1]]
 r=subprocess.run(command+[str(fixture)],cwd=ROOT,capture_output=True,text=True,timeout=180)
 assert r.returncode==0 and not r.stderr,(backend,r.returncode,r.stderr[-4000:])
 actual=[json.loads(s) for s in r.stdout.splitlines()];assert len(actual)==len(expected)
 for i,(got,want) in enumerate(zip(actual,expected)):
  if got!=want:
   Path('/tmp/text-components-native-word-failure.json').write_text(json.dumps(dict(case=cases[i],actual=got,expected=want),ensure_ascii=False,indent=2))
   raise AssertionError((backend,i,'/tmp/text-components-native-word-failure.json'))
 print(f'{backend}: {len(expected)} loaded-context Input/SettingsList sequences pass (CJK, Khmer, Lao, Latin, deterministic Common marks, two missing engines)',flush=True)

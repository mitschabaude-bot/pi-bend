"""Input/SettingsList integration with decoded native six native ICU word assets."""
import argparse,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
E='\x1b'
texts=['ー'*12,'ｰ'*12,'ﾞ'*12,'ﾟ'*12,'hello world','foo.bar / path/to/file','你好世界','東京大学日本語','カタカナ ｶﾞｯﾂ','한국어 문장','ភាសាខ្មែរ','កុំអី','ភាសា\u0301ខ្មែរ','ភាសា\u200dខ្មែរ','helloភាសាខ្មែរ世界 again','😀 café東京 កុំអី','a\u0301b 👩‍💻 foo','日本','ー'*12]
texts += ['ພາສາ','ພາສາລາວ','ສະບາຍດີ','ປະເທດລາວ','ພາສາ\u0301ລາວ','ພາສາ\u200dລາວ','helloພາສາລາວ世界 ភាសាខ្មែរ']
texts += ['ภาษา','ภาษาไทย','ประเทศไทย','ภาษา\u0301ไทย','ภาษา\u200dไทย','ภาษาฯภาษา','helloภาษาไทย世界 ភាសាខ្មែរ','မြန်မာ','မြန်မာဘာသာ','မြန်မာနိုင်ငံ','မြန်မာ\u0301စာ','မြန်မာ\u200dစာ','helloမြန်မာ世界','ภาษาမြန်မာພາສາខ្មែរ']
key_sets=[[E+'b']*8,["\x01"]+[E+'f']*8,['\x17']*8,['\x01']+[E+'d']*8,[E+'b','\x17','\x19',E+'f',E+'d','\x19',E+'[45;5u']]
cases=[dict(text=text,keys=keys) for text in texts for keys in key_sets]
fixture=ROOT/'build/text-components-native-word.json'; fixture.write_text(json.dumps(cases,ensure_ascii=False))
oracle=['bun','tests/text_components_native_word_reference.ts','/home/agent/code/pi-mono','build/input-reference/node_modules',str(fixture)]
expected=[json.loads(s) for s in subprocess.check_output(oracle,cwd=ROOT,text=True).splitlines()]
for backend in a.backends:
 command=['bun','build/text-components-native-word.js'] if backend=='bun' else ['build/text-components-native-word','--threads',backend[-1]]
 r=subprocess.run(command+[str(fixture)],cwd=ROOT,capture_output=True,text=True,timeout=180)
 assert r.returncode==0 and not r.stderr,(backend,r.returncode,r.stderr[-4000:])
 actual=[json.loads(s) for s in r.stdout.splitlines()];assert len(actual)==len(expected)
 for i,(got,want) in enumerate(zip(actual,expected)):
  if got!=want:
   Path('/tmp/text-components-native-word-failure.json').write_text(json.dumps(dict(case=cases[i],actual=got,expected=want),ensure_ascii=False,indent=2))
   raise AssertionError((backend,i,'/tmp/text-components-native-word-failure.json'))
 print(f'{backend}: {len(expected)} loaded-context Input/SettingsList sequences pass (CJK, Khmer, Lao, Thai, Myanmar, Latin, deterministic Common marks)',flush=True)

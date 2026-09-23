"""Extract pinned ICU78.3 word-rule DFA and scalar categories into native data."""
import argparse,hashlib,importlib.util,json,struct,subprocess
from pathlib import Path
from urllib.request import urlopen
ROOT=Path(__file__).resolve().parents[1]
RULE_URL='https://raw.githubusercontent.com/unicode-org/icu/release-78.3/icu4c/source/data/brkitr/rules/word.txt'
RULE_SHA='8c623551556473c97f32a1ecc22716c4d73fbf71b8dc500a4b461302ca146171'
BINARY_SHA='b72fd92aefc26d34b070b3bddfa9edcce3beb4f3eec7fe3bc8a77c577a08c1f0'
CATEGORIES_SHA='baf2903cc7d4559e25e221fced822edd10bb2036ee883de682877b36dcd726b9'
spec=importlib.util.spec_from_file_location('ucd',ROOT/'scripts/generate-regex-unicode.py');ucd=importlib.util.module_from_spec(spec);spec.loader.exec_module(ucd)
def source():
 directory=ROOT/'build/icu78-source';directory.mkdir(parents=True,exist_ok=True)
 rule=directory/'word.txt'
 if not rule.exists():rule.write_bytes(urlopen(RULE_URL).read())
 assert hashlib.sha256(rule.read_bytes()).hexdigest()==RULE_SHA
 binary=directory/'word-rules.bin';categories=directory/'word-categories.bin'
 if not binary.exists() or not categories.exists():
  version=json.loads(subprocess.check_output(['node','-p','JSON.stringify({icu:process.versions.icu,unicode:process.versions.unicode})'],text=True));assert version=={'icu':'78.3','unicode':'17.0'},version
  subprocess.run(['cc','-shared','-fPIC','-I/usr/include/node','tests/icu78_word_rules_oracle.c','-o','build/icu78-word-rules.node'],cwd=ROOT,check=True)
  subprocess.run(['node','-e','const r=require("./build/icu78-word-rules.node").extract(),fs=require("fs");for(const k of ["rules","categories"])fs.writeFileSync("build/icu78-source/word-"+k+".bin",r[k]);'],cwd=ROOT,check=True)
 b=binary.read_bytes();c=categories.read_bytes()
 assert hashlib.sha256(b).hexdigest()==BINARY_SHA
 assert hashlib.sha256(c).hexdigest()==CATEGORIES_SHA
 return rule.read_text(),b,c

def generate(check=False):
 source_rules,binary,categories=source();header=struct.unpack_from('<20I',binary)
 magic,version,length,classes,forward,forward_length,reverse,reverse_length,trie,trie_length,rule,rule_length,status,status_length,*_=header
 assert magic==0xb1a0 and version==6 and length==len(binary)
 assert ''.join(''.join(line.split('#')[0].split()) for line in source_rules.splitlines())==binary[rule:rule+rule_length].decode()
 states,row_length,dict_start,lookahead,flags=struct.unpack_from('<5I',binary,forward)
 # These assertions keep the interpreter honest: upgrades with new machinery
 # must implement it rather than silently discard lookahead or start conditions.
 assert (states,classes,dict_start,lookahead,flags,row_length)==(58,31,24,0,4,34)
 statuses=struct.unpack_from('<'+str(status_length//4)+'I',binary,status)
 rows=[]
 for i in range(states):
  row=list(binary[forward+20+i*row_length:forward+20+(i+1)*row_length]);accept,look,tag=row[:3]
  assert accept in (0,1) and look==0 and max(row[3:])<states
  values=statuses[tag+1:tag+1+statuses[tag]];assert values and all(v in (0,100,200,400) for v in values)
  rows.append(bytes([accept])+struct.pack('<H',max(values))+bytes(row[3:]))
 engines=[0]*0x110000
 for span,name,*_ in ucd.records(ucd.source(),'Scripts.txt'):
  engine={'Han':1,'Hiragana':1,'Katakana':1,'Hangul':2,'Thai':3,'Lao':4,'Myanmar':5,'Khmer':6}.get(name,0)
  if engine:
   for cp in ucd.points(span):engines[cp]=engine
 # CjkBreakEngine's explicit Common-script additions; dispatch policy is documented.
 for cp in [0x30fc,0xff70,0xff9e,0xff9f]:engines[cp]=7
 values=[categories[2*cp]|categories[2*cp+1]<<8|engines[cp]<<8 for cp in range(0x110000)]
 assert all((v&255)<classes for v in values)
 spans=[(0,values[0])]+[(cp,value) for cp,value in enumerate(values[1:],1) if values[cp-1]!=value]
 data=b'ICUWRD01'+struct.pack('<4H',states,classes,dict_start,len(spans))+b''.join(rows)+b''.join(struct.pack('<IH',start,value) for start,value in spans)
 target=ROOT/'packages/runtime/data/icu78-word-rules.bin'
 if check:assert target.read_bytes()==data,'regenerate ICU word rules'
 else:target.write_bytes(data)
 manifest={'icu':'78.3','unicode':'17.0','source':RULE_URL,'source_sha256':RULE_SHA,'compiled_rules_sha256':BINARY_SHA,'scalar_categories_sha256':CATEGORIES_SHA,'states':states,'categories':classes,'dictionary_start':dict_start,'property_ranges':len(spans),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'license':'icu78-cjk.LICENSE','format':'ICUWRD01; states,categories,dictionaryStart,rangeCount:u16le; state(accept:u8,status:u16le,targets:categories*u8); ranges(start:u32le,categoryAndEngine:u16le)'}
 text=json.dumps(manifest,indent=2)+'\n';target=ROOT/'packages/runtime/data/icu78-word-rules.manifest.json'
 if check:assert target.read_text()==text
 else:target.write_text(text)
 print(f'{states} states, {classes} categories, {len(spans)} scalar ranges; {len(data)} bytes')
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');generate(p.parse_args().check)

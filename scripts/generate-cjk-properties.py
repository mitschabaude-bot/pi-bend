"""Unicode17 ICU CJK range and exact NFKC boundary-before predicates."""
import argparse,functools,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('ucd',ROOT/'scripts/generate-regex-unicode.py');ucd=importlib.util.module_from_spec(spec);spec.loader.exec_module(ucd)
def properties():
 z=ucd.source();decomp={};ccc={};pairs=[];excluded=set();handled=set()
 for span,name,*_ in ucd.records(z,'DerivedNormalizationProps.txt'):
  if name=='Full_Composition_Exclusion':excluded.update(ucd.points(span))
 for p in ucd.records(z,'UnicodeData.txt'):
  cp=int(p[0],16);ccc[cp]=int(p[3]);parts=p[5].split()
  if parts:
   canonical=not parts[0].startswith('<');d=[int(x,16) for x in (parts if canonical else parts[1:])];decomp[cp]=d
   if canonical and len(d)==2 and cp not in excluded:pairs.append(d)
 backward={b for a,b in pairs}|set(range(0x1161,0x1176))|set(range(0x11a8,0x11c3))
 @functools.cache
 def first(cp):
  if 0xac00<=cp<=0xd7a3:return 0x1100+(cp-0xac00)//588
  return first(decomp[cp][0]) if cp in decomp else cp
 for span,name,*_ in ucd.records(z,'Scripts.txt'):
  if name in ('Han','Hiragana','Katakana'):handled.update(ucd.points(span))
 handled.update([0x30fc,0xff70,0xff9e,0xff9f])
 return [int(ccc.get(first(cp),0)==0 and first(cp) not in backward)+2*int(cp in handled) for cp in range(0x110000)]
def generate(check=False):
 values=properties();spans=[(0,values[0])]+[(i,v) for i,v in enumerate(values[1:],1) if values[i-1]!=v]
 def tree(rows):
  if len(rows)==1:return str(rows[0][1])
  mid=len(rows)//2
  return f'Bool.pick(Unit -> U32,U32.is_lt(code,{rows[mid][0]}),\n  _ => {tree(rows[:mid])},\n  _ => {tree(rows[mid:])})(Unit{{}})'
 text='# Generated Unicode17 CJK properties; Unicode License V3.\n# bit0: NFKC boundary before; bit1: ICU CjkBreakEngine character set.\nimport Base\n\ndef properties(+code: U32) -> U32:\n  '+tree(spans)+'\n'
 target=ROOT/'packages/runtime/src/unicode-17-cjk.bend'
 if check:assert target.read_text()==text
 else:target.write_text(text)
 print(len(spans),'CJK property ranges')
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');generate(p.parse_args().check)

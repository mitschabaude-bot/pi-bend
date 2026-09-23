"""Compile ICU 78.3's CLDR 48 root collation into packages/runtime/data.

Source: ICU's FractionalUCA.txt (the CLDR root table exactly as ICU builds its
root collator; allkeys_CLDR.txt lacks ICU's radical-stroke Han order, explicit
Tangut/Nushu/Khitan weights and the U+FDD1 index-boundary contractions) plus
the pinned Unicode 17 UCD for the canonical decompositions ICU normalizes
non-FCD input with. Weights are re-ranked densely; only order matters.
"""
import argparse,hashlib,importlib.util,json,re,struct
from pathlib import Path
from urllib.request import urlopen
ROOT=Path(__file__).resolve().parents[1]
URL='https://raw.githubusercontent.com/unicode-org/icu/release-78.3/icu4c/source/data/unidata/FractionalUCA.txt'
SHA='d7cdfab860bf94c6f470c1fae39b81619a12f3a51f80d7cad1ba08404dec3de6'
spec=importlib.util.spec_from_file_location('ucd',ROOT/'scripts/generate-regex-unicode.py');ucd=importlib.util.module_from_spec(spec);spec.loader.exec_module(ucd)

def source():
 path=ROOT/'build/icu78-source/FractionalUCA.txt'
 if not path.exists():path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(urlopen(URL,timeout=60).read())
 data=path.read_bytes();assert hashlib.sha256(data).hexdigest()==SHA,'FractionalUCA.txt changed'
 return data.decode('utf-8').splitlines()

def unicode_data():
 ccc={};decomposition={}
 for f in ucd.records(ucd.source(),'UnicodeData.txt'):
  c=int(f[0],16)
  if f[3]!='0':ccc[c]=int(f[3])
  if f[5] and not f[5].startswith('<'):decomposition[c]=[int(x,16) for x in f[5].split()]
 def full(c):
  if 0xac00<=c<0xd7a4:
   s=c-0xac00;return [0x1100+s//588,0x1161+s%588//28]+([0x11a7+s%28] if s%28 else [])
  return [y for x in decomposition[c] for y in full(x)] if c in decomposition else [c]
 fcd={}
 for c in list(ccc)+list(decomposition):
  d=full(c);value=ccc.get(d[0],0)<<8|ccc.get(d[-1],0)
  if value:fcd[c]=value
 return ccc,{c:full(c) for c in decomposition},fcd

def byte_value(field,width):
 parts=[int(x,16) for x in field.split()];assert len(parts)<=width
 value=0
 for part in parts:value=value<<8|part
 return value<<8*(width-len(parts))

def parse(lines):
 han=[]
 for line in lines:
  if line.startswith('[radical ') and ':' in line:
   body=line.rstrip().rstrip(']').split(':',1)[1];i=0
   while i<len(body):
    if i+2<len(body) and body[i+1]=='-':han+=range(ord(body[i]),ord(body[i+2])+1);i+=3
    else:han.append(ord(body[i]));i+=1
 unified=set()
 for line in lines:
  if line.startswith('[Unified_Ideograph '):
   for span in line.strip('[]').split()[1:]:
    a,_,b=span.partition('..');unified.update(range(int(a,16),int(b or a,16)+1))
 assert sorted(han)==sorted(unified) and len(han)==len(set(han)),'radical-stroke order must cover Unified_Ideograph once'
 rank={c:i for i,c in enumerate(han)}
 def ces(text):
  out=[]
  for body in re.findall(r'\[([^\]]*)\]',text):
   if body.startswith('U+'):
    parts=[x.strip() for x in body.split(',')];c=int(parts[0][2:],16);assert c in rank,body
    out.append(('han',rank[c],0x0500,int(parts[1],16)<<8 if len(parts)>1 else 0x0500))
   else:
    p,s,t=[x.strip() for x in body.split(',')]
    out.append(('explicit',byte_value(p,4),byte_value(s,2),byte_value(t,2)&0x3f3f))
  return out
 singles={};contractions={};prefixes={}
 for line in lines:
  if not line or line[0] in '#[':continue
  key,value=line.split(';',1);value=value.split('#')[0]
  if '|' in key:
   before,code=key.split('|');before=[int(x,16) for x in before.split()];assert len(before)==1
   prefixes.setdefault(int(code,16),[]).append((before[0],ces(value)));continue
  codes=[int(x,16) for x in key.split()]
  # U+FDD0 rows are genuca build anchors (numeric lead byte, reorder
  # reservations, tailoring homes), not runtime contractions: Node agrees.
  if codes[0]==0xfdd0:continue
  if len(codes)==1:singles[codes[0]]=ces(value)
  else:contractions.setdefault(codes[0],[]).append((codes[1:],ces(value)))
 return han,rank,singles,contractions,prefixes

def generate(check=False):
 lines=source();ccc,decomposition,fcd=unicode_data()
 han,han_rank,singles,contractions,prefixes=parse(lines)
 explicit=set()
 for weights in [*singles.values(),*(w for rows in contractions.values() for _,w in rows),*(w for rows in prefixes.values() for _,w in rows)]:
  explicit.update(p for kind,p,_,_ in weights if kind=='explicit' and p)
 low=sorted(p for p in explicit if p<0xe0000000);high=sorted(p for p in explicit if p>=0xe0000000)
 # Han (radical-stroke) sorts in ICU's implicit range E0..E3, unassigned code
 # points after the U+FDD1 U+FDD0 boundary (E4), then the two trailing weights.
 assert high==[0xe4000000,0xeffd0000,0xefff0000],[hex(p) for p in high]
 han_base=len(low)+1;boundary=han_base+len(han);unassigned_base=boundary+1
 primary={p:i+1 for i,p in enumerate(low)}
 primary.update({0xe4000000:boundary,0xeffd0000:unassigned_base+0x110000,0xefff0000:unassigned_base+0x110001})
 def ranked(values):return {v:i+1 for i,v in enumerate(sorted(values-{0}))}
 all_weights=[w for ws in [*singles.values(),*(w for rows in contractions.values() for _,w in rows),*(w for rows in prefixes.values() for _,w in rows)] for w in ws]
 secondary=ranked({s for _,_,s,_ in all_weights}|{0x0500});tertiary=ranked({t for _,_,_,t in all_weights}|{0x0500});secondary[0]=tertiary[0]=0
 pairs=sorted({(secondary[s],tertiary[t]) for _,_,s,t in all_weights}|{(secondary[0x0500],tertiary[0x0500])})
 pair_index={pair:i for i,pair in enumerate(pairs)};common=pair_index[(secondary[0x0500],tertiary[0x0500])]
 assert len(pairs)<2048 and unassigned_base+0x110002<1<<21
 def packed(weight):
  kind,p,s,t=weight;rank=0 if not p and kind=='explicit' else (han_base+p if kind=='han' else primary[p])
  return rank<<11|pair_index[(secondary[s],tertiary[t])]
 def implicit(c):return (unassigned_base+c)<<11|common
 def ce_list(weights):assert len(weights)<256;return bytes([len(weights)])+b''.join(struct.pack('<I',packed(w)) for w in weights)
 u24=lambda v:struct.pack('<I',v)[:3]
 jamo=set(range(0x1100,0x1200))
 assert not any(0xac00<=c<0xd7a4 for c in singles) and not jamo&(set(contractions)|set(prefixes))
 assert not set(contractions)&set(prefixes)
 records=[];runs=0
 codes=sorted(set(singles)|set(contractions)|set(prefixes))
 i=0
 while i<len(codes):
  c=codes[i]
  if c in contractions:
   rows=sorted(contractions[c]);fallback=singles.get(c)
   trailing=any(fcd.get(r[-1],0)>0xff for r,_ in rows)
   body=bytes([2])+u24(c)+bytes([trailing|(fallback is None)<<1])
   body+=ce_list(fallback) if fallback is not None else bytes([1])+struct.pack('<I',implicit(c))
   body+=bytes([len(rows)])+b''.join(bytes([len(r)])+b''.join(u24(x) for x in r)+ce_list(w) for r,w in rows)
   records.append(body);i+=1;continue
  if c in prefixes:
   rows=sorted(prefixes[c]);records.append(bytes([3])+u24(c)+ce_list(singles[c])+bytes([len(rows)])+b''.join(u24(p)+ce_list(w) for p,w in rows));i+=1;continue
  weights=singles[c]
  if len(weights)!=1:records.append(bytes([1])+u24(c)+ce_list(weights));i+=1;continue
  first=packed(weights[0]);j=i
  # Runs: consecutive scalars with one weight each, equal lower weights and
  # consecutive (or all zero) primaries.
  while j+1<len(codes) and codes[j+1]==codes[j]+1 and codes[j+1] in singles and codes[j+1] not in contractions and codes[j+1] not in prefixes and len(singles[codes[j+1]])==1:
   nxt=packed(singles[codes[j+1]][0]);step=j+1-i
   if (nxt&2047)!=(first&2047) or (nxt>>11)!=((first>>11)+step if first>>11 else 0):break
   j+=1
  records.append(bytes([0])+u24(c)+u24(codes[j])+struct.pack('<I',first));runs+=1;i=j+1
 han_spans=[]
 for c in sorted(han_rank):
  if han_spans and han_spans[-1][1]==c-1 and han_spans[-1][2]+c-han_spans[-1][0]==han_rank[c]:han_spans[-1][1]=c
  else:han_spans.append([c,c,han_rank[c]])
 def spans(values):
  out=[]
  for c in sorted(values):
   if out and out[-1][1]==c-1 and out[-1][2]==values[c]:out[-1][1]=c
   else:out.append([c,c,values[c]])
  return out
 ccc_spans=spans(ccc);fcd_spans=spans(fcd)
 leads={}
 for c,value in fcd.items():
  if c>0xffff:
   lead=0xd7c0+(c>>10);leads[lead]=leads.get(lead,0)|(1 if value>>8 else 0)|2
 data=b'ICUCOL01'+struct.pack('<10I',0,han_base,unassigned_base,common,len(pairs),len(records),len(han_spans),len(ccc_spans),len(fcd_spans),len(decomposition))
 data+=b''.join(struct.pack('<HH',s,t) for s,t in pairs)+b''.join(records)
 data+=b''.join(u24(a)+u24(b)+u24(r) for a,b,r in han_spans)
 data+=b''.join(u24(a)+u24(b)+bytes([v]) for a,b,v in ccc_spans)
 data+=b''.join(u24(a)+u24(b)+struct.pack('<H',v) for a,b,v in fcd_spans)
 data+=b''.join(u24(c)+bytes([len(d)])+b''.join(u24(x) for x in d) for c,d in sorted(decomposition.items()))
 data+=struct.pack('<H',len(leads))+b''.join(struct.pack('<HB',lead,flags) for lead,flags in sorted(leads.items()))
 data=data[:8]+struct.pack('<I',len(data))+data[12:]
 target=ROOT/'packages/runtime/data/icu78-collation.bin'
 if check:assert target.read_bytes()==data,'regenerate ICU collation data'
 else:target.write_bytes(data)
 manifest={'icu':'78.3','unicode':'17.0','cldr':'48','source':URL,'source_sha256':SHA,'ucd':ucd.URL,'ucd_sha256':ucd.SHA,
  'mappings':len(records),'weight_runs':runs,'contraction_starters':len(contractions),'contractions':sum(len(r) for r in contractions.values()),
  'han':len(han),'han_spans':len(han_spans),'weight_pairs':len(pairs),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'license':'icu78-cjk.LICENSE',
  'format':'ICUCOL01; bytes,hanBase,unassignedBase,commonPair,pairs,mappings,hanSpans,cccSpans,fcdSpans,decompositions:u32le; pairs(secondary,tertiary:u16le); '
   'mapping kind:u8 code:u24le then 0:last:u24,weight:u32 | 1:weights | 2:flags:u8,weights,count:u8,(length:u8,codes:u24*,weights)* | 3:weights,count:u8,(prefix:u24,weights)*; '
   'weights=count:u8,(primaryRank<<11|pair:u32le)*; han(first,last,rank:u24); ccc(first,last:u24,ccc:u8); fcd(first,last:u24,lccc<<8|tccc:u16); '
   'decomposition(code:u24,count:u8,codes:u24*); leads count:u16,(lead:u16,hasLccc|hasTccc<<1:u8)*'}
 text=json.dumps(manifest,indent=2)+'\n';target=ROOT/'packages/runtime/data/icu78-collation.manifest.json'
 if check:assert target.read_text()==text,'regenerate ICU collation manifest'
 else:target.write_text(text)
 print(f'{len(records)} mappings ({runs} runs), {len(han_spans)} Han spans, {len(pairs)} weight pairs; {len(data)} bytes')
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');generate(p.parse_args().check)

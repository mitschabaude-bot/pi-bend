"""Generate Unicode 17 regex property data from the official, pinned UCD archive."""
from collections import defaultdict
from pathlib import Path
from urllib.request import urlopen
import base64, hashlib, json, zipfile

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://www.unicode.org/Public/17.0.0/ucd/UCD.zip'
SHA = '2066d1909b2ea93916ce092da1c0ee4808ea3ef8407c94b4f14f5b7eb263d28e'

def normalized(value):
    return ''.join(c.lower() for c in value if c not in '_- \t\r\n')

def source():
    path = ROOT / 'build/UCD-17.zip'
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(urlopen(URL, timeout=60).read())
    assert hashlib.sha256(path.read_bytes()).hexdigest() == SHA
    return zipfile.ZipFile(path)

def records(archive, name):
    for line in archive.read(name).decode().splitlines():
        line = line.split('#')[0].strip()
        if line:
            yield [field.strip() for field in line.split(';')]

def points(span):
    values = span.split('..')
    return range(int(values[0],16), int(values[-1],16)+1)

def ranges(values):
    out=[]
    for p in sorted(values):
        if out and p == out[-1][1]+1: out[-1][1]=p
        else: out.append([p,p])
    return out

def varint(value):
    out=[]
    while value >= 128:
        out.append((value&127)|128);value >>= 7
    return out+[value]

def encoded(values):
    out=[];previous=0
    for lo,hi in ranges(values):
        out += varint(lo-previous)+varint(hi-lo)
        previous=hi+1
    return base64.b64encode(bytes(out)).decode()

def hash_name(name):
    h=2166136261
    for c in name: h=((h ^ ord(c))*16777619)&0xffffffff
    return h

def table(rows):
    if not rows: return 'Table.Empty{}'
    mid=len(rows)//2;key,value=rows[mid]
    return f'Table.Branch{{{key},{value},{table(rows[:mid])},{table(rows[mid+1:])}}}'

def generate():
    archive=source()
    aliases={}
    for row in records(archive,'PropertyAliases.txt'):
        for alias in row: aliases[normalized(alias)]=row[1]
    values={}
    canonical_values={}
    for row in records(archive,'PropertyValueAliases.txt'):
        prop=aliases.get(normalized(row[0]),row[0])
        canonical=row[2]
        canonical_values[(prop,row[1])]=canonical
        for alias in row[1:]: values[(prop,normalized(alias))]=canonical
    sets=defaultdict(set)
    for row in records(archive,'UnicodeData.txt'):
        p=int(row[0],16);category=row[2]
        if row[9]=='Y': sets[('Binary','Bidi_Mirrored')].add(p)
        if row[1].endswith(', First>'): start=p;continue
        if row[1].endswith(', Last>'): selected=range(start,p+1)
        else: selected=[p]
        sets[('General_Category',canonical_values[('General_Category',category)])].update(selected)
    all_points=set(range(0x110000))
    assigned=set().union(*sets.values())
    sets[('General_Category','Unassigned')]=all_points-assigned
    for short in 'LMNPSZC':
        # LC is the separate cased-letter union, added below.
        prefix=short
        sets[('General_Category',canonical_values[('General_Category',short)])]=set().union(*(v for (p,n),v in list(sets.items()) if p=='General_Category' and any(k.startswith(prefix) and len(k)==2 and canonical_values.get((p,k))==n for k in ['Lu','Ll','Lt','Lm','Lo','Mn','Mc','Me','Nd','Nl','No','Pc','Pd','Ps','Pe','Pi','Pf','Po','Sm','Sc','Sk','So','Zs','Zl','Zp','Cc','Cf','Cs','Co','Cn'])))
    sets[('General_Category','Cased_Letter')]=set().union(*(sets[('General_Category',n)] for n in ['Uppercase_Letter','Lowercase_Letter','Titlecase_Letter']))
    for name,prop in [('Scripts.txt','Script'),('DerivedAge.txt','Age'),('auxiliary/GraphemeBreakProperty.txt','Grapheme_Cluster_Break'),('auxiliary/WordBreakProperty.txt','Word_Break'),('auxiliary/SentenceBreakProperty.txt','Sentence_Break')]:
        for span,value,*_ in records(archive,name):
            canonical=values.get((prop,normalized(value)),value)
            sets[(prop,canonical)].update(points(span))
    for prop,default in [('Script','Unknown'),('Grapheme_Cluster_Break','Other'),('Word_Break','Other'),('Sentence_Break','Other')]:
        covered=set().union(*(v for (p,_),v in sets.items() if p==prop))
        sets[(prop,default)].update(all_points-covered)
    for (prop,name),v in list(sets.items()):
        if prop=='Script': sets[('Script_Extensions',name)]=v.copy()
    for span,scripts,*_ in records(archive,'ScriptExtensions.txt'):
        selected=set(points(span))
        for (prop,_),v in sets.items():
            if prop=='Script_Extensions': v.difference_update(selected)
        for script in scripts.split(): sets[('Script_Extensions',values[('Script',normalized(script))])].update(selected)
    for filename in ['PropList.txt','DerivedCoreProperties.txt','emoji/emoji-data.txt']:
        for span,prop,*rest in records(archive,filename):
            if rest: continue # Enumerated InCB is not a regex boolean property.
            sets[('Binary',aliases.get(normalized(prop),prop))].update(points(span))
    sets[('Binary','Any')]=all_points
    sets[('Binary','ASCII')]=set(range(128))
    sets[('Binary','Assigned')]=assigned
    sets[('Binary','Word')]=set().union(sets[('Binary','Alphabetic')],sets[('Binary','Join_Control')],sets[('General_Category','Mark')],sets[('General_Category','Decimal_Number')],sets[('General_Category','Connector_Punctuation')])
    # regex's Age query is cumulative (introduced at or before this version).
    accumulated=set()
    for key in sorted((k for k in sets if k[0]=='Age'),key=lambda k:tuple(map(int,k[1].replace('V','').replace('_','.').split('.')))):
        accumulated |= sets[key];sets[key]=accumulated.copy()
    names={}
    def install(name,key):
        name=normalized(name)
        if key in sets: names[name]=key
    for key in sets:
        prop,value=key
        if prop in ['General_Category','Script','Binary']: install(value,key)
        if prop!='Binary': install(prop+'='+value,key)
    for (prop,alias),canonical in values.items():
        key=(prop,canonical)
        if prop in ['General_Category','Script']: install(alias,key)
        for alias_prop,target in aliases.items():
            if target==prop: install(alias_prop+'='+alias,key)
        if prop=='Script':
            for alias_prop,target in aliases.items():
                if target=='Script_Extensions': install(alias_prop+'='+alias,('Script_Extensions',canonical))
    for alias,prop in aliases.items():
        if normalized(alias) not in names: install(alias,('Binary',prop))
    for special in ['Any','ASCII','Assigned','Word']: install(special,('Binary',special))
    keys=sorted(set(names.values())); ids={key:i for i,key in enumerate(keys)}
    hashed={}
    for name,key in sorted(names.items()):
        h=hash_name(name);assert h not in hashed,(name,hashed.get(h))
        hashed[h]=f'Alias{{{json.dumps(name)},{ids[key]}}}'
    rows=sorted(hashed.items())
    out=['# Generated from official Unicode 17 by scripts/generate-regex-unicode.py.', '# Unicode License V3; see unicode-LICENSE.txt.', 'import Base','import ./u32-table.bend as Table','','type Alias is Data:','  Alias{name: String,index: U32}','','def aliases() -> Table.Table<Alias>:',f'  Table.Table{{{len(rows).bit_length()}n,{table(rows)}}}','','def ranges(index: U32) -> String:','  match index:']
    for i,key in enumerate(keys): out.append(f'    case {i}: "{encoded(sets[key])}"')
    out.append('    case _: ""\n')
    target=ROOT/'packages/runtime/src/unicode-17-regex.bend';target.write_text('\n'.join(out))
    print(len(keys),'properties',len(names),'aliases',target.stat().st_size,'bytes')
    (ROOT/'build/regex-unicode-reference.json').write_text(json.dumps({name:ranges(sets[key]) for name,key in names.items()}))

if __name__=='__main__':generate()

"""Pin ICU78 Southeast Asian words and Unicode sets; pack native radix data."""
import argparse, hashlib, importlib.util, json, struct
from pathlib import Path
from urllib.request import urlopen
ROOT=Path(__file__).resolve().parents[1]
SOURCES={
 'khmer':('Khmer','Khmr','87bee2d17cd5148aa36957eb05409eefc124de8ad519b81b789298ef3e60b5d9',b'ICUKHM01'),
 'lao':('Lao','Laoo','3c876934a3fa81031d2333525eafaca6a7c9f842e3b98f18c38880420afb5d36',b'ICULAO01'),
 'thai':('Thai','Thai','3166abde40c0f44ab91c28f5ce96d7d1472cb7882e1c0bda0a72f8f69dba4274',b'ICUTHA01'),
 'burmese':('Myanmar','Mymr','61d8abc3d9102b2f9bf0c9f44db0d7ab89b18172d8cd26832e4c83174bd8673b',b'ICUMYM01'),
}

def language(name,check=False):
    script,short,SHA,magic=SOURCES[name]
    URL='https://raw.githubusercontent.com/unicode-org/icu/release-78.3/icu4c/source/data/brkitr/dictionaries/'+name+'dict.txt'
    path=ROOT/('build/icu78-source/'+name+'dict.txt')
    if not path.exists():path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(urlopen(URL).read())
    data=path.read_bytes();assert hashlib.sha256(data).hexdigest()==SHA
    words=set();root={}
    for line in data.decode('utf-8-sig').splitlines():
        word=line.split('#')[0].strip()
        if not word:continue
        assert all(ord(c)<65536 and not 0xd800<=ord(c)<0xe000 for c in word),repr(word)
        words.add(word);node=root
        for char in word:node=node.setdefault(char,{})
        node['']=0
    max_candidates=max(sum(word[:i] in words for i in range(1,len(word)+1)) for word in words)
    assert max_candidates<=20  # ICU's PossibleWord candidate capacity.
    output=bytearray();nodes=0
    def pack(node):
        nonlocal nodes
        edges=[]
        for char,child in sorted(node.items()):
            if not char:continue
            label=char
            while '' not in child and len(child)==1 and len(label)<20:
                char,child=next(iter(child.items()));label+=char
            edges.append((label,child))
        for _,child in edges:pack(child)
        output.extend(struct.pack('<BH',node.get('',255),len(edges)))
        for label,_ in reversed(edges):output.append(len(label));output.extend(label.encode('utf-16-le'))
        nodes+=1
    pack(root)
    binary=magic+struct.pack('<II',nodes,len(words))+output
    stack=[];offset=16
    for _ in range(nodes):
        cost,count=struct.unpack_from('<BH',binary,offset);offset+=3;children=[]
        for _ in range(count):
            length=binary[offset];offset+=1;label=binary[offset:offset+length*2].decode('utf-16-le');offset+=length*2
            children.append((label,stack.pop()))
        stack.append((cost,children))
    assert offset==len(binary) and len(stack)==1
    restored=set()
    def collect(node,prefix):
        cost,children=node
        if cost==0:restored.add(prefix)
        else:assert cost==255
        for label,child in children:collect(child,prefix+label)
    collect(stack[0],'');assert restored==words
    spec=importlib.util.spec_from_file_location('ucd',ROOT/'scripts/generate-regex-unicode.py');ucd=importlib.util.module_from_spec(spec);spec.loader.exec_module(ucd)
    archive=ucd.source();script_chars=set();sa=set();marks=set()
    for span,propertyName,*_ in ucd.records(archive,'Scripts.txt'):
        if propertyName==script:script_chars.update(ucd.points(span))
    for span,propertyName,*_ in ucd.records(archive,'LineBreak.txt'):
        if propertyName=='SA':sa.update(ucd.points(span))
    for row in ucd.records(archive,'UnicodeData.txt'):
        if row[2].startswith('M'):marks.add(int(row[0],16))
    def predicate(name,points):
        checks=['(U32.is_ge(code,%d) && U32.is_le(code,%d))'%(lo,hi) for lo,hi in ucd.ranges(points)]
        return 'def '+name+'(char: Char) -> Bool:\n  match char:\n    case Chr{+code}: '+' || '.join(checks)+'\n'
    native='def decode'+script+'(bytes: List<&2,U32>) -> Dictionary.Parsed(Dictionary.Trie):\n  match bytes:\n    case '+' <> '.join(map(str,binary[:16]))+' <> rest:\n      Dictionary.records('+str(nodes)+'n,Done{Dictionary.Building{rest,Nil{}}})\n    case _: Fail{Dictionary.InvalidDictionary{}}\n'
    handles=script_chars&sa
    begin={'Khmer':set(range(0x1780,0x17b4)),'Lao':set(range(0xe81,0xeaf))|set(range(0xedc,0xede))|set(range(0xec0,0xec5)),'Thai':set(range(0xe01,0xe2f))|set(range(0xe40,0xe45)),'Myanmar':set(range(0x1000,0x102b))}[script]
    end=handles-{'Khmer':{0x17d2},'Lao':set(range(0xec0,0xec5)),'Thai':{0xe31}|set(range(0xe40,0xe45)),'Myanmar':set()}[script]
    for fn,points in [('handles',handles),('mark',(handles&marks)|{32}),('beginWord',begin),('endWord',end)]:native+=predicate(fn+script,points)
    license=(ROOT/'packages/runtime/data/icu78-cjk.LICENSE').read_bytes().split(b'\nComplete cjdict.txt source notices:')[0]
    license+=('\nComplete '+name+'dict.txt source notices:\n'+'\n'.join(line for line in data.decode('utf-8-sig').splitlines() if '#' in line)+'\n').encode()
    manifest={'source':URL,'source_sha256':SHA,'icu':'78.3','unicode':'17.0','entries':len(words),'nodes':nodes,'bytes':len(binary),'sha256':hashlib.sha256(binary).hexdigest(),'max_word_length':max(map(len,words)),'max_prefix_candidates':max_candidates,'format':magic.decode()+': magic8,nodeCount:u32le,wordCount:u32le; CJK radix record format with cost0 terminal,255 nonterminal; edge labels capped20','license':'icu78-'+name+'.LICENSE','unicode_sha256':ucd.SHA}
    files={'packages/runtime/data/icu78-'+name+'.bin':binary,'packages/runtime/data/icu78-'+name+'.manifest.json':(json.dumps(manifest,indent=2)+'\n').encode(),'packages/runtime/data/icu78-'+name+'.LICENSE':license}
    for filename,content in files.items():
        target=ROOT/filename
        if check:assert target.read_bytes()==content,filename
        else:target.write_bytes(content)
    print(f'{len(words)} {script} words, {nodes} radix nodes, {len(binary)} bytes; exact serialized roundtrip passes')
    return native,max(map(len,words))

def generate(check=False):
    native='import Base\nimport ./cjk-dictionary.bend as Dictionary\n\n# Generated by scripts/generate-sea-dictionaries.py; ICU78/Unicode17.\ntype Language is Data: Khmer{} Lao{} Thai{} Myanmar{}\n'
    lengths=[]
    for name in SOURCES:
        code,length=language(name,check);native+=code;lengths.append(length)
    native+='def maxWordLength(language: Language) -> Nat:\n  match language:\n'
    for (script,*_),length in zip(SOURCES.values(),lengths):native+='    case '+script+'{}: '+str(length)+'n\n'
    for fn in ['handles','mark','beginWord','endWord']:
        native+='def '+fn+'(language: Language,char: Char) -> Bool:\n  match language:\n'
        for script,*_ in SOURCES.values():native+='    case '+script+'{}: '+fn+script+'(char)\n'
    target=ROOT/'packages/runtime/src/sea-word-data.bend'
    if check:assert target.read_text()==native
    else:target.write_text(native)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');generate(p.parse_args().check)

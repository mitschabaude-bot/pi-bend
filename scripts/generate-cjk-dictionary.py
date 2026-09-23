"""Pack the pinned ICU78.3 CJK dictionary as a postorder radix trie."""
import argparse, hashlib, json, struct
from pathlib import Path
from urllib.request import urlopen
ROOT=Path(__file__).resolve().parents[1]
URL='https://raw.githubusercontent.com/unicode-org/icu/release-78.3/icu4c/source/data/brkitr/dictionaries/cjdict.txt'
SHA='e73fd72048981d0cc13e9dc436a7eaba07ffb6eff58c8a59dc75c1df746663a0'
LICENSE_SHA='e55522d81edc687a341a4411e0776e54ca654e90147f354a90458aaced4116af'

def source():
    path=ROOT/'build/icu78-source/cjdict.txt'
    if not path.exists():path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(urlopen(URL).read())
    data=path.read_bytes();assert hashlib.sha256(data).hexdigest()==SHA
    return data

def generate(check=False):
    data=source();root={};words={}
    for line in data.decode('utf-8-sig').splitlines():
        line=line.split('#')[0].strip()
        if not line:continue
        word,cost=line.split();cost=int(cost)
        assert word not in words and 0<=cost<255 and len(word)<=20 and all(ord(c)<65536 for c in word)
        words[word]=cost;node=root
        for char in word:node=node.setdefault(char,{})
        node['']=cost
    output=bytearray();nodes=0
    def pack(node):
        nonlocal nodes
        edges=[]
        for char,child in sorted(node.items()):
            if not char:continue
            label=char
            while '' not in child and len(child)==1:
                char,child=next(iter(child.items()));label+=char
            edges.append((label,child))
        for label,child in edges:pack(child)
        output.extend(struct.pack('<BH',node.get('',255),len(edges)))
        for label,child in reversed(edges):
            output.append(len(label));output.extend(label.encode('utf-16-le'))
        nodes+=1
    pack(root)
    binary=b'ICUCJK01'+struct.pack('<II',nodes,len(words))+output
    # Independently reconstruct every word/cost from the serialized representation.
    stack=[];offset=16
    for _ in range(nodes):
        cost,count=struct.unpack_from('<BH',binary,offset);offset+=3;children=[]
        for _ in range(count):
            length=binary[offset];offset+=1;label=binary[offset:offset+length*2].decode('utf-16-le');offset+=length*2
            children.append((label,stack.pop()))
        stack.append((cost,children))
    assert offset==len(binary) and len(stack)==1
    restored={}
    def collect(node,prefix):
        cost,children=node
        if cost!=255:restored[prefix]=cost
        for label,child in children:collect(child,prefix+label)
    collect(stack[0],'');assert restored==words
    target=ROOT/'packages/runtime/data/icu78-cjk.bin'
    if check:assert target.read_bytes()==binary,'regenerate CJK dictionary'
    else:target.write_bytes(binary)
    manifest={'source':URL,'source_sha256':SHA,'icu':'78.3','format':'ICUCJK01: magic8, nodeCount:u32le, wordCount:u32le; postorder node(cost:u8 or255, children:u16le, reversed edges(labelLength:u8, label:utf16le))','entries':len(words),'nodes':nodes,'bytes':len(binary),'sha256':hashlib.sha256(binary).hexdigest(),'license':'icu78-cjk.LICENSE'}
    text=json.dumps(manifest,indent=2)+'\n';target=ROOT/'packages/runtime/data/icu78-cjk.manifest.json'
    if check:assert target.read_text()==text
    else:target.write_text(text)
    license_path=ROOT/'build/icu78-source/LICENSE'
    if not license_path.exists():license_path.write_bytes(urlopen('https://raw.githubusercontent.com/unicode-org/icu/release-78.3/LICENSE').read())
    license=license_path.read_bytes();assert hashlib.sha256(license).hexdigest()==LICENSE_SHA
    notices=[]
    for line in data.decode('utf-8-sig').splitlines():
        if line.split('#')[0].strip():break
        notices.append(line)
    license += ('\nComplete cjdict.txt source notices:\n'+'\n'.join(notices)+'\n').encode()
    target=ROOT/'packages/runtime/data/icu78-cjk.LICENSE'
    if check:assert target.read_bytes()==license
    else:target.write_bytes(license)
    print(f'{len(words)} exact weighted entries, {nodes} nodes, {len(binary)} bytes; serialized roundtrip passes')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');generate(p.parse_args().check)

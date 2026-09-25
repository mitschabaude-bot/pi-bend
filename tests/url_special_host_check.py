"""Composed special-host parsing with explicitly selected strict Unicode flags.

Known Node/Unicode policy differences remain review cases, not parity passes.
"""
import ipaddress
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import re
import subprocess
import sys
from urllib.parse import quote

ROOT=Path(__file__).resolve().parents[1]
if '--js-only' in sys.argv and '--native-only' in sys.argv:
    raise SystemExit('Choose at most one backend restriction')
texts=['','example.com','EXAMPLE.COM','bücher.example','BÜCHER.example','faß.de','FAẞ.DE',
       'e\u0301.example','é.example','中文.example','مثال.example','א.example',
       'foo_bar','foo+bar','foo-bar','-foo','foo-','ab--cd','.', '..','a..b','example.com.',
       'xn--bcher-kva','XN--BCHER-KVA','xn--','xn--abc-','xn--8i7caa','\u00ad','\ufeff','\ufeffexample.com',
       '%EF%BB%BFexample.com','%EF%BB%BF%EF%BB%BFexample.com','%65xample.com','a%2eb',
       '%31%32%37','%2E','%252e','%gg','%','%2','%F0%9F','%C0%80','%ED%A0%80','%F4%90%80%80',
       '①.②.③.④','１２７.０.０.１','０x７f.１','127','127.1','0177.01','0x7f.1','0x',
       '1.2.3.999','1.2.3.4.','example.123','example.1a','[::1]','[2001:db8::1]',
       '[::ffff:192.0.2.1]','[::ffff:192.00.2.1]','[::1]:80','[::1','%5B::1%5D',
       '[::1%25lo]','a/b','a?b','a#b','a@b','a:b','a\\b','a\tb','a\nb','a\rb']
texts += [f'a%{code:02X}b' for code in range(256)]
texts += ['a'+chr(code)+'b' for code in range(256)]
for value in ['bücher.example','中文.example','é.example','faß.de','①.②.③.④','[::1]','\ufeffa']:
    texts += [quote(value,safe=''), ''.join(f'%{b:02X}' for b in value.encode())]
rng=random.Random(20260927)
labels=['example','bücher','é','e\u0301','中文','faß','xn--bcher-kva','a_b','foo+bar','-a','a-','a..b','a%2eb','１２７','']
for _ in range(600):
    texts.append('.'.join(rng.choices(labels,k=rng.randrange(1,5))))
for _ in range(300):
    address=rng.randrange(2**32)
    texts += [str(address),hex(address),'0'+format(address,'o')]
for _ in range(100):
    texts.append('['+ipaddress.IPv6Address(rng.randrange(2**128)).exploded+']')
texts += ['a'*size+'.example' for size in [63,64,255,1024,8192]]
texts += ['a.'*size+'example' for size in [128,1024]]
# Raw authority delimiters and constructor-removed controls cannot be passed to
# Node's host helper as equivalent raw host tokens. Their host rejection is
# checked directly against the forbidden-host rule instead.
forbidden=set('\0\t\n\r #/:<>?@[\\]^|')
def boundary(text):
    if text.startswith('['):return not re.fullmatch(r'\[[0-9A-Fa-f:.]+\]',text)
    return any(c in forbidden for c in text)
indices=[i for i,text in enumerate(texts) if not boundary(text)]
script=r'''
const {domainToASCII}=require('url');
const texts=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(texts.map(text=>domainToASCII(text))));
'''
actual=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps([texts[i] for i in indices]),text=True))
def codes(text):return ','.join(map(str,map(ord,text)))
def wire(host):
    if not host:return 'invalid'
    kind='ipv6' if host.startswith('[') else 'ipv4' if re.fullmatch(r'[0-9]+(?:\.[0-9]+){3}',host) else 'domain'
    return kind+';'+codes(host)
expected=['invalid']*len(texts)
for index,host in zip(indices,actual,strict=True):expected[index]=wire(host)
# These assertions exercise explicit strict options only. No default URL
# compatibility decision has been made, and these are not Node parity cases.
review=json.loads((ROOT/'docs/idna-context-review.json').read_text())
assert len(review['cases'])==9
for row in review['cases']:
    assert row['standardAccepted'] is False and row['matches'] is False
    texts.append(row['input']);expected.append('invalid')
print(f'{len(indices)} Node host comparisons; {len(texts)-len(indices)-9} raw-boundary checks; 9 pending strict-policy review cases',flush=True)
if '--prepare-only' in sys.argv:raise SystemExit(0)
if '--no-build' not in sys.argv and '--js-only' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/url-special-host.bend','build/url-special-host'],cwd=ROOT,check=True)
if '--native-only' not in sys.argv:
    subprocess.run([str(Path(BEND)),'packages/runtime/test/url-special-host.bend','-o','build/url-special-host.js'],cwd=ROOT,check=True)
arguments=list(map(codes,texts))
backends=[('native 1',['build/url-special-host','--threads','1']),('native 4',['build/url-special-host','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-special-host.js'])]
if '--js-only' in sys.argv:backends=backends[2:]
if '--native-only' in sys.argv:backends=backends[:2]
for label,command in backends:
    for start in range(0,len(arguments),32):
        result=subprocess.run([*command,*arguments[start:start+32]],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+32],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got,want)
    print(f'{label}: {len(texts)} composed special-host cases PASS (9 explicit strict-policy cases are not Node parity)',flush=True)

"""Compare native POSIX path-input policy with the actual pinned Pi source."""
from upstream_pin import UPSTREAM
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = UPSTREAM / 'packages/coding-agent/src/utils/paths.ts'
PREFIX = ROOT / 'build/coding-paths'
cases = []
texts = ['', '.', '..', '../..', '/x//y/../z/', '@x', '@@x', '@~/x', '~', '~/x',
         '~//x/../', '~other/x', 'x\u202fy', '\ufeff\u00a0 x \u3000', 'a\u2003b',
         'a\u1680b', 'a\u2028b', 'é漢😀', 'file:///tmp/a%20b',
         'file://localhost/tmp/%E6%BC%A2', 'file:///a/../b?ignored#also-ignored',
         'file:///a%2Fb', 'file:///a%2fb', 'file:///a%252Fb', 'file:///a%5Cb',
         'file:///a%00b', 'file:///bad%', 'file:///bad%ff', 'file:///bad%ED%A0%80',
         'file://remote/path', 'file://[::1]/path', 'file:///C:/path',
         'file://localhost:80/a', 'file:///a\\b', 'FILE:///tmp/x', 'file:/tmp/x']
for mode in ['n', 'r']:
    for value in texts:
        for trim, tilde, strip, spaces in [(False, True, False, False),
                                          (False, True, True, True),
                                          (True, False, True, True)]:
            cases.append([mode, str(ROOT), str(Path.home()), value, '/workspace/base',
                          trim, tilde, None, strip, spaces])
for home in ['', '.', 'relative/home', '../home', '/custom/home/', '/']:
    for text in ['~', '~/x', '~/../x', '~//x/', '~/']:
        for mode in ['n', 'r']:
            cases.append([mode, str(ROOT), str(Path.home()), text, '.', False, True, home, False, False])
for base in ['.', '../base', '~/base', 'file:///base/dir', 'file://remote/base']:
    for text in ['child', '../child', '/absolute']:
        cases.append(['r', str(ROOT), str(Path.home()), text, base, False, True, None, False, False])
oracle = r'''
import { registerHooks } from 'node:module';
// The imported source also references an unused Windows process helper.
// Fail if it is called; path policy and every Node builtin remain unchanged.
registerHooks({resolve(name,context,next) {
  if (name==='cross-spawn') return {shortCircuit:true,url:'data:text/javascript,export default function(){throw new Error("unexpected Windows process helper");}'};
  return next(name,context);
}});
const P = await import(process.argv[1]);
let data=''; for await(const chunk of process.stdin) data+=chunk;
const vectors = JSON.parse(data);
console.log(JSON.stringify(vectors.map(([mode,cwd,home,input,base,trim,expandTilde,homeDir,stripAtPrefix,normalizeUnicodeSpaces]) => {
  const options={trim,expandTilde,homeDir:homeDir??undefined,stripAtPrefix,normalizeUnicodeSpaces};
  try {
    const result=mode==='n'?P.normalizePath(input,options):P.resolvePath(input,base,options);
    return '+'+[...result].map(c=>c.codePointAt(0)).join(',');
  } catch { return '!'; }
})));
'''
expected = json.loads(subprocess.check_output(['node','--input-type=module','--eval',oracle,str(UPSTREAM)],
                     input=json.dumps(cases),text=True,cwd=ROOT))

def text(s): return ','.join(str(ord(c)) for c in s)
def encode(c):
    mode,cwd,home,value,base,trim,tilde,override,strip,spaces=c
    return '|'.join([mode,text(cwd),text(home),text(value),text(base),str(int(trim)),
                     str(int(tilde)), '-' if override is None else text(override),
                     str(int(strip)),str(int(spaces))])

for backend, command in [('bun',['bun',str(PREFIX)+'.js']),
                         ('native-1',[str(PREFIX),'--threads','1']),
                         ('native-4',[str(PREFIX),'--threads','4'])]:
    if len(sys.argv)>1 and backend not in sys.argv[1:]: continue
    result=subprocess.run(command+[encode(c) for c in cases],capture_output=True,text=True,timeout=90)
    assert result.returncode==0 and not result.stderr, (backend,result.stderr)
    actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(backend,len(actual),len(expected))
    for case,want,got in zip(cases,expected,actual):
        assert got==want,(backend,case,want,got)
    print(f'{backend}: {len(cases)} pinned Pi path-input comparisons PASS',flush=True)

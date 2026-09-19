"""WPT absolute inputs, comparing the pinned pi Node behavior and WPT separately.

Relative/base-dependent rows remain pending rather than counted as passes.
This runner uses already built URL fixtures; build selection is explicit.
"""
import json
from pathlib import Path
import subprocess
import sys
import wpt_url_data as data

ROOT=Path(__file__).resolve().parents[1]
if '--js-only' in sys.argv and '--native-only' in sys.argv:
    raise SystemExit('Choose at most one backend restriction')
all_rows=data.rows()
rows=[(index,row) for index,row in all_rows if row.get('base') is None]
texts=[data.scalar_value(row['input']) for _,row in rows]
script=r'''
const a=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify({versions:process.versions,values:a.map(x=>{try{return new URL(x).href}catch{return null}})}));
'''
node=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps(texts),text=True))
def codes(text):return ','.join(map(str,map(ord,text)))
expected=['invalid' if value is None else '+'+codes(value) for value in node['values']]
differences=[{'index':i,'input':row['input'],'wpt':row.get('href'),'node':value} for (i,row),value in zip(rows,node['values'],strict=True) if value!=row.get('href')]
report={'source':data.URL,'sha256':data.SHA256,'nodeVersions':node['versions'],
        'absoluteInputs':len(rows),'baseDependentInputsNotChecked':len(all_rows)-len(rows),
        'scalarBoundaryConversions':sum(text!=row['input'] for text,(_,row) in zip(texts,rows,strict=True)),
        'wptNodeDifferences':differences,'note':'Bend must match pinned Node outcomes on these inputs; differing WPT expectations are not claimed as standard conformance.'}
(ROOT/'build/url-absolute-wpt-report.json').write_text(json.dumps(report,ensure_ascii=True,indent=2)+'\n')
print(f'{len(rows)} absolute WPT inputs; {len(differences)} WPT/Node differences; {len(all_rows)-len(rows)} base-dependent inputs pending',flush=True)
arguments=list(map(codes,texts))
backends=[('native 1',['build/url-absolute','--threads','1']),('native 4',['build/url-absolute','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/url-absolute.js'])]
if '--js-only' in sys.argv:backends=backends[2:]
if '--native-only' in sys.argv:backends=backends[:2]
for label,command in backends:
    for start in range(0,len(arguments),16):
        result=subprocess.run([*command,*arguments[start:start+16]],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+16],strict=True)):
            assert got==want,(label,rows[start+offset][0],texts[start+offset],got,want)
    print(f'{label}: {len(rows)} WPT absolute inputs match Node PASS',flush=True)

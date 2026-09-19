"""Pending Node/Unicode behavior review, not a passing parity assertion.

These labels violate RFC 5892 ContextJ or RFC 5893 Bidi requirements. The normal
property/context checker separately verifies the native standard-rule result.
Exit nonzero while Node accepts any; never count this review as passed parity.
"""
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
CASES=[
    ('ب\u200c\u200cب','Consecutive ZWNJs do not provide joining context for each other.'),
    ('ب\u200c\u200dب','The later ZWJ has no immediate virama predecessor.'),
    ('ب-\u200cب','The intervening hyphen is not Joining_Type Transparent.'),
    ('क्\u200da\u200cb','The later ZWNJ has no valid joining context.'),
    ('क्\u200dאב','A label in a Bidi domain mixes L with R.'),
]
ORACLE="""
const {domainToASCII}=require('url');
const inputs=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify({versions:process.versions,values:inputs.map(value=>({ascii:domainToASCII(value),url:(()=>{try{return new URL('http://'+value).hostname}catch{return null}})()}))}));
"""
actual=json.loads(subprocess.check_output(['node','-e',ORACLE],input=json.dumps([text for text,_ in CASES]),text=True))
rows=[{'input':text,'reason':reason,'standardAccepted':False,'node':value,'matches':value['ascii']=='' and value['url'] is None} for (text,reason),value in zip(CASES,actual['values'],strict=True)]
report={'versions':actual['versions'],'cases':rows,'status':'pending user behavior decision; not parity'}
path=ROOT/'build/idna-context-review.json'
path.write_text(json.dumps(report,ensure_ascii=True,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=True,indent=2))
raise SystemExit(0 if all(row['matches'] for row in rows) else 1)

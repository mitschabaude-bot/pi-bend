"""Normalized URL to HTTP endpoint projection and local Fetch wire targets.

Node supplies normalized records; URL parsing has its own differential suites.
No external HTTP requests are made. TLS/DNS/blocked-port policy are not tested.
"""
import argparse
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
if not args.no_build:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', 'build/http-url-native-build.json', '--', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/http-url.bend', 'build/http-url'], cwd=ROOT, check=True)
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', 'build/http-url-js-build.json', '--', str(Path(BEND)), 'packages/runtime/test/http-url.bend', '-o', 'build/http-url.js'], cwd=ROOT, check=True)
rng = random.Random(20260919)
hosts = ['example.com', 'EXAMPLE.com', 'bücher.example', '127.1', '0x7f.1', '[::1]', '[2001:0db8::1]', 'localhost.']
paths = ['/', '/a', '//x', '/a/../b', '/é/%2f', '/x%20y']
queries = ['', '?', '?a=1', '?é=2']
urls = [f'{scheme}://{host}:{port}{path}{query}{rng.choice(["", "#", "#hash"])}'
        for scheme in ['http', 'https'] for host in hosts for port in [0, 80, 443, 8080, 65535]
        for path in paths for query in queries]
urls += ['http://u@h/', 'http://:p@h/', 'https://u:p@h/', 'http://@h/',
         'ftp://h/a', 'file:///C:/a', 'data:text,a', 'ws://h/a', 'wss://h/', 'custom://host/a']
urls += ['http://h/' + 'x' * 8192 + query + '#ignored' for query in queries]
script = r'''
const fs=require('node:fs'), http=require('node:http');
const inputs=JSON.parse(fs.readFileSync(0,'utf8'));
function record(value) {
  const u=new URL(value), noHash=u.href.split('#')[0], qi=noHash.indexOf('?');
  const query=qi<0?null:noHash.slice(qi+1), hi=u.href.indexOf('#');
  const fields=[u.protocol.slice(0,-1),u.username,u.password,u.hostname,u.port,u.pathname,query,hi<0?null:u.href.slice(hi+1)];
  let error;
  if(!['http:','https:'].includes(u.protocol))error='scheme';
  else {try{new Request(u)}catch{error='credentials'}}
  const target=u.pathname+(query===null?'':'?'+query);
  const result=error??[u.protocol==='https:'?'tls':'plain',u.hostname,+(u.port||(u.protocol==='https:'?443:80)),u.host,target];
  return {fields,result};
}
(async()=>{
  const seen=[];
  const server=http.createServer((req,res)=>{seen.push({target:req.url,host:req.headers.host});res.end('ok')});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try{
    const origin=`http://127.0.0.1:${server.address().port}`;
    const wireInputs=['/','/?','/?#f','/a?b#f','//a','/a%2fb','/é?a=🙂','/a/../b?'];
    for(const path of wireInputs)await(await fetch(origin+path)).text();
    const wire=wireInputs.map((path,i)=>({url:origin+path,observed:seen[i],record:record(origin+path)}));
    for(const row of wire){if(row.observed.target!==row.record.result[4]||row.observed.host!==row.record.result[3])throw Error('wire oracle mismatch')}
    console.log(JSON.stringify({versions:process.versions,records:inputs.map(record),wire}));
  }finally{await new Promise(resolve=>server.close(resolve))}
})().catch(e=>{console.error(e);process.exitCode=1});
'''
oracle = json.loads(subprocess.check_output(['node', '-e', script], input=json.dumps(urls), text=True, timeout=30))
records = oracle['records'] + [row['record'] for row in oracle['wire']]
def codes(value):
    return ','.join(map(str, map(ord, value)))
def optional(value):
    return '-' if value is None else '+' + codes(value)
def arguments(row):
    scheme, user, password, host, port, path, query, fragment = row['fields']
    return [scheme, codes(user), codes(password), codes(host), port, codes(path), optional(query), optional(fragment)]
def expected(row):
    value = row['result']
    return value if isinstance(value, str) else '|'.join([value[0], codes(value[1]), str(value[2]), codes(value[3]), codes(value[4])])
for label, command in [('native 1', ['build/http-url', '--threads', '1']), ('native 4', ['build/http-url', '--threads', '4']), ('Bun', [str(Path.home()/'.bun/bin/bun'), 'build/http-url.js'])]:
    for start in range(0, len(records), 16):
        batch = records[start:start+16]
        result = subprocess.run([*command, *[field for row in batch for field in arguments(row)]], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, (label, start, result.stderr)
        assert result.stdout.splitlines() == [expected(row) for row in batch], (label, start, result.stdout)
    print(f'{label}: {len(records)} endpoint projections PASS', flush=True)
report = {'scope': __doc__, 'nodeVersions': oracle['versions'], 'cases': len(records), 'localFetchWireCases': oracle['wire'], 'backends': ['native 1','native 4','Bun']}
(ROOT/'build/http-url-result.json').write_text(json.dumps(report, indent=2)+'\n')

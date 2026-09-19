"""Compose normalized URLs, Host defaults, buffered bodies and HTTP heads.

Compare fields this layer owns with five local Node Fetch requests. Additional
Fetch transport defaults and real Bend socket exchange are separate coverage.
"""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
if not args.no_build:
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '12', '--stats', 'build/http-url-request-native-build.json', '--', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/http-url-request.bend', 'build/http-url-request'], cwd=ROOT, check=True)
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', 'build/http-url-request-js-build.json', '--', str(Path.home()/'.bend/bin/bend'), 'packages/runtime/test/http-url-request.bend', '-o', 'build/http-url-request.js'], cwd=ROOT, check=True)
script = r'''
const http=require('node:http');
(async()=>{
 const rows=[];
 const server=http.createServer(async(req,res)=>{const chunks=[];for await(const x of req)chunks.push(x);rows.push({method:req.method,target:req.url,headers:req.headers,body:[...Buffer.concat(chunks)]});res.end('ok')});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const port=server.address().port;
 try{
   const url=`http://127.0.0.1:${port}/a?#ignored`;
   for(const options of [{method:'get'}, {method:'POST',body:'hé🙂'}, {method:'PUT',body:new Uint8Array([0,255])}, {method:'GET',headers:{Host:'elsewhere.example:9'}}, {method:'POST',body:''}])await(await fetch(url,options)).text();
   console.log(JSON.stringify({versions:process.versions,port,rows}));
 }finally{await new Promise(resolve=>server.close(resolve))}
})().catch(e=>{console.error(e);process.exitCode=1});
'''
oracle = json.loads(subprocess.check_output(['node', '-e', script], text=True, timeout=30))
def raw(value):
    return bytes(map(int, value.split(','))) if value else b''
for label, command in [('native 1',['build/http-url-request','--threads','1']), ('native 4',['build/http-url-request','--threads','4']), ('Bun',[str(Path.home()/'.bun/bin/bun'),'build/http-url-request.js'])]:
    result = subprocess.run([*command,str(oracle['port'])],cwd=ROOT,capture_output=True,text=True,timeout=60)
    assert result.returncode == 0, (label,result.stderr)
    for index,(line,row) in enumerate(zip(result.stdout.splitlines(),oracle['rows'],strict=True)):
        host,port,method,target,head,body = line.split('|')
        assert (host,int(port)) == ('127.0.0.1',oracle['port']), (label,index,'Host override changed connection endpoint')
        assert method == row['method'] and raw(target).decode() == row['target'], (label,index,'target')
        wire = raw(head)
        assert wire.endswith(b'\r\n\r\n'), (label,index,'head terminator')
        first,*fields = wire[:-4].decode('latin1').split('\r\n')
        assert first == f'{method} {row["target"]} HTTP/1.1', (label,index,first)
        headers = dict(field.split(': ',1) for field in fields)
        assert set(headers) <= {'host','content-type','content-length'}, (label,index,headers)
        for name in ['host','content-type','content-length']:
            assert headers.get(name) == row['headers'].get(name), (label,index,name,headers,row['headers'])
        assert list(raw(body)) == row['body'], (label,index,'body')
    print(f'{label}: five URL/request compositions match local Fetch PASS',flush=True)
report = {'scope':__doc__, 'nodeVersions':oracle['versions'], 'oracle':oracle['rows'], 'backends':['native 1','native 4','Bun']}
(ROOT/'build/http-url-request-result.json').write_text(json.dumps(report,indent=2)+'\n')

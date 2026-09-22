"""Local HTTPS model -> real write -> real edit -> final model response."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from native_agent_check import response, completion
from fetch_https_check import trusted_context, ROOT

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backend',choices=['bun','native-1','native-4'])
p.add_argument('--prefix',default='build/native-edit-agent')
args=p.parse_args()
TARGET='nested/feature.bend'
CONTENT='import Base\n\ndef twice(value: U32) -> U32:\n  (value * 2 : U32)\n'
UPDATED=CONTENT.replace('twice','triple').replace('* 2','* 3')
PROMPT='Create the feature, edit it as requested, then report the result.'

def request(stream):
    wire=bytearray()
    while b'\r\n\r\n' not in wire:
        data=stream.recv(16384)
        assert data,'closed before request headers'
        wire.extend(data)
    head,body=bytes(wire).split(b'\r\n\r\n',1)
    lines=head.decode('ascii').split('\r\n')
    assert lines[0]=='POST /v1/responses HTTP/1.1'
    headers=dict(line.lower().split(': ',1) for line in lines[1:])
    assert headers['authorization']=='bearer fixture-key'
    size=int(headers['content-length'])
    while len(body)<size:
        data=stream.recv(16384)
        assert data,'closed before request body'
        body+=data
    assert len(body)==size
    value=json.loads(body)
    assert value['model']=='fixture-model' and value['stream'] is True and value['store'] is False
    tools=value['tools']
    assert [t['name'] for t in tools]==['write','edit']
    assert tools[0]['parameters']['required']==['path','content']
    assert tools[1]['parameters']['required']==['path','edits']
    assert tools[1]['parameters']['properties']['edits']['items']['required']==['oldText','newText']
    return value

def call(stream,name,parameters,identifier):
    encoded=json.dumps(parameters,ensure_ascii=False,separators=(',',':'))
    item={'type':'function_call','id':'fc-'+identifier,'call_id':'call-'+identifier,'name':name,'arguments':''}
    response(stream,[
        {'type':'response.created','response':{'id':'resp-'+identifier}},
        {'type':'response.output_item.added','output_index':0,'item':item},
        {'type':'response.function_call_arguments.delta','output_index':0,'delta':encoded},
        {'type':'response.function_call_arguments.done','output_index':0,'arguments':encoded},
        {'type':'response.output_item.done','output_index':0,'item':{**item,'arguments':encoded}},
        completion('resp-'+identifier)])

def final(stream):
    item={'type':'message','id':'msg-final','role':'assistant','content':[]}
    response(stream,[
        {'type':'response.created','response':{'id':'resp-final'}},
        {'type':'response.output_item.added','output_index':0,'item':item},
        {'type':'response.output_text.delta','output_index':0,'delta':'done'},
        {'type':'response.output_item.done','output_index':0,'item':{**item,'content':[{'type':'output_text','text':'done'}]}},
        completion('resp-final')])

def serve(listener,context,directory,scenario):
    first={'path':TARGET,'content':CONTENT}
    tool='write' if scenario=='schema rejection' else 'edit'
    second={'path':TARGET,'edits':[{'oldText':'twice','newText':'triple'},{'oldText':'* 2','newText':'* 3'}]}
    if scenario=='schema rejection': second={'path':TARGET}
    if scenario=='malformed edit': second={'path':TARGET,'edits':[{'oldText':'twice','newText':False}]}
    expected_disk=UPDATED if scenario=='success' else CONTENT
    for turn in range(3):
        raw,_=listener.accept()
        raw.settimeout(180)
        with context.wrap_socket(raw,server_side=True) as stream:
            value=request(stream)
            assert any(item.get('role')=='user' and item['content'][0]['text']==PROMPT for item in value['input'])
            calls=[item for item in value['input'] if item.get('type')=='function_call']
            results=[item for item in value['input'] if item.get('type')=='function_call_output']
            assert len(calls)==len(results)==turn,(scenario,turn,value['input'])
            if turn:
                assert calls[0]['call_id']==results[0]['call_id']=='call-write'
                assert calls[0]['name']=='write' and json.loads(calls[0]['arguments'])==first
                assert results[0]['output']=='Successfully wrote to '+TARGET
                assert (directory/TARGET).read_text()==(CONTENT if turn==1 else expected_disk),(scenario,turn,(directory/TARGET).read_text(),expected_disk,results)
            if turn==0: call(stream,'write',first,'write')
            elif turn==1: call(stream,tool,second,'change')
            else:
                assert calls[1]['call_id']==results[1]['call_id']=='call-change'
                assert calls[1]['name']==tool and json.loads(calls[1]['arguments'])==second
                if scenario=='success': assert results[1]['output']==f'Successfully replaced 2 block(s) in {TARGET}.'
                elif scenario=='schema rejection': assert 'Validation failed' in results[1]['output']
                else: assert 'Edit tool input is invalid' in results[1]['output']
                final(stream)

def text(points): return ''.join(chr(int(p)) for p in points.split(',')) if points else ''

for scenario in ['success','schema rejection','malformed edit']:
    with tempfile.TemporaryDirectory(prefix='pi-native-edit-') as folder, ThreadPoolExecutor(max_workers=1) as executor:
        directory=Path(folder)
        context,root=trusted_context(directory,'localhost')
        trust=directory/'root.pem'
        trust.write_bytes(x509.load_der_x509_certificate(root).public_bytes(serialization.Encoding.PEM))
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0));listener.listen(3);listener.settimeout(180)
            server=executor.submit(serve,listener,context,directory,scenario)
            prefix=ROOT/args.prefix
            command=['bun',str(prefix)+'.js'] if args.backend=='bun' else [str(prefix),'--threads',args.backend[-1]]
            run=subprocess.run(command+[str(trust),'fixture-model',f'https://localhost:{listener.getsockname()[1]}/v1',PROMPT,str(directory)],cwd=ROOT,env={**os.environ,'OPENAI_API_KEY':'fixture-key'},capture_output=True,text=True,timeout=540)
            server.result(timeout=10)
            assert run.returncode==0,(run.stdout[-4000:],run.stderr[-2000:])
            lines=run.stdout.splitlines()
            assert f'executions write=1 edit={int(scenario=="success")}' in lines
            assert lines[-1]=='answer done'
            events=[line.removeprefix('event ') for line in lines if line.startswith('event ')]
            assert events[0]=='agent_start' and events[-1]=='agent_end'
            assert events.count('turn_start')==events.count('turn_end')==3
            starts=[i for i,e in enumerate(events) if e=='turn_start']
            for start,end in zip(starts,starts[1:]):
                segment=events[start:end]
                assert segment.count('tool_execution_start')==segment.count('tool_execution_end')==1
                assert segment.index('tool_execution_start')<segment.index('tool_execution_end')
            details=[line.split('|') for line in lines if line.startswith('edit-details|')]
            if scenario=='success':
                assert len(details)==1 and details[0][3]=='3'
                diff,patch=map(text,details[0][1:3])
                assert '-3 def twice' in diff and '+3 def triple' in diff and '* 3' in diff
                assert patch.startswith(f'--- {TARGET}\n+++ {TARGET}\n')
                assert '-def twice' in patch and '+def triple' in patch
            else: assert not details
        print(f'{args.backend}: model/write/edit/history/{scenario} PASS',flush=True)

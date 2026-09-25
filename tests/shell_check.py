"""Pinned shell policies plus real POSIX executable-path fixtures."""
from upstream_pin import UPSTREAM
import argparse
import json
import os
from pathlib import Path
import random
import shutil
import socket
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
UPSTREAM=UPSTREAM / 'packages/coding-agent/src'

def text(s):return ','.join(str(ord(c)) for c in s)
def entries(values):return ';'.join(text(k+'='+v) for k,v in values)
def config(path):return text(path)+'|'+text('-c')+'|none'
def main():
    p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');args=p.parse_args()
    bun=shutil.which('bun');runner=[bun,str(Path(args.runner).resolve())] if args.runner.endswith('.js') else [str(Path(args.runner).resolve()),'--threads',args.threads]
    rng=random.Random(127);cases=[]
    samples=[list(range(256)),[0xfff8,0xfff9,0xfffa,0xfffb,0xfffc,0x200b,0x200d,0x202e,0xfeff,0x1f600],[0xd7ff,0xe000,0x10ffff],[]]
    samples += [[rng.choice([rng.randrange(0x110000),rng.randrange(32),0xfff9,0x200d]) for _ in range(rng.randrange(200))] for _ in range(90)]
    samples=[[c for c in codes if not 0xd800<=c<=0xdfff] for codes in samples]
    for codes in samples:cases.append({'kind':'sanitize','codes':codes})
    for key in ['PATH','Path','pAtH']:
        for path in ['',':','/usr/bin','/chosen/bin','/usr/bin:/chosen/bin','/chosen/bin:/usr/bin:','/chosen/bin-extra','::/usr/bin::']:
            for extra in [[],[['PATH' if key!='PATH' else 'Path','other']]]:
                cases.append({'kind':'env','entries':[['PI_CODING_AGENT_DIR','/chosen'],['HOME','/home/example'],[key,path],['EMPTY',''],['VALUE','a=b'],*extra]})
    cases += [{'kind':'env','entries':[['PI_CODING_AGENT_DIR','/chosen']]},{'kind':'env','entries':[]}]
    with tempfile.TemporaryDirectory() as tmp:
        base=Path(tmp);(base/'program').write_text('#!/bin/sh\n');(base/'program').chmod(0o700);(base/'plain').write_text('not executable');(base/'directory').mkdir();(base/'link').symlink_to(base/'program');(base/'broken').symlink_to(base/'absent')
        for custom in [None,'',str(base/'program'),str(base/'plain'),str(base/'directory'),str(base/'link'),str(base/'broken'),str(base/'absent')]:cases.append({'kind':'config','custom':custom})
        data=base/'cases.json';data.write_text(json.dumps(cases))
        references=[json.loads(x) for x in subprocess.check_output([bun,str(ROOT/'tests/shell_reference.ts'),str(UPSTREAM),str(data)],text=True).splitlines()]
        commands=[];wanted=[]
        for item,ref in zip(cases,references):
            if item['kind']=='sanitize':
                commands.append('s:'+','.join(map(str,item['codes'])));wanted.append(','.join(map(str,ref)))
            elif item['kind']=='env':commands.append('e:'+text(ref['bin'])+':'+entries(item['entries']));wanted.append(entries(ref['entries']))
            else:
                commands.append('n:'+('-' if item['custom'] is None else text(item['custom'])))
                wanted.append('missing|'+text(item['custom']) if 'error' in ref else config(ref['shell']))
        output=[]
        for start in range(0,len(commands),32):output += subprocess.check_output([*runner,*commands[start:start+32]],text=True).splitlines()
        assert len(output)==len(wanted)
        for i,(actual,expect) in enumerate(zip(output,wanted)):assert actual==expect,(i,cases[i],actual,expect)
        # All candidate kinds are owned fixtures: directory/FIFO/socket are never
        # opened. Real which is an independent test oracle, not production code.
        dirs=[]
        for kind in ['missing','directory','plain','fifo','socket','broken','good','link']:
            # Keep fixture directories distinct from custom-shell fixtures.
            d=base/('path-'+kind);d.mkdir();target=d/'bash';dirs.append(str(d))
            if kind=='directory':target.mkdir()
            elif kind=='plain':target.write_text('no execute')
            elif kind=='fifo':os.mkfifo(target,0o700)
            elif kind=='socket':sock=socket.socket(socket.AF_UNIX);sock.bind(str(target));target.chmod(0o700)
            elif kind=='broken':target.symlink_to(base/'absent')
            elif kind=='good':target.write_text('#!/bin/sh\n');target.chmod(0o700)
            elif kind=='link':target.symlink_to(base/'program')
        path_cases=[':'.join(dirs[:n]) for n in range(1,len(dirs)+1)]+[':'.join(reversed(dirs)),str(base/'path-link'),'',':']
        (base/'bash').write_text('#!/bin/sh\n');(base/'bash').chmod(0o700)
        which=shutil.which('which');assert which
        for path in path_cases:
            oracle=subprocess.run([which,'bash'],text=True,capture_output=True,env=dict(os.environ,PATH=path),cwd=tmp)
            expected=oracle.stdout.strip().splitlines()[0] if oracle.returncode==0 else None
            if path=='':expected='./bash'  # POSIX empty component means cwd; which mishandles this sole case.
            cmd=['f:'+text('bash')+':'+text(path),'c:-:'+text(str(base/'absent'))+':'+text(path)]
            actual=subprocess.check_output([*runner,*cmd],text=True,cwd=tmp).splitlines()
            assert actual==[text(expected) if expected else 'none',config(expected or 'sh')],(path,actual,expected)
        invalid=['BAD','=value','A=one;A=two','A=bad\0value']
        bad=['r:'+(';'.join(text(x) for x in value.split(';'))) for value in invalid]
        assert subprocess.check_output([*runner,*bad],text=True).splitlines()==['invalid','invalid','duplicate','invalid']
        # Ambient env loading is checked by comparing named values, not order.
        env={'PATH':'/usr/bin','VALUE':'a=b','EMPTY':''}
        loaded=subprocess.check_output([*runner,'l:'+text('/bin-extra')],text=True,env=env).strip()
        decoded=dict(''.join(chr(int(c)) for c in item.split(',')).split('=',1) for item in loaded.split(';'))
        assert decoded['PATH']=='/bin-extra:/usr/bin' and decoded['VALUE']=='a=b' and decoded['EMPTY']==''
        if 'sock' in locals():sock.close()
    print(f'{len(cases)} pinned policy checks; {len(path_cases)*2} executable/fallback checks; 4 malformed environments; native environment load passed')
if __name__=='__main__':main()

"""Independent OS/Python civil-time oracle, actual child PID, and syscall failures."""
import datetime as dt
import errno
import os
from pathlib import Path
import subprocess
import time
from zoneinfo import ZoneInfo

ROOT=Path(__file__).resolve().parents[1]
FAULTS=ROOT/'build/process-clock-faults.so'
ZONES=['UTC','Pacific/Kiritimati','America/New_York','Asia/Kathmandu']
INSTANTS=['1969-12-31T23:59:59','2000-02-29T12:34:56','2024-03-10T06:59:59','2024-03-10T07:00:00','2024-11-03T05:59:59','2024-11-03T06:00:00','2026-12-31T23:59:59']
EPOCHS=[int(dt.datetime.fromisoformat(x).replace(tzinfo=dt.timezone.utc).timestamp()) for x in INSTANTS]

def fields(epoch,zone):
    value=dt.datetime.fromtimestamp(epoch,ZoneInfo(zone))
    return ':'.join(str(x) for x in (value.year,value.month,value.day,value.hour,value.minute,value.second))

def run(command,zone,epoch=None,fault=None):
    env={**os.environ,'TZ':zone}
    if command[0]=='bun':command=[command[0],'--preload','./tests/process_clock_preload.js',*command[1:]]
    else:env['LD_PRELOAD']=str(FAULTS)
    if epoch is not None:env['BEND_CLOCK_EPOCH']=str(epoch)
    if fault:env['BEND_CLOCK_FAULT']=fault
    before=int(time.time())
    process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    text,error=process.communicate(timeout=10)
    after=int(time.time())
    assert process.returncode==0 and not error,(command,error)
    rows=[]
    for line in text.splitlines():
        pid,*parts=line.split('|');assert int(pid)==process.pid,(pid,process.pid)
        if parts[0].startswith('error:'):assert len(parts)==1
        else:assert len(parts)==2 and parts[0]==parts[1],parts
        rows.append(parts[0])
    assert len(rows)==4,rows
    return rows,before,after

for name,command in [('bun',['bun','build/process-clock.js']),('native1',['build/process-clock','--threads','1']),('native4',['build/process-clock','--threads','4']),('split1',['build/process-clock-split','--threads','1']),('split4',['build/process-clock-split','--threads','4'])]:
    count=0
    for zone in ZONES:
        for epoch in EPOCHS:
            rows,_,_=run(command,zone,epoch)
            assert rows==[fields(epoch,zone)]*4,(name,zone,epoch,rows)
            count+=1
        rows,before,after=run(command,zone)
        possible={fields(value,zone) for value in range(before,after+1)}
        assert all(value in possible for value in rows),(name,zone,rows,possible)
        count+=1
    rows,_,_=run(command,'UTC',-62198755200)
    assert rows==[f'error:{errno.EOVERFLOW}']*4,(name,rows)
    count+=1
    if name!='bun':
        for fault,code in [('clock',errno.EIO),('clock-once',errno.EIO),('local',errno.EOVERFLOW),('local-once',errno.EOVERFLOW),('local-no-errno',errno.EOVERFLOW)]:
            rows,_,_=run(command,'UTC',EPOCHS[1],fault)
            expected=[f'error:{code}']*4 if not fault.endswith('-once') else [f'error:{code}']+[fields(EPOCHS[1],'UTC')]*3
            assert rows==expected,(name,fault,rows,expected)
            count+=1
    print(name,count,'PID/local-time cases passed',flush=True)

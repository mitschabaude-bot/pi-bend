"""Exercise one owned HTTP attempt inside pi's native retry loop.

Build the fixture to build/openai-responses-attempt.{c,js} before running.
Python asserts effect traces and audits resources; it supplies no runtime behavior.
"""
from contextlib import nullcontext
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
candidate = Path(sys.argv[1]).resolve()
bun = Path.home()/'.bun/bin/bun'
fixture = root/'packages/ai/test/openai-responses-attempt.bend'
def sleep(ms):
    high, low = struct.unpack('>II', struct.pack('>d', ms))
    return f'sleep {high}:{low}\n'
fetch = 'fetch:0\n'
diagnostic = 'read\nread\nclose\n'
success = 'success\nclose\nreleased\n'
retry = sleep(1) + 'fetch:1\n' + success + 'count:2\n'
connection = fetch + 'random\n' + sleep(500) + 'fetch:1\n' + success + 'count:2\n'
expected = {
  0: fetch + diagnostic + retry,
  1: fetch + diagnostic + 'provider:http:400 busy:400 busy\ncount:1\n',
  2: fetch + diagnostic + 'provider:http:429 busy:429 busy\ncount:1\n',
  3: fetch + diagnostic + retry,
  4: connection,
  5: fetch + 'other:fetch\ncount:1\n',
  6: connection,
  7: fetch + 'read\nclose\n' + retry,
  8: fetch + diagnostic + retry,
  9: fetch + 'read\nclose\nprovider:diagnostic-read:Could not read the error response diagnostic.\ncount:1\n',
  10: fetch + 'read\nclose\nprovider:diagnostic-read:Could not read the error response diagnostic.\ncount:1\n',
  11: fetch + diagnostic + 'delay-rejected\ncount:1\n',
  12: 'aborted\ncount:0\n',
  13: fetch + success + 'count:1\n',
}
results=[]
directory=root/'build/openai-responses-attempt-audit'
directory.mkdir(exist_ok=True)
with nullcontext(directory):
    folder=Path(directory)
    for suffix in ('c','js'):
        (folder/('run.'+suffix)).write_bytes((root/'build'/('openai-responses-attempt.'+suffix)).read_bytes())
    subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'run.c'),'-lpthread','-lm','-o',str(folder/'production')],check=True)
    for backend, command in [('native-1',[str(folder/'production'),'--threads','1']),('native-4',[str(folder/'production'),'--threads','4']),('bun',[str(bun),str(folder/'run.js')])]:
        for mode, output in expected.items():
            result=subprocess.run([*command,str(mode)],capture_output=True,text=True,timeout=15)
            assert result.returncode==0 and result.stdout==output and not result.stderr,(backend,mode,result)
            results.append(dict(backend=backend,mode=mode,instrumented=False))
    c=folder/'audit.c'
    c.write_bytes((folder/'run.c').read_bytes())
    original = (candidate / 'effs/timer.c').read_text()
    assert original in c.read_text()
    instrumented = 'static unsigned long long audit_created, audit_closed, audit_live, audit_peak, audit_parked;\n' + original
    instrumented = instrumented.replace('  row->gen += 1;', '  audit_created++; audit_live++; if (audit_live > audit_peak) audit_peak = audit_live;\n  row->gen += 1;')
    instrumented = instrumented.replace('  row->state = 2;', '  audit_parked += row->waiter != NULL;\n  row->state = 2;')
    instrumented = instrumented.replace('  row->live = 0;', '  audit_closed++; audit_live--;\n  row->live = 0;')
    audit = r'''
static void __attribute__((destructor)) sleep_audit(void) {
  u32 live=0,waiting=0,channels=0;
  for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
  for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
  fprintf(stderr,"DEADLINE_AUDIT %llu %llu %u %llu %llu %u %u\n",audit_created,audit_closed,live,audit_peak,audit_parked,waiting,channels);
}
'''
    c.write_text(c.read_text().replace(original, instrumented) + audit)
    js = folder / 'audit.js'
    js.write_bytes((folder/'run.js').read_bytes())
    original_js = (candidate / 'effs/timer.js').read_text()
    assert original_js in js.read_text()
    instrumented_js = 'const timerAudit={created:0,closed:0,live:0,peak:0,parked:0,waiting:0};\n' + original_js
    instrumented_js = instrumented_js.replace('  const row = { deadline:', '  timerAudit.created++; timerAudit.live++; timerAudit.peak=Math.max(timerAudit.peak,timerAudit.live);\n  const row = { deadline:')
    instrumented_js = instrumented_js.replace('    io.waits.splice(index, 1);', '    timerAudit.parked++;\n    io.waits.splice(index, 1);')
    instrumented_js = instrumented_js.replace('  row.state = 3;', '  timerAudit.closed++; timerAudit.live--;\n  row.state = 3;')
    instrumented_js = instrumented_js.replace('  row.waiter = wait;', '  timerAudit.waiting++;\n  row.waiter = wait;').replace('row.waiter = null;', 'timerAudit.waiting--; row.waiter = null;')
    instrumented_js += "\nprocess.on('exit',()=>console.error('DEADLINE_AUDIT',timerAudit.created,timerAudit.closed,timerAudit.live,timerAudit.peak,timerAudit.parked,timerAudit.waiting,-1));\n"
    js.write_text(js.read_text().replace(original_js, instrumented_js))
    subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(c),'-lpthread','-lm','-o',str(folder/'audit')],check=True)
    for backend, command in [('native-1',[str(folder/'audit'),'--threads','1']),('native-4',[str(folder/'audit'),'--threads','4']),('bun',[str(bun),str(folder/'audit.js')])]:
        for mode, output in expected.items():
            for repetition in range(3):
                start=time.monotonic()
                result=subprocess.run([*command,str(mode)],capture_output=True,text=True,timeout=15)
                assert result.returncode==0 and result.stdout==output,(backend,mode,result)
                fields=result.stderr.split()
                assert fields[0]=='DEADLINE_AUDIT' and len(fields)==8,result.stderr
                created,closed,live,peak,parked,waiting,channels=map(int,fields[1:])
                attempts=0 if mode==12 else (2 if mode in (0,3,4,6,7,8) else 1)
                assert created==closed==attempts,result.stderr
                assert live==waiting==0,result.stderr
                assert peak==(0 if attempts==0 else 1),result.stderr
                assert channels==(0 if backend.startswith('native') else -1),result.stderr
                results.append(dict(backend=backend,mode=mode,instrumented=True,repetition=repetition,seconds=time.monotonic()-start,created=created,closed=closed,live=live,peak=peak,waiting=waiting,channels=channels))
        print(backend,'PASS',flush=True)
# Hash the complete application source closure and the exact emitted programs.
pending=[fixture]; sources=set()
while pending:
    path=pending.pop().resolve()
    if path in sources: continue
    sources.add(path)
    pending.extend(path.parent/p for p in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
sources.update([Path(__file__).resolve(),candidate/'base.bend',candidate/'effs/timer.c',candidate/'effs/timer.js'])
record=dict(scope='14 cases on native one/four threads and Bun: 42 unmodified and 126 instrumented runs. Exact cleanup-before-retry traces, unread successful body, terminal/retryable HTTP policy, connection/configuration/timeout classification, failed or oversized diagnostic, pre-abort, delay cap. Native timer/waiter/channel and Bun timer audits. Mock transport, not live HTTP or TLS.',sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)},programs={suffix:hashlib.sha256((root/'build'/('openai-responses-attempt.'+suffix)).read_bytes()).hexdigest() for suffix in ('c','js')},samples=results)
(root/'build/openai-responses-attempt-result.json').write_text(json.dumps(record,indent=2)+'\n')

"""Run a build in its own process group with a sampled Linux RSS guard.

RSS is summed across the group's processes (shared pages may count twice).
This is a shared-host safeguard, not a hard memory limit or precise benchmark.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--limit-gib',type=float,default=40)
parser.add_argument('--stats',type=Path)
parser.add_argument('command',nargs=argparse.REMAINDER)
args=parser.parse_args()
command=args.command[1:] if args.command[:1]==['--'] else args.command
if args.limit_gib<=0 or not command:parser.error('positive memory limit and command required')
page_kib=os.sysconf('SC_PAGE_SIZE')//1024
limit=args.limit_gib*1024*1024
started=time.monotonic()
process=subprocess.Popen(command,start_new_session=True)
peak=0
stopped=False
while process.poll() is None:
    rss=0
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields=path.read_text().rsplit(')',1)[1].split()
            if int(fields[2])==process.pid:rss+=int(fields[21])*page_kib
        except (FileNotFoundError,ProcessLookupError,PermissionError,IndexError,ValueError):
            pass
    peak=max(peak,rss)
    if rss>limit:
        stopped=True
        try:os.killpg(process.pid,signal.SIGTERM)
        except ProcessLookupError:pass
        try:process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:os.killpg(process.pid,signal.SIGKILL)
            except ProcessLookupError:pass
        print(f'RSS guard stopped build at {rss} KiB (limit {args.limit_gib:g} GiB)',flush=True)
        break
    time.sleep(.5)
exit_code=process.wait()
stats={'command':command,'elapsed_seconds':time.monotonic()-started,'peak_sampled_group_rss_kib':peak,'limit_gib':args.limit_gib,'stopped':stopped,'child_exit_code':exit_code}
if args.stats:
    args.stats.parent.mkdir(parents=True,exist_ok=True)
    args.stats.write_text(json.dumps(stats,indent=2)+'\n')
raise SystemExit(137 if stopped else (exit_code if exit_code>=0 else 128-exit_code))

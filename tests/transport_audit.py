"""Instrument emitted fixtures for transport/timer ownership (test-only)."""
from pathlib import Path
from channel_audit import instrument

def replace_once(source, before, after):
    assert source.count(before) == 1, before
    return source.replace(before, after)

def transport_audit(prefix, candidate, js_only=False):
    if not js_only:
        c = Path(f'{prefix}.c').read_text()
        original = (candidate / 'effs/timer.c').read_text()
        changed = 'static unsigned probe_created,probe_live,probe_peak;\n' + original
        changed = replace_once(changed, '  row->gen += 1;', '  probe_created++; probe_live++; if(probe_live>probe_peak)probe_peak=probe_live;\n  row->gen += 1;')
        changed = replace_once(changed, '  row->live = 0;', '  probe_live--;\n  row->live = 0;')
        audit = r'''
        static void __attribute__((destructor)) attempt_audit(void) {
         unsigned timers=0,waiters=0,channels=0,connects=0,fds=0,sockets=0,udp=0;
         for(u32 i=0;i<udp_read_len;i++)udp+=udp_read_rows[i].live;
         for(u32 i=0;i<udp_write_len;i++)udp+=udp_write_rows[i].live;
         for(u32 i=0;i<timer_len;i++){timers+=timer_rows[i].live;waiters+=timer_rows[i].waiter!=NULL;}
         for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
         for(u32 i=0;i<connect_len;i++){connects+=connect_rows[i].live;fds+=connect_rows[i].fd>=0;waiters+=connect_rows[i].waiter!=NULL;}
         for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
         fprintf(stderr,"RESOURCES %u %u %u %u %u %u %u %u %u %u %u\n",probe_created,probe_peak,probe_live,timers,waiters,channels,connects,fds,sockets,io_park.head!=NULL,udp);
        }
        '''
        Path(f'{prefix}-audit.c').write_text(replace_once(c, original, changed) + audit)
    js = Path(f'{prefix}.js').read_text()
    original = (candidate / 'effs/timer.js').read_text()
    changed = original
    changed = replace_once(changed, 'function timer_new(ms) {', 'function timer_new(ms) { probeCreated++;probeLive++;probePeak=Math.max(probePeak,probeLive);')
    # Keep rows only in this audited fixture; production effects are unchanged.
    changed = replace_once(changed, '  row.state = 3;', '  probeLive--;\n  row.state = 3;')
    needle = '  return io_tup(row, row);'
    # Native effect and Bun have different wrappers; use the actual return form.
    if needle not in changed:
        needle = '  return io_done(io_tup(row, row));'
    changed = replace_once(changed, needle, '  probeTimers.push(row);\n' + needle)
    js = replace_once(js, original, changed)
    original = (candidate / 'effs/connect.js').read_text()
    changed = original
    changed = replace_once(changed, 'return io_done(io_tup(row, row));', 'probeConnects.push(row); return io_done(io_tup(row, row));')
    js = replace_once(js, original, changed)
    js = "const probeTimers=[],probeConnects=[];let probeCreated=0,probeLive=0,probePeak=0;\nprocess.on('exit',()=>console.error('RESOURCES',probeCreated,probePeak,probeLive,probeTimers.filter(x=>x.state!==3).length,probeTimers.filter(x=>x.waiter!==null).length+probeConnects.filter(x=>x.waiter!==null).length,probeConnects.filter(x=>x.state!==3).length,probeConnects.filter(x=>x.fd>=0).length));\n" + js
    for file,needle in [('udp_recv_bytes.js','  return io_tup(row, row);'),('udp_send_bytes.js','  return io_tup(row,row);')]:
        original = (candidate / 'effs' / file).read_text()
        changed = replace_once(original, needle, '  probeUDP.push(row);\n' + needle)
        js = replace_once(js, original, changed)
    js = "const probeUDP=[];process.on('exit',()=>console.error('UDP',probeUDP.filter(x=>x.state!==3).length,probeUDP.filter(x=>x.waiter!==null).length));\n" + js
    Path(f'{prefix}-audit.js').write_text(instrument(js))


if __name__ == '__main__':
    import argparse
    import subprocess
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix', type=Path)
    parser.add_argument('compiler', type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--compile', action='store_true')
    mode.add_argument('--js-only', action='store_true')
    args = parser.parse_args()
    transport_audit(args.prefix, args.compiler, args.js_only)
    if args.compile:
        for suffix in ['', '-audit']:
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{args.prefix}{suffix}.c', '-lpthread', '-lm', '-o', f'{args.prefix}{suffix}'], check=True)

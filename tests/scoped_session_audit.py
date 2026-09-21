"""Test-only generated-program audits for channel/IO, socket and timer retirement."""
from pathlib import Path
from channel_audit import instrument


def prepare(prefix, compiler, native):
    prefix = str(prefix)
    if native:
        source = Path(prefix + '.c').read_text()
        source += r'''
static void __attribute__((destructor)) scoped_session_audit(void) {
  unsigned channels=0,sockets=0,live=0,waiting=0;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
  for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
  fprintf(stderr,"AUDIT %u %u %u\nTIMERS %u %u\n",channels,io_park.head!=NULL,sockets,live,waiting);
}
'''
        Path(prefix + '-audit.c').write_text(source)
    source = instrument(Path(prefix + '.js').read_text())
    original = (compiler / 'effs/timer.js').read_text()
    needle = '  return io_tup(row, row);'
    assert source.count(original) == 1 and original.count(needle) == 1
    source = source.replace(original, original.replace(needle, '  scopedTimerRows.push(row);\n' + needle))
    source = "const scopedTimerRows=[];process.on('exit',()=>console.error('TIMERS',scopedTimerRows.filter(x=>x.state!==3).length,scopedTimerRows.filter(x=>x.waiter!==null).length));\n" + source
    Path(prefix + '-audit.js').write_text(source)

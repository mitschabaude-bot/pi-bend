#!/usr/bin/env python3
"""Owned Linux PTY tests; no writes or signals target a user's terminal."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import queue
import select
import signal
import struct
import subprocess
import termios
import threading
import time
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ESC = b'\x1b'

class Session:
    def __init__(self, threads, mode='hold', drain_output=True, env=None, output=None, inherited=()):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        self.saved = termios.tcgetattr(self.slave)
        self.flags = fcntl.fcntl(self.slave, fcntl.F_GETFL)
        self.output = bytearray()
        self.lines = []
        self.queue = queue.Queue()
        self.process = subprocess.Popen(['build/terminal', '--threads', str(threads), mode], cwd=ROOT, stdin=self.slave, stdout=self.slave if output is None else output, stderr=subprocess.PIPE, text=True, env=env, pass_fds=inherited)
        def stderr():
            for line in self.process.stderr:
                self.lines.append(line.rstrip('\n'))
                self.queue.put(line.rstrip('\n'))
        self.reader = threading.Thread(target=stderr)
        self.reader.start()
        self.keep_reading = True
        def output():
            while self.keep_reading:
                if select.select([self.master], [], [], .05)[0]:
                    try:
                        data = os.read(self.master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            return
                        raise
                    if not data:
                        return
                    self.output.extend(data)
        self.output_reader = threading.Thread(target=output) if drain_output else None
        if self.output_reader:
            self.output_reader.start()
        self.wait('ready')
        if mode in ('hold','progress','drain','cancel'):
            assert not termios.tcgetattr(self.slave)[3] & termios.ICANON
        assert fcntl.fcntl(self.slave, fcntl.F_GETFL) == self.flags

    def wait(self, prefix):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            line = self.queue.get(timeout=max(.01, end-time.monotonic()))
            if line.startswith(prefix):
                return line
        raise AssertionError((prefix, self.lines))

    def send(self, text):
        os.write(self.master, text.encode() if isinstance(text,str) else text)

    def finish(self, expected='ok'):
        try:
            assert self.process.wait(timeout=5) == 0, self.lines
            self.reader.join()
            time.sleep(.03)
            self.keep_reading = False
            if self.output_reader:
                self.output_reader.join()
            assert f'stopped:{expected}' in self.lines, self.lines
            last_stop=max(i for i,line in enumerate(self.lines) if line.startswith('stopped:'))
            assert not any(line.startswith(('input:','resize')) for line in self.lines[last_stop+1:]),self.lines
            assert termios.tcgetattr(self.slave) == self.saved, 'termios not restored'
            assert fcntl.fcntl(self.slave, fcntl.F_GETFL) == self.flags, 'flags changed'
            return bytes(self.output), self.lines
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            os.close(self.master)
            os.close(self.slave)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--threads',type=int,default=1)
    args=parser.parse_args()
    count=0
    for response,kitty,enable,disable in [('\x1b[?7u',True,0,0),('\x1b[?0u',False,1,1),('\x1b[?1;2c',False,1,1)]:
        s=Session(args.threads)
        s.send(response)
        out,lines=s.finish()
        assert out.startswith(ESC+b'[?2004h'+ESC+b'[>7u'+ESC+b'[?u'+ESC+b'[c'),out
        assert ('kitty:true' if kitty else 'kitty:false') in lines,lines
        assert not any(line.startswith('input:') for line in lines),lines
        assert out.count(ESC+b'[>4;2m') == enable,out
        assert out.count(ESC+b'[>4;0m') == disable,out
        assert out.count(ESC+b'[<u') == 1,out
        count+=1
    s=Session(args.threads)
    s.send('\x1b[?7');time.sleep(.07);s.send('u')
    out,lines=s.finish()
    assert 'kitty:true' in lines and not any(x.startswith('input:') for x in lines),lines
    count+=1
    s=Session(args.threads)
    s.send('\x1b[');time.sleep(.24)
    out,lines=s.finish()
    assert 'input:"\\u001b["' in lines,lines
    count+=1
    s=Session(args.threads)
    s.send('é'.encode()[:1]);time.sleep(.02);s.send('é'.encode()[1:])
    s.send('\x1b[200~hello\n世界\x1b[201~')
    out,lines=s.finish()
    inputs=[json.loads(x[6:]) for x in lines if x.startswith('input:')]
    assert inputs == ['é','\x1b[200~hello\n世界\x1b[201~'],inputs
    count+=1
    s=Session(args.threads)
    fcntl.ioctl(s.slave,termios.TIOCSWINSZ,struct.pack('HHHH',41,123,0,0))
    os.kill(s.process.pid,signal.SIGWINCH)
    s.wait('resize')
    out,lines=s.finish()
    assert 'size:123:41' in lines,lines
    count+=1
    s=Session(args.threads,'progress')
    out,lines=s.finish()
    assert out.count(ESC+b']9;4;3\x07') >= 2,out
    assert out.count(ESC+b']9;4;0\x07') == 1,out
    count+=1
    s=Session(args.threads,'controls')
    out,lines=s.finish()
    assert ESC+b'[?25l'+ESC+b'[?25h'+ESC+b'[2A'+ESC+b'[3B'+ESC+b'[K'+ESC+b'[J'+ESC+b'[2J'+ESC+b'[H'+ESC+b']0;test\x07' in out,out
    count+=1
    s=Session(args.threads,'drain')
    s.wait('draining')
    for _ in range(5):
        s.send('\x1b[97;1:3u');time.sleep(.035)
    drained=s.wait('drained:')
    assert 180 <= int(drained.split(':')[-1]) < 600,drained
    s.send('z')
    out,lines=s.finish()
    assert [json.loads(x[6:]) for x in lines if x.startswith('input:')] == ['z'],lines
    assert out.count(ESC+b'[<u') == 1,out
    count+=1
    s=Session(args.threads,'cancel',drain_output=False)
    out,lines=s.finish('error')
    assert 'cancelled:error' in lines,lines
    count+=1
    with tempfile.TemporaryDirectory() as directory:
        target=Path(directory)/'output.log'
        target.write_text('before:')
        env={**os.environ,'PI_TUI_WRITE_LOG':str(target)}
        s=Session(args.threads,'write',env=env)
        out,lines=s.finish()
        assert 'write:ok' in lines,lines
        assert target.read_text()=='before:logged Ω',target.read_text()
        assert b'logged ' in out and ESC+b'[?25l' in out,out
        count+=1
        env['PI_TUI_WRITE_LOG']=str(Path(directory)/'missing'/'out.log')
        s=Session(args.threads,'write',env=env)
        out,lines=s.finish()
        assert 'write:error' in lines and b'logged ' in out,lines
        count+=1
    s=Session(args.threads)
    s.send(bytes([255]))
    out,lines=s.finish('error')
    assert not any(line.startswith('input:') for line in lines),lines
    count+=1
    s=Session(args.threads,env={**os.environ,'LD_PRELOAD':str(ROOT/'build/terminal-faults.so'),'BEND_TERMINAL_PRIOR':'1'})
    os.kill(s.process.pid,signal.SIGWINCH)
    s.wait('prior')
    out,lines=s.finish()
    assert lines.count('prior')>=2,lines  # Chained while live, restored at exit.
    count+=1
    for mode in ['raw','pipe','signal','write-first']:
        master,slave=pty.openpty();saved=termios.tcgetattr(slave);flags=fcntl.fcntl(slave,fcntl.F_GETFL)
        env={**os.environ,'LD_PRELOAD':str(ROOT/'build/terminal-faults.so'),'BEND_TERMINAL_FAULT':mode}
        result=subprocess.run(['build/terminal','--threads',str(args.threads),'cycle'],stdin=slave,stdout=slave,stderr=subprocess.PIPE,cwd=ROOT,env=env,text=True,timeout=5)
        assert result.returncode==1 and 'start:error' in result.stderr,(mode,result)
        assert termios.tcgetattr(slave)==saved,(mode,'raw rollback')
        assert fcntl.fcntl(slave,fcntl.F_GETFL)==flags,(mode,'flag rollback')
        os.close(master);os.close(slave);count+=1
    for mode in ['close','write-stop','replaced']:
        env={**os.environ,'LD_PRELOAD':str(ROOT/'build/terminal-faults.so'),'BEND_TERMINAL_FAULT':mode,'BEND_TERMINAL_PRIOR':'1'}
        s=Session(args.threads,env=env)
        out,lines=s.finish('error')
        if mode=='replaced':assert 'replacement' in lines and 'prior' not in lines,lines
        count+=1
    env={**os.environ,'LD_PRELOAD':str(ROOT/'build/terminal-faults.so'),'BEND_TERMINAL_FAULT':'signal-restore','BEND_TERMINAL_PRIOR':'1'}
    s=Session(args.threads,'restore-retry',env=env)
    s.wait('stopped:error')
    time.sleep(.1)
    os.kill(s.process.pid,signal.SIGWINCH)
    out,lines=s.finish()
    assert lines.count('stopped:error')==1 and lines.count('stopped:ok')==1 and lines.count('prior')>=2,lines
    count+=1
    s=Session(args.threads,'cycles')
    s.wait('fds-start');before=len(os.listdir(f'/proc/{s.process.pid}/fd'))
    s.wait('fds-end');after=len(os.listdir(f'/proc/{s.process.pid}/fd'))
    out,lines=s.finish()
    assert before==after,(before,after)
    assert lines.count('stopped:ok')==101,lines
    count+=1
    s=Session(args.threads,'cycles')
    def resize_storm():
        while s.process.poll() is None:
            try: os.kill(s.process.pid,signal.SIGWINCH)
            except ProcessLookupError: return
            time.sleep(.001)
    sender=threading.Thread(target=resize_storm);sender.start()
    out,lines=s.finish();sender.join()
    assert lines.count('stopped:ok')==101,lines
    count+=1
    replacement_master,replacement_slave=pty.openpty()
    fcntl.ioctl(replacement_slave,termios.TIOCSWINSZ,struct.pack('HHHH',42,111,0,0))
    env={**os.environ,'LD_PRELOAD':str(ROOT/'build/terminal-faults.so'),'BEND_TERMINAL_FAULT':'reuse-output','BEND_TERMINAL_REPLACEMENT':str(replacement_slave)}
    try:
        s=Session(args.threads,env=env,inherited=(replacement_slave,))
        fcntl.ioctl(s.slave,termios.TIOCSWINSZ,struct.pack('HHHH',33,99,0,0))
        os.kill(s.process.pid,signal.SIGWINCH)
        s.wait('resize')
        out,lines=s.finish()
        assert 'size:99:33' in lines,lines
        assert ESC+b'[?2004l' in out,out
        assert not select.select([replacement_master],[],[],.01)[0],'owned terminal wrote to reused caller fd'
    finally:
        os.close(replacement_master);os.close(replacement_slave)
    count+=1
    s=Session(args.threads,'capability')
    out,lines=s.finish()
    assert lines.count('dimensions:bad-capability')==2,lines
    count+=1
    s=Session(args.threads,'collision')
    out,lines=s.finish()
    assert 'busy' in lines,lines
    count+=1
    with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as target:
        source.write('ignore:é'.encode());source.seek(7)
        target.write(b'prefix:');target.flush()
        before_in=fcntl.fcntl(source,fcntl.F_GETFL);before_out=fcntl.fcntl(target,fcntl.F_GETFL)
        result=subprocess.run(['build/terminal','--threads',str(args.threads),'hold'],cwd=ROOT,stdin=source,stdout=target,stderr=subprocess.PIPE,text=True,timeout=5,env={**os.environ,'COLUMNS':'93','LINES':'37'})
        assert result.returncode==0 and 'stopped:ok' in result.stderr,result
        assert 'input:"é"' in result.stderr and 'size:93:37' in result.stderr,result.stderr
        assert source.tell()==9 and target.tell()>7,(source.tell(),target.tell())
        target.seek(0);assert target.read().startswith(b'prefix:'+ESC+b'[?2004h')
        assert fcntl.fcntl(source,fcntl.F_GETFL)==before_in and fcntl.fcntl(target,fcntl.F_GETFL)==before_out
        count+=1
    for mode,expected in [('slow-output','ok'),('slow-cancel','error')]:
        with tempfile.TemporaryFile() as target:
            env={**os.environ,'LD_PRELOAD':str(ROOT/'build/terminal-faults.so'),'BEND_TERMINAL_FAULT':'slow-regular'}
            s=Session(args.threads,mode,env=env,output=target)
            s.wait('slow-enter')
            if mode=='slow-output':
                s.send('z')
                s.wait('input:')
            out,lines=s.finish(expected)
            if mode=='slow-output':assert lines.index('input:"z"')<lines.index('slow-exit'),lines
            else:assert 'slow-cancel:error' in lines,lines
            count+=1
    s=Session(args.threads,'progress-immediate')
    out,lines=s.finish()
    assert ESC+b']9;4;3\x07between'+ESC+b']9;4;0\x07' in out,out
    assert out.count(ESC+b']9;4;0\x07')==1,out
    count+=1
    print(f'native {args.threads}: {count} actual terminal PTY scenarios passed')

if __name__=='__main__':main()

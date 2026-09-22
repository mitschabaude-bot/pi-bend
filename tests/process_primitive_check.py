"""Native POSIX process lifecycle checks; no host implementation supplies behavior."""
import argparse
import errno
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--prefix', type=Path, default=ROOT / 'build/process-primitive')
parser.add_argument('--null-prefix', type=Path, default=ROOT / 'build/process-null-stdin')
args = parser.parse_args()


def decoded(lines, name):
    text = next(line[len(name)+1:] for line in lines if line.startswith(name + ':'))
    return bytes(int(word) for word in text.replace(';', ',').split(',') if word)


def checks(threads, folder):
    count = 0
    base = [str(args.prefix), '--threads', str(threads)]

    def run(command='', mode='normal', shell='/bin/sh', cwd=folder, code=0):
        nonlocal count
        result = subprocess.run(base + [mode, shell, str(cwd), command],
                                capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, (command, result.stdout, result.stderr)
        assert not result.stderr, result.stderr
        lines = result.stdout.splitlines()
        if code is not None:
            assert f'exit:{code}' in lines and f'again:exit:{code}' in lines, lines[:15]
            assert 'close:ok:ok:ok' in lines and 'stale:False:False:False:False' in lines, lines[:15]
            assert 'reuse:False:False:False:False' in lines and 'reuse-close:ok:ok:ok:ok' in lines, lines[:15]
        count += 1
        return lines

    lines = run('cat; printf "$TEST_VALUE" >&2; exit 7', code=7)
    assert decoded(lines, 'stdout') == b'A\0\xff\n'
    assert decoded(lines, 'stderr') == b'hello spaces'
    assert decoded(run('pwd'), 'stdout') == os.fsencode(folder) + b'\n'
    fds = decoded(run('for fd in /proc/$$/fd/*; do test -e "$fd" && printf "%s\\n" "$fd"; done; true'), 'stdout')
    assert [Path(fd.decode()).name for fd in fds.splitlines()] == ['0', '1', '2']
    assert decoded(run('printf "$PI_PROCESS_TEST_ENV"', 'inherit'), 'stdout') == b'inherited value'
    assert decoded(run('printf "%s" "spaces ; literal"'), 'stdout') == b'spaces ; literal'
    # Both pipes fill independently; waiting for the child must not prevent draining.
    lines = run('head -c 131072 /dev/zero & head -c 131072 /dev/zero >&2 & wait')
    assert decoded(lines, 'stdout') == bytes(131072)
    assert decoded(lines, 'stderr') == bytes(131072)
    lines = run('cat', 'large-input')
    size = int(next(line.removeprefix('write:count:') for line in lines if line.startswith('write:count:')))
    assert 0 < size <= 65536 and decoded(lines, 'stdout') == b'A' * size
    lines = run('sleep .05; cat', 'partial-write')
    size = int(next(line.removeprefix('write:count:') for line in lines if line.startswith('write:count:')))
    assert 0 < size < 65536 and decoded(lines, 'stdout') == b'A\0\xff\n' + b'A' * size
    for mode in ['invalid-byte', 'oversize-input']:
        lines = run('cat', mode)
        assert 'write:error:' + str(errno.EINVAL) in lines and decoded(lines, 'stdout') == b''
    lines = run('exec 0<&-; sleep .1', 'broken-input')
    assert f'write:error:{errno.EPIPE}' in lines  # Runtime itself survives SIGPIPE.
    for mode in ['cancel', 'cancel-write']:
        lines = run('sleep .1', mode)
        assert 'cancel:True:False' in lines
        assert ('stdout:' if mode == 'cancel' else 'write:') + f'error:{errno.ECANCELED}' in lines
    lines = run('sleep 10 & wait', 'kill', code=None)
    assert 'signal:9' in lines and 'again:signal:9' in lines and 'kill:True' in lines
    lines = run('kill -PIPE $$', code=None)
    assert 'signal:13' in lines  # Spawn resets inherited SIGPIPE-ignore disposition.
    for mode, error in [('nul-path', errno.EILSEQ), ('nul-cwd', errno.EILSEQ),
                        ('nul-argv', errno.EILSEQ), ('nul-env', errno.EILSEQ),
                        ('invalid-env', errno.EINVAL), ('empty-key', errno.EINVAL)]:
        assert run('', mode, code=None) == [f'spawn-error:{error}']
    assert run('', shell='/missing/executable', code=None) == [f'spawn-error:{errno.ENOENT}']
    assert run('', cwd=folder / 'missing', code=None) == [f'spawn-error:{errno.ENOENT}']
    noexec = folder / 'not-executable'
    noexec.write_text('#!/bin/sh\nexit 0\n')
    noexec.chmod(0o600)
    assert run('', shell=str(noexec), code=None) == [f'spawn-error:{errno.EACCES}']

    null_base = [str(args.null_prefix), '--threads', str(threads)]
    for command, expected in [
        ('test -c /dev/stdin && ! test -p /dev/stdin && printf null', b'null'),
        ('read line; printf "%s" "$?"', b'1'),
        ('readlink /proc/self/fd/0', b'/dev/null\n'),
        ("python3 -c 'import fcntl,os; print(fcntl.fcntl(0,fcntl.F_GETFL)&os.O_ACCMODE)'", b'0\n'),
        ('head -c 65536 /dev/zero', bytes(65536)),
    ]:
        result = subprocess.run(null_base + ['/bin/sh', str(folder), command],
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 0 and not result.stderr, result
        lines = result.stdout.splitlines()
        assert decoded(lines, 'stdout') == expected and decoded(lines, 'stderr') == b'', lines[:5]
        assert 'exit:0' in lines and 'pipes-close:ok:ok' in lines and 'process-close:ok' in lines
        count += 1
    lines = run('test -p /dev/stdin && printf pipe')
    assert decoded(lines, 'stdout') == b'pipe'
    repeated_null = subprocess.run(null_base + ['/bin/sh', str(folder), 'ls /proc/$PPID/fd | wc -l', '32'],
                                   capture_output=True, text=True, timeout=10)
    assert repeated_null.returncode == 0 and not repeated_null.stderr, repeated_null
    lines = repeated_null.stdout.splitlines()
    fd_counts = [int(bytes(int(n) for n in line[7:].replace(';', ',').split(',') if n))
                 for line in lines if line.startswith('stdout:')]
    assert len(fd_counts) == 32 and len(set(fd_counts)) == 1 and fd_counts[0] < 20, fd_counts
    assert lines.count('process-close:ok') == 32
    count += 1

    # The leader has exited but a descendant owns the pipes: wait reports before
    # EOF, and /proc confirms the zombie reserves its PID until explicit reap.
    pid_file = folder / f'leader-{threads}'
    child_file = folder / f'descendant-{threads}'
    command = f'echo $$ > {shlex.quote(str(pid_file))}; sleep .35 & echo $! > {shlex.quote(str(child_file))}; exit 23'
    child = subprocess.Popen(base + ['normal', '/bin/sh', str(folder), command],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    prefix = []
    while True:
        line = child.stdout.readline().strip()
        assert line, prefix
        prefix.append(line)
        if line == 'leader:exit:23':
            break
    pid = int(pid_file.read_text())
    stat = Path(f'/proc/{pid}/stat').read_text().split(') ')[1].split()
    assert stat[0] == 'Z' and int(stat[2]) == pid and int(stat[3]) == pid, stat
    suffix, errors = child.communicate(timeout=5)
    assert child.returncode == 0 and not errors, (suffix, errors)
    assert not Path(f'/proc/{pid}').exists(), 'leader was not reaped'
    count += 1

    # Group cancellation remains valid after the leader has exited; it reaches
    # the descendant holding stdout/stderr, so the fixture cannot hang for10s.
    started = time.monotonic()
    lines = run('sleep 10 & exit 23', 'kill', code=23)
    assert 'kill:True' in lines and time.monotonic() - started < 2

    # Reuse hundreds of capability slots in one runtime, sampling live FDs and
    # direct child lifetimes. No instrumented production code is needed.
    log = folder / f'repeated-{threads}.log'
    with log.open('w') as output:
        child = subprocess.Popen(base + ['repeat', '/bin/sh', str(folder), 'sleep .003'],
                                 stdout=output, stderr=subprocess.PIPE, text=True)
        high_fds = high_children = 0
        while child.poll() is None:
            try:
                high_fds = max(high_fds, len(list(Path(f'/proc/{child.pid}/fd').iterdir())))
                children = set()
                for task in Path(f'/proc/{child.pid}/task').glob('*/children'):
                    children.update(task.read_text().split())
                high_children = max(high_children, len(children))
            except (FileNotFoundError, PermissionError):
                # /proc entries can disappear or become unreadable during exit.
                pass
            time.sleep(.001)
        _, errors = child.communicate(timeout=3)
    assert child.returncode == 0 and not errors, errors
    text = log.read_text()
    assert text.count('reuse-close:ok:ok:ok:ok') == 128
    assert text.count('reuse:False:False:False:False') == 128
    assert 0 < high_fds < 32 and high_children <= 1, (high_fds, high_children)
    count += 1
    return count, high_fds, high_children


os.environ['PI_PROCESS_TEST_ENV'] = 'inherited value'
with tempfile.TemporaryDirectory(prefix='process checks ') as name:
    for threads in [1, 4]:
        count, fds, children = checks(threads, Path(name))
        print(f'native-{threads}: {count} lifecycle scenarios; 128 repeated retire/reuse pairs; peak {fds} FDs/{children} unreaped children')

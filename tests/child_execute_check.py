"""Real execution, cancellation precedence, input/output concurrency and cleanup."""
import argparse
import base64
import math
from pathlib import Path
import random
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--prefix', type=Path, default=ROOT / 'build/child-execute')
a = p.parse_args()

for threads in [1, 4]:
    prefix = [str(a.prefix.resolve()), '--threads', str(threads)]
    cases = 0

    def run(command, mode='normal', timeout='none', abort_ms=0, shell='/bin/sh', cwd='/tmp', count=1):
        global cases
        start = time.monotonic()
        result = subprocess.run(prefix + [mode, timeout, str(abort_ms), shell, str(cwd), command, str(count)],
                                capture_output=True, text=True, timeout=8)
        assert result.returncode == 0 and not result.stderr, (result.stdout[-3000:], result.stderr)
        lines = result.stdout.splitlines()
        output = b''.join(base64.b64decode(line[5:], validate=True) for line in lines if line.startswith('data '))
        outcomes = [line[7:] for line in lines if line.startswith('result ')]
        assert len(outcomes) == count, lines[-5:]
        cases += 1
        return output, outcomes, time.monotonic() - start

    assert run('printf hello; printf error >&2; exit 7')[:2] in [
        (b'helloerror', ['exit:7']), (b'errorhello', ['exit:7'])]
    assert run('test -c /dev/stdin && ! test -p /dev/stdin')[:2] == (b'', ['exit:0'])
    assert run('printf no-signal', 'no-signal')[:2] == (b'no-signal', ['exit:0'])
    assert run('kill -TERM $$')[:2] == (b'', ['exit:143'])
    assert run('true', 'abort', abort_ms=100)[:2] == (b'', ['exit:0'])
    assert run('exit 255')[:2] == (b'', ['exit:255'])
    assert run('printf "\\000\\377\\303\\251"')[:2] == (b'\0\xff\xc3\xa9', ['exit:0'])
    assert run('printf "[a b]; literal"')[:2] == (b'[a b]; literal', ['exit:0'])
    assert run('head -c 131072 /dev/zero & head -c 131072 /dev/zero >&2 & wait')[:2] == (bytes(262144), ['exit:0'])
    for mode in ['normal', 'no-signal', 'stdin']:
        output, outcomes, elapsed = run('sleep 5', mode, '.02')
        assert output == b'' and outcomes == ['timeout'] and elapsed < 1, (mode, outcomes, elapsed)
    for mode in ['abort', 'stdin-abort']:
        output, outcomes, elapsed = run('sleep 5', mode, abort_ms=20)
        assert output == b'' and outcomes == ['aborted'] and elapsed < 1, (mode, outcomes, elapsed)
    output, outcomes, elapsed = run('printf trigger; sleep 5', 'fail')
    assert output == b'trigger' and outcomes == ['failed:output:0:consumer failed;'] and elapsed < 1
    # Output callback deliberately awaits 80ms. Deadline wins first, parent abort
    # then arrives before settlement and must override the retained timeout.
    for _ in range(8):
        output, outcomes, _ = run('printf trigger; sleep 5', 'both', '.01', 30)
        assert output == b'trigger' and outcomes == ['aborted'], (output, outcomes)
    # Cancellation also reaches inherited descriptors after the shell exits.
    for mode, timeout, delay, expected in [('abort', 'none', 25, 'aborted'), ('normal', '.025', 0, 'timeout')]:
        _, outcomes, elapsed = run('sleep 5 & exit 0', mode, timeout, delay)
        assert outcomes == [expected] and elapsed < 1
    assert run('printf "é日本"', 'stdin')[:2] == ('é日本'.encode(), ['exit:0'])
    assert run('test -p /dev/stdin && printf pipe', 'stdin')[:2] == (b'pipe', ['exit:0'])
    # Child output fills its pipe before it reads the large remaining script.
    # The writer must run concurrently with draining and handle partial writes.
    script = 'printf before; head -c 131072 /dev/zero\n#' + 'x' * 100000 + '\nprintf after\n'
    assert run(script, 'stdin')[:2] == (b'before' + bytes(131072) + b'after', ['exit:0'])
    assert run('exit 0\n#' + 'x' * 100000, 'stdin')[:2] == (b'', ['exit:0'])
    assert run('exec sleep 5\n#' + 'x' * 100000, 'stdin-abort', abort_ms=20)[:2] == (b'', ['aborted'])
    with tempfile.TemporaryDirectory(prefix='execute checks ') as folder:
        marker = Path(folder) / 'spawned'
        command = f'touch "{marker}"'
        assert run(command, 'preabort')[:2] == (b'', ['aborted'])
        assert not marker.exists(), 'pre-aborted execution spawned a process'
        for invalid in ['0', '-0', '-1', 'nan', 'inf', '-inf', '2147483.648']:
            assert run(command, timeout=invalid)[:2] == (b'', ['invalid-timeout'])
            assert not marker.exists(), 'invalid timeout spawned a process'
        # Timeout validation runs before pre-abort, matching upstream ordering.
        assert run(command, 'preabort', 'nan')[:2] == (b'', ['invalid-timeout'])
        assert run('pwd', cwd=folder)[:2] == ((folder + '\n').encode(), ['exit:0'])
        assert run('', shell='/missing/shell')[1][0].startswith('failed:spawn:2:')
        assert run('', cwd=Path(folder) / 'missing')[1][0].startswith('failed:spawn:2:')

    # Direct spawn: PATH lookup of a bare name, stderr to its own consumer,
    # and either of two signals interrupts the process.
    def spawn(command, mode='spawn', abort_ms=0, shell='sh', cwd='/tmp'):
        global cases
        start = time.monotonic()
        result = subprocess.run(prefix + [mode, 'none', str(abort_ms), shell, str(cwd), command, '1'],
                                capture_output=True, text=True, timeout=8)
        assert result.returncode == 0 and not result.stderr, (result.stdout[-3000:], result.stderr)
        lines = result.stdout.splitlines()
        stream = lambda tag: b''.join(base64.b64decode(line.split(' ', 1)[1], validate=True) for line in lines if line.startswith(tag + ' '))
        cases += 1
        return stream('data'), stream('error'), [line[7:] for line in lines if line.startswith('result ')], time.monotonic() - start

    assert spawn('printf out; printf err >&2; exit 3')[:3] == (b'out', b'err', ['exit:3'])
    assert spawn('head -c 131072 /dev/zero & head -c 70000 /dev/zero >&2 & wait')[:3] == (bytes(131072), bytes(70000), ['exit:0'])
    output, errors, outcomes, elapsed = spawn('printf early; sleep 5', 'spawn-abort', 20)
    assert (output, errors, outcomes) == (b'early', b'', ['aborted']) and elapsed < 1, (output, outcomes, elapsed)
    assert spawn('true', shell='pi-bend-missing-command')[2][0].startswith('failed:spawn:2:')
    assert spawn('printf direct', shell='/bin/sh')[:3] == (b'direct', b'', ['exit:0'])
    # Observers and timers must retire on normal completion: repetition must
    # neither hang the runtime nor accumulate descriptors/deferred waiters.
    output, outcomes, _ = run('ls /proc/$PPID/fd | wc -l', timeout='60', count=48)
    counts = [int(line) for line in output.splitlines()]
    assert len(counts) == 48 and len(set(counts)) == 1 and counts[0] < 20, counts
    assert outcomes == ['exit:0'] * 48
    assert run('sleep 5', 'abort', abort_ms=2, count=24)[1] == ['aborted'] * 24
    assert run('sleep 5', timeout='.002', count=24)[1] == ['timeout'] * 24

    # Binary64 reference for validation/quantization; arbitrary fractional
    # seconds matter because rounding before the upper bound would be wrong.
    values = ['none', '0', '-0', '-1', 'nan', 'inf', '-inf', '5e-324', '0.000001',
              '0.0019', '0.002', '2147483.647', '2147483.6470002', '2147483.648', '1e308']
    rng = random.Random(1237)
    values += [repr(10 ** rng.uniform(-8, 7)) for _ in range(60)]
    for value in values:
        if value == 'none':
            expected = 'none'
        else:
            seconds = float(value)
            milliseconds = seconds * 1000
            expected = str(max(1, math.floor(milliseconds))) if seconds > 0 and milliseconds <= 2147483647 else 'invalid'
        result = subprocess.run(prefix + ['quantize', value], capture_output=True, text=True, timeout=3)
        assert result.returncode == 0 and not result.stderr and result.stdout.strip() == expected, (value, expected, result)
    print(f'native-{threads}: {cases} execution scenarios (including 96 repeated lifecycles), {len(values)} timeout conversions PASS', flush=True)

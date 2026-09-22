"""Fixed decimal formatting against exact Decimal.from_float arithmetic."""
import argparse
from decimal import Decimal, ROUND_HALF_UP, localcontext
from pathlib import Path
import random
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
a = p.parse_args()
rng = random.Random(100)
values = [0., -0., 1.005, 2.675, -2.675, -0.0001, 0.125, 0.375, 1e21, 1e100, 1e308, 5e-324]
values += [struct.unpack('>d', rng.getrandbits(64).to_bytes(8, 'big'))[0] for _ in range(70)]
cases = [(value, digits) for value in values for digits in [0, 2, 9, 100]]
cases += [(float('inf'), 2), (float('-inf'), 2), (float('nan'), 2), (1., 101)]
requests, expected = [], []
with localcontext() as context:
    context.prec = 450
    for value, digits in cases:
        hi, lo = struct.unpack('>II', struct.pack('>d', value))
        requests.append(f'{hi}:{lo}:{digits}')
        exact = Decimal.from_float(value)
        if not exact.is_finite() or digits > 100:
            expected.append('none')
        else:
            if exact.is_zero():
                exact = abs(exact)
            expected.append(format(exact.quantize(Decimal(1).scaleb(-digits), rounding=ROUND_HALF_UP), 'f'))
for backend in a.backends:
    command = ['bun', str(ROOT/'build/number-fixed.js')] if backend == 'bun' else [str(ROOT/'build/number-fixed'), '--threads', backend[-1]]
    actual = []
    for start in range(0, len(requests), 24):
        run = subprocess.run(command+requests[start:start+24], capture_output=True, text=True, check=True, timeout=90)
        actual.extend(run.stdout.splitlines())
    mismatches = [(case, got, want) for case, got, want in zip(requests, actual, expected) if got != want]
    assert len(actual) == len(expected) and not mismatches, (backend, mismatches[:3])
    print(f'{backend}: {len(cases)} exact fixed-decimal comparisons PASS', flush=True)

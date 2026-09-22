#!/usr/bin/env python3
"""Independent integer oracle for public scalar arithmetic; no host production code."""
import argparse
import math
import random
import subprocess
import time

ORDERS = {
    256: int('FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551', 16),
    384: int('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF581A0DB248B0A77AECEC196ACCC52973', 16),
}
PRIMES = [2**256-2**224+2**192+2**96-1, 2**384-2**128-2**96+2**32-1]


def cases():
    rng = random.Random(927405)
    result = []
    for bits, n in ORDERS.items():
        values = [0, 1, 2, n-2, n-1] + [rng.randrange(n) for _ in range(80)]
        values += [1 << shift for shift in range(0, bits, 16)]
        for a in values:
            result.append((f'i:{a}:{n}', str(pow(a, -1, n)) if a else 'none'))
            for b in [0, 1, n-1, rng.randrange(n)]:
                result.append((f'm:{bits}:{a}:{b}', str(a*b % n)))
        for a in [n, n+1, (1 << bits)-1]:
            for b in [0, 1, n-1, rng.randrange(n)]:
                result.append((f'm:{bits}:{a}:{b}', str(a*b % n)))
    for n in PRIMES + [2**384-1, 2**383+1, 2**256-1, 2**255+1, 2**521-1, 1, 3, 9, 15, 65535, 65537, 65536, 0]:
        for _ in range(30):
            a = rng.randrange(max(n, 1))
            valid = n > 1 and n % 2 and math.gcd(a, n) == 1
            result.append((f'i:{a}:{n}', str(pow(a, -1, n)) if valid else 'none'))
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--backend', choices=['bun', 'native-1', 'native-4'], default='native-1')
    p.add_argument('--prefix', default='build/modular')
    p.add_argument('--benchmark', action='store_true')
    args = p.parse_args()
    command = ['bun', args.prefix + '.js'] if args.backend == 'bun' else [args.prefix, '--threads', args.backend[-1]]
    vectors = cases()
    for start in range(0, len(vectors), 64):
        batch = vectors[start:start+64]
        actual = subprocess.check_output(command + [v[0] for v in batch], text=True).splitlines()
        assert actual == [v[1] for v in batch], [(v, got) for v, got in zip(batch, actual) if got != v[1]]
    print(f'PASS {len(vectors)} modular arithmetic cases on {args.backend}')
    if args.benchmark:
        for bits, n in ORDERS.items():
            a = random.Random(bits).randrange(2, n)
            for operation, expected in [('bi', pow(a, -1, n)*1000), ('bm', (a*a % n)*1000), ('b', 1000)]:
                timings = []
                for _ in range(3):
                    start = time.perf_counter()
                    actual = subprocess.check_output(command + [f'{operation}:{bits}:{a}'], text=True).strip()
                    elapsed = time.perf_counter() - start
                    assert actual == str(expected), actual
                    timings.append(elapsed / 1000)
                print(f'{bits}: {operation} seconds/op: {timings}')


if __name__ == '__main__':
    main()

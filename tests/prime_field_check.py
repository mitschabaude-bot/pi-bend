#!/usr/bin/env python3
"""Independent integer oracle for NIST field operations and chained squares."""
import argparse
import json
import random
import statistics
import subprocess
import time
from pathlib import Path

PRIMES = {
    256: 2**256 - 2**224 + 2**192 + 2**96 - 1,
    384: 2**384 - 2**128 - 2**96 + 2**32 - 1,
}


def vectors():
    rng = random.Random(0x50_256_384)
    result = []
    for bits, p in PRIMES.items():
        edges = [0, 1, 2, p - 1, p - 2, p - 65536, p // 2]
        edges += [min(p - 1, (1 << i) + offset)
                  for i in range(16, bits, 16) for offset in (-1, 0, 1)]
        pairs = [(a, b) for a in edges[:7] for b in edges]
        pairs += [(rng.randrange(p), rng.randrange(p)) for _ in range(256)]
        for a, b in pairs:
            result += [
                (f"{bits}:add:{a}:{b}", (a + b) % p),
                (f"{bits}:sub:{a}:{b}", (a - b) % p),
                (f"{bits}:mul:{a}:{b}", a * b % p),
            ]
        for a in edges:
            for k in (0, 1, 2, 3, 4, 8, 65535):
                result.append((f"{bits}:scale:{a}:{k}", a * k % p))
    return result


def run(command, cases):
    proc = subprocess.run(command + [c[0] for c in cases], check=True,
                          text=True, capture_output=True, timeout=120)
    actual = proc.stdout.splitlines()
    expected = [str(c[1]) for c in cases]
    if actual != expected:
        for (arg, want), got in zip(cases, actual):
            if got != str(want):
                raise AssertionError(f"{arg}: expected {want}, got {got}")
        raise AssertionError(f"output count {len(actual)}, expected {len(expected)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', default='build/prime-field')
    parser.add_argument('--backends', nargs='+', default=['bun', 'native-1', 'native-4'])
    parser.add_argument('--benchmark', type=int, default=0, metavar='SQUARES')
    args = parser.parse_args()
    cases = vectors()
    for backend in args.backends:
        command = ['bun', args.prefix + '.js'] if backend == 'bun' else [
            str(Path(args.prefix).resolve()), '--threads', backend.removeprefix('native-')]
        for offset in range(0, len(cases), 128):
            run(command, cases[offset:offset + 128])
        print(f'PASS {backend}: {len(cases)} independent field comparisons', flush=True)
        if args.benchmark:
            timings = {}
            for bits, p in PRIMES.items():
                value = p // 3
                expected = value
                for _ in range(args.benchmark):
                    expected = expected * expected % p
                case = [(f'{bits}:bench:{value}:{args.benchmark}', expected)]
                samples = []
                for _ in range(5):
                    start = time.perf_counter()
                    run(command, case)
                    samples.append(time.perf_counter() - start)
                timings[bits] = {'squares': args.benchmark, 'seconds': samples,
                                 'median_us_per_square': statistics.median(samples) * 1e6 / args.benchmark}
            print(json.dumps({'backend': backend, 'benchmark': timings}), flush=True)


if __name__ == '__main__':
    main()

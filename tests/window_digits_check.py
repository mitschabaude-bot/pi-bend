"""Integer reconstruction and non-adjacency of signed width-five digits."""
import argparse
import random
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prefix', default='build/p256-recoded')
    parser.add_argument('--backend', choices=['native-1', 'native-4', 'bun'], default='native-1')
    args = parser.parse_args()
    command = ['bun', args.prefix + '.js'] if args.backend == 'bun' else [args.prefix, '--threads', args.backend[-1]]
    rng = random.Random(2841)
    cases = [b''] + [n.to_bytes(2, 'big') for n in range(65536)]
    for width in [1, 3, 4, 32, 48]:
        cases += [bytes([byte])*width for byte in [0, 1, 15, 16, 31, 127, 128, 254, 255]]
        cases += [rng.randbytes(width) for _ in range(40)]
    for start in range(0, len(cases), 1000):
        batch = cases[start:start+1000]
        inputs = ['w:' + ','.join(map(str, value)) for value in batch]
        lines = subprocess.check_output(command + inputs, text=True).splitlines()
        assert len(lines) == len(batch)
        for source, line in zip(batch, lines):
            digits = [int(d) for d in line.split(',')]
            assert len(digits) == len(source)*8+1, (source, digits)
            value = 0
            zeros = 4
            for digit in digits:
                assert digit == 0 or digit % 2 == 1 and 1 <= digit <= 31
                signed = digit if digit < 16 else digit-32
                value = value*2 + signed
                if digit:
                    assert zeros >= 4, (source, digits)
                    zeros = 0
                else:
                    zeros += 1
            assert value == int.from_bytes(source, 'big'), (source, digits)
    print(f'PASS {len(cases)} window reconstructions and non-adjacency checks on {args.backend}')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Compare thinking-picker frames and input/mouse behavior with pinned pi."""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh']


def mouse(kind, zone='list', y=0, x=3, **kwargs):
    return dict(type=kind, zone=zone, y=y, x=x, **kwargs)


def cases():
    sequences = [
        ['down', 'up', 'up', 'enter', 'save', 'escape'],
        ['high', 'up', 'save'],
        ['default', 'enter'],
        ['nothing', 'enter', mouse('wheel', delta=1), 'escape'],
        [mouse('press', y=1), mouse('click', y=3), mouse('click', y=4)],
        [mouse('wheel', delta=1), mouse('wheel', delta=-5), mouse('wheel', delta=0), mouse('wheel', delta=10)],
        [mouse('press', button='right'), mouse('move'), mouse('press', y=-1), mouse('click', y=6)],
        ['high', mouse('press', 'search', x=2), 'x', 'left', mouse('press', 'search', x=4), 'h'],
    ]
    for width in (7, 12, 24, 40, 80, 120):
        for steps in sequences:
            yield dict(width=width, current='medium', default='low', levels=LEVELS, steps=steps)
    for levels in ([], ['off'], ['low', 'high']):
        yield dict(width=40, current='medium', default=None, levels=levels,
                   steps=['down', mouse('wheel', delta=-1), mouse('press'), mouse('click'), 'save'])


def coordinate(value):
    return f"{'n' if value < 0 else 'p'}:{abs(value)}"


def argument(step):
    if isinstance(step, str):
        return 'key|' + step
    delta = '' if step.get('delta') is None else coordinate(step['delta'])
    return '|'.join(['mouse', step['type'], step['zone'], coordinate(step['y']),
                     coordinate(step['x']), delta, step.get('button', 'left')])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT / 'build/thinking-selector')
    args = parser.parse_args()
    inputs = list(cases())
    reference = subprocess.run(['bun', 'tests/thinking_selector_reference.mts'], cwd=ROOT,
                               input=json.dumps(inputs), text=True, capture_output=True, check=True)
    expected = json.loads(reference.stdout)
    for threads in (1, 4):
        for index, (case, want) in enumerate(zip(inputs, expected)):
            command = [str(args.binary.resolve()), '--threads', str(threads), '--', str(ROOT),
                       str(case['width']), case['current'], case['default'] or '-',
                       ','.join(case['levels']), *map(argument, case['steps'])]
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=True)
            try:
                got = [json.loads(line) for line in result.stdout.splitlines()]
            except ValueError:
                raise AssertionError(result.stdout + result.stderr)
            if got != want:
                for step, (actual, expected_step) in enumerate(zip(got, want)):
                    if actual != expected_step:
                        raise AssertionError(f'threads={threads} case={index} step={step} {case}\n'
                                             f'actual={actual!r}\nexpected={expected_step!r}')
                raise AssertionError(f'case {index}: expected {len(want)} snapshots, got {len(got)}')
        print(f'thinking picker: {len(inputs)} sequences match pinned pi on {threads} threads')


if __name__ == '__main__':
    main()

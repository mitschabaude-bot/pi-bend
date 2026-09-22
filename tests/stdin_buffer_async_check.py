#!/usr/bin/env python3
"""Real timers, reentrant listeners, ordered delivery and owned retirement."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ESC = '\x1b'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--command', nargs=argparse.REMAINDER, default=['bun', 'build/stdin-buffer-async.js'])
    args = parser.parse_args()
    count = 0

    def check(name, commands, expected, *, timeout=50, escape=10, mode='', minimum=None):
        nonlocal count
        scenario = json.dumps([timeout, escape, mode, commands])
        run = subprocess.run([*args.command, scenario], cwd=ROOT, text=True, capture_output=True, timeout=15)
        assert run.returncode == 0, (name, run.stdout, run.stderr)
        rows = [json.loads(line) for line in run.stdout.splitlines()]
        assert rows[0][0] == 'start' and rows[-1][0] == 'done', (name, rows)
        disposed = next(i for i, row in enumerate(rows) if row[0] == 'disposed')
        assert all(row[0] == 'done' for row in rows[disposed + 1:]), (name, 'late event', rows)
        actual = [row[:2] for row in rows if row[0] in ('data', 'paste', 'flush', 'buffer')]
        assert actual == expected, (name, actual, expected)
        if minimum is not None:
            data = next(row for row in rows if row[0] == 'data')
            assert data[2] - rows[0][2] >= minimum, (name, 'early timeout', rows)
        if name == 'disposal cancels long timer promptly':
            assert rows[disposed][2] - rows[0][2] < 1000, (name, rows)
        if mode == 'slow':
            data = next(row for row in rows if row[0] == 'data')
            assert rows[disposed][2] - data[2] >= 75, (name, 'callback not joined', rows)
        count += 1

    p = lambda text: ['process', text]
    s = lambda ms: ['sleep', ms]
    check('lone escape uses separate short timeout', [p(ESC), s(120)], [['data', ESC]], timeout=500, minimum=8)
    check('incomplete CSI timeout', [p(ESC+'['), s(150)], [['data', ESC+'[']], minimum=45)
    check('custom escape timeout merges Alt Enter', [p(ESC), s(30), p('\r'), s(140)], [['data', ESC+'\r']], escape=100)
    check('escape expiry separates Enter', [p(ESC), s(90), p('\r'), s(80)], [['data', ESC], ['data', '\r']])
    check('completed CSI cancels pending timer', [p(ESC+'['), s(20), p('A'), s(180)], [['data', ESC+'[A']])
    check('new fragment resets whole sequence deadline', [p(ESC+'['), s(80), p('1;'), s(80), p('2A'), s(180)], [['data', ESC+'[1;2A']], timeout=140)
    check('explicit flush does not publish', [p(ESC+'['), 'flush', s(160)], [['flush', ESC+'[']])
    check('flush leaves incomplete paste', [p(ESC+'[200~abc'), 'flush', s(150), p(ESC+'[201~'), s(80)], [['paste', 'abc']])
    check('paste has no inactivity timer', [p(ESC+'[200~abc'), s(160), p('def'+ESC+'[201~'), s(80)], [['paste', 'abcdef']])
    check('clear cancels timer', [p(ESC+'['), 'clear', s(160), 'get'], [['buffer', '']])
    check('clear discards paste and allows reuse', [p(ESC+'[200~abc'), 'clear', p('z'), s(80)], [['data', 'z']])
    check('buffer read observes committed pending text', [p(ESC+'['), 'get', 'clear'], [['buffer', ESC+'[']])
    check('ordered events and listener reentry', [p('xy'), s(120)], [['data', 'x'], ['data', 'y'], ['data', 'r']], mode='reenter')
    check('clear preserves already committed events', [p('abc'), 'clear', s(100)], [['data', 'a'], ['data', 'b'], ['data', 'c']])
    check('disposal cancels long timer promptly', [p(ESC)], [], escape=10000)
    check('disposal joins listener already running', [p('x'), s(35)], [['data', 'x']], mode='slow')
    check('default sequence and paste callback order', [p('a'+ESC+'[A'+ESC+'[200~hello'+ESC+'[201~z'), s(100)], [['data', 'a'], ['data', ESC+'[A'], ['paste', 'hello'], ['data', 'z']])
    check('zero timeout is immediate', [p(ESC), s(100)], [['data', ESC]], escape=0)
    check('Kitty duplicate suppression through async driver', [p(ESC+'[97u'), p('a'), s(100)], [['data', ESC+'[97u']])
    check('many input resets leave one surviving timeout', [item for _ in range(100) for item in (p(ESC+'['), 'clear')] + [p(ESC+'['), s(140)], [['data', ESC+'[']])
    check('large chunk remains ordered', [p('a'*1000), s(400)], [['data', 'a']]*1000)
    print(f'{count} owned input-driver scenarios passed: {args.command}')


if __name__ == '__main__':
    main()

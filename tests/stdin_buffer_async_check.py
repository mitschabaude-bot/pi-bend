#!/usr/bin/env python3
"""Real timers, reentrant listeners, ordered delivery and owned retirement."""
import argparse
import json
import random
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
        actual = [row[:2] for row in rows if row[0] in ('data', 'paste', 'flush', 'buffer', 'error', 'rejected')]
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
    b = lambda raw: ['bytes', list(raw)]
    text = 'é世界😀\ufeffz'
    check('UTF8 scalars survive every single-byte chunk', [b([byte]) for byte in text.encode()] + ['eof', s(100)], [['data', char] for char in text])
    for cut in range(1, 4):
        raw = '😀'.encode()
        check(f'UTF8 four-byte split {cut}', [b(raw[:cut]), s(30), b(raw[cut:]), 'eof', s(80)], [['data', '😀']])
    check('initial and repeated BOM are terminal text', [b([239]), b([187]), b([191]), b('\ufeff'.encode()), 'eof', s(80)], [['data', '\ufeff'], ['data', '\ufeff']])
    check('empty byte chunks do not invent keys', [b([]), b([195]), b([]), b([169]), b([]), 'eof', s(80)], [['data', 'é']])
    check('UTF8 input within bracketed paste', [b((ESC+'[200~').encode()), b([240,159]), s(120), b([152,128]), b((ESC+'[201~').encode()), s(80)], [['paste', '😀']])
    check('partial UTF8 leaves Escape deadline active', [b([27]), b([195]), s(80), b([169]), s(80)], [['data', ESC], ['data', 'é']])
    check('UTF8 arriving before Escape timeout forms Alt key', [b([27,195]), b([169]), s(150)], [['data', ESC+'é']], escape=100)
    check('EOF does not flush escape framing itself', [b([27,91]), 'eof', 'flush', s(80)], [['flush', ESC+'[']])
    check('repeated successful EOF validation is harmless', [b([97]), 'eof', 'eof', s(80)], [['data', 'a']])
    check('valid text cannot splice into pending UTF8', [b([195]), p('x'), b([169]), s(80)], [['rejected', 'text'], ['data', 'é']])
    check('clear resets incomplete UTF8 and byte offset', [b([195]), 'clear', b([255])], [['error', 'invalid:0:255']])
    check('error sticks until explicit clear', [b([255]), b([97]), 'eof', p('z'), 'clear', b([98]), s(80)], [['error', 'invalid:0:255']]*3 + [['rejected', 'text'], ['data', 'b']])
    check('malformed chunk cancels earlier pending framing', [b([27,91]), b([255]), s(150), 'get'], [['error', 'invalid:2:255'], ['buffer', '']])
    check('malformed chunk is atomic', [b([97,255]), s(80)], [['error', 'invalid:1:255']])
    check('offset survives draining previous chunks', [b([195,169]), s(80), b([240,159]), b([65])], [['data', 'é'], ['error', 'invalid:4:65']])
    for raw, cause in [([128], 'invalid:0:128'), ([192,128], 'invalid:0:192'), ([224,128,128], 'invalid:1:128'), ([237,160,128], 'invalid:1:160'), ([240,128,128,128], 'invalid:1:128'), ([244,144,128,128], 'invalid:1:144'), ([245], 'invalid:0:245'), ([256], 'byte:0:256'), ([4294967295], 'byte:0:4294967295')]:
        check(f'strict UTF8 rejection {raw}', [b(raw)], [['error', cause]])
    for raw in ([194], [224,160], [240,159,152]):
        check(f'EOF rejects truncated scalar {raw}', [b(raw), 'eof'], [['error', f'incomplete:{len(raw)}']])
    # ProcessTerminal.setEncoding("utf8") uses Node's streaming StringDecoder.
    # Its decoded text is the oracle; Bend emits Unicode scalars, not JS halves.
    rng = random.Random(63020)
    samples = []
    for _ in range(24):
        points = [rng.randrange(0x20, 0x110000) for _ in range(16)]
        text = ''.join(chr(point) for point in points if not 0xd800 <= point <= 0xdfff)
        raw = text.encode()
        chunks = []
        while raw:
            cut = rng.randrange(1, 8)
            chunks.append(list(raw[:cut]))
            raw = raw[cut:]
        samples.append(chunks)
    oracle = subprocess.run(['node', '-e', "const {StringDecoder}=require('node:string_decoder'); let s=''; process.stdin.on('data',x=>s+=x); process.stdin.on('end',()=>console.log(JSON.stringify(JSON.parse(s).map(parts=>{const d=new StringDecoder('utf8'); return parts.map(p=>d.write(Buffer.from(p))).join('')+d.end()}))))"], input=json.dumps(samples), text=True, capture_output=True, check=True)
    for index, (chunks, text) in enumerate(zip(samples, json.loads(oracle.stdout))):
        check(f'actual terminal decoder oracle {index}', [b(chunk) for chunk in chunks] + ['eof', s(80)], [['data', char] for char in text])
    print(f'{count} owned input-driver scenarios passed: {args.command}')


if __name__ == '__main__':
    main()

"""Exercise picker mouse selection through both interactive terminals."""
import argparse
import os
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests/parity'))
import runner
import scenarios


class PickerTerminal(runner.Terminal):
    def keys(self, text):
        if text in ('<click-high>', '<wheel-down>', '<drag-high>'):
            rows = self.screen().splitlines()
            row = next(i for i, line in enumerate(rows) if re.search(r'^\s*(?:→ )?\s*high\s+Deep reasoning', line))
            # SGR mouse coordinates are one-based. A release after the left
            # press produces the terminal's click, invoking the chosen hook.
            if text == '<wheel-down>':
                text = f'\x1b[<65;4;{row + 1}M'
            elif text == '<drag-high>':
                text = f'\x1b[<0;4;{row + 1}M\x1b[<32;4;{row}M\x1b[<0;4;{row}m'
            else:
                text = f'\x1b[<0;4;{row + 1}M\x1b[<0;4;{row + 1}m'
        super().keys(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend', type=Path, default=ROOT / 'build/pi-cli-thinking-mouse')
    args = parser.parse_args()
    runner.Terminal = PickerTerminal
    runner.package_links()
    original = next(s for s in scenarios.SCENARIOS if s['name'] == 'thinking-selector')
    scenario = {**original, 'args': original['args'] + ['--tui-mode', 'fullscreen'],
                'name': 'thinking-selector-mouse', 'steps': [
        ('wait', scenarios.READY, 'startup'), ('settle', 1),
        ('keys', '/thinking'), ('key', 'Enter'), ('wait', 'Thinking Level', 'open'),
        ('settle', .2), ('keys', '<click-high>'),
        ('wait', 'Thinking level: high', 'selected'), ('settle', .2), ('snap', 'selected'),
        ('keys', '/thinking'), ('key', 'Enter'), ('wait', 'Thinking Level', 'reopen'),
        ('key', 'C-s'), ('wait', 'Default thinking level:', 'saved'), ('settle', .2), ('snap', 'saved')
    ]}
    wheel = {**scenario, 'name':'thinking-selector-wheel', 'steps': [
        ('wait', scenarios.READY, 'startup'), ('settle', 1),
        ('keys', '/thinking'), ('key', 'Enter'), ('wait', 'Thinking Level', 'open'),
        ('settle', .2), ('keys', '<wheel-down>'), ('settle', .2), ('snap', 'scrolled'),
        ('key', 'C-s'), ('wait', 'Default thinking level:', 'saved'), ('settle', .2), ('snap', 'saved')
    ]}
    drag = {**scenario, 'name':'thinking-selector-drag', 'steps': [
        ('wait', scenarios.READY, 'startup'), ('settle', 1),
        ('keys', '/thinking'), ('key', 'Enter'), ('wait', 'Thinking Level', 'open'),
        ('settle', .2), ('keys', '<drag-high>'), ('settle', .2), ('snap', 'dragged'),
        ('key', 'Enter'), ('wait', 'Thinking level: high', 'selected'), ('settle', .2), ('snap', 'selected')
    ]}
    for case in (scenario, wheel, drag):
        expected = runner.run_side('pi', [shutil.which('pi')], case, False)
        assert all(value is not None for value in expected['timings'].values()), expected['timings']
        for threads in (1, 4):
            os.environ['BEND_THREADS'] = str(threads)
            actual = runner.run_side('bend', [str(args.bend.resolve())], case, False)
            assert all(value is not None for value in actual['timings'].values()), actual['timings']
            assert actual['snaps'] == expected['snaps'], (case['name'], threads, actual['snaps'], expected['snaps'])
            assert not actual['requests'], 'picker unexpectedly sent a model request'
            print(f"native{threads}: {case['name']} terminal frames and settings match pi", flush=True)



if __name__ == '__main__':
    main()

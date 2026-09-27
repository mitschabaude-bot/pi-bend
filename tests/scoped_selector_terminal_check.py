"""Compare mounted scoped search editing, word navigation and persistence."""
import argparse
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests/parity'))
import runner
import scenarios


class ModelTerminal(runner.Terminal):
    def keys(self, text):
        if text == '<search-start>':
            row = next(i for i, line in enumerate(self.screen().splitlines())
                       if line.lstrip().startswith('> mini'))
            text = f'\x1b[<0;3;{row + 1}M\x1b[<0;3;{row + 1}m'
        super().keys(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend', type=Path, default=ROOT / 'build/pi-cli-scoped-picker')
    args = parser.parse_args()
    runner.Terminal = ModelTerminal
    runner.package_links()
    base = next(s for s in scenarios.SCENARIOS if s['name'] == 'scoped-models-selector')
    case = {**base, 'name': 'scoped-models-search-editing',
            'args': base['args'] + ['--tui-mode', 'fullscreen'], 'steps': [
        ('wait', scenarios.READY, 'startup'), ('settle', 1),
        ('keys', '/scoped-models'), ('key', 'Enter'),
        ('wait', 'Model Configuration', 'open'), ('settle', .5),
        ('keys', 'mini'), ('settle', .2), ('snap', 'filtered'),
        ('keys', '<search-start>'), ('keys', 'x'), ('settle', .2), ('snap', 'inserted'),
        ('key', 'Backspace'), ('key', 'End'), ('key', 'C-w'),
        ('settle', .2), ('snap', 'word-deleted'), ('key', 'C-y'),
        ('settle', .2), ('snap', 'yanked'),
        ('key', 'C-c'), ('key', 'Down'), ('keys', 'gpt'), ('key', 'C-c'),
        ('settle', .2), ('snap', 'cleared'), ('key', 'Enter'),
        ('key', 'C-s'), ('settle', .2), ('snap', 'saved'),
        ('key', 'Escape'), ('settle', .2), ('snap', 'closed')
    ]}
    expected = runner.run_side('pi', [shutil.which('pi')], case, False)
    assert all(value is not None for value in expected['timings'].values()), expected['timings']
    for threads in (1, 4):
        os.environ['BEND_THREADS'] = str(threads)
        actual = runner.run_side('bend', [str(args.bend.resolve())], case, False)
        assert all(value is not None for value in actual['timings'].values()), actual['timings']
        assert actual['snaps'] == expected['snaps'], (threads, actual['snaps'], expected['snaps'])
        assert not actual['requests'], 'picker unexpectedly sent a model request'
        print(f'native{threads}: scoped search terminal frames and persistence match pi', flush=True)


if __name__ == '__main__':
    main()

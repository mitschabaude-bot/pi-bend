"""Compare mounted provider search editing, mouse placement and API-key login."""
import argparse
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests/parity'))
import runner
import scenarios


class ProviderTerminal(runner.Terminal):
    def keys(self, text):
        if text == '<search-start>':
            row = next(i for i, line in enumerate(self.screen().splitlines())
                       if line.lstrip().startswith('> OpenAI'))
            text = f'\x1b[<0;3;{row + 1}M\x1b[<0;3;{row + 1}m'
        super().keys(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend', type=Path, default=ROOT / 'build/pi-cli-login-picker')
    args = parser.parse_args()
    runner.Terminal = ProviderTerminal
    runner.package_links()
    base = next(s for s in scenarios.SCENARIOS if s['name'] == 'login-api-key')
    case = {**base, 'name': 'login-provider-search-editing',
            'args': base['args'] + ['--tui-mode', 'fullscreen'], 'steps': [
        ('wait', scenarios.READY, 'startup'), ('settle', 1),
        ('keys', '/login'), ('key', 'Enter'),
        ('wait', 'Select authentication method:', 'method'),
        ('key', 'Down'), ('key', 'Enter'),
        ('wait', 'Select provider to configure:', 'providers'), ('settle', .2),
        ('keys', 'OpenAI'), ('settle', .2), ('snap', 'filtered'),
        ('keys', '<search-start>'), ('keys', 'x'), ('settle', .2), ('snap', 'inserted'),
        ('key', 'Backspace'), ('key', 'End'), ('key', 'Left'),
        ('key', 'Backspace'), ('settle', .2), ('snap', 'edited'),
        ('key', 'C-a'), ('key', 'C-k'), ('keys', '\x1b[200~OpenAI\x1b[201~'),
        ('key', 'Enter'), ('wait', 'Enter OpenAI API key', 'prompt'), ('snap', 'prompt'),
        ('keys', 'sk-parity-new'), ('key', 'Enter'),
        ('wait', 'Saved API key for OpenAI', 'saved'),
        ('settle', .2), ('snap', 'saved')
    ]}
    expected = runner.run_side('pi', [shutil.which('pi')], case, False)
    assert all(value is not None for value in expected['timings'].values()), expected['timings']
    for threads in (1, 4):
        os.environ['BEND_THREADS'] = str(threads)
        actual = runner.run_side('bend', [str(args.bend.resolve())], case, False)
        assert all(value is not None for value in actual['timings'].values()), actual['timings']
        assert actual['snaps'] == expected['snaps'], (threads, actual['snaps'], expected['snaps'])
        assert not actual['requests'], 'login unexpectedly sent a model request'
        print(f'native{threads}: provider search terminal frames and login match pi', flush=True)


if __name__ == '__main__':
    main()

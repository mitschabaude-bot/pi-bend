"""Compare Bend's platform identity with pinned pi-mono's Node formula."""
from upstream_pin import UPSTREAM
import argparse
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--toolchain', required=True)
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=UPSTREAM, text=True).strip()
    assert revision.startswith('f07218c4d'), revision
    source = (UPSTREAM / 'packages/ai/src/utils/pi-user-agent.ts').read_text()
    assert 'pi (${nodeOs.platform()} ${nodeOs.release()}; ${nodeOs.arch()})' in source
    expected = subprocess.check_output(['node', '-e', "const os=require('node:os');console.log(`pi (${os.platform()} ${os.release()}; ${os.arch()})`)"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix='bend-identity-') as directory:
        output = pathlib.Path(directory) / 'identity'
        fixture = ROOT / 'tests/system-identity.bend'
        subprocess.run(['bun', args.toolchain, str(fixture), '-o', str(output)], cwd=ROOT, check=True)
        subprocess.run(['bun', args.toolchain, str(fixture), '-o', str(output) + '.js'], cwd=ROOT, check=True)
        for name, command in [('bun', ['bun', str(output) + '.js']), ('native1', [str(output), '--threads', '1']), ('native4', [str(output), '--threads', '4'])]:
            actual = subprocess.check_output(command, text=True).strip()
            assert actual == expected, (name, actual, expected)
            print(f'{name}: {actual}')

if __name__ == '__main__':
    main()

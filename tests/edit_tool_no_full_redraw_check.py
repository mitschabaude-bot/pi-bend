"""Run the three pinned edit-tool TUI contracts with real native preflight IO."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--runner', default='build/edit-tool-no-full-redraw.js')
p.add_argument('--threads', default='1')
args = p.parse_args()
runner = (ROOT / args.runner).resolve()
command = ['bun', str(runner)] if runner.suffix == '.js' else [str(runner), '--threads', args.threads, '--']
expected = [
    'renders the large diff in the call preview and does not full-redraw when the result settles',
    'reconstructs the boxed preview from a settled result without argsComplete',
    'shows a preflight error without rendering a diff when the edits do not apply',
    'input revisions discard old completions and disposal joins owned reads',
]
with tempfile.TemporaryDirectory(prefix='pi-edit-redraw-') as place:
    directory = Path(place)
    large = '\n'.join(f'line {i}' for i in range(1000)) + '\n'
    (directory / 'large.txt').write_text(large)
    (directory / 'replay.txt').write_text('\n'.join(f'line {i}' for i in range(200)) + '\n')
    (directory / 'error.txt').write_text('line 0\nline 1\n')
    result = subprocess.run(command + [place], cwd=ROOT, capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert result.stdout.splitlines() == expected, result.stdout
    assert not result.stderr, result.stderr
    assert (directory / 'large.txt').read_text() == large
    assert (directory / 'error.txt').read_text() == 'line 0\nline 1\n'
    assert not (directory / 'replay.txt').exists()
    print(f'{runner.name}: three upstream contracts and owned/stale-read checks pass without preflight file mutations')

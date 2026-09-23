"""Check the native query lifecycle against the pinned pi TUI test contracts."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM = ROOT.parent / 'pi-mono'
if not UPSTREAM.exists():
    UPSTREAM = pathlib.Path('/home/agent/code/pi-mono')
PIN = 'f07218c4d'
source = subprocess.check_output(['git', 'show', f'{PIN}:packages/tui/src/tui.ts'], cwd=UPSTREAM, text=True)
tests = subprocess.check_output(['git', 'show', f'{PIN}:packages/tui/test/terminal-colors.test.ts'], cwd=UPSTREAM, text=True)
for fragment in ('this.terminal.write("\\x1b]11;?\\x07")', 'this.terminal.write("\\x1b[?996n")', 'this.pendingOsc11BackgroundReplies -= 1', 'this.pendingOsc11BackgroundQueries.shift()', 'this.terminal.write(enabled ? "\\x1b[?2031h" : "\\x1b[?2031l")'):
    assert fragment in source, fragment
for name in ('writes OSC 11 query and resolves with the parsed RGB reply', 'consumes unparseable strict OSC 11 replies and resolves undefined', 'dispatches non-matching input normally while waiting for an OSC 11 reply', 'keeps consuming a late OSC 11 reply after timeout'):
    assert name in tests, name
expected = [
    'write:\x1b]11;?\x07',
    'ordinary:False',
    'color:True:255,128,64',
    'malformed:True:none',
    'late:none:True',
    'ordered:none:True:True:255,255,255',
    'notification:\x1b[?2031h',
    'scheme-write:\x1b[?996n',
    'listener:dark',
    'scheme:True:dark',
    'scheme-timeout:False:none',
    'notification:\x1b[?2031l',
]
for name, command in [('Bun', ['bun', 'build/terminal-query.js']), ('native1', ['build/terminal-query', '--threads', '1']), ('native4', ['build/terminal-query', '--threads', '4'])]:
    actual = subprocess.check_output(command, cwd=ROOT, text=True, timeout=10).splitlines()
    assert actual == expected, (name, actual, expected)
    print(f'{name}: pinned query, dispatch, late reply, listener and notification cases passed')

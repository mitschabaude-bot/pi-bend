"""Check controller setting precedence and fallback against pi v0.87.1."""
from upstream_pin import UPSTREAM
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PIN = 'f07218c4d'
source = subprocess.check_output(['git', 'show', f'{PIN}:packages/coding-agent/src/modes/interactive/theme/theme-controller.ts'], cwd=UPSTREAM, text=True)
tests = subprocess.check_output(['git', 'show', f'{PIN}:packages/coding-agent/test/theme-controller.test.ts'], cwd=UPSTREAM, text=True)
for fragment in ('const autoTheme = parseAutoThemeSetting(themeSetting)', 'if (themeSetting !== undefined)', 'setAutoSync(true)', 'this.applyThemeName(detection.theme)', 'if (detection.confidence === "high")'):
    assert fragment in source, fragment
for title in ('uses the initial theme without persisting it', 'resolves a theme pair and follows terminal appearance changes', 'disables terminal appearance updates when disposed', 'detects the current terminal appearance when selecting a theme pair'):
    assert title in tests, title
expected = [
    'undefined|detect|dark|light',
    'light|explicit:light|light|light',
    'light/dark|auto|dark|light',
    'light/dark/extra|explicit:light/dark/extra|dark|light',
    'missing|explicit:missing|missing|missing',
    'load-light:light:light:False',
    'load-missing:dark:dark:True',
]
for backend, command in [('Bun', ['bun', 'build/theme-controller.js']), ('native1', ['build/theme-controller', '--threads', '1']), ('native4', ['build/theme-controller', '--threads', '4'])]:
    actual = subprocess.check_output(command, cwd=ROOT, text=True, timeout=10).splitlines()
    assert actual == expected, (backend, actual, expected)
    print(f'{backend}: pinned controller setting precedence and dark fallback passed')

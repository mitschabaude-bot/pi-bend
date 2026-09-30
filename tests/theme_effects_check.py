"""Compare terminal effects, nested escapes and line breaks with pinned pi.

Build tests/theme-effects.bend to build/theme-effects and build/theme-effects.js,
and tests/markdown-theme.bend to build/markdown-theme and build/markdown-theme.js.
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
texts = ['', 'plain', '日本語🙂', '\n', '\r', '\r\n', 'a\nb', 'a\r\nb',
         'a\r\nb\nc\rd', '\n\n', 'a\n', '\na', '\r\r\n']
for closing in (22, 23, 24, 27, 29, 0, 39):
    escape = f'\x1b[{closing}m'
    texts.extend([escape, 'a' + escape + 'b', escape + '\r\n' + escape,
                  '\x1b[31mred' + escape + '\nnext'])
texts.extend(['$ cd /tmp && python3 - << \'EOF\'\nprint("hello")\nEOF',
              'a' * 2000 + '\r\n' + 'b' * 2000])
env = dict(os.environ, FORCE_COLOR='3')
expected = subprocess.run(['bun', 'tests/theme-effects-reference.ts', *texts],
                          cwd=ROOT, env=env, check=True, capture_output=True).stdout
for command in (['bun', 'build/theme-effects.js'],
                ['build/theme-effects', '--threads', '1'],
                ['build/theme-effects', '--threads', '4']):
    actual = subprocess.run([*command, *texts], cwd=ROOT, env=env,
                            check=True, capture_output=True).stdout
    assert actual == expected, (command, actual[:200], expected[:200])
    print(f'{command}: {len(texts)} cases, ten theme/Markdown effects each match pi')

expected = subprocess.run(['bun', 'tests/markdown-theme-reference.ts'], cwd=ROOT,
                          env=env, check=True, capture_output=True).stdout
for command in (['bun', 'build/markdown-theme.js'],
                ['build/markdown-theme', '--threads', '1'],
                ['build/markdown-theme', '--threads', '4']):
    actual = subprocess.run(command, cwd=ROOT, env=env,
                            check=True, capture_output=True).stdout
    assert actual == expected, (command, actual[:200], expected[:200])
    print(f'{command}: eight Markdown theme renders match pi')

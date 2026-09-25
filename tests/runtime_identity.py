"""Check the channel-identity compiler primitive and its pure Bend wrappers."""
import os
from pathlib import Path
from bend_toolchain import BEND
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
BEND = BEND
SOURCE = 'packages/runtime/test/identity.bend'

subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', SOURCE, 'build/test-identity'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(BUILD / 'test-identity'), '--threads', threads], check=True, timeout=30)

# Exercise both compiler lowerings. JavaScript is a compiler regression target,
# not a production implementation or adapter used by the native libraries.
subprocess.run([BEND, SOURCE, '-o', str(BUILD / 'test-identity.js')], cwd=ROOT, check=True)
subprocess.run(['node', str(BUILD / 'test-identity.js')], check=True, timeout=30)

invalid = BUILD / 'identity-invalid.bend'
invalid.write_text('''import Base
def invalid(left: Chan(U32), right: Chan(String)) -> Bool:
  Chan.same(U32, left, right)
''')
result = subprocess.run([BEND, str(invalid)], text=True, capture_output=True, timeout=30)
diagnostic = result.stdout + result.stderr
assert result.returncode != 0, 'channel identity accepted incompatible element types'
assert 'Chan(U32)' in diagnostic and 'Chan(String)' in diagnostic, diagnostic
print('PASS native/JS channel identity and rejected mismatched channel types')

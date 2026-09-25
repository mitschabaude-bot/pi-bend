"""Run canonical typed artifact construction checks on native runtime threads."""
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/agent/test/tool-result-message.bend','build/test-tool-result-message'],cwd=ROOT,check=True)
for threads in ('1','4'):
    subprocess.run(['build/test-tool-result-message','--threads',threads],cwd=ROOT,check=True,timeout=30)

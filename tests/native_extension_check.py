"""Run after building with: sh scripts/build-cli.sh build/pi-native-extension-smoke tests/fixtures/native-extension.bend"""

import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "build/pi-native-extension-smoke"
EXTENSION = ROOT / "tests/fixtures/native-extension.bend"


with tempfile.TemporaryDirectory(prefix="pi-native-extension-") as agent_dir:
    env = os.environ | {"PI_CODING_AGENT_DIR": agent_dir, "PI_OFFLINE": "1"}
    for selection in (str(EXTENSION), "tests/fixtures/native-extension.bend"):
        result = subprocess.run(
            [str(BINARY), "--provider", "openai", "--model", "gpt-6-luna", "--api-key", "dummy", "--no-session", "-p", "--no-extensions", "--extension", selection, "/native-check"],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (selection, result.stdout, result.stderr)
        assert result.stderr.strip() == "native-extension-invoked", (selection, result.stderr)
        assert result.stdout == "", (selection, result.stdout)

print("Native extension command: absolute and relative selections passed")

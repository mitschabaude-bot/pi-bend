"""Exercise a native CLI built with tests/fixtures/native-extension.bend linked."""

import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "build/pi-native-extension-smoke"
EXTENSION = ROOT / "tests/fixtures/native-extension.bend"


with tempfile.TemporaryDirectory(prefix="pi-native-extension-") as agent_dir:
    env = os.environ | {"PI_CODING_AGENT_DIR": agent_dir, "PI_OFFLINE": "1"}
    cases = [(str(EXTENSION), True, []), ("tests/fixtures/native-extension.bend", True, []), (None, False, []), ("tests/fixtures/native-extension.bend", False, []), (str(EXTENSION), False, ["-native-extension.bend"])]
    for selection, no_extensions, filters in cases:
        (Path(agent_dir) / "settings.json").write_text(json.dumps({"packages": [str(EXTENSION)], "extensions": filters}))
        args = [str(BINARY), "--provider", "openai", "--model", "gpt-6-luna", "--api-key", "dummy", "--no-session", "-p"]
        if no_extensions:
            args.append("--no-extensions")
        if selection is not None:
            args += ["--extension", selection]
        args.append("/native-check")
        result = subprocess.run(
            args,
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (selection, result.stdout, result.stderr)
        assert result.stderr.splitlines() == ["native-extension-loaded", "native-extension-invoked"], (selection, result.stderr)
        assert result.stdout == "", (selection, result.stdout)

print("Native extension command: explicit, package and deduplicated selections passed")

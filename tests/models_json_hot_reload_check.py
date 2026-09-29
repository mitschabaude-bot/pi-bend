"""Run the upstream #6999 provider replacement and selector-render regression."""

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path


def config(provider: str, model: str) -> str:
    return json.dumps({"providers": {provider: {"baseUrl": "https://example.test/v1", "api": "openai-completions", "apiKey": "test-key", "models": [{"id": model}]}}})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runner", type=Path, required=True)
    parser.add_argument("--threads", type=int, default=1)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "models.json"
        path.write_text(config("old-provider", "old-model"))
        command = (["bun", str(args.runner)] if args.runner.suffix == ".js" else [str(args.runner)]) + [str(path), config("new-provider", "new-model")]
        env = {key: os.environ[key] for key in ("PATH", "HOME", "TMPDIR") if key in os.environ}
        env["BEND_THREADS"] = str(args.threads)
        result = subprocess.run(command, text=True, capture_output=True, timeout=30, env=env, check=True)
        assert result.stdout.strip() == "old/- -> -/new", result.stdout
        assert not result.stderr.strip(), result.stderr
    print(f"ok models.json hot reload and selector render ({args.threads} thread(s))")


if __name__ == "__main__":
    main()

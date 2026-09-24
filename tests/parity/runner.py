#!/usr/bin/env python3
"""Side-by-side acceptance runs of upstream pi and Bend pi.

Both CLIs run in identical tmux terminals with the same HOME, agent dir,
project files, environment and scripted model server. A scenario is a list
of steps; `snap` captures the rendered screen, `wait` records how long the
screen took to show a pattern after the last input. Screens are normalised
(versions, temp paths, ids, durations) and diffed; timings are reported side
by side.

  python3 tests/parity/runner.py [--bend build/pi-cli] [--only NAME] [--keep]
"""
import argparse
import difflib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fake_openai  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WIDTH, HEIGHT = 100, 32
PI_PACKAGE = str(Path(shutil.which("pi") or "pi").resolve().parents[2]) if shutil.which("pi") else "/nonexistent"
# The system prompt names each CLI's package directory, whose length enters
# token estimates. Both CLIs see their package through a link of equal length.
LINKS = {"pi": "/tmp/pi-parity-pkg-u", "bend": "/tmp/pi-parity-pkg-b"}

def package_links():
    for link, target in ((LINKS["pi"], PI_PACKAGE), (LINKS["bend"], str(ROOT))):
        if os.path.islink(link) and os.readlink(link) == target:
            continue
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(target, link)
    return {"PI_PACKAGE_DIR": LINKS["pi"], "PI_BEND_PACKAGE_DIR": LINKS["bend"]}

def unpackage(text):
    for path in (LINKS["pi"], LINKS["bend"], PI_PACKAGE, str(ROOT)):
        text = text.replace(path, "<package>")
    return text

def tmux(*args, check=True):
    # A private server keeps runs off the user's own tmux sessions.
    return subprocess.run(["tmux", "-L", "pi-parity", "-f", "/dev/null", *args], capture_output=True, text=True, check=check).stdout

class Terminal:
    def __init__(self, name, argv, env, cwd):
        self.name = name
        assignments = " ".join(f"{k}={shlex.quote(v)}" for k, v in env.items())
        # A prompt marker after exit shows where the shell prompt would land.
        command = f"cd {shlex.quote(str(cwd))} && env -i {assignments} {' '.join(shlex.quote(a) for a in argv)}; printf \'shell$ \'; sleep 3600"
        tmux("kill-session", "-t", name, check=False)
        tmux("new-session", "-d", "-s", name, "-x", str(WIDTH), "-y", str(HEIGHT), command)
        self.last_input = time.monotonic()

    def screen(self, ansi=False):
        args = ["capture-pane", "-p", "-t", self.name]
        if ansi:
            args.insert(2, "-e")
        return tmux(*args)

    def keys(self, text):
        tmux("send-keys", "-t", self.name, "-l", text)
        self.last_input = time.monotonic()

    def key(self, name):
        tmux("send-keys", "-t", self.name, name)
        self.last_input = time.monotonic()

    def wait(self, pattern, timeout):
        regex = re.compile(pattern, re.M)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if regex.search(self.screen()):
                return time.monotonic() - self.last_input
            time.sleep(0.005)
        return None

    def settle(self, quiet, timeout):
        """Wait until the screen is unchanged for `quiet` seconds."""
        previous, stable_since = None, time.monotonic()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            current = self.screen(ansi=True)
            now = time.monotonic()
            if current != previous:
                previous, stable_since = current, now
            elif now - stable_since >= quiet:
                return
            time.sleep(0.01)

    def close(self):
        tmux("kill-session", "-t", self.name, check=False)

def normalise(text, root):
    # Session directories encode the project path.
    text = text.replace("--" + str(root / "project").strip("/").replace("/", "-") + "--", "<cwd-dir>")
    text = text.replace(str(root), "<root>")
    text = re.sub(r"\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z_", "<stamp>_", text)
    text = re.sub(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "<uuid>", text)
    text = re.sub(r"\b\d+(\.\d+)?(ms|s)\b", "<duration>", text)
    return "\n".join(line.rstrip() for line in text.rstrip("\n").split("\n"))

def working_screen(text, root):
    # Streamed text advances at different rates; compare the editor and footer.
    lines = normalise(text, root).split("\n")[-5:]
    frame = re.sub(r"[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]", "<spinner>", "\n".join(lines))
    return re.sub(r"\d+(?:\.\d+)?%/\d+k", "<usage>", frame)

IDS = {"id", "parentId", "responseId", "toolCallId", "sessionId", "targetId", "firstKeptEntryId", "fromId", "leafId", "entryId"}

def mask(value, key=None, names=None):
    """Clock readings and generated ids vary per run; ids are numbered by first
    appearance so references between entries still compare. Key order is
    JavaScript insertion order, which the port does not reproduce, so keys
    are sorted."""
    names = {} if names is None else names
    if isinstance(value, dict):
        return {k: mask(v, k, names) for k, v in sorted(value.items())}
    if isinstance(value, list):
        return [mask(v, None, names) for v in value]
    if key == "timestamp":
        return "<time>"
    if key in IDS and isinstance(value, str):
        return names.setdefault(value, f"<id{len(names)}>")
    if isinstance(value, str):
        return unpackage(value)
    return value

# Differences recorded in tests/parity/KNOWN.md, masked so a run shows only
# unexplained ones. Request headers Node fetch or the OpenAI SDK add on their
# own (content-length follows the install path in the system prompt).
KNOWN_HEADERS = {"accept-encoding", "accept-language", "connection", "sec-fetch-mode", "content-length",
                 "x-stainless-arch", "x-stainless-lang", "x-stainless-os", "x-stainless-package-version",
                 "x-stainless-runtime", "x-stainless-runtime-version"}
# Upstream providers stream one mutable output object, so pi's early events
# show the final usage and responseId (JavaScript aliasing).
ALIASED_EVENTS = {"message_start", "message_update"}

def mask_known(value):
    if isinstance(value, dict) and value.get("type") in ALIASED_EVENTS:
        value = dict(value)
        for holder in ("message", "assistantMessageEvent"):
            if isinstance(value.get(holder), dict):
                value[holder] = {k: v for k, v in value[holder].items() if k not in ("usage", "responseId")}
        value.pop("usage", None)
    return value

def normalise_events(text):
    """JSON lines compare as values; other lines as text."""
    lines, names = [], {}
    for line in text.split("\n"):
        try:
            lines.append(json.dumps(mask(mask_known(json.loads(line)), None, names), sort_keys=True))
        except ValueError:
            lines.append(line)
    return "\n".join(lines)

def settings_snap(agent, snaps):
    """The agent's settings.json after the run, as a value (pi records e.g.
    lastChangelogVersion on first start)."""
    path = agent / "settings.json"
    if path.exists():
        try:
            snaps["settings"] = json.dumps(json.loads(path.read_text()), indent=1, sort_keys=True)
        except ValueError:
            snaps["settings"] = path.read_text()

def run_side(label, argv, scenario, keep):
    # Equal-length names: the cwd enters the system prompt and token estimates.
    root = Path(tempfile.mkdtemp(prefix=f"pi-parity-{label[0]}-"))
    home = root / "home"
    agent = home / ".pi" / "agent"
    project = root / "project"
    agent.mkdir(parents=True)
    project.mkdir()
    for relative, content in scenario.get("files", {}).items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        # `<root>` in a text file stands for this run's temporary root.
        path.write_bytes(content) if isinstance(content, bytes) else path.write_text(content.replace("<root>", str(root)))
    log = root / "requests.jsonl"
    server = fake_openai.serve(scenario.get("turns", []), str(log))
    port = server.server_address[1]
    provider = {"baseUrl": f"http://127.0.0.1:{port}/v1", **scenario.get("provider", {})}
    (agent / "models.json").write_text(json.dumps({"providers": {"openai": provider}}))
    env = {"HOME": str(home), "PI_CODING_AGENT_DIR": str(agent), "PATH": os.environ["PATH"],
           "TERM": "xterm-256color", "LANG": "C.UTF-8", "OPENAI_API_KEY": "sk-parity", "PI_OFFLINE": "1",
           **package_links(),
           **scenario.get("env", {})}
    snaps, timings = {}, {}
    if scenario.get("process"):
        # Non-interactive modes: exact stdout/stderr of a plain process.
        try:
            # Earlier invocations in the same environment (e.g. create a
            # session before continuing it); their output is not compared.
            for earlier in scenario.get("before", []):
                subprocess.run(argv + earlier, cwd=project, env=env, capture_output=True, text=True, timeout=scenario.get("timeout", 60), stdin=subprocess.DEVNULL)
            started = time.monotonic()
            result = subprocess.run(argv + scenario.get("args", []), cwd=project, env=env, capture_output=True, text=True, timeout=scenario.get("timeout", 60), stdin=subprocess.DEVNULL)
            timings["done"] = time.monotonic() - started
            snaps["stdout"] = normalise(normalise_events(result.stdout), root)
            snaps["stderr"] = normalise(result.stderr, root)
            snaps["exit"] = str(result.returncode)
            # Session files written under the agent directory, as values.
            stored = [path for directory in (agent / "sessions", project / "sessions-here") if directory.exists() for path in sorted(directory.rglob("*.jsonl"))]
            for index, path in enumerate(stored):
                snaps[f"session{index}"] = normalise(normalise_events(path.read_text().rstrip("\n")), root)
        finally:
            server.shutdown()
            logged = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        for request in logged:
            request["headers"] = {k: v for k, v in request.get("headers", {}).items() if k not in KNOWN_HEADERS}
        requests = re.sub(r"127\.0\.0\.1:\d+", "<server>", normalise(json.dumps(logged, indent=1, sort_keys=True), root)) if logged else ""
        requests = unpackage(requests)
        settings_snap(agent, snaps)
        if not keep:
            shutil.rmtree(root, ignore_errors=True)
        return {"snaps": snaps, "timings": timings, "requests": requests}
    terminal = Terminal(f"parity-{label}-{scenario['name']}", argv + scenario.get("args", []), env, project)
    try:
        for step in scenario["steps"]:
            kind = step[0]
            if kind == "keys":
                terminal.keys(step[1])
            elif kind == "key":
                terminal.key(step[1])
            elif kind == "wait":
                timings[step[2] if len(step) > 2 else step[1]] = terminal.wait(step[1], scenario.get("timeout", 30))
            elif kind == "settle":
                terminal.settle(step[1] if len(step) > 1 else 0.5, scenario.get("timeout", 30))
            elif kind == "snap":
                snaps[step[1]] = working_screen(terminal.screen(), root) if step[1] == "working" else normalise(terminal.screen(), root)
    finally:
        terminal.close()
        server.shutdown()
        logged = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        for request in logged:
            request["headers"] = {k: v for k, v in request.get("headers", {}).items() if k not in KNOWN_HEADERS}
        requests = re.sub(r"127\.0\.0\.1:\d+", "<server>", normalise(json.dumps(logged, indent=1, sort_keys=True), root)) if logged else ""
        # The system prompt names the installed package's docs directory.
        requests = unpackage(requests)
        settings_snap(agent, snaps)
        if not keep:
            shutil.rmtree(root, ignore_errors=True)
    return {"snaps": snaps, "timings": timings, "requests": requests}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pi", default=shutil.which("pi") or "pi")
    parser.add_argument("--bend", default=str(ROOT / "build/pi-cli"))
    parser.add_argument("--only")
    parser.add_argument("--keep", action="store_true")
    parser.add_argument("--out", default=str(ROOT / "build/parity"))
    args = parser.parse_args()
    import scenarios
    out = Path(args.out)
    failures = 0
    for scenario in scenarios.SCENARIOS:
        if args.only and scenario["name"] != args.only:
            continue
        upstream = run_side("pi", [args.pi], scenario, args.keep)
        native = run_side("bend", [str(Path(args.bend).resolve())], scenario, args.keep)
        directory = out / scenario["name"]
        directory.mkdir(parents=True, exist_ok=True)
        mismatched = []
        for name, expected in upstream["snaps"].items():
            actual = native["snaps"].get(name, "<missing>")
            (directory / f"{name}.pi.txt").write_text(expected + "\n")
            (directory / f"{name}.bend.txt").write_text(actual + "\n")
            if expected != actual:
                mismatched.append(name)
                diff = difflib.unified_diff(expected.split("\n"), actual.split("\n"), "pi", "bend", lineterm="")
                (directory / f"{name}.diff").write_text("\n".join(diff) + "\n")
        # What each client sent to the model server, normalised like the screens.
        wanted, sent = upstream["requests"], native["requests"]
        if wanted or sent:
            (directory / "requests.pi.json").write_text(wanted + "\n")
            (directory / "requests.bend.json").write_text(sent + "\n")
            if wanted != sent:
                mismatched.append("requests")
                diff = difflib.unified_diff(wanted.split("\n"), sent.split("\n"), "pi", "bend", lineterm="")
                (directory / "requests.diff").write_text("\n".join(diff) + "\n")
        timing = {key: {"pi": upstream["timings"].get(key), "bend": native["timings"].get(key)} for key in upstream["timings"]}
        (directory / "timings.json").write_text(json.dumps(timing, indent=1) + "\n")
        status = "MATCH" if not mismatched else "DIFF " + ",".join(mismatched)
        failures += bool(mismatched)
        rendered = ", ".join(f"{k}: pi {fmt(v['pi'])} / bend {fmt(v['bend'])}" for k, v in timing.items())
        print(f"{scenario['name']:<24} {status}  {rendered}")
    return 1 if failures else 0

def fmt(value):
    return "timeout" if value is None else f"{value * 1000:.0f}ms"

if __name__ == "__main__":
    sys.exit(main())

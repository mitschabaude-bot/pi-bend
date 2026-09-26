#!/usr/bin/env python3
"""The Radius suites over the native Radius provider and OAuth flow.

ai radius-provider.test.ts and radius-oauth.test.ts and coding-agent
radius.test.ts: each case runs tests/radius.bend against a loopback gateway
that answers as the upstream tests' fetch stubs do. The runner sends requests
for the public gateway (https://radius.pi.dev) and the custom test gateway
(http://localhost:8788) to the loopback server and prints each request; the
gateway records the form fields the upstream tests assert.

Usage: python3 tests/radius_check.py [--backend bun|native|all]
"""
import argparse
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tests/radius.bend"


def gateway_config(base_url):
    return {"baseUrl": base_url, "models": [{"id": "auto", "name": "Radius Auto", "reasoning": False, "input": ["text"], "cost": {"input": 1, "output": 2, "cacheRead": 0.1, "cacheWrite": 0.2}, "contextWindow": 128000, "maxTokens": 16384}]}


FRESH = {"baseUrl": "https://radius.example/v1", "models": [
    {"id": "balanced", "name": "Fresh Balanced", "reasoning": True, "input": ["text"], "cost": {"input": 1, "output": 2, "cacheRead": 0.1, "cacheWrite": 0}, "contextWindow": 424242, "maxTokens": 32000},
    {"id": "organization-only", "name": "Organization Only", "reasoning": False, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 128000, "maxTokens": 16000},
]}


class Gateway:
    def __init__(self, config, discovery=None):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def reply(self, body, status=200):
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                outer.requests.append({"method": "GET", "path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}})
                if self.path == "/v1/config":
                    return self.reply(config)
                if self.path == "/v1/oauth":
                    return self.reply(discovery or {"issuer": "https://radius-ui.example"})
                self.reply({"error": "not found"}, 404)

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("content-length", "0"))).decode()
                form = dict(urllib.parse.parse_qsl(raw))
                outer.requests.append({"method": "POST", "path": self.path, "form": form, "headers": {k.lower(): v for k, v in self.headers.items()}})
                if self.path == "/v1/oauth/device":
                    return self.reply({"device_code": "device-code", "user_code": "ABCD-1234", "verification_uri": "https://radius-ui.example/pair", "expires_in": 600, "interval": 5})
                if self.path == "/v1/oauth/token" and form.get("grant_type") == "refresh_token":
                    return self.reply({"access_token": "new-access", "refresh_token": "new-refresh", "expires_in": 3600})
                if self.path == "/v1/oauth/token":
                    return self.reply({"access_token": "access-token", "refresh_token": "refresh-token", "expires_in": 3600, "scope": "gateway offline_access"})
                self.reply({"error": "not found"}, 404)

            def log_message(self, *_):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def expect(ok, value):
    if not ok:
        raise AssertionError(value)


def device_forms(requests, output):
    device, token = requests
    expect(device["form"] == {"client_id": "pi-gateway", "scope": "gateway offline_access"}, device)
    expect(token["form"] == {"grant_type": "urn:ietf:params:oauth:grant-type:device_code", "client_id": "pi-gateway", "device_code": "device-code"}, token)
    expect(device["headers"].get("content-type") == "application/x-www-form-urlencoded" and device["headers"].get("accept") == "application/json", device)
    credential = next(line for line in output.splitlines() if line.startswith("credential ")).split(" ", 4)
    low, high = (float(v) for v in next(line for line in output.splitlines() if line.startswith("expires-window ")).split(" ")[1:])
    expect(credential[1:3] == ["access-token", "refresh-token"] and low <= float(credential[3]) <= high, credential)
    expect(json.loads(credential[4]) == {"scope": "gateway offline_access"}, credential)


def refresh_form(requests, output):
    expect(requests[0]["form"] == {"grant_type": "refresh_token", "client_id": "pi-gateway", "refresh_token": "old-refresh"}, requests)


# (suite, name, mode, gateway config, models.json, check(requests, output))
CASES = [
    ("radius-provider", "ships a static public catalog for the default gateway", "static", FRESH, None, None),
    ("radius-provider", "does not apply the public Radius catalog to custom gateways", "custom", FRESH, None, None),
    ("radius-provider", "overlays refreshed models on the static public catalog", "overlay", FRESH, None, None),
    ("radius-provider", "overlays a cached effective catalog without network access", "cached", FRESH, None, None),
    ("radius-oauth", "uses gateway endpoints directly for device login", "device", FRESH, None, device_forms),
    ("radius-oauth", "refreshes directly through the gateway without discovery", "refresh", FRESH, None, refresh_form),
    ("radius-oauth", "discovers only the interactive browser authorization endpoint", "discovery", FRESH, None, None),
    ("radius", "restores the legacy credential catalog without network access", "legacy", gateway_config("https://radius.example.com/v1"), None, None),
    ("radius", "fetches and stores the catalog for configured Radius auth", "stored", gateway_config("https://radius.example.com/v1"), None, None),
    ("radius", "does not refresh catalogs over the network by default", "offline", gateway_config("https://radius.example.com/v1"), None, None),
    ("radius", "does not fetch or make Radius models available without configured auth", "unconfigured", gateway_config("https://radius.example.com/v1"), None, None),
    ("radius", "supports custom Radius gateways from models.json", "custom-gateway", gateway_config("http://localhost:8788/v1"), {"providers": {"radius-dev": {"name": "Radius (dev)", "baseUrl": "http://localhost:8788", "oauth": "radius"}}}, None),
    ("radius", "requires baseUrl for custom Radius gateways", "requires-base-url", FRESH, {"providers": {"radius-dev": {"oauth": "radius"}}}, None),
]


def browser_case(command, env, callback_query):
    """Browser login: follow the auth_url event to the local callback."""
    gateway = Gateway(FRESH, {"authorizationEndpoint": "https://radius-ui.example/authorize?stale=1#frag"})
    try:
        process = subprocess.Popen([*command, "browser", gateway.url], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        lines, answers = [], []
        for line in process.stdout:
            lines.append(line.rstrip("\n"))
            if line.startswith("event auth_url "):
                url = urllib.parse.urlsplit(line.split(" ", 2)[2].strip())
                query = dict(urllib.parse.parse_qsl(url.query))
                expect(url.netloc == "radius-ui.example" and url.path == "/authorize" and url.fragment == "frag", url)
                expect({k: query[k] for k in ("response_type", "client_id", "redirect_uri", "scope", "code_challenge_method", "handoff")} == {"response_type": "code", "client_id": "pi-gateway", "redirect_uri": "http://127.0.0.1:1456/oauth/callback", "scope": "gateway offline_access", "code_challenge_method": "S256", "handoff": "url"} and "stale" not in query, query)
                for extra in callback_query(query):
                    for _ in range(50):
                        try:
                            with urllib.request.urlopen("http://127.0.0.1:1456/oauth/callback?" + urllib.parse.urlencode(extra)) as response:
                                answers.append(response.status)
                            break
                        except urllib.error.HTTPError as error:
                            answers.append(error.code)
                            break
                        except OSError:
                            time.sleep(0.1)
        process.wait(timeout=120)
        return process.returncode, lines, answers, gateway.requests, process.stderr.read()
    finally:
        gateway.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    parser.add_argument("--only")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="radius-") as directory:
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "radius.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "radius"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        home = pathlib.Path(directory) / "home"
        home.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith("RADIUS_") and k not in ("PI_OFFLINE", "PI_CODING_AGENT_DIR")}
        env.update({"HOME": str(home), "PI_CODING_AGENT_DIR": str(home / "agent")})
        for backend, command in commands:
            for suite, name, mode, config, models, check in CASES:
                if args.only and args.only not in name:
                    continue
                gateway = Gateway(config)
                try:
                    argv = [*command, mode, gateway.url]
                    if models is not None:
                        path = pathlib.Path(directory) / "models.json"
                        path.write_text(json.dumps(models))
                        argv.append(str(path))
                    result = subprocess.run(argv, capture_output=True, text=True, timeout=300, env=env)
                    expect(result.returncode == 0 and f"PASS {name}" in result.stdout, (backend, name, result.returncode, result.stdout[-3000:], result.stderr[-3000:]))
                    if check:
                        check(gateway.requests, result.stdout)
                finally:
                    gateway.close()
                print(f"PASS {backend}: {suite}: {name}")
            if not args.only or "browser" in args.only:
                code, lines, answers, requests, err = browser_case(command, env, lambda q: [{"code": "c", "state": "wrong"}, {"state": q["state"]}, {"code": "auth-code", "state": q["state"]}])
                expect(code == 0 and "PASS browser login exchanges the callback code" in lines and answers == [400, 400, 200], (lines, answers, err[-2000:]))
                token = [r for r in requests if r["path"] == "/v1/oauth/token"][0]
                expect(token["form"]["grant_type"] == "authorization_code" and token["form"]["code"] == "auth-code" and token["form"]["redirect_uri"] == "http://127.0.0.1:1456/oauth/callback" and len(token["form"]["code_verifier"]) >= 43, token)
                expect([r["path"] for r in requests] == ["/v1/oauth", "/v1/oauth/token"], requests)
                print(f"PASS {backend}: native: browser login rejects a state mismatch and a missing code, then exchanges the callback code")
                code, lines, answers, requests, err = browser_case(command, env, lambda q: [{"error": "access_denied", "error_description": "Denied", "state": q["state"]}])
                expect(code == 0 and any(line == "credential error OAuth callback did not complete." for line in lines) and answers == [400], (lines, answers, err[-2000:]))
                print(f"PASS {backend}: native: a callback error ends browser login")


if __name__ == "__main__":
    main()

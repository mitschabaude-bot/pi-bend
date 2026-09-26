#!/usr/bin/env python3
"""upstream openrouter-images.test.ts over the native OpenRouter images API.

Each case runs packages/ai/test/openrouter-images.bend against a loopback
server that answers as the upstream test's OpenAI mock does (or with the
responses a further case needs), asserts the upstream expectations, and
compares the payload onPayload saw, the onResponse value, the result (without
its timestamp) and the requests the server received with upstream images.ts
driving the pinned OpenAI SDK against the same server
(packages/ai/test/openrouter-images-oracle.ts). Request headers are compared
for the members pi sets; the SDK's own identity headers (User-Agent,
X-Stainless-*) are not modelled natively.

Adaptation: upstream's mock throws `new Error("Request aborted")` for an
aborted signal; against the real SDK the message is the SDK's, which the
native result matches.
"""
from upstream_pin import UPSTREAM
import argparse
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "packages/ai/test/openrouter-images.bend"
ORACLE = ROOT / "packages/ai/test/openrouter-images-oracle.ts"
COMPARED_HEADERS = ("authorization", "content-type", "accept", "http-referer", "x-title", "x-custom")

# The upstream mock's response.
IMAGE_RESPONSE = {
    "id": "img-1",
    "usage": {"prompt_tokens": 12, "completion_tokens": 34, "prompt_tokens_details": {"cached_tokens": 0}},
    "choices": [{"message": {"content": "Here is your image.", "images": [{"image_url": "data:image/png;base64,ZmFrZS1wbmc="}]}}],
}


class Server:
    """Answers the n-th POST with the n-th scripted (status, headers, body), repeating the last."""

    def __init__(self, responses):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("content-length", "0"))).decode()
                outer.requests.append({"method": "POST", "url": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": json.loads(raw) if raw else None})
                status, headers, body = responses[min(len(outer.requests), len(responses)) - 1]
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                self.send_response(status)
                for name, value in headers.items():
                    self.send_header(name, value)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *_):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_port}/api/v1"

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()


def parse(output):
    lines = {"payload": [], "response": [], "result": [], "thrown": [], "model": [], "providers": []}
    for line in output.splitlines():
        kind, _, rest = line.partition(" ")
        lines[kind].append(rest if kind == "thrown" else json.loads(rest))
    return lines


def run(command, mode, base):
    result = subprocess.run([*command, mode, base], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise AssertionError((command, mode, result.returncode, result.stdout, result.stderr))
    return parse(result.stdout)


def oracle(mode, base):
    result = subprocess.run(["node", str(ORACLE), mode, base], capture_output=True, text=True, timeout=60, env=dict(os.environ, PI_MONO=str(UPSTREAM)))
    if result.returncode != 0:
        raise AssertionError(("oracle", mode, result.stdout, result.stderr))
    return parse(result.stdout)


def requests_trace(requests):
    return [{"method": r["method"], "url": r["url"], "body": r["body"], "headers": {k: r["headers"].get(k) for k in COMPARED_HEADERS}} for r in requests]


def normalized(lines):
    """Response headers without the per-request Date."""
    responses = [{**r, "headers": {k: v for k, v in r["headers"].items() if k != "date"}} for r in lines["response"]]
    return {**lines, "response": responses}


def only(lines, kind):
    assert len(lines[kind]) == 1, lines
    return lines[kind][0]


# Cases: (suite case name, mode, responses, check(lines, requests))

def text_and_image(lines, requests):
    output = only(lines, "result")
    assert output["stopReason"] == "stop" and output["responseId"] == "img-1", output
    assert output["output"][0] == {"type": "text", "text": "Here is your image."}, output
    assert output["output"][1] == {"type": "image", "mimeType": "image/png", "data": "ZmFrZS1wbmc="}, output
    params = requests[0]["body"]
    assert params["stream"] is False and params["modalities"] == ["image", "text"], params
    assert params["messages"][0]["content"][0] == {"type": "text", "text": "Generate a dog"}, params
    assert requests[0]["headers"]["http-referer"] == "https://example.com"
    assert requests[0]["url"] == "/api/v1/chat/completions"


def aborted(lines, requests):
    output = only(lines, "result")
    assert output["stopReason"] == "aborted" and output["errorMessage"], output
    assert requests == [], requests


def resolves(lines, requests):
    output = only(lines, "result")
    assert any(item["type"] == "image" for item in output["output"]), output


def usage(lines, requests):
    output = only(lines, "result")
    assert output["usage"]["cacheRead"] == 20 and output["usage"]["cacheWrite"] == 10 and output["usage"]["input"] == 70, output


def failed(expected):
    def check(lines, requests):
        output = only(lines, "result")
        assert output["stopReason"] == "error" and expected in output["errorMessage"], output
    return check


def headers(lines, requests):
    sent = requests[0]["headers"]
    assert "http-referer" not in sent and sent["x-title"] == "pi-bend" and sent["x-custom"] == "value", sent


def replaced(lines, requests):
    assert requests[0]["body"]["seed"] == 7 and requests[0]["body"]["messages"][0]["content"] == "replaced prompt", requests


def retried(lines, requests):
    assert len(requests) == 2 and only(lines, "result")["stopReason"] == "stop", (lines, requests)


def thrown(expected):
    def check(lines, requests):
        assert lines["thrown"] == [expected] and requests == [], lines
    return check


def variants(lines, requests):
    output = only(lines, "result")["output"]
    assert [item.get("mimeType") for item in output] == ["image/webp", "image/jpeg"], output


OK = [(200, {}, IMAGE_RESPONSE)]
VARIANTS = {
    "id": "img-2",
    "choices": [{"message": {"content": "", "images": [
        {"image_url": {"url": "data:image/webp;base64,d2VicA=="}},
        {"image_url": "https://example.com/not-inline.png"},
        {"image_url": "data:image/png,notbase64"},
        {"image_url": "data:;base64,ZW1wdHk="},
        {"image_url": "data:image/gif;base64,"},
        {"image_url": "data:image/png;base64,bGluZQ==\nbGluZQ=="},
        {},
        {"image_url": "data:image/jpeg;base64,anBlZw=="},
    ]}}],
}
CASES = [
    ("returns text plus images in final output", "text-and-image", OK, text_and_image),
    ("passes through abort signal and returns aborted result", "abort", OK, aborted),
    ("generateImages resolves the final assistant images result", "flux", OK, resolves),
    ("catalog model with an image input", "catalog", OK, resolves),
    ("cached and written prompt tokens are priced", "usage", [(200, {}, {"id": "img-3", "usage": {"prompt_tokens": 100, "completion_tokens": 50, "prompt_tokens_details": {"cached_tokens": 30, "cache_write_tokens": 10}}, "choices": [{"message": {"content": None, "images": [{"image_url": "data:image/png;base64,eA=="}]}}]})], usage),
    ("only inline data-URL images are kept", "variants", [(200, {}, VARIANTS)], variants),
    ("a missing api key is an error result", "no-key", OK, failed("No API key for provider: openrouter")),
    ("an HTTP error is an error result", "http-error", [(400, {}, {"error": {"message": "Invalid model", "code": 400}})], failed("Invalid model")),
    ("a response without choices is an error result", "no-choices", [(200, {}, {"id": "img-4"})], failed("Cannot read properties of undefined")),
    ("an empty choice list has no output", "empty", [(200, {}, {"id": "img-5", "choices": []})], lambda lines, requests: None),
    ("request headers overlay the model headers", "headers", OK, headers),
    ("onPayload replaces the params", "replace", OK, replaced),
    ("a retryable status is retried", "retry", [(429, {"retry-after": "0"}, {"error": {"message": "rate limited"}}), (200, {}, IMAGE_RESPONSE)], retried),
    ("an api without a registered provider rejects", "unregistered", OK, thrown("No API provider registered for api: other-images")),
]


MODELS_SOURCE = ROOT / "packages/ai/test/images-models.bend"


def images_models_command(backend, directory, args):
    if backend == "bun":
        output = pathlib.Path(directory) / "images-models.js"
        if not output.exists():
            subprocess.run(["bun", args.toolchain, str(MODELS_SOURCE), "-o", str(output)], cwd=ROOT, check=True)
        return ["bun", str(output)]
    output = pathlib.Path(directory) / "images-models"
    if not output.exists():
        subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(MODELS_SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
    return [str(output), "--threads", "1" if backend == "native1" else "4"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    parser.add_argument("--only")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="openrouter-images-") as directory:
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "openrouter-images.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "openrouter-images"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        for backend, command in commands:
            for name, mode, responses, check in CASES:
                if args.only and args.only not in name:
                    continue
                server = Server(responses)
                with server as base:
                    native = run(command, mode, base)
                check(native, server.requests)
                reference_server = Server(responses)
                with reference_server as base:
                    reference = oracle(mode, base)
                check(reference, reference_server.requests)
                assert normalized(native) == normalized(reference), (name, native, reference)
                assert requests_trace(server.requests) == requests_trace(reference_server.requests), (name, requests_trace(server.requests), requests_trace(reference_server.requests))
                print(f"PASS {backend}: {name}")
            # image-models.generated.ts: every model of the generated catalog.
            dumped = subprocess.run([*command, "catalog-dump"], capture_output=True, text=True, timeout=120)
            assert dumped.returncode == 0, dumped
            native = parse(dumped.stdout)
            upstream = json.loads(subprocess.run(["node", "-e", 'import(process.env.PI_MONO + "/packages/ai/src/image-models.generated.ts").then(m => console.log(JSON.stringify(m.IMAGE_MODELS)))'], capture_output=True, text=True, timeout=60, check=True, env=dict(os.environ, PI_MONO=str(UPSTREAM))).stdout)
            assert native["providers"] == [list(upstream)], native["providers"]
            assert native["model"] == list(upstream["openrouter"].values()), "image catalog differs"
            print(f"PASS {backend}: image catalog ({len(native['model'])} models) equals image-models.generated.ts")
            # images-models.test.ts
            models = subprocess.run(images_models_command(backend, directory, args), capture_output=True, text=True, timeout=300)
            assert models.returncode == 0, models
            for line in models.stdout.splitlines():
                print(f"{line.split(' ', 1)[0]} {backend}: ImagesModels: {line.split(' ', 1)[1]}")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Upstream llama load/download SSE fixtures plus fallback and cancellation.

Build tests/llama-client-stream.bend to build/llama-client-stream(.js).
The oracle executes the pinned TS client; each lane gets its own router.
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


class Router(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def json(self, value, status=200):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def event_stream(self):
        if self.server.mode == "fallback":
            self.json({}, 403)
            return
        events = queue.Queue()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        with self.server.lock:
            self.server.streams.add(events)
        self.server.ready.set()
        try:
            while not self.server.stopped.is_set():
                try:
                    event = events.get(timeout=.02)
                    payload = json.dumps(event, ensure_ascii=False, indent=1)
                    frame = ("event: update\r\n" + "\r\n".join("data: " + line for line in payload.splitlines()) + "\r\n\r\n").encode()
                except queue.Empty:
                    frame = b": heartbeat\r\n\r\n"
                # Exercise fragmented UTF-8, CRLF and multi-line data frames.
                for start in range(0, len(frame), 7):
                    self.wfile.write(frame[start:start + 7])
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with self.server.lock:
                self.server.streams.discard(events)

    def do_GET(self):
        assert self.headers.get("Authorization") == "Bearer test-key"
        if self.path == "/models/sse":
            self.event_stream()
        elif self.path.startswith("/models"):
            status = {"value": self.server.status}
            if self.server.mode == "failure" and self.server.status == "unloaded":
                status.update(failed=True, exit_code=7)
            self.json({"data": [{"id": self.server.model, "status": status}]})
        else:
            self.json({}, 404)

    def finish_operation(self):
        if self.server.mode == "fallback":
            self.server.status = "loaded"
            return
        assert self.server.ready.wait(2), "event subscription did not open"
        time.sleep(.02)
        def send(event):
            with self.server.lock:
                for events in self.server.streams:
                    events.put(event)
        # Other-model events must not affect this operation.
        send({"model": "other", "event": "status_change", "data": {"status": "unloaded"}})
        if self.server.mode == "download":
            send({"model": self.server.model, "event": "download_progress", "data": {"progress": {"https://example/雪.gguf": {"done": 512, "total": 1024}}}})
            self.server.status = "unloaded"
            send({"model": self.server.model, "event": "download_finished", "data": {}})
        elif self.server.mode == "failure":
            self.server.status = "unloaded"
            send({"model": self.server.model, "event": "status_change", "data": {"status": "unloaded"}})
        elif self.server.mode != "cancel":
            send({"model": self.server.model, "event": "status_change", "data": {"status": "loading", "progress": {"stages": ["text_model", "mmproj_model"], "current": "text_model", "value": .5}}})
            self.server.status = "loaded"
            send({"model": self.server.model, "event": "status_change", "data": {"status": "loaded"}})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert body == {"model": self.server.model}
        assert self.headers.get("Authorization") == "Bearer test-key"
        self.server.status = "downloading" if self.server.mode == "download" else "loading"
        self.json({"success": True})
        worker = threading.Thread(target=self.finish_operation, daemon=True)
        self.server.jobs.append(worker)
        worker.start()


def run(argv, mode, env=None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Router)
    server.mode = mode
    server.model = "owner/repo:Q4_K_M" if mode == "download" else "test-model"
    server.status = "unloaded"
    server.lock = threading.Lock()
    server.streams = set()
    server.jobs = []
    server.ready = threading.Event()
    server.stopped = threading.Event()
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        base = f"http://127.0.0.1:{server.server_port}"
        result = subprocess.run([*argv, base, mode], cwd=ROOT, env=env, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, (argv, mode, result.stdout, result.stderr)
        assert not result.stderr, result.stderr
        deadline = time.monotonic() + 1
        while server.streams and time.monotonic() < deadline:
            time.sleep(.01)
        assert not server.streams, (mode, "event stream left open")
        return result.stdout
    finally:
        server.stopped.set()
        for job in server.jobs:
            job.join(timeout=3)
        server.shutdown()
        server.server_close()
        worker.join()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    lanes = []
    if args.backend in ("bun", "all"):
        lanes.append(("bun", ["bun", "build/llama-client-stream.js"], os.environ.copy()))
    if args.backend in ("native", "all"):
        lanes.extend((f"native{n}", [str(ROOT / "build/llama-client-stream")], {**os.environ, "BEND_THREADS": str(n)}) for n in (1, 4))
    # Pi runs on Node; its default AbortError wording differs from Bun.
    for mode in ("load", "download", "failure", "fallback", "cancel"):
        expected = run(["node", "tests/llama_client_stream_reference.ts"], mode)
        if mode == "load":
            assert "Loading text model|0.25|-" in expected, expected
        if mode == "download":
            assert "Downloading model|0.5|512 B / 1.00 KiB" in expected, expected
        for name, argv, env in lanes:
            actual = run(argv, mode, env)
            assert actual == expected, (name, mode, actual, expected)
            print(f"{name}: {mode} result/progress and closed event stream MATCH")


if __name__ == "__main__":
    main()

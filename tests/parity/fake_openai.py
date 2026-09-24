#!/usr/bin/env python3
"""A scripted OpenAI Responses endpoint for side-by-side runs of pi and Bend pi.

Each POST /responses consumes the next scripted turn and streams it as SSE in
the event shapes upstream's openai-responses parser reads. A turn is
  {"text": "...", "chunks": N, "delay_ms": D}          assistant text
  {"tool": {"name": "...", "arguments": {...}}}         one function call
  {"usage": {"input": I, "output": O}}                  optional, with either
  {"status": 500, "error": {...}}                       an HTTP error response
  {"failed": {"code": "...", "message": "..."}}         a response.failed event
Requests are appended as JSON lines to the log path so scenarios can compare
what each client sent.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Script:
    def __init__(self, turns, log_path):
        self.turns = list(turns)
        self.lock = threading.Lock()
        self.count = 0
        self.log_path = log_path

    def next(self, body, path, headers):
        with self.lock:
            index = self.count
            self.count += 1
            if self.log_path:
                with open(self.log_path, "a") as log:
                    log.write(json.dumps({"index": index, "path": path, "headers": headers, "body": body}) + "\n")
            return self.turns[index] if index < len(self.turns) else {"text": "(script exhausted)"}

def events(turn, index):
    rid = f"resp_{index}"
    usage = turn.get("usage", {"input": 100, "output": 10})
    yield {"type": "response.created", "response": {"id": rid, "status": "in_progress"}}
    if "failed" in turn:
        yield {"type": "response.failed", "response": {"id": rid, "status": "failed", "error": turn["failed"]}}
        return
    if "tool" in turn:
        call = turn["tool"]
        arguments = json.dumps(call.get("arguments", {}))
        item = {"type": "function_call", "id": f"fc_{index}", "call_id": f"call_{index}", "name": call["name"], "arguments": ""}
        yield {"type": "response.output_item.added", "output_index": 0, "item": item}
        yield {"type": "response.function_call_arguments.delta", "output_index": 0, "item_id": item["id"], "delta": arguments}
        yield {"type": "response.function_call_arguments.done", "output_index": 0, "item_id": item["id"], "arguments": arguments}
        yield {"type": "response.output_item.done", "output_index": 0, "item": {**item, "arguments": arguments, "status": "completed"}}
    else:
        text = turn.get("text", "")
        chunks = max(1, int(turn.get("chunks", 1)))
        size = max(1, -(-len(text) // chunks))
        item = {"type": "message", "id": f"msg_{index}", "role": "assistant", "status": "in_progress", "content": []}
        yield {"type": "response.output_item.added", "output_index": 0, "item": item}
        yield {"type": "response.content_part.added", "output_index": 0, "item_id": item["id"], "content_index": 0, "part": {"type": "output_text", "text": ""}}
        for start in range(0, len(text), size):
            yield {"type": "response.output_text.delta", "output_index": 0, "item_id": item["id"], "content_index": 0, "delta": text[start:start + size], "_delay": turn.get("delay_ms", 0)}
        yield {"type": "response.output_text.done", "output_index": 0, "item_id": item["id"], "content_index": 0, "text": text}
        done = {**item, "status": "completed", "content": [{"type": "output_text", "text": text, "annotations": []}]}
        yield {"type": "response.output_item.done", "output_index": 0, "item": done}
    total = usage["input"] + usage["output"]
    yield {"type": "response.completed", "response": {"id": rid, "status": "completed",
           "usage": {"input_tokens": usage["input"], "output_tokens": usage["output"], "total_tokens": total,
                     "input_tokens_details": {"cached_tokens": 0}, "output_tokens_details": {"reasoning_tokens": 0}}}}

def handler(script):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
            pass

        def do_POST(self):
            length = int(self.headers.get("content-length", "0"))
            raw = self.rfile.read(length)
            try:
                body = json.loads(raw)
            except ValueError:
                body = raw.decode(errors="replace")
            headers = {name.lower(): value for name, value in self.headers.items()}
            turn = script.next(body, self.path, headers)
            if "status" in turn:
                # A plain HTTP error response.
                payload = json.dumps(turn.get("error", {"error": {"message": "scripted failure", "type": "server_error"}})).encode()
                self.send_response(turn["status"])
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.send_header("cache-control", "no-cache")
            self.send_header("transfer-encoding", "chunked")
            self.end_headers()
            for event in events(turn, script.count - 1):
                delay = event.pop("_delay", 0)
                if delay:
                    time.sleep(delay / 1000)
                payload = f"event: {event['type']}\ndata: {json.dumps(event)}\n\n".encode()
                self.wfile.write(f"{len(payload):x}\r\n".encode() + payload + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()

    return Handler

def serve(turns, log_path=None, port=0):
    server = ThreadingHTTPServer(("127.0.0.1", port), handler(Script(turns, log_path)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server

if __name__ == "__main__":
    turns = json.load(open(sys.argv[1]))
    server = serve(turns, sys.argv[2] if len(sys.argv) > 2 else None, int(sys.argv[3]) if len(sys.argv) > 3 else 0)
    print(server.server_address[1], flush=True)
    threading.Event().wait()

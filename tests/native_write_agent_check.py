"""Native model -> canonical write tool -> filesystem -> model integration."""

import argparse
import json
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import socket
import subprocess
import tempfile
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from native_agent_check import request, response, completion
from fetch_https_check import trusted_context, ROOT

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("backend", choices=["bun", "native-1", "native-4"])
parser.add_argument("--prefix", default="build/native-write-agent")
args = parser.parse_args()
TARGET = "nested/feature.bend"
CONTENT = "import Base\n\ndef twice(value: U32) -> U32:\n  (value * 2 : U32)\n"
PROMPT = "Write the requested file, then report the result."


def serve(listener, context, directory, scenario):
    valid = scenario == "success"
    parameters = {"path": TARGET, "content": CONTENT} if valid else {"path": TARGET}
    call = {
        "type": "function_call",
        "id": "fc-write",
        "call_id": "call-write",
        "name": "write",
        "arguments": "",
    }
    for turn in range(2):
        raw, _ = listener.accept()
        raw.settimeout(180)
        with context.wrap_socket(raw, server_side=True) as stream:
            value = request(stream, "write")
            assert value["tools"][0]["parameters"]["required"] == ["path", "content"]
            if scenario == "HTTP failure":
                body = b'{"error":{"message":"fixture authorization rejected"}}'
                stream.sendall(
                    b"HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\n"
                    + f"Content-Length: {len(body)}\r\n\r\n".encode()
                    + body
                )
                assert stream.recv(1) == b"", "provider did not retire failed response"
                return
            if turn == 0:
                assert any(
                    (
                        item.get("role") == "user" and item["content"][0]["text"] == PROMPT
                        for item in value["input"]
                    )
                )
                encoded = json.dumps(parameters, ensure_ascii=False, separators=(",", ":"))
                response(
                    stream,
                    [
                        {"type": "response.created", "response": {"id": "resp-write"}},
                        {
                            "type": "response.output_item.added",
                            "output_index": 0,
                            "item": call,
                        },
                        {
                            "type": "response.function_call_arguments.delta",
                            "output_index": 0,
                            "delta": encoded,
                        },
                        {
                            "type": "response.function_call_arguments.done",
                            "output_index": 0,
                            "arguments": encoded,
                        },
                        {
                            "type": "response.output_item.done",
                            "output_index": 0,
                            "item": {**call, "arguments": encoded},
                        },
                        completion("resp-write"),
                    ],
                )
            else:
                outputs = [item for item in value["input"] if item.get("type") == "function_call_output"]
                calls = [item for item in value["input"] if item.get("type") == "function_call"]
                assert len(outputs) == len(calls) == 1
                assert outputs[0]["call_id"] == calls[0]["call_id"] == "call-write"
                assert calls[0]["name"] == "write"
                assert json.loads(calls[0]["arguments"]) == parameters
                if valid:
                    assert outputs[0]["output"] == "Successfully wrote to " + TARGET
                    assert (directory / TARGET).read_text() == CONTENT
                else:
                    assert "Validation failed" in outputs[0]["output"]
                    assert not (directory / "nested").exists()
                item = {
                    "type": "message",
                    "id": "msg-final",
                    "role": "assistant",
                    "content": [],
                }
                response(
                    stream,
                    [
                        {"type": "response.created", "response": {"id": "resp-final"}},
                        {
                            "type": "response.output_item.added",
                            "output_index": 0,
                            "item": item,
                        },
                        {
                            "type": "response.output_text.delta",
                            "output_index": 0,
                            "delta": "done",
                        },
                        {
                            "type": "response.output_item.done",
                            "output_index": 0,
                            "item": {
                                **item,
                                "content": [{"type": "output_text", "text": "done"}],
                            },
                        },
                        completion("resp-final"),
                    ],
                )


for scenario in ["success", "validation rejection", "HTTP failure"]:
    valid = scenario == "success"
    with (
        tempfile.TemporaryDirectory(prefix="pi-native-write-") as folder,
        ThreadPoolExecutor(max_workers=1) as executor,
    ):
        directory = Path(folder)
        context, root = trusted_context(directory, "localhost")
        root_path = directory / "root.pem"
        root_path.write_bytes(x509.load_der_x509_certificate(root).public_bytes(serialization.Encoding.PEM))
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(2)
            listener.settimeout(180)
            server = executor.submit(serve, listener, context, directory, scenario)
            prefix = ROOT / args.prefix
            command = (
                ["bun", str(prefix) + ".js"]
                if args.backend == "bun"
                else [str(prefix), "--threads", args.backend[-1]]
            )
            run = subprocess.run(
                command
                + [
                    str(root_path),
                    "fixture-model",
                    f"https://localhost:{listener.getsockname()[1]}/v1",
                    PROMPT,
                    str(directory),
                ],
                cwd=ROOT,
                env={**os.environ, "OPENAI_API_KEY": "fixture-key"},
                capture_output=True,
                text=True,
                timeout=360,
            )
            server.result(timeout=10)
            if scenario == "HTTP failure":
                assert run.returncode != 0, run.stdout
                assert "fixture authorization rejected" in run.stdout + run.stderr
                assert "executions 0" in run.stdout.splitlines()
                assert "event agent_end" in run.stdout.splitlines()
                assert not (directory / "nested").exists()
                print(f"{args.backend}: native model/write/filesystem/{scenario} PASS", flush=True)
                continue
            assert run.returncode == 0, (run.stdout[-3000:], run.stderr[-2000:])
            lines = run.stdout.splitlines()
            assert f"executions {int(valid)}" in lines and lines[-1] == "answer done", lines
            events = [line.removeprefix("event ") for line in lines if line.startswith("event ")]
            assert events[0] == "agent_start" and events[-1] == "agent_end"
            assert events.count("turn_start") == events.count("turn_end") == 2
            if valid:
                second = events.index("turn_start", events.index("turn_start") + 1)
                assert events.index("tool_execution_start") < events.index("tool_execution_end") < second
        print(
            f"{args.backend}: native model/write/filesystem/{scenario} PASS",
            flush=True,
        )

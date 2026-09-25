#!/usr/bin/env python3
"""Differential Anthropic request and SSE checks against pi-mono f07218c4d."""
from upstream_pin import UPSTREAM
import argparse
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM_COMMIT = "f07218c4d4bbc12bef056a7058c3dd49dfe41abe"


def execute(argv, *, env=None, cwd=ROOT):
    result = subprocess.run(argv, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, argv[:3]))}: {result.stdout}{result.stderr}")
    return result.stdout.strip()


def events():
    start = lambda ident, model="claude-opus-5", usage=None: {"type": "message_start", "message": {"id": ident, "model": model, "usage": usage or {"input_tokens": 12, "output_tokens": 0}}}
    return {
        "text": [start("msg_test"), {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}, {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}, {"type": "content_block_stop", "index": 0}, {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 5}}, {"type": "message_stop"}],
        "thinking_tool": [start("msg_tool", "kimi-for-coding", {"input_tokens": 100, "output_tokens": 0, "cache_read_input_tokens": 3, "cache_creation_input_tokens": 4}), {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "reason", "signature": "sig"}}, {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "ing"}}, {"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "-tail"}}, {"type": "content_block_stop", "index": 0}, {"type": "content_block_start", "index": 2, "content_block": {"type": "tool_use", "id": "toolu_2", "name": "lookup", "input": {}}}, {"type": "content_block_delta", "index": 2, "delta": {"type": "input_json_delta", "partial_json": '{"value":'}}, {"type": "content_block_delta", "index": 2, "delta": {"type": "input_json_delta", "partial_json": '"42"}'}}, {"type": "content_block_stop", "index": 2}, {"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 20, "output_tokens_details": {"thinking_tokens": 8}}}, {"type": "message_stop"}],
        "redacted": [start("msg_redacted", usage={"input_tokens": 7, "output_tokens": 0}), {"type": "content_block_start", "index": 0, "content_block": {"type": "redacted_thinking", "data": "opaque"}}, {"type": "content_block_stop", "index": 0}, {"type": "message_delta", "delta": {"stop_reason": "max_tokens"}, "usage": {"output_tokens": 10}}, {"type": "message_stop"}],
        "missing_stop": [start("msg_missing"), {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": "partial"}}, {"type": "content_block_stop", "index": 0}],
        "refusal": [start("msg_refusal", usage={"input_tokens": 1, "output_tokens": 0}), {"type": "message_delta", "delta": {"stop_reason": "refusal", "stop_details": {"explanation": "Policy refusal"}}, "usage": {"output_tokens": 1}}, {"type": "message_stop"}],
        "late_fallback": [start("msg_fallback", usage={"input_tokens": 1, "output_tokens": 0}), {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": "partial"}}, {"type": "content_block_stop", "index": 0}, {"type": "content_block_start", "index": 1, "content_block": {"type": "fallback", "from": {"model": "claude-opus-5"}, "to": {"model": "claude-opus-4-8"}}}],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default="/tmp/pi-bend-theme-controller/build/theme-toolchain/bend2/main.ts")
    parser.add_argument("--upstream", type=pathlib.Path, default=UPSTREAM)
    parser.add_argument("--backend", choices=("bun", "native1", "native4", "all"), default="all")
    args = parser.parse_args()
    actual_commit = execute(["git", "rev-parse", "HEAD"], cwd=args.upstream)
    if actual_commit != UPSTREAM_COMMIT:
        raise RuntimeError(f"upstream source changed: {actual_commit}")
    oracle_env = dict(os.environ, PI_MONO_ROOT=str(args.upstream.resolve()))
    with tempfile.TemporaryDirectory(prefix="pi-bend-anthropic-") as directory:
        temporary = pathlib.Path(directory)
        runners = {}
        for kind in ("request", "stream"):
            source = ROOT / "packages/ai/test" / f"anthropic-messages-{kind}.bend"
            if args.backend in ("bun", "all"):
                target = temporary / f"{kind}.js"
                execute(["bun", args.toolchain, source, "-o", target])
                runners[kind, "bun"] = ["bun", str(target)]
            if args.backend in ("native1", "native4", "all"):
                target = temporary / kind
                build_env = dict(os.environ, BEND=args.toolchain)
                execute(['flock', '/tmp/pi-bend-build.lock', "sh", "scripts/build-pure.sh", source.relative_to(ROOT), target], env=build_env)
                for backend, threads in (("native1", "1"), ("native4", "4")):
                    runners[kind, backend] = [str(target), "--threads", threads]
        for backend in ("bun", "native1", "native4"):
            if ("request", backend) not in runners:
                continue
            for mode in ("basic", "adaptive", "replay", "cache"):
                expected = execute(["bun", ROOT / "packages/ai/test/anthropic-request-oracle.ts", mode], env=oracle_env)
                execute([*runners["request", backend], mode, expected])
            for name, event_list in events().items():
                payload = json.dumps(event_list, separators=(",", ":"))
                expected = execute(["bun", ROOT / "packages/ai/test/anthropic-stream-oracle.ts", payload], env=oracle_env)
                execute([*runners["stream", backend], payload, expected])
            print(f"{backend}: 4 request and 6 SSE traces match pinned pi-mono")


if __name__ == "__main__":
    main()

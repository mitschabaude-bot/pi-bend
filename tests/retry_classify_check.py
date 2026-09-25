#!/usr/bin/env python3
"""Differential check of packages/ai/src/utils/retry.bend and overflow.bend against
the pinned pi-ai classifiers: every case is classified by both and compared."""
from upstream_pin import UPSTREAM
import argparse, json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = UPSTREAM / 'packages' / 'ai'

RETRY_TEXTS = [
    # retry.test.ts
    "An error occurred while processing your request. You can retry your request, or contact us through our help center at help.openai.com if the error persists. Please include the request ID req_******** in your message.",
    '{"message":"The system encountered an unexpected error during processing. Try your request again."}',
    "ResourceExhausted: Worker local total request limit reached (288/48)",
    "The socket connection was closed unexpectedly. For more information, pass `verbose: true` in the second argument to fetch()",
    "Error: exceeded request buffer limit while retrying upstream",
    "The pending stream has been canceled (caused by: getaddrinfo ENOTFOUND bedrock-runtime.us-east-1.amazonaws.com)",
    "connect ENOTFOUND api.example.com", "EAI_AGAIN api.example.com", "getaddrinfo failed for api.example.com",
    "OpenAI Responses stream ended before a terminal response event",
    "The system is currently experiencing high demand and cannot process your request. Your request exceeds the maximum usage size allowed during peak load. For improved capacity reliability, consider switching to Provisioned Throughput.",
    "429 quota exceeded", "overloaded_error", "520 status code (no body)", "524 status code (no body)", "not an error",
    # limit patterns and near misses
    "GoUsageLimitError: 429", "FreeUsageLimitError", "Monthly usage limit reached; enable available balance", "insufficient_quota", "You are out of budget (503)", "billing hard limit reached 500",
    "Rate limit exceeded", "rate-limit", "ratelimit hit", "Too Many Requests", "HTTP 500", "502 Bad Gateway", "503 Service Unavailable", "504 Gateway Time-out", "service_unavailable", "Internal Server Error", "internal-error", "server error",
    "Provider returned error", "provider_returned_error", "network error", "NetworkError when attempting to fetch resource", "connection refused", "connection lost", "other side closed", "fetch failed", "upstream connect error or disconnect/reset before headers", "socket hang up",
    "timed out", "time out", "Request timeout", "terminated", "WebSocket closed", "websocket_error", "stream ended without message_stop", "Anthropic stream ended before message_stop", "http2 request did not get a response", "retry delay 90000ms exceeds the maximum",
    "please retry your request", "invalid_api_key", "Unauthorized", "model not found", "", "TIMEOUT", "Overloaded", "A 4290 code", "e500x", "connectionerror", "connection  refused", "wasn't terminated properly",
    # overflow.ts examples
    "prompt is too long: 213462 tokens > 200000 maximum",
    '413 {"error":{"type":"request_too_large","message":"Request exceeds the maximum size"}}',
    "Your input exceeds the context window of this model",
    "Requested token count exceeds the model's maximum context length of 131072 tokens",
    "Input length (265330) exceeds model's maximum context length (262144).",
    "The input token count (1196265) exceeds the maximum number of tokens allowed (1048575)",
    "This model's maximum prompt length is 131072 but the request contains 537812 tokens",
    "Please reduce the length of the messages or completion",
    "This endpoint's maximum context length is 8192 tokens. However, you requested about 9000 tokens",
    "Input length 300000 exceeds the maximum allowed input length of 262,144 tokens.",
    "The input (300000 tokens) is longer than the model's context length (262144 tokens).",
    "the request exceeds the available context size, try increasing it",
    "tokens to keep from the initial prompt is greater than the context length",
    "prompt token count of 200000 exceeds the limit of 128000",
    "invalid params, context window exceeds limit",
    "Your request exceeded model token limit: 262144 (requested: 300000)",
    "Prompt has 40,000 tokens, but the configured context size is 32,768 tokens",
    "400 status code (no body)", "413 status code (no body)", "400 (no body)", "413status code(no body)", " 400 status code (no body)", "4000 status code (no body)",
    "Prompt contains 300000 tokens and 0 images too large for model with 262144 maximum context length",
    "model_context_window_exceeded", "prompt too long; exceeded max context length by 100 tokens", "prompt too long; exceeded context length",
    "Range of input length should be [1, 129024]", "context_length_exceeded", "context length exceeded", "Context Length Exceeded", "too many tokens", "token limit exceeded",
    "ThrottlingException: Too many tokens, please wait before trying again.", "Throttling error: Too many tokens", "Service unavailable: too many tokens", "Rate limit: too many tokens", "input is too long for requested model",
    # overflow.test.ts
    "400 `prompt too long; exceeded max context length by 100918 tokens`", "400 The input (516368 tokens) is longer than the model's context length (262144 tokens).",
    "Error: 503 litellm.ServiceUnavailableError: litellm.MidStreamFallbackError: litellm.APIConnectionError: APIConnectionError: OpenAIException - Requested token count exceeds the model's maximum context length of 131072 tokens.",
    "Error: 400 Input length (265330) exceeds model's maximum context length (262144).", "Provider returned error: Input length 131393 exceeds the maximum allowed input length of 131040 tokens.",
    "400 Prompt has 256468 tokens, but the configured context size is 256000 tokens", "Prompt has 5,958,968 tokens, but the configured context size is 256,000 tokens",
    "500 `model runner crashed unexpectedly`", "Service unavailable: The service is temporarily unavailable.", "Rate limit exceeded, please retry after 30 seconds.", "Too many requests. Please slow down.",
    "exceeds maximum context length", "exceeds the model's maximum context length of 4096 token", "exceeds maximum context length (4096)", "exceeds the maximum context length of 10,000 tokens", "exceeds maximum allowed input length of 10 tokens",
    "input (5 tokens) is longer than the models context length (4 tokens)", "maximum prompt length is x", "unknown error", "Bad Request", "context window", "prompt is too longish",
]

NAMED = {}

def cases():
    out = []
    for text in RETRY_TEXTS:
        out.append({'provider': 'faux', 'errorMessage': text, 'stopReason': 'error', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': 200000, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    out.append({'provider': 'faux', 'errorMessage': 'overloaded_error', 'stopReason': 'stop', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': 200000, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    out.append({'provider': 'faux', 'errorMessage': None, 'stopReason': 'error', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': 200000, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    # Cerebras's bodyless 400/413 means overflow only from Cerebras; z.ai says "Prompt too long".
    for provider in ['cerebras', 'faux']:
        for text in ['400 status code (no body)', '413 (no body)', '413 status code (no body) extra', '404 status code (no body)']:
            out.append({'provider': provider, 'errorMessage': text, 'stopReason': 'error', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': 200000, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    for text in ['{"code":"1261","message":"Prompt too long"}', 'Prompt too long', 'prompt is too long', 'prompt  too long']:
        out.append({'provider': 'zai', 'errorMessage': text, 'stopReason': 'error', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': 200000, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    # overflow.test.ts v0.87.1, as written: "detects z.ai prompt-too-long errors" (#9805) and
    # "only treats bodyless 400 and 413 errors as overflow for Cerebras" (#9482)
    NAMED.update({'zai-1261': len(out)})
    out.append({'provider': 'zai', 'errorMessage': '400 {"code":"1261","message":"Prompt too long"}', 'stopReason': 'error', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': 1048576, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    for text in ['400 status code (no body)', '413 status code (no body)']:
        for provider, window in [('cerebras', 131072), ('opencode-go', 1000000)]:
            NAMED[provider + ':' + text] = len(out)
            out.append({'provider': provider, 'errorMessage': text, 'stopReason': 'error', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': window, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    # usage-based overflow (overflow.test.ts and z.ai / Xiaomi shapes)
    usage = [
        ('stop', 200001, 0, 10, 200000), ('stop', 100000, 100001, 10, 200000), ('stop', 200000, 0, 10, 200000), ('stop', 300000, 0, 10, 0),
        ('length', 58, 1048512, 0, 1048576), ('length', 1000, 0, 4096, 200000), ('length', 100, 0, 0, 200000), ('length', 198000, 0, 0, 200000), ('length', 197999, 0, 0, 200000), ('length', 0, 198000, 0, 0),
        ('toolUse', 300000, 0, 0, 200000), ('aborted', 300000, 0, 0, 200000), ('error', 300000, 0, 0, 200000),
    ]
    for stop, inp, cache, outp, window in usage:
        out.append({'provider': 'faux', 'errorMessage': None, 'stopReason': stop, 'input': inp, 'cacheRead': cache, 'output': outp, 'contextWindow': window, 'desiredMaxOutput': 0, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    # recoverable length stops
    for stop, inp, cache, outp, desired in [('length', 3, 253584, 16, 128000), ('length', 4062, 0, 1024, 1024), ('length', 100, 0, 0, 128000), ('length', 100, 0, 5, 0), ('stop', 100, 0, 5, 128000), ('length', 100, 0, 2000, 1024)]:
        out.append({'provider': 'faux', 'errorMessage': None, 'stopReason': stop, 'input': inp, 'cacheRead': cache, 'output': outp, 'contextWindow': 0, 'desiredMaxOutput': desired, 'baseDelayMs': 2000, 'maxAgentDelayMs': None, 'attempt': 1})
    # retry delays (retry.test.ts "caps agent retry delay" and boundaries)
    for base, cap, attempt in [(2000, None, 6), (2000, 5000, 5), (2000, 0, 5), (2000, None, 1), (2000, None, 0), (1, None, 3), (1, 100000, 20), (1, 10 ** 17, 60), (0.5, None, 2), (2000, 75000, 6), (1, 2 ** 60, 60)]:
        out.append({'provider': 'faux', 'errorMessage': None, 'stopReason': 'stop', 'input': 0, 'cacheRead': 0, 'output': 0, 'contextWindow': 0, 'desiredMaxOutput': 0, 'baseDelayMs': base, 'maxAgentDelayMs': cap, 'attempt': attempt})
    return out

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', required=True)
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    rows = cases()
    with tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False) as handle:
        for row in rows:
            handle.write(json.dumps(row) + '\n')
        path = handle.name
    reference = subprocess.run(['bun', str(ROOT / 'tests' / 'retry_classify_reference.ts'), str(UPSTREAM), path], capture_output=True, text=True, check=True).stdout.splitlines()
    if runner.endswith('.js'):
        # The unpatched Bun lane overflows its stack on large byte lists (docs/bend-issues.md BEND-019), so it reads the cases in chunks.
        ported = []
        for start in range(0, len(rows), 16):
            with tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False) as chunk:
                for row in rows[start:start + 16]:
                    chunk.write(json.dumps(row) + '\n')
            ported += subprocess.run(['bun', runner, '--', '--', chunk.name], capture_output=True, text=True, check=True).stdout.splitlines()
    else:
        ported = subprocess.run([runner, '--threads', args.threads, '--', path], capture_output=True, text=True, check=True).stdout.splitlines()
    assert len(reference) == len(rows) == len(ported), (len(reference), len(rows), len(ported))
    failures = 0
    for row, expected, actual in zip(rows, reference, ported):
        if json.loads(expected) != json.loads(actual):
            failures += 1
            print('MISMATCH', json.dumps(row), 'upstream', expected, 'port', actual)
    # pinned upstream expectations that must hold regardless of the oracle
    byText = {row['errorMessage']: json.loads(actual) for row, actual in zip(rows, ported) if row['stopReason'] == 'error' and row['input'] == 0}
    assert byText['overloaded_error']['retryable'] and byText['520 status code (no body)']['retryable'] and not byText['429 quota exceeded']['retryable'] and not byText['not an error']['retryable']
    assert byText['prompt is too long: 213462 tokens > 200000 maximum']['overflow'] and not byText['Throttling error: Too many tokens']['overflow']
    assert json.loads(ported[NAMED['zai-1261']])['overflow'], 'detects z.ai prompt-too-long errors'
    for text in ['400 status code (no body)', '413 status code (no body)']:
        assert json.loads(ported[NAMED['cerebras:' + text]])['overflow'] and not json.loads(ported[NAMED['opencode-go:' + text]])['overflow'], 'only treats bodyless 400 and 413 errors as overflow for Cerebras'
    if failures:
        sys.exit('retry-classify: %d of %d cases differ' % (failures, len(rows)))
    print('retry-classify: %d cases agree with upstream' % len(rows))

if __name__ == '__main__':
    main()

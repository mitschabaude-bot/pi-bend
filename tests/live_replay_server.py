"""Loopback provider for tests/live_replay_check.py: replays provider wire
responses for pi-mono's live suites.

Requests arrive under `/<run>/...`, where the run names the scenario, the API
and the executor (`<scenario>~<api>~<executor>`). The server keeps each run's
requests and answers request k of a run with the scenario's k-th reply, encoded
in the API's wire format: Anthropic Messages SSE, Gemini streamGenerateContent
SSE, Chat Completions chunks, or Responses events (OpenAI, Azure and Codex).

The replies follow each provider's documented stream shapes: Anthropic and
Gemini report input usage early (message_start / every chunk's
usageMetadata); Chat Completions and Responses report usage only in the final
chunk / response.completed. A reply may `hang`: after its chunks the server
keeps the connection open until the client closes it, so an abort interrupts
a blocked read and the partial content is deterministic.

Codex request bodies may arrive zstd-compressed (Content-Encoding: zstd, as
upstream sends them); the server decodes them with the zstd tool.

The server also rejects requests the way the providers do for the defects the
suites guard against: a body that is not strict JSON (an unpaired UTF-16
surrogate escape: "no low surrogate in string") and a tool call without a
matching tool result. Those checks model the provider-side validation; they
are not a general provider emulation.
"""
import http.server
import json
import re
import select
import subprocess
import threading
import time

LONE_SURROGATE = re.compile(r'\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F][0-9a-fA-F]{2})|(?<!\\u[dD][89abAB][0-9a-fA-F]{2})\\u[dD][c-fC-F][0-9a-fA-F]{2}')


def usage(input=0, output=0, cache_read=0, cache_write=0):
    return dict(input=input, output=output, cache_read=cache_read, cache_write=cache_write)


class Reply:
    """One scripted model turn: blocks are ('thinking', text, signature),
    ('text', text) or ('tool', id, name, arguments JSON text)."""

    def __init__(self, blocks, stop='stop', usage=None, hang=False, chunk=None, error=None, status=400):
        self.blocks = blocks
        self.status = status
        self.stop = stop
        self.usage = usage or dict(input=20, output=10, cache_read=0, cache_write=0)
        self.hang = hang
        self.chunk = chunk
        self.error = error


def pieces(text, size):
    if not size:
        size = max(1, (len(text) + 2) // 3)
    return [text[i:i + size] for i in range(0, len(text), size)] or ['']


def sse(event, data):
    head = f'event: {event}\n' if event else ''
    return (head + 'data: ' + json.dumps(data) + '\n\n').encode()


# Anthropic Messages
# ------------------
def anthropic(reply, model):
    u = reply.usage
    yield sse('message_start', {'type': 'message_start', 'message': {'id': 'msg_replay', 'type': 'message', 'role': 'assistant', 'model': model, 'content': [], 'stop_reason': None, 'stop_sequence': None, 'usage': {'input_tokens': u['input'], 'output_tokens': min(1, u['output']), 'cache_read_input_tokens': u['cache_read'], 'cache_creation_input_tokens': u['cache_write']}}})
    for index, block in enumerate(reply.blocks):
        kind = block[0]
        if kind == 'thinking':
            yield sse('content_block_start', {'type': 'content_block_start', 'index': index, 'content_block': {'type': 'thinking', 'thinking': '', 'signature': ''}})
            for part in pieces(block[1], reply.chunk):
                yield sse('content_block_delta', {'type': 'content_block_delta', 'index': index, 'delta': {'type': 'thinking_delta', 'thinking': part}})
            yield sse('content_block_delta', {'type': 'content_block_delta', 'index': index, 'delta': {'type': 'signature_delta', 'signature': block[2]}})
        elif kind == 'text':
            yield sse('content_block_start', {'type': 'content_block_start', 'index': index, 'content_block': {'type': 'text', 'text': ''}})
            for part in pieces(block[1], reply.chunk):
                yield sse('content_block_delta', {'type': 'content_block_delta', 'index': index, 'delta': {'type': 'text_delta', 'text': part}})
            if reply.hang:
                return
        else:
            yield sse('content_block_start', {'type': 'content_block_start', 'index': index, 'content_block': {'type': 'tool_use', 'id': block[1], 'name': block[2], 'input': {}}})
            for part in pieces(block[3], None):
                yield sse('content_block_delta', {'type': 'content_block_delta', 'index': index, 'delta': {'type': 'input_json_delta', 'partial_json': part}})
        yield sse('content_block_stop', {'type': 'content_block_stop', 'index': index})
    stop = {'stop': 'end_turn', 'tool': 'tool_use', 'length': 'max_tokens'}[reply.stop]
    yield sse('message_delta', {'type': 'message_delta', 'delta': {'stop_reason': stop, 'stop_sequence': None}, 'usage': {'output_tokens': u['output']}})
    yield sse('message_stop', {'type': 'message_stop'})


# Gemini
# ------
def gemini(reply, model):
    u = reply.usage
    produced = 0

    def chunk(parts, finish=None):
        metadata = {'promptTokenCount': u['input'] + u['cache_read'], 'candidatesTokenCount': produced, 'totalTokenCount': u['input'] + u['cache_read'] + produced}
        if u['cache_read']:
            metadata['cachedContentTokenCount'] = u['cache_read']
        candidate = {'content': {'role': 'model', 'parts': parts}, 'index': 0}
        if finish:
            candidate['finishReason'] = finish
        return ('data: ' + json.dumps({'candidates': [candidate], 'usageMetadata': metadata, 'modelVersion': model, 'responseId': 'replay-response'}) + '\r\n\r\n').encode()

    outputs = sum(1 for block in reply.blocks for _ in (pieces(block[1], reply.chunk) if block[0] != 'tool' else [0]))
    for block in reply.blocks:
        if block[0] == 'tool':
            produced = min(u['output'], produced + max(1, u['output'] // max(1, outputs)))
            part = {'functionCall': {'name': block[2], 'args': json.loads(block[3])}}
            if len(block) > 4:
                part['thoughtSignature'] = block[4]
            yield chunk([part])
            continue
        for part in pieces(block[1], reply.chunk):
            produced = min(u['output'], produced + max(1, u['output'] // max(1, outputs)))
            item = {'text': part}
            if block[0] == 'thinking':
                item['thought'] = True
            yield chunk([item])
        if reply.hang:
            return
    produced = u['output']
    yield chunk([], {'stop': 'STOP', 'tool': 'STOP', 'length': 'MAX_TOKENS'}[reply.stop])


# Chat Completions
# ----------------
def completions(reply, model):
    u = reply.usage

    def chunk(delta, finish=None):
        return ('data: ' + json.dumps({'id': 'chatcmpl-replay', 'object': 'chat.completion.chunk', 'created': 1, 'model': model, 'choices': [{'index': 0, 'delta': delta, 'finish_reason': finish}]}) + '\n\n').encode()

    yield chunk({'role': 'assistant', 'content': ''})
    calls = 0
    for block in reply.blocks:
        if block[0] == 'text':
            for part in pieces(block[1], reply.chunk):
                yield chunk({'content': part})
            if reply.hang:
                return
        elif block[0] == 'thinking':
            for part in pieces(block[1], reply.chunk):
                yield chunk({'reasoning_content': part})
        else:
            yield chunk({'tool_calls': [{'index': calls, 'id': block[1], 'type': 'function', 'function': {'name': block[2], 'arguments': ''}}]})
            for part in pieces(block[3], None):
                yield chunk({'tool_calls': [{'index': calls, 'function': {'arguments': part}}]})
            calls += 1
    yield chunk({}, {'stop': 'stop', 'tool': 'tool_calls', 'length': 'length'}[reply.stop])
    total = u['input'] + u['cache_read'] + u['output']
    yield ('data: ' + json.dumps({'id': 'chatcmpl-replay', 'object': 'chat.completion.chunk', 'created': 1, 'model': model, 'choices': [], 'usage': {'prompt_tokens': u['input'] + u['cache_read'], 'completion_tokens': u['output'], 'total_tokens': total, 'prompt_tokens_details': {'cached_tokens': u['cache_read']}}}) + '\n\n').encode()
    yield b'data: [DONE]\n\n'


# Responses (OpenAI, Azure, Codex)
# --------------------------------
def responses(reply, model):
    u = reply.usage
    sequence = [0]

    def event(kind, data):
        data = {'type': kind, 'sequence_number': sequence[0], **data}
        sequence[0] += 1
        return sse(kind, data)

    output = []
    yield event('response.created', {'response': {'id': 'resp_replay', 'object': 'response', 'status': 'in_progress', 'model': model, 'output': []}})
    for index, block in enumerate(reply.blocks):
        if block[0] == 'thinking':
            item = {'id': f'rs_{index}', 'type': 'reasoning', 'summary': []}
            yield event('response.output_item.added', {'output_index': index, 'item': item})
            yield event('response.reasoning_summary_part.added', {'item_id': item['id'], 'output_index': index, 'summary_index': 0, 'part': {'type': 'summary_text', 'text': ''}})
            for part in pieces(block[1], reply.chunk):
                yield event('response.reasoning_summary_text.delta', {'item_id': item['id'], 'output_index': index, 'summary_index': 0, 'delta': part})
            yield event('response.reasoning_summary_text.done', {'item_id': item['id'], 'output_index': index, 'summary_index': 0, 'text': block[1]})
            yield event('response.reasoning_summary_part.done', {'item_id': item['id'], 'output_index': index, 'summary_index': 0, 'part': {'type': 'summary_text', 'text': block[1]}})
            done = {**item, 'summary': [{'type': 'summary_text', 'text': block[1]}], 'encrypted_content': block[2]}
            output.append(done)
            yield event('response.output_item.done', {'output_index': index, 'item': done})
        elif block[0] == 'text':
            item = {'id': f'msg_{index}', 'type': 'message', 'status': 'in_progress', 'role': 'assistant', 'content': []}
            yield event('response.output_item.added', {'output_index': index, 'item': item})
            yield event('response.content_part.added', {'item_id': item['id'], 'output_index': index, 'content_index': 0, 'part': {'type': 'output_text', 'text': '', 'annotations': []}})
            for part in pieces(block[1], reply.chunk):
                yield event('response.output_text.delta', {'item_id': item['id'], 'output_index': index, 'content_index': 0, 'delta': part})
            if reply.hang:
                return
            yield event('response.output_text.done', {'item_id': item['id'], 'output_index': index, 'content_index': 0, 'text': block[1]})
            yield event('response.content_part.done', {'item_id': item['id'], 'output_index': index, 'content_index': 0, 'part': {'type': 'output_text', 'text': block[1], 'annotations': []}})
            done = {**item, 'status': 'completed', 'content': [{'type': 'output_text', 'text': block[1], 'annotations': []}]}
            output.append(done)
            yield event('response.output_item.done', {'output_index': index, 'item': done})
        else:
            item = {'id': f'fc_{index}', 'type': 'function_call', 'status': 'in_progress', 'call_id': block[1], 'name': block[2], 'arguments': ''}
            yield event('response.output_item.added', {'output_index': index, 'item': item})
            for part in pieces(block[3], None):
                yield event('response.function_call_arguments.delta', {'item_id': item['id'], 'output_index': index, 'delta': part})
            yield event('response.function_call_arguments.done', {'item_id': item['id'], 'output_index': index, 'arguments': block[3]})
            done = {**item, 'status': 'completed', 'arguments': block[3]}
            output.append(done)
            yield event('response.output_item.done', {'output_index': index, 'item': done})
    status = 'incomplete' if reply.stop == 'length' else 'completed'
    total = u['input'] + u['cache_read'] + u['output']
    yield event('response.completed', {'response': {'id': 'resp_replay', 'object': 'response', 'status': status, 'model': model, 'output': output, 'usage': {'input_tokens': u['input'] + u['cache_read'], 'input_tokens_details': {'cached_tokens': u['cache_read']}, 'output_tokens': u['output'], 'output_tokens_details': {'reasoning_tokens': 0}, 'total_tokens': total}}})


ENCODERS = {'anthropic': anthropic, 'google': gemini, 'completions': completions, 'responses': responses, 'azure': responses, 'codex': responses}


# Provider-side validation
# ------------------------
def error_body(api, message, code=None, status=400):
    if message is None:
        return status, None
    if api == 'anthropic':
        return status, {'type': 'error', 'error': {'type': 'invalid_request_error', 'message': message}}
    if api == 'google':
        return status, {'error': {'code': status, 'message': message, 'status': 'INVALID_ARGUMENT'}}
    return status, {'error': {'message': message, 'type': 'invalid_request_error', 'param': None, 'code': code}}


def orphan_calls(api, body):
    """Tool call ids that the request leaves without a result."""
    missing = []
    if api == 'anthropic':
        messages = body.get('messages', [])
        for i, message in enumerate(messages):
            if message.get('role') != 'assistant' or not isinstance(message.get('content'), list):
                continue
            ids = [block['id'] for block in message['content'] if block.get('type') == 'tool_use']
            following = messages[i + 1] if i + 1 < len(messages) else {}
            results = {block.get('tool_use_id') for block in following.get('content', []) if isinstance(following.get('content'), list) and block.get('type') == 'tool_result'}
            missing += [id for id in ids if id not in results]
    elif api == 'completions':
        messages = body.get('messages', [])
        for i, message in enumerate(messages):
            ids = [call['id'] for call in message.get('tool_calls') or []] if message.get('role') == 'assistant' else []
            results = set()
            for later in messages[i + 1:]:
                if later.get('role') != 'tool':
                    break
                results.add(later.get('tool_call_id'))
            missing += [id for id in ids if id not in results]
    elif api == 'google':
        contents = body.get('contents', [])
        for i, content in enumerate(contents):
            names = [part['functionCall']['name'] for part in content.get('parts', []) if 'functionCall' in part]
            following = contents[i + 1] if i + 1 < len(contents) else {}
            answered = [part['functionResponse']['name'] for part in following.get('parts', []) if 'functionResponse' in part]
            missing += names[len(answered):] if len(answered) < len(names) else []
    else:
        items = body.get('input', [])
        outputs = {item.get('call_id') for item in items if isinstance(item, dict) and item.get('type') == 'function_call_output'}
        missing += [item['call_id'] for item in items if isinstance(item, dict) and item.get('type') == 'function_call' and item.get('call_id') not in outputs]
    return missing


def rejection(api, raw):
    text = raw.decode('utf-8', errors='replace')
    if LONE_SURROGATE.search(text):
        return error_body(api, 'The request body is not valid JSON: no low surrogate in string: line 1 column 1')
    try:
        body = json.loads(raw)
    except ValueError:
        return error_body(api, 'The request body is not valid JSON')
    missing = orphan_calls(api, body)
    if missing:
        if api == 'anthropic':
            return error_body(api, f'messages: `tool_use` ids were found without `tool_result` blocks immediately after: {", ".join(missing)}. Each `tool_use` block must have a corresponding `tool_result` block in the next message.')
        if api == 'completions':
            return error_body(api, f"An assistant message with 'tool_calls' must be followed by tool messages responding to each 'tool_call_id'. The following tool_call_ids did not have response messages: {', '.join(missing)}")
        if api == 'google':
            return error_body(api, 'Please ensure that the number of function response parts is equal to the number of function call parts of the function call turn.')
        return error_body(api, f'No tool output found for function call {missing[0]}.')
    return None


class Server:
    def __init__(self, script):
        """script(scenario, api, index, body) -> Reply."""
        self.script = script
        self.requests = {}
        self.lock = threading.Lock()
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def do_POST(self):
                length = int(self.headers.get('content-length', 0))
                raw = self.rfile.read(length)
                encoding = self.headers.get('content-encoding')
                if encoding == 'zstd':
                    raw = subprocess.run(['zstd', '-d', '-c'], input=raw, capture_output=True, check=True).stdout
                run = self.path.split('/')[1]
                scenario, api, _ = run.split('~')
                with owner.lock:
                    seen = owner.requests.setdefault(run, [])
                    index = len(seen)
                    seen.append(dict(path=self.path[len(run) + 1:], headers={k.lower(): v for k, v in self.headers.items()}, raw=raw, encoding=encoding))
                rejected = rejection(api, raw)
                reply = None if rejected else owner.script(scenario, api, index, json.loads(raw))
                if rejected or reply.error:
                    status, body = rejected or error_body(api, *reply.error, status=reply.status)
                    data = b'' if body is None else json.dumps(body).encode()
                    self.send_response(status)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.send_header('Cache-Control', 'no-cache')
                self.send_header('Connection', 'close')
                self.end_headers()
                model = json.loads(raw).get('model') or 'replay-model'
                try:
                    for part in ENCODERS[api](reply, model):
                        self.wfile.write(part)
                        self.wfile.flush()
                    if reply.hang:
                        self.wait_closed()
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            def wait_closed(self):
                deadline = time.time() + 30
                while time.time() < deadline:
                    ready, _, _ = select.select([self.connection], [], [], 0.05)
                    if ready and not self.connection.recv(4096):
                        return

            def log_message(self, *_):
                pass

        self.http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.http.daemon_threads = True
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.http.shutdown()

    @property
    def base(self):
        return f'http://127.0.0.1:{self.http.server_port}'

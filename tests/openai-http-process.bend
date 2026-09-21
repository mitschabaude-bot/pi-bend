import Base
import ../packages/runtime/src/http-exchange-response.bend as HTTP
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-body-source.bend as Source
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/sse-reader.bend as SSE
import ../packages/runtime/src/sse-decoder.bend as Event
import ../packages/runtime/test/utf8-runner.bend as Text

import ../packages/ai/src/api/openai-http-responses-reader.bend as Adapter
import ../packages/ai/src/api/openai-http-errors.bend as Errors
import ../packages/ai/src/api/openai-sse-reader.bend as Protocol
import ../packages/ai/src/api/openai-sse-json.bend as Json
import ../packages/ai/src/api/openai-responses-reader.bend as Reader
import ../packages/ai/src/api/openai-responses-stream.bend as Events
import ../packages/ai/src/api/openai-responses-stream-state.bend as State
import ../packages/ai/src/api/openai-responses-stream-content.bend as Content
import ../packages/runtime/src/callback.bend as Cb

import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-stream-pricing.bend as Pricing
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/u64.bend as W
def mapError(value: Reader.Error<Errors.TransportError(String)>) -> String:
  match value:
    case Reader.ProtocolFailure{_}: "wire"
    case Reader.StreamingFailure{Protocol.DispatchFailure{Json.InvalidJson{_, _, _, _}}}: "json"
    case Reader.StreamingFailure{Protocol.DispatchFailure{_}}: "api"
    case Reader.StreamingFailure{Protocol.TransportFailure{_}}: "transport"
    case _: "diagnostic"

def abortHook(controller: Abort.AbortController<String>, unused: Unit) -> IO(Unit):
  do IO<Unit>:
    IO.print("abort-hook")
    won : Bool <- Abort.abort(String, controller, None{})
    return Unit{}

def diagnosticHook(environment: Unit, error: Json.Error) -> IO(Result<&2, &2, Protocol.ReadError<Errors.TransportError(String)>, Unit>):
  do IO<Result<&2, &2, Protocol.ReadError<Errors.TransportError(String)>, Unit>>:
    IO.print("diagnostic")
    return Done{Unit{}}

def createHooks(controller: Abort.AbortController<String>) -> IO(Protocol.Hooks<Errors.TransportError(String)>):
  do IO<Protocol.Hooks<Errors.TransportError(String)>>:
    abort : Cb.Callback<Unit, Unit> <- Cb.create(~Abort.AbortController<String>, ~Unit, ~Unit, ~abortHook, controller)
    diagnostic : Cb.Callback<Json.Error, Result<&2, &2, Protocol.ReadError<Errors.TransportError(String)>, Unit>> <- Cb.create(~Unit, ~Json.Error, ~Result<&2, &2, Protocol.ReadError<Errors.TransportError(String)>, Unit>, ~diagnosticHook, Unit{})
    return Protocol.Hooks{abort, diagnostic}

def retireHooks(hooks: Protocol.Hooks<Errors.TransportError(String)>) -> IO(Unit):
  match hooks:
    case Protocol.Hooks{abort, diagnostic}:
      do IO<Unit>:
        Cb.dispose(Unit, Unit, abort)
        Cb.dispose(Json.Error, Result<&2, &2, Protocol.ReadError<Errors.TransportError(String)>, Unit>, diagnostic)


def model() -> T.Model<Unit>:
  T.Model{"test", "Test", T.OpenAIResponsesApi{}, "openai", "http://localhost", False{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{F.fromU32(1000000), F.fromU32(2000000), F.fromU32(3000000), F.fromU32(4000000), None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def initial() -> T.AssistantMessage<V.Value, Unit>:
  +zero = F.fromU32(0)
  tokens = {T.Usage{zero, zero, zero, zero, None{}, None{}, zero, T.UsageCost{zero, zero, zero, zero, zero}} : T.Usage}
  T.AssistantMessage{Nil{}, "openai-responses", "openai", "test", None{}, None{}, None{}, None{}, tokens, T.Pending{}, None{}, None{}, None{}, None{}, zero}

def contents(values: List<&2, T.AssistantContent<V.Value>>) -> String:
  match values:
    case Nil{}: ""
    case T.AssistantText{T.TextContent{text, _}} <> rest: Text.showText(text) ++ ";" ++ contents(rest)
    case _ <> rest: "other;" ++ contents(rest)

def snapshot(value: T.AssistantMessage<V.Value, Unit>) -> String:
  match value:
    case T.AssistantMessage{blocks, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: contents(blocks)

def emitted(value: T.AssistantMessageEvent<V.Value, Unit>) -> String:
  match value:
    case T.TextStart{_, partial}: "text-start:" ++ snapshot(partial)
    case T.TextDelta{_, delta, partial}: "text-delta:" ++ Text.showText(delta) ++ ":" ++ snapshot(partial)
    case T.TextEnd{_, text, partial}: "text-end:" ++ Text.showText(text) ++ ":" ++ snapshot(partial)
    case _: "other-event"

def isDelta(value: T.AssistantMessageEvent<V.Value, Unit>) -> Bool:
  match value:
    case T.TextDelta{_, _, _}: True{}
    case _: False{}

def sink(mode: U32, event: T.AssistantMessageEvent<V.Value, Unit>) -> IO(Result<&2, &2, String, Unit>):
  +value = event
  do IO<Result<&2, &2, String, Unit>>:
    IO.print(emitted(value))
    return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 1) && isDelta(value), Fail{"sink"}, Done{Unit{}})

def number(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ "," ++ U32.show(low)

def usage(value: T.Usage) -> String:
  match value:
    case T.Usage{input, output, read, write, _, _, total, T.UsageCost{_, _, _, _, cost}}: number(F.toBits(input)) ++ ":" ++ number(F.toBits(output)) ++ ":" ++ number(F.toBits(read)) ++ ":" ++ number(F.toBits(write)) ++ ":" ++ number(F.toBits(total)) ++ ":" ++ number(F.toBits(cost))

def reason(value: T.StopReason) -> String:
  match value:
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.Error{}: "error"
    case T.Pending{}: "pending"
    case _: "other"

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text

def output(value: T.AssistantMessage<V.Value, Unit>) -> String:
  match value:
    case T.AssistantMessage{blocks, _, _, _, _, id, _, _, tokens, stop, _, _, _, _, _}: "output:" ++ contents(blocks) ++ ":" ++ optional(id) ++ ":" ++ reason(stop) ++ ":" ++ usage(tokens)

def failure(value: Maybe<&2, Events.Error<String>>) -> String:
  match value:
    case None{}: "ok"
    case Some{Events.ReadFailure{error}}: "read:" ++ error
    case Some{Events.EmitFailure{error}}: "emit:" ++ error
    case Some{Events.TerminalFailure{_}}: "terminal"
    case Some{_}: "other"

def finished(value: Adapter.Processed<String, Unit, String>) -> IO(Unit):
  match value:
    case Adapter.Processed{Events.RunResult{message, error}, Done{_}}:
      do IO<Unit>:
        IO.print(output(message))
        IO.print("result:" ++ failure(error))
        IO.print("dispose:ok")
    case _: IO.die(Unit, 1, "disposal failed")

def response(mode: U32, controller: Abort.AbortController<String>, hooks: Protocol.Hooks<Errors.TransportError(String)>, value: Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "response failed")
    case Done{Response.Response{_, body}}:
      do IO<Unit>:
        owner : Adapter.Owner<String, String> <- Adapter.create(~String, ~String, ~mapError, body, hooks, False{})
        +callback : Cb.Callback<T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, String, Unit>> <- Cb.create(~U32, ~T.AssistantMessageEvent<V.Value, Unit>, ~Result<&2, &2, String, Unit>, ~sink, mode)
        processed : Adapter.Processed<String, Unit, String> <- Adapter.process(String, Unit, String, Unit, owner, initial(), callback, model(), Pricing.defaultOptions(String))
        Cb.dispose(T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, String, Unit>, callback)
        finished(processed)

def exchange(mode: U32, controller: Abort.AbortController<String>, hooks: Protocol.Hooks<Errors.TransportError(String)>, value: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "exchange failed")
    case Done{owner}:
      do IO<Unit>:
        value : Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- HTTP.start(~String, owner)
        response(mode, controller, hooks, value)

def prepared(mode: U32, +controller: Abort.AbortController<String>, hooks: Protocol.Hooks<Errors.TransportError(String)>, socket: Socket, signal: Abort.AbortSignal<String>, value: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Unit):
  match value:
    case Fail{_}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "prepare failed")
    case Done{request}:
      do IO<Unit>:
        value : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, signal, request, 7, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        exchange(mode, controller, hooks, value)

def run(args: List<String>) -> IO(Unit):
  match args:
    case port <> mode <> _:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        +hooks : Protocol.Hooks<Errors.TransportError(String)> <- createHooks(controller)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Text.decimal(port, 0)))
        prepared(Text.decimal(mode, 0), controller, hooks, socket, Abort.signal(String, controller), Request.prepare("GET", "/sse", Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Body.Absent{}))
        retireHooks(hooks)
        Abort.dispose(String, controller)
    case _: IO.die(Unit, 1, "expected port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

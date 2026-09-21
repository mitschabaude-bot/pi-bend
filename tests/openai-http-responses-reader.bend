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

def disposed(value: Result<&2, &2, Adapter.CloseError<String>, Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.print("dispose:ok")
    case Fail{_}: IO.die(Unit, 1, "provider disposal failed")

def event(value: Events.ResponseStreamEvent) -> String:
  match value:
    case Events.ResponseCreated{id}: "created:" ++ id
    case Events.ContentEvent{State.Changed{_, Content.TextDelta{text}}}: "text:" ++ Text.showText(text)
    case Events.IgnoredEvent{}: "ignored"
    case _: "event"

def next(handle: Events.Reader<String>) -> IO(Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>>):
  match handle:
    case Events.Reader{callback, _}: Cb.call(Unit, Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>>, callback, Unit{})

def finish(owner: Adapter.Owner<String, String>) -> IO(Unit):
  do IO<Unit>:
    value : Result<&2, &2, Adapter.CloseError<String>, Unit> <- Adapter.dispose(String, String, owner)
    disposed(value)

def loop(fuel: Nat, +early: Bool, owner: Adapter.Owner<String, String>, +handle: Events.Reader<String>, value: Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>>) -> IO(Unit):
  match fuel early value:
    case Succ{rest} False{} Done{Some{value}}:
      do IO<Unit>:
        IO.print(event(value))
        fresh : Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>> <- next(handle)
        loop(rest, early, owner, handle, fresh)
    case _ _ Done{Some{value}}:
      do IO<Unit>:
        IO.print(event(value))
        finish(owner)
    case _ _ Done{None{}}:
      do IO<Unit>:
        IO.print("end")
        finish(owner)
    case _ _ Fail{error}:
      do IO<Unit>:
        IO.print("error:" ++ error)
        finish(owner)

def acquired(mode: U32, controller: Abort.AbortController<String>, pair: Adapter.Owner<String, String> & Events.Reader<String>) -> IO(Unit):
  match mode pair:
    case 2 Tuple{owner, _}: finish(owner)
    case 3 Tuple{owner, +handle}:
      do IO<Unit>:
        task : Chan(Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>>) <- IO.fork(Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>>, next(handle))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        value : Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>> <- IO.join(Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>>, task)
        loop(128n, False{}, owner, handle, value)
    case other Tuple{owner, +handle}:
      do IO<Unit>:
        value : Result<&2, &2, String, Maybe<&2, Events.ResponseStreamEvent>> <- next(handle)
        loop(128n, U32.is_eq(other, 1), owner, handle, value)

def response(mode: U32, controller: Abort.AbortController<String>, hooks: Protocol.Hooks<Errors.TransportError(String)>, value: Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "response failed")
    case Done{Response.Response{_, body}}:
      do IO<Unit>:
        owner : Adapter.Owner<String, String> <- Adapter.create(~String, ~String, ~mapError, body, hooks, False{})
        acquired(mode, controller, Adapter.borrow(String, String, owner))

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

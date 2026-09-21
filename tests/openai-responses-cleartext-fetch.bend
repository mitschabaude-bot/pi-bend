import Base
import ../packages/ai/src/api/openai-responses-fetch.bend as Fetch
import ../packages/ai/src/api/openai-responses-cleartext-fetch.bend as Native
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/runtime/src/http-fetch-scope.bend as Scope
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-exchange-response.bend as Reader
import ../packages/runtime/src/http-exchange-plan.bend as Plan
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/http-body-buffer.bend as Buffer
import ../packages/runtime/src/http-response-reader.bend as Wire
import ../packages/runtime/src/http-socket-source.bend as Source
import ../packages/runtime/src/abortable-socket.bend as SocketIO
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/url-scheme.bend as Scheme
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/resolver-configuration.bend as Settings
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/dns-udp-plan.bend as UDP
import ../packages/runtime/src/random-index.bend as Index
import ./http-resolved-exchange.bend as Setup
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/resolver-search.bend as Search
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/test/utf8-runner.bend as Scalar

def Transport() -> Type: Exchange.Exchange<Deadline.Cause<String>>
def State() -> Type: Scope.State<String, Transport()>
def ReadError() -> Data: Exchange.ReadError<Deadline.Cause<String>>
def FetchError() -> Data: Native.Error<String, File.Failure>
def FetchResult() -> Type: Result<&2, &1, Fetch.Error<String, FetchError()>, Response.Response<State()>>

def read(state: State()) -> IO(State() & Result<&2, &2, ReadError(), Maybe<&2, Stream.Event>>):
  Scope.read(String, ReadError(), Transport(), Reader.read(Deadline.Cause<String>), state)

def close(state: State()) -> IO(Result<&2, &2, ReadError(), Unit>):
  Scope.close(String, ReadError(), Transport(), Exchange.close(Deadline.Cause<String>), state)

def transportError(error: ReadError()) -> String:
  match error:
    case Exchange.ResponseFailure{Wire.PrimaryFailure{Wire.SourceError{Source.SocketFailure{SocketIO.Aborted{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{why}}}}}}}}: "abort:" ++ why
    case _: "body-error"

def bodyError(error: Consume.TextError<ReadError()>) -> String:
  match error:
    case Consume.BodyFailure{Buffer.PrimaryFailure{Buffer.ReadFailure{Progress.PrimaryFailure{Progress.TransportFailure{cause}}}}}: transportError(cause)
    case _: "body-error"

def consumed(value: Result<&2, &2, Consume.TextError<ReadError()>, String>) -> IO(Unit):
  match value:
    case Done{text}: IO.print("body:" ++ text)
    case Fail{error}: IO.print(bodyError(error))

def cancelled(flow: U32, parent: Abort.AbortController<String>) -> IO(Unit):
  match flow:
    case 2:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, parent, Some{"stop"})
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def closed(value: Response.Next<ReadError(), State()>) -> IO(Unit):
  match value:
    case Response.Next{Response.Closed{_}, Done{_}}: IO.print("closed")
    case _: IO.die(Unit, 1, "early close failed")

def body(flow: U32, parent: Abort.AbortController<String>, content: Response.Body<State()>) -> IO(Unit):
  match flow:
    case 1:
      do IO<Unit>:
        result : Response.Next<ReadError(), State()> <- Response.closeWith(ReadError(), State(), close, content)
        closed(result)
    case _:
      do IO<Unit>:
        cancelled(flow, parent)
        result : Result<&2, &2, Consume.TextError<ReadError()>, String> <- Consume.textWith(~(ReadError()), ~(State()), ~read, ~close, 65536n, content)
        consumed(result)

def received(flow: U32, parent: Abort.AbortController<String>, result: FetchResult()) -> IO(Unit):
  match result:
    case Fail{Fetch.FetchFailure{Scope.DispatchFailure{_, Some{Abort.Supplied{Deadline.Expired{}}}}}}: IO.print("timeout")
    case Fail{Fetch.FetchFailure{Scope.DispatchFailure{Native.Rejected{Plan.TLSRequired{}}, _}}}: IO.print("tls-required")
    case Fail{Fetch.FetchFailure{Scope.DispatchFailure{Native.HeaderFailure{_, _, _}, _}}}: IO.print("header-error")
    case Fail{_}: IO.die(Unit, 1, "unexpected fetch failure")
    case Done{Response.Response{metadata, content}}:
      do IO<Unit>:
        IO.print("head:" ++ U32.show(Metadata.status(metadata)))
        body(flow, parent, content)

def envelope(+route: U32, family: Bool, port: U32, flow: U32) -> Envelope.Request:
  Envelope.Request{URL.URL{Bool.pick(Scheme.Scheme, U32.is_eq(route, 3), Scheme.Https{}, Scheme.Http{}), "", "", Some{Setup.host(route, family)}, Some{port}, URL.Hierarchical{"responses" <> Nil{}}, Some{"x=1"}, Some{"hidden"}}, "post", Headers.appendField(Headers.appendField(Headers.new(), Header.Header{"host", "wrong.invalid"}), Header.Header{"x-fixture", "yes"}), "{\"message\":\"héllo\"}", F.fromU32(Bool.pick(U32, U32.is_eq(flow, 4), 50, 1000))}

def run(+route: U32, +family: Bool, port: U32, +flow: U32, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, resolver):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +fetch : C.Callback<Fetch.Input<String>, Result<&2, &1, FetchError(), Response.Response<Transport()>>> <- Native.create(~String, ~File.Failure, Native.Context{resolver, Setup.database(route, family), Setup.options(route, family)})
        result : FetchResult() <- Fetch.run(String, FetchError(), Transport(), envelope(route, family, port, flow), Abort.signal(String, parent), fetch)
        received(flow, parent, result)
        C.dispose(Fetch.Input<String>, Result<&2, &1, FetchError(), Response.Response<Transport()>>, fetch)
        Resolver.close(owner)
        Abort.dispose(String, parent)

def created(route: U32, family: Bool, port: U32, flow: U32, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver initialization")
    case Done{owner}: run(route, family, port, flow, Resolver.borrow(owner))

def configured(route: U32, family: Bool, port: U32, flow: U32, result: Result<&2, &2, UDP.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver settings")
    case Done{config}:
      do IO<Unit>:
        result : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~Setup.seed, 0, config)
        created(route, family, port, flow, result)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case route <> family <> port <> flow <> Nil{}:
      configured(Scalar.decimal(route, 0), String.eq(family, "6"), Scalar.decimal(port, 0), Scalar.decimal(flow, 0), Settings.prepare(Endpoint.Endpoint, Endpoint.V4{IPv4.Address{2130706433}, 9} <> Nil{}, 1000, 512, Search.prepare(Options.Options{1, 1, 1, Nil{}}, Nil{})))
    case _: IO.die(Unit, 1, "expected route family port flow")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

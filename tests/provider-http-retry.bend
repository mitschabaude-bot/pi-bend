import Base
import ../packages/ai/src/utils/provider-http-response.bend as Provider
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/test/provider-retry.bend as Reference
import ../packages/runtime/src/http-exchange-response.bend as HTTP
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/test/utf8-runner.bend as Text
import ./http-body-consume-native.bend as Show

type Failure is Data:
  StatusFailure{value: Provider.Failure<Exchange.ReadError<String>>}
  StartFailure{value: Exchange.StartError<String>}
  HeadFailure{value: Progress.Error<Exchange.ReadError<String>>}

type Environment is Data:
  Environment{port: U32, controller: A.AbortController<String>, request: Request.Prepared, diagnosticLimit: Nat}

# This fixture supplies a strict policy for diagnostic failures. SDK error
# normalization is intentionally not supplied by the shared status adapter.
def statusFailure(value: Provider.Failure<Exchange.ReadError<String>>) -> IO(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>):
  match value:
    case Provider.StatusFailure{+metadata, Done{+text}}:
      do IO<Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>>:
        IO.print("diagnostic:" ++ U32.show(Metadata.status(metadata)) ++ ":" ++ Text.showText(text))
        return Fail{Provider.retryFailure(Failure, StatusFailure{Provider.StatusFailure{metadata, Done{text}}}, text, metadata)}
    case Provider.StatusFailure{+metadata, Fail{+cause}}:
      do IO<Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>>:
        IO.print("diagnostic-error:" ++ U32.show(Metadata.status(metadata)) ++ ":" ++ Show.textFailure(cause))
        return Fail{Retry.Other{StatusFailure{Provider.StatusFailure{metadata, Fail{cause}}}}}

def accepted(value: Result<&2, &1, Provider.Failure<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>):
  match value:
    case Fail{cause}: statusFailure(cause)
    case Done{response}: IO.pure(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>, Done{response})

def headed(limit: Nat, value: Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>>) -> IO(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>):
  match value:
    case Fail{cause}: IO.pure(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>, Fail{Retry.Other{HeadFailure{cause}}})
    case Done{response}:
      do IO<Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>>:
        result : Result<&2, &1, Provider.Failure<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- Provider.acceptWith(Exchange.ReadError<String>, Exchange.Exchange<String>, HTTP.read(String), Exchange.close(String), limit, response)
        accepted(result)

def started(limit: Nat, value: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>):
  match value:
    case Fail{cause}: IO.pure(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>, Fail{Retry.Other{StartFailure{cause}}})
    case Done{owner}:
      do IO<Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>>:
        result : Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Response.Response<Exchange.Exchange<String>>> <- HTTP.start(String, owner)
        headed(limit, result)

def requestBody(environment: Environment, unused: Unit) -> IO(Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>):
  match environment:
    case Environment{port, controller, request, limit}:
      do IO<Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>>:
        IO.print("request")
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, A.signal(String, controller), request, 7, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        started(limit, result)

def finished(value: Result<&2, &1, Retry.RetryFailure<Failure>, Response.Response<Exchange.Exchange<String>>>) -> IO(Unit):
  match value:
    case Fail{Retry.RequestFailed{Retry.Provider{_}}}: IO.print("failed:status")
    case Fail{Retry.RequestFailed{Retry.Other{_}}}: IO.print("failed:diagnostic-or-transport")
    case Fail{Retry.RequestAborted{}}: IO.print("failed:aborted")
    case Fail{Retry.DelayRejected{_, _}}: IO.print("failed:delay")
    case Done{Response.Response{metadata, body}}:
      do IO<Unit>:
        IO.print("accepted:" ++ U32.show(Metadata.status(metadata)))
        result : Result<&2, &2, Consume.TextError<Exchange.ReadError<String>>, String> <- HTTP.text(String, 1000n, body)
        IO.print(Show.shownText(result))

def run(port: U32, retries: Nat, limit: Nat, prepared: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Unit):
  match prepared:
    case Fail{_}: IO.die(Unit, 1, "prepare failed")
    case Done{prepared}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        +request : C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>> <- C.create(~Environment, ~Unit, ~Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>, ~requestBody, Environment{port, controller, prepared, limit})
        +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.randomBody, Unit{})
        +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Reference.dateBody, Unit{})
        +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.nowBody, Unit{})
        +sleep : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>> <- C.create(~Bool, ~Retry.SleepInput<String>, ~Result<&2, &2, Unit, Unit>, ~Reference.sleepBody, False{})
        result : Result<&2, &1, Retry.RetryFailure<Failure>, Response.Response<Exchange.Exchange<String>>> <- Retry.retryProviderRequestOwned(String, Failure, Response.Response<Exchange.Exchange<String>>, request, Retry.Effects{random, date, now, sleep}, Retry.ProviderRetryOptions{Some{retries}, None{}, Some{A.signal(String, controller)}})
        finished(result)
        C.dispose(Unit, Result<&2, &1, Retry.RequestFailure<Failure>, Response.Response<Exchange.Exchange<String>>>, request)
        C.dispose(Unit, F.F64, random)
        C.dispose(String, F.F64, date)
        C.dispose(Unit, F.F64, now)
        C.dispose(Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>, sleep)
        A.dispose(String, controller)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> retries <> limit <> Nil{}: run(Text.decimal(port, 0), U32.to_nat(Text.decimal(retries, 0)), U32.to_nat(Text.decimal(limit, 0)), Request.prepare("GET", "/retry", Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Body.Absent{}))
    case _: IO.die(Unit, 1, "expected port retries diagnostic-limit")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

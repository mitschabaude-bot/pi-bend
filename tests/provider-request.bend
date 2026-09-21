import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-request.bend as Driver
import ../packages/ai/src/utils/provider-response-view.bend as View
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
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/test/utf8-runner.bend as Text
import ./http-body-consume-native.bend as Show

def Owner() -> Type: Response.Response<Exchange.Exchange<String>>
def Payload() -> Data: T.Nullable<U32>

def text(value: Payload()) -> String:
  match value:
    case T.NullValue{}: "null"
    case T.PresentValue{value}: U32.show(value)

def payloadHook(+mode: U32, input: T.PayloadInput<Payload(), String>) -> IO(Result<&2, &2, String, Maybe<&2, Payload()>>):
  match input:
    case T.PayloadInput{value, model}:
      do IO<Result<&2, &2, String, Maybe<&2, Payload()>>>:
        IO.print("payload:" ++ text(value) ++ ":" ++ model)
        return Bool.pick(Result<&2, &2, String, Maybe<&2, Payload()>>, U32.is_eq(mode, 4), Fail{"payload"}, Done{Bool.pick(Maybe<&2, Payload()>, U32.is_eq(mode, 2), Some{T.PresentValue{9}}, Bool.pick(Maybe<&2, Payload()>, U32.is_eq(mode, 3), Some{T.PresentValue{0}}, Bool.pick(Maybe<&2, Payload()>, U32.is_eq(mode, 10), Some{T.NullValue{}}, None{})))})

def header(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "missing"
    case Some{headerText}: headerText

def responseHook(+mode: U32, input: T.ResponseInput<String>) -> IO(Result<&2, &2, String, Unit>):
  match input:
    case T.ResponseInput{T.ProviderResponse{status, fields}, model}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("response:" ++ model ++ ":" ++ Reference.scalar(F.toBits(status)) ++ ":" ++ header(R.get(String, fields, "x-response")))
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 5) || U32.is_eq(mode, 6), Fail{"response"}, Done{Unit{}})

def released(fails: Bool, value: Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>>) -> Result<&2, &2, String, Unit>:
  match value:
    case Response.Next{Response.Closed{_}, Done{_}}: Bool.pick(Result<&2, &2, String, Unit>, fails, Fail{"cleanup"}, Done{Unit{}})
    case _: Fail{"body-close"}

def release(fails: Bool, value: Owner()) -> IO(Result<&2, &2, String, Unit>):
  match value:
    case Response.Response{_, body}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("release")
        result : Response.Next<Exchange.ReadError<String>, Exchange.Exchange<String>> <- HTTP.close(String, body)
        return released(fails, result)

def accepted(value: Result<&2, &1, Provider.Failure<Exchange.ReadError<String>>, Owner()>) -> Result<&2, &1, Retry.RequestFailure<String>, Owner()>:
  match value:
    case Done{owner}: Done{owner}
    case Fail{Provider.StatusFailure{metadata, Done{message}}}: Fail{Provider.retryFailure(String, "original", message, metadata)}
    case Fail{_}: Fail{Retry.Other{"diagnostic"}}

def headed(value: Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Owner()>) -> IO(Result<&2, &1, Retry.RequestFailure<String>, Owner()>):
  match value:
    case Fail{_}: IO.pure(Result<&2, &1, Retry.RequestFailure<String>, Owner()>, Fail{Retry.Other{"head"}})
    case Done{owner}:
      do IO<Result<&2, &1, Retry.RequestFailure<String>, Owner()>>:
        result : Result<&2, &1, Provider.Failure<Exchange.ReadError<String>>, Owner()> <- Provider.acceptWith(Exchange.ReadError<String>, Exchange.Exchange<String>, HTTP.read(String), Exchange.close(String), 1000n, owner)
        return accepted(result)

def started(value: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Result<&2, &1, Retry.RequestFailure<String>, Owner()>):
  match value:
    case Fail{_}: IO.pure(Result<&2, &1, Retry.RequestFailure<String>, Owner()>, Fail{Retry.Other{"start"}})
    case Done{owner}:
      do IO<Result<&2, &1, Retry.RequestFailure<String>, Owner()>>:
        value : Result<&2, &1, Progress.Error<Exchange.ReadError<String>>, Owner()> <- HTTP.start(String, owner)
        headed(value)

type Environment is Data:
  Environment{port: U32, controller: A.AbortController<String>}

def prepared(port: U32, controller: A.AbortController<String>, value: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Result<&2, &1, Retry.RequestFailure<String>, Owner()>):
  match value:
    case Fail{_}: IO.pure(Result<&2, &1, Retry.RequestFailure<String>, Owner()>, Fail{Retry.Other{"prepare"}})
    case Done{request}:
      do IO<Result<&2, &1, Retry.RequestFailure<String>, Owner()>>:
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        value : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, A.signal(String, controller), request, 7, Stream.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        started(value)

def requestBody(environment: Environment, +value: Payload()) -> IO(Result<&2, &1, Retry.RequestFailure<String>, Owner()>):
  match environment:
    case Environment{port, controller}:
      do IO<Result<&2, &1, Retry.RequestFailure<String>, Owner()>>:
        IO.print("request:" ++ text(value))
        prepared(port, controller, Request.prepare("POST", "/responses", Headers.appendField(Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Header.Header{"content-type", "application/json"}), Body.Text{text(value)}))

def cleanupResult(value: Result<&2, &2, String, Unit>) -> String:
  match value:
    case Done{_}: "ok"
    case Fail{cause}: cause

def finished(value: Result<&2, &1, Driver.Error<String>, Owner()>) -> IO(Unit):
  match value:
    case Fail{Driver.PayloadFailure{cause}}: IO.print("failed:payload:" ++ cause)
    case Fail{Driver.RequestFailure{cause}}: Reference.show(Fail{cause})
    case Fail{Driver.ResponseFailure{cause, cleanup}}: IO.print("failed:response:" ++ cause ++ ":" ++ cleanupResult(cleanup))
    case Done{Response.Response{_, body}}:
      do IO<Unit>:
        IO.print("accepted")
        result : Result<&2, &2, Consume.TextError<Exchange.ReadError<String>>, String> <- HTTP.text(String, 1000n, body)
        IO.print(Show.shownText(result))

def run(port: U32, +mode: U32) -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<String> <- A.new(String)
    +request : C.Callback<Payload(), Result<&2, &1, Retry.RequestFailure<String>, Owner()>> <- C.create(~Environment, ~Payload(), ~Result<&2, &1, Retry.RequestFailure<String>, Owner()>, ~(environment => value => requestBody(environment, value)), Environment{port, controller})
    +payload : T.PayloadCallback(Payload(), String, String) <- C.create(~U32, ~T.PayloadInput<Payload(), String>, ~Result<&2, &2, String, Maybe<&2, Payload()>>, ~(selectedMode => input => payloadHook(selectedMode, input)), mode)
    +response : T.ResponseCallback(String, String) <- C.create(~U32, ~T.ResponseInput<String>, ~Result<&2, &2, String, Unit>, ~(selectedMode => input => responseHook(selectedMode, input)), mode)
    +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.randomBody, Unit{})
    +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Reference.dateBody, Unit{})
    +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.nowBody, Unit{})
    +sleep : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>> <- C.create(~Bool, ~Retry.SleepInput<String>, ~Result<&2, &2, Unit, Unit>, ~Reference.sleepBody, False{})
    result : Result<&2, &1, Driver.Error<String>, Owner()> <- Driver.run(~String, ~Payload(), ~String, ~String, ~Owner(), "model", T.PresentValue{7}, Bool.pick(Maybe<&2, T.PayloadCallback(Payload(), String, String)>, U32.is_eq(mode, 0) || U32.is_eq(mode, 9), None{}, Some{payload}), Bool.pick(Maybe<&2, T.ResponseCallback(String, String)>, U32.is_eq(mode, 0) || U32.is_eq(mode, 8), None{}, Some{response}), request, Retry.Effects{random, date, now, sleep}, Retry.ProviderRetryOptions{Some{2n}, None{}, Some{A.signal(String, controller)}}, View.inspect(Exchange.Exchange<String>), release(U32.is_eq(mode, 6)))
    finished(result)
    C.dispose(Payload(), Result<&2, &1, Retry.RequestFailure<String>, Owner()>, request)
    C.dispose(T.PayloadInput<Payload(), String>, Result<&2, &2, String, Maybe<&2, Payload()>>, payload)
    C.dispose(T.ResponseInput<String>, Result<&2, &2, String, Unit>, response)
    C.dispose(Unit, F.F64, random)
    C.dispose(String, F.F64, date)
    C.dispose(Unit, F.F64, now)
    C.dispose(Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>, sleep)
    A.dispose(String, controller)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> mode <> Nil{}: run(Text.decimal(port, 0), Text.decimal(mode, 0))
    case _: IO.die(Unit, 1, "expected port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

import Base
import ../src/api/openai-responses-attempt.bend as Request
import ../src/api/openai-responses-fetch.bend as Fetch
import ../src/api/openai-http-error.bend as HTTPError
import ../src/utils/provider-retry.bend as Retry
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/http-response-stream.bend as Stream
import ../../runtime/src/http-response-metadata.bend as Metadata
import ../../runtime/src/http-head.bend as Head
import ../../runtime/src/http-status.bend as Status
import ../../runtime/src/http-header.bend as Header
import ../../runtime/src/http-fetch-scope.bend as Scope
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/utf8.bend as UTF8
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as Text
import ./provider-retry.bend as Effects
import ./openai-responses-fetch.bend as Envelope

type Transport is Type:
  Transport{step: U32, mode: U32}

def Error() -> Data: Request.Error<String, String, String>
def Owner() -> Type: Response.Response<Scope.State<String, Transport>>
def Attempt() -> Type: Result<&2, &1, Retry.RequestFailure<Error()>, Owner()>

def category(value: String) -> Request.FetchCategory:
  match value:
    case "configuration": Request.NonRetryable{}
    case "timeout": Request.Timeout{}
    case _: Request.Connection{"Connection error."}

def readResult(step: U32, mode: U32) -> Result<&2, &2, String, Maybe<&2, Stream.Event>>:
  match step mode:
    case 0 7: Fail{"read"}
    case 0 9: Fail{"read"}
    case 0 8: Done{Some{Stream.BodyData{255 <> Nil{}}}}
    case 0 _: Done{Some{Stream.BodyData{UTF8.encode("{\"error\":{\"message\":\"busy\"}}")}}}
    case _ _: Done{Some{Stream.Completed{Nil{}}}}

def read(transport: Transport) -> IO(Transport & Result<&2, &2, String, Maybe<&2, Stream.Event>>):
  match transport:
    case Transport{+step, +mode}:
      do IO<Transport & Result<&2, &2, String, Maybe<&2, Stream.Event>>>:
        IO.print("read")
        return (Transport{(step + 1 : U32), mode}, readResult(step, mode))

def close(transport: Transport) -> IO(Result<&2, &2, String, Unit>):
  match transport:
    case Transport{_, mode}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("close")
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 9), Fail{"cleanup"}, Done{Unit{}})

def fields(mode: U32) -> List<&2, Header.Header>:
  match mode:
    case 2: Header.Header{"x-should-retry", "false"} <> Nil{}
    case 3: Header.Header{"x-should-retry", "true"} <> Header.Header{"retry-after-ms", "1"} <> Nil{}
    case 9: Header.Header{"x-should-retry", "false"} <> Nil{}
    case 10: Header.Header{"x-should-retry", "false"} <> Nil{}
    case 11: Header.Header{"retry-after-ms", "70000"} <> Nil{}
    case _: Header.Header{"retry-after-ms", "1"} <> Nil{}

def status(mode: U32, count: U32) -> U32:
  match mode count:
    case 13 _: 200
    case 1 0: 400
    case 3 0: 400
    case _ 0: 429
    case _ _: 200

def response(+mode: U32, count: U32) -> Result<&2, &1, String, Response.Response<Transport>>:
  Done{Response.Response{Metadata.fromHead(Head.ResponseHead{Status.StatusLine{1, 1, status(mode, count), Nil{}}, fields(mode)}, True{}), Response.Open{Transport{0, mode}, True{}}}}

def reply(+mode: U32, +count: U32) -> Result<&2, &1, String, Response.Response<Transport>>:
  match mode count:
    case 4 0: Fail{"connection"}
    case 5 0: Fail{"configuration"}
    case 6 0: Fail{"timeout"}
    case _ _: response(mode, count)

type FetchEnvironment is Data:
  FetchEnvironment{mode: U32, counter: R.Ref<U32>}

def increment(+value: U32) -> U32 & U32: ((value + 1 : U32), value)

def fetch(environment: FetchEnvironment, unused: Fetch.Input<String>) -> IO(Result<&2, &1, String, Response.Response<Transport>>):
  match environment:
    case FetchEnvironment{mode, counter}:
      do IO<Result<&2, &1, String, Response.Response<Transport>>>:
        +count : U32 <- R.modify(U32, U32, counter, value => increment(value))
        IO.print("fetch:" ++ U32.show(count))
        return reply(mode, count)

type RequestEnvironment is Data:
  RequestEnvironment{signal: Abort.AbortSignal<String>, fetch: C.Callback<Fetch.Input<String>, Result<&2, &1, String, Response.Response<Transport>>>, limit: Nat}

def attempt(environment: RequestEnvironment, unused: Unit) -> IO(Attempt()):
  match environment:
    case RequestEnvironment{signal, handle, limit}:
      Request.run(~String, ~String, ~String, ~Transport, ~read, ~close, Envelope.request("default"), signal, handle, category, limit)

def original(value: Error()) -> String:
  match value:
    case Request.HTTPFailure{HTTPError.APIError{_, _, message}}: "http:" ++ message
    case Request.DiagnosticFailure{HTTPError.DiagnosticReadFailure{_, _}}: "diagnostic-read"
    case Request.DiagnosticFailure{_}: "diagnostic-encoding"
    case Request.FetchFailure{_}: "fetch"

def failure(value: Retry.RequestFailure<Error()>) -> IO(Unit):
  match value:
    case Retry.Other{value}: IO.print("other:" ++ original(value))
    case Retry.Provider{Retry.ProviderError{value, message, _, _, _, _}}: IO.print("provider:" ++ original(value) ++ ":" ++ message)

def released(next: Response.Next<String, Scope.State<String, Transport>>) -> IO(Unit):
  match next:
    case Response.Next{Response.Closed{_}, Done{_}}: IO.print("released")
    case _: IO.die(Unit, 1, "response release failed")

def finished(result: Result<&2, &1, Retry.RetryFailure<Error()>, Owner()>) -> IO(Unit):
  match result:
    case Fail{Retry.RequestFailed{cause}}: failure(cause)
    case Fail{Retry.SleepRejected{_}}: IO.print("invalid-sleep-duration")
    case Fail{Retry.RequestAborted{}}: IO.print("aborted")
    case Fail{Retry.DelayRejected{_, _}}: IO.print("delay-rejected")
    case Done{Response.Response{_, body}}:
      do IO<Unit>:
        IO.print("success")
        next : Response.Next<String, Scope.State<String, Transport>> <- Response.closeWith(String, Scope.State<String, Transport>, state => Scope.close(String, String, Transport, close, state), body)
        released(next)

def run(+mode: U32) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    +counter : R.Ref<U32> <- R.new(U32, 0)
    +handle : C.Callback<Fetch.Input<String>, Result<&2, &1, String, Response.Response<Transport>>> <- C.create(~FetchEnvironment, ~Fetch.Input<String>, ~Result<&2, &1, String, Response.Response<Transport>>, ~fetch, FetchEnvironment{mode, counter})
    +request : C.Callback<Unit, Attempt()> <- C.create(~RequestEnvironment, ~Unit, ~Attempt(), ~attempt, RequestEnvironment{Abort.signal(String, parent), handle, Bool.pick(Nat, U32.is_eq(mode, 10), 1n, 65536n)})
    +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.randomBody, Unit{})
    +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Effects.dateBody, Unit{})
    +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.nowBody, Unit{})
    +sleep : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>> <- C.create(~Bool, ~Retry.SleepInput<String>, ~Result<&2, &2, Retry.SleepError, Unit>, ~Effects.sleepBody, False{})
    Effects.preAbort(U32.is_eq(mode, 12), parent)
    result : Result<&2, &1, Retry.RetryFailure<Error()>, Owner()> <- Retry.retryProviderRequestOwned(String, Error(), Owner(), request, Retry.Effects{random, date, now, sleep}, Retry.ProviderRetryOptions{Some{1n}, None{}, Some{Abort.signal(String, parent)}})
    finished(result)
    C.dispose(Unit, Attempt(), request)
    C.dispose(Fetch.Input<String>, Result<&2, &1, String, Response.Response<Transport>>, handle)
    C.dispose(Unit, F.F64, random)
    C.dispose(String, F.F64, date)
    C.dispose(Unit, F.F64, now)
    C.dispose(Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>, sleep)
    count : U32 <- R.dispose(U32, counter)
    IO.print("count:" ++ U32.show(count))
    Abort.dispose(String, parent)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> Nil{}: run(Text.decimal(mode, 0))
    case _: IO.die(Unit, 1, "mode required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

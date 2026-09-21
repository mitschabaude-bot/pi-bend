import Base
import ../packages/ai/src/api/openai-responses-cleartext-attempt.bend as Attempt
import ../packages/ai/src/api/openai-responses-attempt.bend as Generic
import ../packages/ai/src/api/openai-responses-cleartext-fetch.bend as Native
import ../packages/ai/src/api/openai-responses-fetch.bend as Fetch
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/api/openai-http-error.bend as HTTPError
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-retry-sleep.bend as Sleep
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-stream.bend as Stream
import ../packages/runtime/src/http-body-consume.bend as Consume
import ../packages/runtime/src/http-exchange-response.bend as Reader
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/http-fetch-scope.bend as Scope
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/resolver-configuration.bend as Settings
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/resolver-search.bend as Search
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/dns-udp-plan.bend as UDP
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/url-scheme.bend as Scheme
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/ai/test/provider-retry.bend as Effects
import ./http-resolved-exchange.bend as Setup

def ErrorValue() -> Data: Attempt.Error(String, File.Failure)
def Outcome() -> Type: Attempt.Outcome(String, File.Failure)
def FetchOutput() -> Type: Attempt.FetchResult(String, File.Failure)
def State() -> Type: Attempt.State(String)
def ReadError() -> Data: Attempt.ReadError(String)

def envelope(+route: U32, port: U32, timeout: U32) -> Envelope.Request:
  Envelope.Request{URL.URL{Bool.pick(Scheme.Scheme, U32.is_eq(route, 3), Scheme.Https{}, Scheme.Http{}), "", "", Some{Setup.host(route, False{})}, Some{port}, URL.Hierarchical{"responses" <> Nil{}}, Some{"x=1"}, None{}}, "post", Headers.appendField(Headers.new(), Header.Header{"x-fixture", "yes"}), "{\"message\":\"héllo\"}", F.fromU32(timeout)}

type Environment is Data:
  Environment{request: Envelope.Request, signal: Abort.AbortSignal<String>, fetch: C.Callback<Fetch.Input<String>, FetchOutput()>, counter: R.Ref<U32>, limit: Nat}

def increment(+count: U32) -> U32 & Unit: ((count + 1 : U32), Unit{})

def request(environment: Environment, unused: Unit) -> IO(Outcome()):
  match environment:
    case Environment{envelope, signal, fetch, counter, limit}:
      do IO<Outcome()>:
        ignored : Unit <- R.modify(U32, Unit, counter, value => increment(value))
        IO.print("request")
        Attempt.run(~String, ~File.Failure, envelope, signal, fetch, limit)

def sleep(environment: Unit, input: Retry.SleepInput<String>) -> IO(Result<&2, &2, Unit, Unit>):
  do IO<Result<&2, &2, Unit, Unit>>:
    IO.print("sleep")
    Sleep.sleep(String, input)

def read(state: State()) -> IO(State() & Result<&2, &2, ReadError(), Maybe<&2, Stream.Event>>):
  Scope.read(String, ReadError(), Attempt.Transport(String), Reader.read(Deadline.Cause<String>), state)

def close(state: State()) -> IO(Result<&2, &2, ReadError(), Unit>):
  Scope.close(String, ReadError(), Attempt.Transport(String), Exchange.close(Deadline.Cause<String>), state)

def original(error: ErrorValue()) -> String:
  match error:
    case Generic.HTTPFailure{HTTPError.APIError{_, _, message}}: "http:" ++ message
    case Generic.DiagnosticFailure{_}: "diagnostic"
    case Generic.FetchFailure{_}: "fetch"

def failure(error: Retry.RequestFailure<ErrorValue()>) -> IO(Unit):
  match error:
    case Retry.Other{cause}: IO.print("other:" ++ original(cause))
    case Retry.Provider{Retry.ProviderError{cause, message, _, _, _, _}}: IO.print("provider:" ++ original(cause) ++ ":" ++ message)

def consumed(value: Result<&2, &2, Consume.TextError<ReadError()>, String>) -> IO(Unit):
  match value:
    case Done{text}: IO.print("body:" ++ text)
    case Fail{_}: IO.print("body-error")

def finished(value: Result<&2, &1, Retry.RetryFailure<ErrorValue()>, Response.Response<State()>>) -> IO(Unit):
  match value:
    case Fail{Retry.RequestFailed{cause}}: failure(cause)
    case Fail{Retry.RequestAborted{}}: IO.print("aborted")
    case Fail{Retry.DelayRejected{_, _}}: IO.print("delay-rejected")
    case Done{Response.Response{_, body}}:
      do IO<Unit>:
        IO.print("success")
        value : Result<&2, &2, Consume.TextError<ReadError()>, String> <- Consume.textWith(~ReadError(), ~State(), ~read, ~close, 65536n, body)
        consumed(value)

def run(+route: U32, port: U32, timeout: U32, limit: Nat, pre: Bool, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, resolver):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +counter : R.Ref<U32> <- R.new(U32, 0)
        +fetch : C.Callback<Fetch.Input<String>, FetchOutput()> <- Native.create(~String, ~File.Failure, Native.Context{resolver, Setup.database(route, False{}), Setup.options(route, False{})})
        +attempt : C.Callback<Unit, Outcome()> <- C.create(~Environment, ~Unit, ~Outcome(), ~request, Environment{envelope(route, port, timeout), Abort.signal(String, parent), fetch, counter, limit})
        +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.randomBody, Unit{})
        +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Effects.dateBody, Unit{})
        +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Effects.nowBody, Unit{})
        +delay : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>> <- C.create(~Unit, ~Retry.SleepInput<String>, ~Result<&2, &2, Unit, Unit>, ~sleep, Unit{})
        Effects.preAbort(pre, parent)
        result : Result<&2, &1, Retry.RetryFailure<ErrorValue()>, Response.Response<State()>> <- Retry.retryProviderRequestOwned(String, ErrorValue(), Response.Response<State()>, attempt, Retry.Effects{random, date, now, delay}, Retry.ProviderRetryOptions{Some{1n}, None{}, Some{Abort.signal(String, parent)}})
        finished(result)
        C.dispose(Unit, Outcome(), attempt)
        C.dispose(Fetch.Input<String>, FetchOutput(), fetch)
        C.dispose(Unit, F.F64, random)
        C.dispose(String, F.F64, date)
        C.dispose(Unit, F.F64, now)
        C.dispose(Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>, delay)
        count : U32 <- R.dispose(U32, counter)
        IO.print("count:" ++ U32.show(count))
        Resolver.close(owner)
        Abort.dispose(String, parent)

def created(route: U32, port: U32, timeout: U32, limit: Nat, pre: Bool, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver initialization")
    case Done{owner}: run(route, port, timeout, limit, pre, Resolver.borrow(owner))

def configured(route: U32, port: U32, timeout: U32, limit: Nat, pre: Bool, result: Result<&2, &2, UDP.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver settings")
    case Done{config}:
      do IO<Unit>:
        result : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~Setup.seed, 0, config)
        created(route, port, timeout, limit, pre, result)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case route <> port <> timeout <> limit <> pre <> dnsPort <> Nil{}:
      configured(Scalar.decimal(route, 0), Scalar.decimal(port, 0), Scalar.decimal(timeout, 0), U32.to_nat(Scalar.decimal(limit, 0)), String.eq(pre, "1"), Settings.prepare(Endpoint.Endpoint, Endpoint.V4{IPv4.Address{2130706433}, Scalar.decimal(dnsPort, 0)} <> Nil{}, 100, 512, Search.prepare(Options.Options{1, 1, 1, Nil{}}, Nil{})))
    case _: IO.die(Unit, 1, "expected route port timeout diagnostic-limit pre-abort DNS-port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

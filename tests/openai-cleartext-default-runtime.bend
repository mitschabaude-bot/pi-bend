import Base
import ../packages/ai/src/api/openai-responses-cleartext-default-runtime.bend as Default
import ../packages/ai/src/api/openai-responses-cleartext-runtime.bend as Runtime
import ../packages/ai/src/api/openai-responses-fetch.bend as Fetch
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-http-date.bend as Date
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/resolver-configuration.bend as Settings
import ../packages/runtime/src/resolver-search.bend as Search
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/dns-udp-plan.bend as UDP
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/random-seed.bend as Seed
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./openai-responses-cleartext-fetch.bend as Check
import ./http-resolved-exchange.bend as Setup

def bits(value: F.F64) -> String:
  match value:
    case F.F64{W.U64{high, low}}: U32.show(high) ++ ":" ++ U32.show(low)

def slept(result: Result<&2, &2, Retry.SleepError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("sleep:ok")
    case Fail{_}: IO.die(Unit, 1, "default sleep failed")

def effects(value: Retry.Effects<String>) -> IO(Unit):
  match value:
    case Retry.Effects{random, +date, now, sleep}:
      do IO<Unit>:
        parsed : F.F64 <- C.call(String, F.F64, date, "Sun, 06 Nov 1994 08:49:37 GMT")
        IO.print("date:" ++ bits(parsed))
        invalid : F.F64 <- C.call(String, F.F64, date, "Sun, 31 Dec 2016 23:59:60 GMT")
        IO.print("invalid:" ++ bits(invalid))
        jitter : F.F64 <- C.call(Unit, F.F64, random, Unit{})
        IO.print("random:" ++ bits(jitter))
        clock : F.F64 <- C.call(Unit, F.F64, now, Unit{})
        IO.print("now:" ++ bits(clock))
        result : Result<&2, &2, Retry.SleepError, Unit> <- C.call(Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>, sleep, Retry.SleepInput{F.fromU32(1), None{}})
        slept(result)

def exercise(+mode: U32, port: U32, pair: Default.Owner<String, File.Failure> & Runtime.Borrowed<String, File.Failure>) -> IO(Unit):
  match pair:
    case Tuple{owner, Runtime.Borrowed{fetch, retry}}:
      do IO<Unit>:
        effects(retry)
        +parent : Abort.AbortController<String> <- Abort.new(String)
        result : Check.FetchResult() <- Fetch.run(String, Check.FetchError(), Check.Transport(), Check.envelope(Bool.pick(U32, U32.is_eq(mode, 6), 3, 0), False{}, port, mode), Abort.signal(String, parent), fetch)
        Check.received(mode, parent, result)
        Default.dispose(String, File.Failure, owner)
        IO.print("owner:closed")
        live : Bool <- Abort.aborted(String, Abort.signal(String, parent))
        IO.print(Bool.pick(String, live, "parent:aborted", "parent:live"))
        Abort.dispose(String, parent)

def created(mode: U32, port: U32, result: Result<&2, &1, Runtime.Error, Default.Owner<String, File.Failure>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "default runtime initialization failed")
    case Done{owner}: exercise(mode, port, Default.borrow(String, File.Failure, owner))

def configured(mode: U32, port: U32, result: Result<&2, &2, UDP.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "invalid fixture settings")
    case Done{config}:
      do IO<Unit>:
        runtime : Result<&2, &1, Runtime.Error, Default.Owner<String, File.Failure>> <- Default.create(~String, ~File.Failure, config, Setup.database(1, False{}), Setup.options(0, False{}))
        created(mode, port, runtime)

def failed(result: Result<&2, &1, Runtime.Error, Default.Owner<String, File.Failure>>) -> IO(Unit):
  match result:
    case Fail{Runtime.ResolverFailure{Index.SourceFailure{code, message}}}: IO.print("resolver:" ++ U32.show(code) ++ ":" ++ message)
    case Fail{Runtime.RetryFailure{Seed.SourceFailure{code, message}}}: IO.print("retry:" ++ U32.show(code) ++ ":" ++ message)
    case _: IO.die(Unit, 1, "initialization cause changed")

def injected(cause: Runtime.Error) -> IO(Unit):
  do IO<Unit>:
    date : C.Callback<String, F.F64> <- Date.create()
    result : Result<&2, &1, Runtime.Error, Default.Owner<String, File.Failure>> <- Default.initialized(String, File.Failure, date, Fail{cause})
    failed(result)

def run(mode: U32, port: U32) -> IO(Unit):
  match mode:
    case 7: injected(Runtime.ResolverFailure{Index.SourceFailure{71, "resolver fixture"}})
    case 8: injected(Runtime.RetryFailure{Seed.SourceFailure{81, "retry fixture"}})
    case _: configured(mode, port, Settings.prepare(Endpoint.Endpoint, Endpoint.V4{IPv4.Address{2130706433}, 9} <> Nil{}, 1000, 512, Search.prepare(Options.Options{1, 1, 1, Nil{}}, Nil{})))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> port <> Nil{}: run(Scalar.decimal(mode, 0), Scalar.decimal(port, 0))
    case _: IO.die(Unit, 1, "expected mode port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

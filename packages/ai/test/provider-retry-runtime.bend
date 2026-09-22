import Base
import ../src/utils/provider-retry.bend as Runtime
import ../src/utils/provider-retry.bend as Retry
import ./provider-retry.bend as T
import ../../runtime/src/random.bend as Random
import ../../runtime/src/random.bend as Seed
import ../../runtime/src/u64.bend as W
import ../../runtime/src/f64.bend as F
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as Ref

def parserBody(environment: Unit, text: String) -> IO(F64): IO.pure(F64, F.fromU32(1234))

def expectSleep(result: Result<&2, &2, Retry.SleepError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("slept")
    case Fail{_}: IO.die(Unit, 1, "unexpected cancellation")

def inspectEffects(effects: Retry.Effects<String>) -> IO(Unit):
  match effects:
    case Retry.Effects{+random, parser, now, sleep}:
      do IO<Unit>:
        first : F64 <- C.call(Unit, F64, random, Unit{})
        second : F64 <- C.call(Unit, F64, random, Unit{})
        epoch : F64 <- C.call(Unit, F64, now, Unit{})
        parsed : F64 <- C.call(String, F64, parser, "input")
        IO.print("random " ++ T.scalar(F.toBits(first)))
        IO.print("random " ++ T.scalar(F.toBits(second)))
        IO.print("now " ++ T.scalar(F.toBits(epoch)))
        IO.print("parsed " ++ T.scalar(F.toBits(parsed)))
        result : Result<&2, &2, Retry.SleepError, Unit> <- C.call(Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>, sleep, Retry.SleepInput{F.fromU32(0), None{}})
        expectSleep(result)

def useBorrowed(pair: Runtime.Runtime<String> & Retry.Effects<String>) -> IO(Unit):
  match pair:
    case Tuple{owner, +effects}:
      do IO<Unit>:
        inspectEffects(effects)
        +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
        configuration : T.Config = T.Config{1, Some{1n}, T.failure(429, None{}, None{}, None{}), None{}, False{}, False{}}
        +request : C.Callback<Unit, Result<&2, &2, Retry.RequestFailure<String>, String>> <- C.create(~T.RequestEnvironment, ~Unit, ~Result<&2, &2, Retry.RequestFailure<String>, String>, ~T.requestBody, T.RequestEnvironment{counter, configuration})
        result : Result<&2, &2, Retry.RetryFailure<String>, String> <- Retry.retryProviderRequest(String, String, String, request, effects, Retry.ProviderRetryOptions{Some{1n}, None{}, None{}})
        T.show(result)
        C.dispose(Unit, Result<&2, &2, Retry.RequestFailure<String>, String>, request)
        calls : U32 <- Ref.dispose(U32, counter)
        Runtime.dispose(String, owner)

def retireNew(result: Result<&2, &1, Seed.SeedError, Runtime.Runtime<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "runtime entropy initialization failed")
    case Done{owner}: Runtime.dispose(U32, owner)

def main() -> IO(Unit):
  do IO<Unit>:
    +parser : C.Callback<String, F64> <- C.create(~Unit, ~String, ~F64, ~parserBody, Unit{})
    generator : Random.Generator <- Random.seeded(W.zero())
    owner : Runtime.Runtime<String> <- Runtime.fromGenerator(~String, parser, generator)
    useBorrowed(Runtime.borrow(String, owner))
    other : Result<&2, &1, Seed.SeedError, Runtime.Runtime<U32>> <- Runtime.new(~U32, parser)
    retireNew(other)
    retained : F64 <- C.call(String, F64, parser, "still alive")
    IO.print("retained " ++ T.scalar(F.toBits(retained)))
    C.dispose(String, F64, parser)

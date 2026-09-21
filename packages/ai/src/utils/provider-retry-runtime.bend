import Base
import ./provider-retry.bend as Retry
import ./provider-retry-random.bend as Jitter
import ./provider-retry-sleep.bend as Sleep
import ../../../runtime/src/random.bend as Random
import ../../../runtime/src/random-seed.bend as Seed
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/callback.bend as C

# One affine lifetime for the callbacks and their generator. The date parser
# is borrowed from the caller and remains valid after this owner is retired.
type Runtime<-Reason: Data> is Type:
  Runtime{effects: Retry.Effects<Reason>, generator: Random.Generator}

def nowBody(environment: Unit, unused: Unit) -> IO(F.F64): Date.now()

def sleepBody(~Reason: Data, environment: Unit, input: Retry.SleepInput<Reason>) -> IO(Result<&2, &2, Retry.SleepError, Unit>):
  Sleep.sleep(Reason, input)

# This constructor takes ownership of the supplied generator. It also permits
# deterministic tests without replacing the production callback assembly.
def fromGenerator(~Reason: Data, parseDate: C.Callback<String, F.F64>, +generator: Random.Generator) -> IO(Runtime<Reason>):
  do IO<Runtime<Reason>>:
    random : C.Callback<Unit, F.F64> <- Jitter.create(generator)
    now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~nowBody, Unit{})
    sleep : C.Callback<Retry.SleepInput<Reason>, Result<&2, &2, Retry.SleepError, Unit>> <- C.create(~Unit, ~Retry.SleepInput<Reason>, ~Result<&2, &2, Retry.SleepError, Unit>, ~(sleepBody(~Reason)), Unit{})
    return Runtime{Retry.Effects{random, parseDate, now, sleep}, generator}

def initialized(~Reason: Data, parseDate: C.Callback<String, F.F64>, result: Result<&2, &2, Seed.SeedError, Random.Generator>) -> IO(Result<&2, &1, Seed.SeedError, Runtime<Reason>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Seed.SeedError, Runtime<Reason>>, Fail{error})
    case Done{generator}:
      do IO<Result<&2, &1, Seed.SeedError, Runtime<Reason>>>:
        runtime : Runtime<Reason> <- fromGenerator(~Reason, parseDate, generator)
        return Done{runtime}

def new(~Reason: Data, parseDate: C.Callback<String, F.F64>) -> IO(Result<&2, &1, Seed.SeedError, Runtime<Reason>>):
  do IO<Result<&2, &1, Seed.SeedError, Runtime<Reason>>>:
    result : Result<&2, &2, Seed.SeedError, Random.Generator> <- Seed.new()
    initialized(~Reason, parseDate, result)

# Borrowed effects may be shared across requests. Join all requests before
# disposing the owner; borrowed handles are not tracked by the type system.
def borrow(-Reason: Data, runtime: Runtime<Reason>) -> Runtime<Reason> & Retry.Effects<Reason>:
  match runtime:
    case Runtime{+effects, generator}: (Runtime{effects, generator}, effects)

def dispose(-Reason: Data, runtime: Runtime<Reason>) -> IO(Unit):
  match runtime:
    case Runtime{Retry.Effects{random, _, now, sleep}, generator}:
      do IO<Unit>:
        C.dispose(Unit, F.F64, random)
        C.dispose(Unit, F.F64, now)
        C.dispose(Retry.SleepInput<Reason>, Result<&2, &2, Retry.SleepError, Unit>, sleep)
        Random.dispose(generator)

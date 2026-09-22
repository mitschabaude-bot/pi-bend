import Base
import ../src/random.bend as R
import ../src/random.bend as Seed
import ../src/u64.bend as W
import ../src/f64.bend as F
import ../src/callback.bend as C
import ../../ai/src/utils/provider-retry.bend as Retry
import ./utf8-runner.bend as H

def bits(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ ":" ++ U32.show(low)

def sequence(count: Nat, +generator: R.Generator) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +word : W.U64 <- R.nextWord(generator)
        IO.print(bits(word) ++ ";" ++ bits(F.toBits(R.unit(word))))
        sequence(rest, generator)

def seeded(high: U32, low: U32, count: Nat) -> IO(Unit):
  do IO<Unit>:
    +generator : R.Generator <- R.seeded(W.U64{high, low})
    sequence(count, generator)
    R.dispose(generator)

def launch(count: Nat, +generator: R.Generator) -> IO(List<&2, Chan(W.U64)>):
  match count:
    case Zero{}: IO.pure(List<&2, Chan(W.U64)>, Nil{})
    case Succ{rest}:
      do IO<List<&2, Chan(W.U64)>>:
        task : Chan(W.U64) <- IO.fork(W.U64, R.nextWord(generator))
        tasks : List<&2, Chan(W.U64)> <- launch(rest, generator)
        return task <> tasks

def drain(tasks: List<&2, Chan(W.U64)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case task <> rest:
      do IO<Unit>:
        +word : W.U64 <- IO.join(W.U64, task)
        IO.print(bits(word) ++ ";" ++ bits(F.toBits(R.unit(word))))
        drain(rest)

def concurrent(high: U32, low: U32, count: Nat) -> IO(Unit):
  do IO<Unit>:
    +generator : R.Generator <- R.seeded(W.U64{high, low})
    tasks : List<&2, Chan(W.U64)> <- launch(count, generator)
    drain(tasks)
    R.dispose(generator)

def showSeed(result: Result<&2, &2, Seed.SeedError, W.U64>) -> IO(Unit):
  match result:
    case Done{value}: IO.print("seed " ++ bits(value))
    case Fail{Seed.SeedSourceFailure{code, _}}: IO.print("error " ++ U32.show(code))
    case Fail{Seed.ShortSeed{length}}: IO.print("short " ++ Nat.show(length))

def callbackCheck(result: Result<&2, &2, Seed.SeedError, R.Generator>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "OS entropy initialization failed")
    case Done{+generator}:
      do IO<Unit>:
        +callback : C.Callback<Unit, F.F64> <- Retry.randomCallback(generator)
        value : F.F64 <- C.call(Unit, F.F64, callback, Unit{})
        IO.print("random " ++ bits(F.toBits(value)))
        C.dispose(Unit, F.F64, callback)
        R.dispose(generator)

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case "s" <> high <> low <> count <> Nil{}: seeded(H.decimal(high, 0), H.decimal(low, 0), U32.to_nat(H.decimal(count, 0)))
    case "c" <> high <> low <> count <> Nil{}: concurrent(H.decimal(high, 0), H.decimal(low, 0), U32.to_nat(H.decimal(count, 0)))
    case "f" <> path <> Nil{}:
      do IO<Unit>:
        value : Result<&2, &2, Seed.SeedError, W.U64> <- Seed.read(path)
        showSeed(value)
    case "r" <> Nil{}:
      do IO<Unit>:
        value : Result<&2, &2, Seed.SeedError, R.Generator> <- Seed.new()
        callbackCheck(value)
    case "u" <> hi <> lo <> Nil{}: IO.print(bits(F.toBits(R.unit(W.U64{H.decimal(hi, 0), H.decimal(lo, 0)}))))
    case _: IO.die(Unit, 1, "invalid random test")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)

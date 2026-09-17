import Base
import ../src/ref.bend as R

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

type RetainedEvent is Data:
  RetainedEvent{partial: R.Ref<String>}

def eventValue(event: RetainedEvent) -> IO(String):
  match event:
    case RetainedEvent{partial}: R.read(String, partial)

def increment(fuel: Nat, +reference: R.Ref<U32>) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+n:
      do IO<Unit>:
        R.modify(U32, Unit, reference, value => ((value + 1 : U32), Unit{}))
        increment(n, reference)

def spawnWorkers(fuel: Nat, +reference: R.Ref<U32>) -> IO(List<&2, Chan(Unit)>):
  match fuel:
    case 0n: IO.pure(List<&2, Chan(Unit)>, Nil{})
    case 1n+n:
      do IO<List<&2, Chan(Unit)>>:
        worker : Chan(Unit) <- IO.fork(Unit, increment(100n, reference))
        rest : List<&2, Chan(Unit)> <- spawnWorkers(n, reference)
        return worker <> rest

def joinWorkers(workers: List<&2, Chan(Unit)>) -> IO(Unit):
  match workers:
    case Nil{}: IO.pure(Unit, Unit{})
    case worker <> rest:
      do IO<Unit>:
        IO.join(Unit, worker)
        joinWorkers(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    +text : R.Ref<String> <- R.new(String, "initial")
    retained : RetainedEvent = RetainedEvent{text}
    old : String <- R.swap(String, text, "updated")
    assertion(String.eq(old, "initial"), "swap must return the previous value")
    observed : String <- eventValue(retained)
    assertion(String.eq(observed, "updated"), "retained events must see live updates")
    R.write(String, text, "final")
    observed : String <- R.read(String, text)
    assertion(String.eq(observed, "final"), "write/read round trip")
    +counter : R.Ref<U32> <- R.new(U32, 0)
    workers : List<&2, Chan(Unit)> <- spawnWorkers(10n, counter)
    joinWorkers(workers)
    count : U32 <- R.read(U32, counter)
    assertion(U32.is_eq(count, 1000), "concurrent updates must not lose increments")
    +array : R.Ref<Array<U32>> <- R.new(Array<U32>, [0 : U32*2n])
    R.modify(Array<U32>, Unit, array, values => (Array.set(U32, values, 0, 42), Unit{}))
    item : U32 <- R.modify(Array<U32>, U32, array, values => Array.get(U32, values, 0))
    assertion(U32.is_eq(item, 42), "affine arrays must remain usable through modify")
    discardedText : String <- R.dispose(String, text)
    discardedCounter : U32 <- R.dispose(U32, counter)
    discardedArray : Array<U32> <- R.dispose(Array<U32>, array)
    IO.print("ref: retained identity, replacement, atomic concurrent updates and affine ownership passed")

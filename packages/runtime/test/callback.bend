import Base
import ../src/callback.bend as C
import ../src/ref.bend as R

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def updated(previous: U32, amount: U32) -> U32 & U32:
  +sum = (previous + amount : U32)
  (sum, sum)

def accumulate(reference: R.Ref<U32>, amount: U32) -> IO(U32):
  R.modify(U32, U32, reference, previous => updated(previous, amount))

def repeat(fuel: Nat, +callback: C.Callback<U32, U32>) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+n:
      do IO<Unit>:
        value : U32 <- C.call(U32, U32, callback, 1)
        repeat(n, callback)

def changeArray(unused: Unit, values: Array<U32>) -> IO(Array<U32>):
  IO.pure(Array<U32>, Array.set(U32, values, 0, 23))

def checkArray(pair: Array<U32> & U32) -> IO(Unit):
  match pair:
    case Tuple{_, item}: assertion(U32.is_eq(item, 23), "affine callback input/output ownership")

type Gates is Data:
  Gates{started: Chan(Unit), release: Chan(Unit)}

def gated(environment: Gates, value: U32) -> IO(U32):
  match environment value:
    case Gates{started, release} 0:
      do IO<U32>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        ready : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return 10
    case Gates{_, release} value:
      do IO<U32>:
        sent : Bool <- Chan.send(Unit, release, Unit{})
        return value

def main() -> IO(Unit):
  do IO<Unit>:
    +counter : R.Ref<U32> <- R.new(U32, 0)
    +increment : C.Callback<U32, U32> <- C.create(~R.Ref<U32>, ~U32, ~U32, ~accumulate, counter)
    first : U32 <- C.call(U32, U32, increment, 5)
    second : U32 <- C.call(U32, U32, increment, 7)
    final : U32 <- R.read(U32, counter)
    assertion(U32.is_eq(first, 5) && U32.is_eq(second, 12) && U32.is_eq(final, 12), "callbacks must preserve captured shared state")
    repeat(U32.to_nat(1000), increment)
    final : U32 <- R.read(U32, counter)
    assertion(U32.is_eq(final, 1012), "callback factories must continue producing fresh closures")
    +affine : C.Callback<Array<U32>, Array<U32>> <- C.create(~Unit, ~Array<U32>, ~Array<U32>, ~changeArray, Unit{})
    values : Array<U32> <- C.call(Array<U32>, Array<U32>, affine, [0 : U32*2n])
    values : Array<U32> <- C.call(Array<U32>, Array<U32>, affine, values)
    checkArray(Array.get(U32, values, 0))
    C.dispose(Array<U32>, Array<U32>, affine)
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +callback : C.Callback<U32, U32> <- C.create(~Gates, ~U32, ~U32, ~gated, Gates{started, release})
    waiting : Chan(U32) <- IO.fork(U32, C.call(U32, U32, callback, 0))
    ready : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    second : U32 <- C.call(U32, U32, callback, 20)
    first : U32 <- IO.join(U32, waiting)
    assertion(U32.is_eq(first, 10) && U32.is_eq(second, 20), "awaiting callbacks must allow concurrent invocations")
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    C.dispose(U32, U32, increment)
    C.dispose(U32, U32, callback)
    previous : U32 <- R.dispose(U32, counter)
    IO.print("callback: reusable captured environments and concurrent async invocation passed")

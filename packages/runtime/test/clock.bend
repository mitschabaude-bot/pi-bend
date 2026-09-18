import Base
import ../src/clock.bend as C
import ../src/u64.bend as W
import ../src/f64.bend as F

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def ordered(order: Cmp) -> Bool:
  match order:
    case GT{}: False{}
    case _: True{}

def advanced(order: Cmp) -> Bool:
  match order:
    case LT{}: True{}
    case _: False{}

def finiteOrder(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{value}: ordered(value)
    case None{}: False{}

def sample(count: Nat, previous: W.U64) -> IO(W.U64):
  match count:
    case 0n: IO.pure(W.U64, previous)
    case 1n+ n:
      do IO<W.U64>:
        +current : W.U64 <- C.ticks()
        assertion(ordered(W.compare(previous, current)), "monotonic ticks moved backwards")
        sample(n, current)

def within(value: W.U64, lower: W.U64, upper: W.U64) -> Bool:
  +v = value
  ordered(W.compare(lower, v)) && ordered(W.compare(v, upper))

def main() -> IO(Unit):
  do IO<Unit>:
    +clock : C.Clock <- C.new()
    +before : W.U64 <- C.ticks()
    +after : W.U64 <- sample(U32.to_nat(1000), before)
    assertion(ordered(W.compare(before, after)), "tick sequence ordering")
    # A clock must advance, not merely return a constant nondecreasing value.
    # No exact latency is assumed; this wait is only a timer/clock liveness check.
    IO.sleep(2)
    +later : W.U64 <- C.ticks()
    assertion(advanced(W.compare(after, later)), "monotonic clock did not advance across a timer wait")
    task : Chan(W.U64) <- IO.fork(W.U64, C.ticks())
    concurrent : W.U64 <- IO.join(W.U64, task)
    end : W.U64 <- C.ticks()
    assertion(within(concurrent, later, end), "concurrent ticks must share the same epoch")
    +lower : F.F64 <- C.now(clock)
    +upper : F.F64 <- C.now(clock)
    assertion(finiteOrder(F.compare(lower, upper)), "elapsed clock moved backwards")
    IO.print("PASS exact monotonic tick ordering, shared epoch and elapsed time")

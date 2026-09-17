import Base
import ../src/u64.bend as W
import ../src/u128.bend as Wide

type Case is Data:
  Case{name: String, a: W.U64, b: W.U64, count: Nat, expected: List<&2, W.U64>, quotient: W.U64, remainder: W.U64, ordering: U32, fullHigh: W.U64, fullLow: W.U64, jamHigh: W.U64, jamLow: W.U64}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def checkValues(actual: List<&2, W.U64>, expected: List<&2, W.U64>, +label: String, +index: Nat) -> IO(Unit):
  match actual expected:
    case Nil{} Nil{}: IO.pure(Unit, Unit{})
    case a <> rest b <> tail:
      do IO<Unit>:
        assertion(W.equal(a, b), label ++ " operation " ++ Nat.show(index))
        checkValues(rest, tail, label, 1n+index)
    case _ _: IO.die(Unit, 1, "vector length mismatch")

def checkDivision(result: Maybe<&2, W.Division>, zeroDivisor: Bool, q: W.U64, r: W.U64, +label: String) -> IO(Unit):
  match result:
    case None{}: assertion(zeroDivisor, label ++ " unexpected division failure")
    case Some{W.Division{quotient, remainder}}:
      assertion(Bool.not(zeroDivisor) && W.equal(q, quotient) && W.equal(r, remainder), label ++ " quotient/remainder")

def orderCode(order: Cmp) -> U32:
  match order:
    case LT{}: 0
    case EQ{}: 1
    case GT{}: 2

def checkWide(actual: Wide.U128, high: W.U64, low: W.U64, label: String) -> IO(Unit):
  match actual:
    case Wide.U128{ah, al}: assertion(W.equal(ah, high) && W.equal(al, low), label)

def checkCase(test: Case) -> IO(Unit):
  match test:
    case Case{+name, +a, +b, +count, expected, quotient, remainder, +ordering, fullHigh, fullLow, jamHigh, jamLow}:
      values = {W.add(a, b) <> W.subtract(a, b) <> W.multiply(a, b) <> W.bitAnd(a, b) <> W.bitOr(a, b) <> W.bitXor(a, b) <> W.bitNot(a) <> W.shiftLeft(a, count) <> W.shiftRight(a, count) <> W.rotateLeft(a, count) <> W.rotateRight(a, count) <> Nil{} : List<&2, W.U64>}
      do IO<Unit>:
        checkValues(values, expected, name, 0n)
        checkDivision(W.divide(a, b), W.equal(b, W.zero()), quotient, remainder, name)
        assertion(U32.is_eq(orderCode(W.compare(a, b)), ordering), name ++ " comparison")
        assertion(Bool.pick(Bool, U32.is_eq(ordering, 1), W.equal(a, b), Bool.not(W.equal(a, b))), name ++ " equality")
        checkWide(Wide.multiply(a, b), fullHigh, fullLow, name ++ " full product")
        checkWide(Wide.shiftRightJam(Wide.multiply(a, b), count), jamHigh, jamLow, name ++ " wide shift/jam")

def checkAll(cases: List<&2, Case>) -> IO(Unit):
  match cases:
    case Nil{}: IO.print("u64: all native vector checks passed")
    case test <> rest:
      do IO<Unit>:
        checkCase(test)
        checkAll(rest)

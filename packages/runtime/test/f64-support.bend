import Base
import ../src/u64.bend as W
import ../src/f64.bend as F

type Case is Data:
  Case{name: String, a: F.F64, b: F.F64, sum: F.F64, difference: F.F64, product: F.F64, quotient: F.F64, ordering: U32, integer: W.U64, converted: F.F64}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def checkValue(+actual: F.F64, +expected: F.F64, label: String) -> IO(Unit):
  assertion(W.equal(F.toBits(actual), F.toBits(expected)) || (F.isNaN(actual) && F.isNaN(expected)), label)

def orderCode(order: Maybe<&2, Cmp>) -> U32:
  match order:
    case None{}: 3
    case Some{LT{}}: 0
    case Some{EQ{}}: 1
    case Some{GT{}}: 2

def checkCase(test: Case) -> IO(Unit):
  match test:
    case Case{+name, +a, +b, sum, difference, product, quotient, ordering, integer, converted}:
      do IO<Unit>:
        checkValue(F.add(a, b), sum, name ++ " addition")
        checkValue(F.subtract(a, b), difference, name ++ " subtraction")
        checkValue(F.multiply(a, b), product, name ++ " multiplication")
        checkValue(F.divide(a, b), quotient, name ++ " division")
        assertion(U32.is_eq(orderCode(F.compare(a, b)), ordering), name ++ " comparison")
        checkValue(F.fromU64(integer), converted, name ++ " integer conversion")

def checkAll(cases: List<&2, Case>) -> IO(Unit):
  match cases:
    case Nil{}: IO.print("f64: all native arithmetic checks passed")
    case test <> rest:
      do IO<Unit>:
        checkCase(test)
        checkAll(rest)

import Base
import ../src/u64.bend as W
import ../src/f64.bend as F

type Case is Data:
  Case{name: String, a: F.F64, b: F.F64, sum: F.F64, difference: F.F64}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def checkValue(+actual: F.F64, +expected: F.F64, label: String) -> IO(Unit):
  assertion(W.equal(F.toBits(actual), F.toBits(expected)) || (F.isNaN(actual) && F.isNaN(expected)), label)

def checkCase(test: Case) -> IO(Unit):
  match test:
    case Case{+name, +a, +b, sum, difference}:
      do IO<Unit>:
        checkValue(F.add(a, b), sum, name ++ " addition")
        checkValue(F.subtract(a, b), difference, name ++ " subtraction")

def checkAll(cases: List<&2, Case>) -> IO(Unit):
  match cases:
    case Nil{}: IO.print("f64: all native addition/subtraction checks passed")
    case test <> rest:
      do IO<Unit>:
        checkCase(test)
        checkAll(rest)

import Base
import ../src/big-nat.bend as B

type Case is Data:
  Case{label: String, a: B.BigNat, b: B.BigNat, shift: Nat, sum: B.BigNat, product: B.BigNat, difference: Maybe<&2, B.BigNat>, division: Maybe<&2, B.Division>, shifted: B.BigNat, order: Cmp, decimal: String, small: U32, smallDivision: Maybe<&2, B.SmallDivision>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def sameMaybe(actual: Maybe<&2, B.BigNat>, expected: Maybe<&2, B.BigNat>) -> Bool:
  match actual expected:
    case None{} None{}: True{}
    case Some{a} Some{b}: B.equal(a, b)
    case _ _: False{}

def sameBytes(actual: List<&2, U32>, expected: List<&2, U32>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case a <> as b <> bs: U32.is_eq(a, b) && sameBytes(as, bs)
    case _ _: False{}

def sameDivision(actual: Maybe<&2, B.Division>, expected: Maybe<&2, B.Division>) -> Bool:
  match actual expected:
    case None{} None{}: True{}
    case Some{B.Division{a, b}} Some{B.Division{c, d}}: B.equal(a, c) && B.equal(b, d)
    case _ _: False{}

def sameSmallDivision(actual: Maybe<&2, B.SmallDivision>, expected: Maybe<&2, B.SmallDivision>) -> Bool:
  match actual expected:
    case None{} None{}: True{}
    case Some{B.SmallDivision{a, b}} Some{B.SmallDivision{c, d}}: B.equal(a, c) && U32.is_eq(b, d)
    case _ _: False{}

def sameOrder(actual: Cmp, expected: Cmp) -> Bool:
  match actual expected:
    case LT{} LT{}: True{}
    case EQ{} EQ{}: True{}
    case GT{} GT{}: True{}
    case _ _: False{}

def checkRemainder(a: B.BigNat, b: B.BigNat, expected: Maybe<&2, B.Division>) -> IO(Unit):
  match expected:
    case None{}: IO.pure(Unit, Unit{})
    case Some{B.Division{_, value}}: assertion(B.equal(B.reduce(a, b), value), "modular reduction")

def check(test: Case) -> IO(Unit):
  match test:
    case Case{+label, +a, +b, shift, sum, product, difference, +division, shifted, order, +decimal, small, smallDivision}:
      do IO<Unit>:
        assertion(B.equal(B.add(a, b), sum), label ++ " addition")
        assertion(B.equal(B.multiply(a, b), product), label ++ " multiplication")
        assertion(sameMaybe(B.subtract(a, b), difference), label ++ " subtraction")
        assertion(sameDivision(B.divide(a, b), division), label ++ " division")
        checkRemainder(a, b, division)
        assertion(B.equal(B.shiftLeft(a, shift), shifted), label ++ " shift")
        assertion(sameOrder(B.compare(a, b), order), label ++ " comparison")
        assertion(String.eq(B.toDecimal(a), decimal), label ++ " decimal formatting")
        assertion(sameMaybe(B.fromDecimal(decimal), Some{a}), label ++ " decimal parsing")
        assertion(sameSmallDivision(B.divideSmall(a, small), smallDivision), label ++ " small division")

def checkAll(tests: List<&2, Case>) -> IO(Unit):
  match tests:
    case Nil{}: IO.pure(Unit, Unit{})
    case test <> rest:
      do IO<Unit>:
        check(test)
        checkAll(rest)

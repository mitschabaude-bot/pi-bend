import Base
import ../src/utils/schema-json.bend as C
import ../src/utils/json.bend as J
import ../../runtime/src/schema-value.bend as S

type Expected is Data:
  Json{text: String}
  Omitted{}
  BigInt{}
  Hook{}
  Invalid{}

def textMatches(actual: Maybe<&2, String>, expected: String) -> Bool:
  match actual:
    case None{}: False{}
    case Some{value}: String.eq(value, expected)

def matches(actual: C.Conversion, expected: Expected) -> Bool:
  match actual expected:
    case C.Converted{value} Json{text}: textMatches(J.stringify(value), text)
    case C.RootOmitted{} Omitted{}: True{}
    case C.BigIntError{} BigInt{}: True{}
    case C.UnsupportedToJSON{} Hook{}: True{}
    case C.InvalidSnapshot{} Invalid{}: True{}
    case _ _: False{}

def check(value: S.Value<U32>, expected: Expected, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), matches(C.toJson(U32, value), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def repeat(count: Nat, +char: Char) -> String:
  match count:
    case 0n: ""
    case 1n+n: SCon{char, repeat(n, char)}

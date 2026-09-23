import Base
import ../packages/runtime/src/prime-field.bend as F
import ../packages/runtime/src/big-nat.bend as Big
import ../packages/runtime/src/string.bend as S

def number(text: String) -> Big.BigNat:
  Maybe.default(&2,Big.BigNat,Big.fromDecimal(text),Big.zero())

def repeat(count: Nat, +prime: F.Prime, x: F.Field) -> F.Field:
  match count:
    case 0n: x
    case 1n+n: repeat(n,prime,F.square(prime,x))

def run(+prime: F.Prime, operation: String, a: String, b: String) -> F.Field:
  match operation:
    case "add": F.add(prime,F.fromBig(prime,number(a)),F.fromBig(prime,number(b)))
    case "sub": F.sub(prime,F.fromBig(prime,number(a)),F.fromBig(prime,number(b)))
    case "mul": F.mul(prime,F.fromBig(prime,number(a)),F.fromBig(prime,number(b)))
    case "scale": F.scale(prime,F.fromBig(prime,number(a)),Maybe.default(&2,U32,U32.read(b),0))
    case "bench": repeat(Maybe.default(&2,Nat,Nat.read(b),0n),prime,F.fromBig(prime,number(a)))
    case _: F.zero()

def selected(bits: String, op: String, a: String, b: String) -> F.Field:
  match bits:
    case "256": run(F.P256{},op,a,b)
    case _: run(F.P384{},op,a,b)

def parts(values: List<&2,String>) -> String:
  match values:
    case bits <> op <> a <> b <> Nil{}: Big.toDecimal(F.toBig(selected(bits,op,a,b)))
    case _: "invalid"

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(parts(S.split(value,':')))
        args(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

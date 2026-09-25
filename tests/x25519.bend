import Base
import ../packages/runtime/src/x25519.bend as X
import ../packages/runtime/src/string.bend as Split
import ./aes128-gcm.bend as Bytes

def show(result: Result<&2, &2, X.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{X.InvalidLength{}}: "length"
    case Fail{X.InvalidByte{}}: "byte"
    case Fail{X.LowOrderPoint{}}: "low-order"
    case Done{bytes}: Bytes.show(bytes)

def field(operation: String, +a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match operation:
    case "a": X.fieldAdd(a, b)
    case "d": X.fieldSubtract(a, b)
    case "m": X.fieldMultiply(a, b)
    case _: X.fieldInverse(a)

def first(values: List<&2, U32>) -> Nat:
  match values:
    case head <> _: U32.to_nat(head)
    case Nil{}: 0n

# RFC 7748 section 5.2's iteration: k, u = X25519(k, u), k.
def iterated(count: Nat, +k: List<&2, U32>, u: List<&2, U32>) -> Result<&2, &2, X.Error, List<&2, U32>>:
  match count:
    case 0n: Done{k}
    case 1n+rest: Result.bind(&2, &2, X.Error, List<&2, U32>, List<&2, U32>, X.scalarMult(k, u), next => iterated(rest, next, k))

def start9(count: Nat, +nine: List<&2, U32>) -> Result<&2, &2, X.Error, List<&2, U32>>: iterated(count, nine, nine)

def request(parts: List<&2, String>) -> String:
  match parts:
    case "x" <> scalar <> point <> Nil{}: show(X.scalarMult(Bytes.bytes(scalar), Bytes.bytes(point)))
    case "s" <> scalar <> point <> Nil{}: show(X.sharedSecret(Bytes.bytes(scalar), Bytes.bytes(point)))
    case "r" <> count <> start <> Nil{}: show(start9(first(Bytes.bytes(count)), Bytes.bytes(start)))
    case "p" <> scalar <> Nil{}: show(X.publicKey(Bytes.bytes(scalar)))
    case operation <> a <> b <> Nil{}: Bytes.show(field(operation, Bytes.bytes(a), Bytes.bytes(b)))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(request(Split.split(head, ':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

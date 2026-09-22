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
    case "a": X.add(a, b)
    case "d": X.subtract(a, b)
    case "m": X.multiply(a, b)
    case "i": X.inverse(a)
    case _: X.normalize(a)

def request(parts: List<&2, String>) -> String:
  match parts:
    case "x" <> scalar <> point <> Nil{}: show(X.scalarMult(Bytes.bytes(scalar), Bytes.bytes(point)))
    case "s" <> scalar <> point <> Nil{}: show(X.sharedSecret(Bytes.bytes(scalar), Bytes.bytes(point)))
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

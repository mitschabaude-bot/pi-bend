import Base
import ../packages/runtime/src/der.bend as DER
import ../packages/runtime/src/string-split.bend as Split
import ./aes128-gcm.bend as Bytes

def error(cause: DER.Error) -> String:
  match cause:
    case DER.Truncated{}: "truncated"
    case DER.InvalidByte{}: "byte"
    case DER.NonCanonical{}: "canonical"
    case DER.LimitExceeded{}: "limit"
    case DER.UnexpectedTag{}: "tag"
    case DER.InvalidValue{}: "value"
    case DER.TrailingData{}: "trailing"

def node(value: DER.Node) -> String:
  match value:
    case DER.Node{DER.Tag{class, constructed, number}, header, content}:
      U32.show(class) ++ ":" ++ Bool.pick(String, constructed, "1", "0") ++ ":" ++ U32.show(number) ++ "|" ++ Bytes.show(header) ++ "|" ++ Bytes.show(content)

def parsed(result: Result<&2, &2, DER.Error, DER.Read>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{DER.Read{value, rest}}: node(value) ++ "|" ++ Bytes.show(rest)

def whole(result: Result<&2, &2, DER.Error, DER.Node>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: Bytes.show(DER.encoded(value))

def unsigned(result: Result<&2, &2, DER.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: "ok:" ++ Bytes.show(value)

def bits(result: Result<&2, &2, DER.Error, DER.Bits>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{DER.Bits{unused, bytes}}: U32.show(unused) ++ ":" ++ Bytes.show(bytes)

def run(parts: List<&2, String>) -> String:
  match parts:
    case "r" <> bytes <> Nil{}: parsed(DER.read(Bytes.bytes(bytes)))
    case "o" <> bytes <> Nil{}: whole(DER.one(Bytes.bytes(bytes)))
    case "u" <> bytes <> Nil{}: unsigned(Result.bind(&2, &2, DER.Error, DER.Node, List<&2, U32>, DER.one(Bytes.bytes(bytes)), DER.unsigned))
    case "b" <> bytes <> Nil{}: bits(Result.bind(&2, &2, DER.Error, DER.Node, DER.Bits, DER.one(Bytes.bytes(bytes)), DER.bits))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

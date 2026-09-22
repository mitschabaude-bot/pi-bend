import Base
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/src/sha256.bend as SHA
import ../packages/runtime/src/hkdf-sha256.bend as HKDF
import ../packages/runtime/test/utf8-runner.bend as Bytes

def bytes(text: String) -> List<&2, U32>: Bytes.numbers(Split.split(text, ','))

def numbers(values: List<&2, U32>, first: Bool, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case head <> rest: numbers(rest, False{}, String.reverse(U32.show(head)) ++ Bytes.scalarSeparator(first, reversed))

def show(result: Result<&2, &2, HKDF.Error, List<&2, U32>>) -> String:
  match result:
    case Done{values}: "ok:" ++ numbers(values, True{}, "")
    case Fail{HKDF.InvalidLength{length}}: "length:" ++ U32.show(length)
    case Fail{HKDF.ShortKey{}}: "key"
    case Fail{HKDF.Hash{SHA.InvalidByte{value}}}: "byte:" ++ U32.show(value)
    case Fail{HKDF.Hash{SHA.MessageTooLong{}}}: "overflow"
    case Fail{HKDF.Hash{SHA.InvalidState{}}}: "state"

def request(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case key <> info <> length <> Nil{}:
      IO.print(show(HKDF.expand(bytes(key), bytes(info), Bytes.decimal(length, 0))))
    case salt <> input <> info <> length <> Nil{}:
      IO.print(show(HKDF.derive(bytes(salt), bytes(input), bytes(info), Bytes.decimal(length, 0))))
    case salt <> input <> Nil{}:
      IO.print(show(Result.bind(&2, &2, HKDF.Error, SHA.Digest, List<&2, U32>, HKDF.extract(bytes(salt), bytes(input)), hash => Done{SHA.toBytes(hash)})))
    case _: IO.print("request")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        request(Split.split(head, ':'))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

import Base
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/src/sha256.bend as SHA
import ../packages/runtime/src/hkdf-sha256.bend as HKDF
import ../packages/runtime/src/tls13-kdf.bend as TLS
import ../packages/runtime/test/utf8-runner.bend as Bytes

def bytes(text: String) -> List<&2, U32>: Bytes.numbers(Split.split(text, ','))

def numbers(values: List<&2, U32>, first: Bool, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case head <> rest: numbers(rest, False{}, String.reverse(U32.show(head)) ++ Bytes.scalarSeparator(first, reversed))

def show(result: Result<&2, &2, TLS.Error, List<&2, U32>>) -> String:
  match result:
    case Done{values}: "ok:" ++ numbers(values, True{}, "")
    case Fail{TLS.InvalidLabel{}}: "label"
    case Fail{TLS.InvalidContext{}}: "context"
    case Fail{TLS.InvalidLength{length}}: "length:" ++ U32.show(length)
    case Fail{TLS.Kdf{HKDF.InvalidLength{length}}}: "length:" ++ U32.show(length)
    case Fail{TLS.Kdf{HKDF.ShortKey{}}}: "key"
    case Fail{TLS.Kdf{HKDF.Hash{SHA.InvalidByte{value}}}}: "byte:" ++ U32.show(value)
    case Fail{_}: "hash"

def digestBytes(result: Result<&2, &2, TLS.Error, SHA.Digest>) -> Result<&2, &2, TLS.Error, List<&2, U32>>:
  Result.bind(&2, &2, TLS.Error, SHA.Digest, List<&2, U32>, result, hash => Done{SHA.toBytes(hash)})

def request(parts: List<&2, String>) -> Result<&2, &2, TLS.Error, List<&2, U32>>:
  match parts:
    case "e" <> label <> context <> length <> Nil{}:
      TLS.encodeLabel(label, bytes(context), Bytes.decimal(length, 0))
    case "x" <> key <> label <> context <> length <> Nil{}:
      TLS.expandLabel(bytes(key), label, bytes(context), Bytes.decimal(length, 0))
    case "a" <> key <> input <> Nil{}: digestBytes(TLS.advance(bytes(key), bytes(input)))
    case "d" <> key <> label <> messages <> Nil{}:
      Result.bind(&2, &2, TLS.Error, SHA.Digest, List<&2, U32>, TLS.kdfResult(SHA.Digest, HKDF.hashResult(SHA.Digest, SHA.digest(bytes(messages)))), hash => TLS.deriveSecret(bytes(key), label, hash))
    case "f" <> key <> messages <> Nil{}:
      Result.bind(&2, &2, TLS.Error, SHA.Digest, List<&2, U32>, TLS.kdfResult(SHA.Digest, HKDF.hashResult(SHA.Digest, SHA.digest(bytes(messages)))), hash => digestBytes(TLS.finished(bytes(key), hash)))
    case _: Fail{TLS.InvalidLabel{}}

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(request(Split.split(head, ':'))))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

import Base
import ../packages/runtime/src/aes128.bend as AES
import ../packages/runtime/src/aes128-gcm.bend as GCM
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Bytes

def parse(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: parse(rest, reversed)
    case head <> rest: parse(rest, Bytes.decimal(head, 0) <> reversed)

def bytes(text: String) -> List<&2, U32>: parse(Split.split(text, ','), Nil{})

def numbers(values: List<&2, U32>, first: Bool, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case head <> rest: numbers(rest, False{}, String.reverse(U32.show(head)) ++ Bytes.scalarSeparator(first, reversed))

def show(values: List<&2, U32>) -> String: numbers(values, True{}, "")

def nonce(block: Maybe<&2, AES.Block>) -> Maybe<&2, GCM.Nonce>:
  match block:
    case None{}: None{}
    case Some{AES.Block{a, b, c, _}}: Some{GCM.Nonce{a, b, c}}

def parseNonce(text: String) -> Maybe<&2, GCM.Nonce>:
  nonce(AES.fromBytes(List.append(&2, U32, bytes(text), 0 <> 0 <> 0 <> 1 <> Nil{})))

def error(value: GCM.Error) -> String:
  match value:
    case GCM.InvalidByte{}: "byte"
    case GCM.MessageTooLong{}: "length"
    case GCM.AuthenticationFailed{}: "authentication"

def sealed(result: Result<&2, &2, GCM.Error, GCM.Sealed>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{GCM.Sealed{text, tag}}: String.reverse.go(String.reverse(show(text)), ":" ++ show(AES.toBytes(tag)))

def opened(result: Result<&2, &2, GCM.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{text}: "ok:" ++ show(text)

def encrypt(key: Maybe<&2, AES.Block>, iv: Maybe<&2, GCM.Nonce>, aad: List<&2, U32>, text: List<&2, U32>) -> String:
  match key iv:
    case Some{key} Some{iv}: sealed(GCM.seal(GCM.key(key), iv, aad, text))
    case _ _: "invalid"

def decrypt(key: Maybe<&2, AES.Block>, iv: Maybe<&2, GCM.Nonce>, aad: List<&2, U32>, text: List<&2, U32>, tag: Maybe<&2, AES.Block>) -> String:
  match key iv tag:
    case Some{key} Some{iv} Some{tag}: opened(GCM.open(GCM.key(key), iv, aad, GCM.Sealed{text, tag}))
    case _ _ _: "invalid"

def request(parts: List<&2, String>) -> String:
  match parts:
    case "s" <> key <> iv <> aad <> text <> Nil{}: encrypt(AES.fromBytes(bytes(key)), parseNonce(iv), bytes(aad), bytes(text))
    case "o" <> key <> iv <> aad <> text <> tag <> Nil{}: decrypt(AES.fromBytes(bytes(key)), parseNonce(iv), bytes(aad), bytes(text), AES.fromBytes(bytes(tag)))
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

import Base
import ../packages/runtime/src/deflate.bend as D
import ../packages/runtime/src/string.bend as S
import ./aes128-gcm.bend as Bytes

def error(value: D.Error) -> String:
  match value:
    case D.InvalidByte{}: "byte"
    case D.UnexpectedEnd{}: "truncated"
    case D.InvalidHeader{}: "header"
    case D.HeaderCheck{}: "header-check"
    case D.DictionaryRequired{}: "dictionary"
    case D.InvalidBlock{}: "block"
    case D.StoredLength{}: "stored-length"
    case D.Oversubscribed{_}: "oversubscribed"
    case D.IncompleteTree{_}: "incomplete"
    case D.MissingEndCode{}: "end-code"
    case D.InvalidCode{}: "code"
    case D.InvalidRepeat{}: "repeat"
    case D.ReservedSymbol{}: "reserved"
    case D.InvalidDistance{_,_}: "distance"
    case D.OutputLimit{}: "limit"
    case D.Checksum{_,_}: "checksum"
    case D.TrailingData{}: "trailing"

def result(value: Result<&2,&2,D.Error,List<&2,U32>>) -> String:
  match value:
    case Fail{cause}: "error " ++ error(cause)
    case Done{bytes}: "ok " ++ Bytes.show(bytes)

def byteCount(bytes: List<&2,U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: byteCount(rest,1n + count)

def summary(value: Result<&2,&2,D.Error,List<&2,U32>>) -> String:
  match value:
    case Fail{cause}: "error " ++ error(cause)
    case Done{bytes}: "size " ++ Nat.show(byteCount(bytes,0n))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "raw" <> limit <> bytes <> Nil{}: result(D.inflateRaw(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case "zlib" <> limit <> bytes <> Nil{}: result(D.inflateZlib(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case "bench" <> limit <> bytes <> Nil{}: summary(D.inflateZlib(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case _: "invalid"

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(S.split(head,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

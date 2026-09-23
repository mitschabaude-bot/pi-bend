import Base
import ../packages/runtime/src/deflate-encode.bend as Encode
import ../packages/runtime/src/string.bend as S
import ./aes128-gcm.bend as Bytes

def result(value: Result<&2,&2,Encode.Error,List<&2,U32>>) -> String:
  match value:
    case Fail{Encode.InvalidByte{}}: "error byte"
    case Fail{Encode.InputLimit{}}: "error input"
    case Fail{Encode.OutputLimit{}}: "error limit"
    case Done{bytes}: "ok " ++ Bytes.show(bytes)

def repeat(count: Nat, +bytes: List<&2,U32>, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: List.reverse(&2,U32,reversed)
    case 1n+n: repeat(n,bytes,List.reverse.go(&2,U32,bytes,reversed))

def random(count: Nat, +state: U32, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: List.reverse(&2,U32,reversed)
    case 1n+n:
      +a = U32.xor(state,U32.shln(state,13n))
      +b = U32.xor(a,U32.shrn(a,17n))
      +c = U32.xor(b,U32.shln(b,5n))
      random(n,c,U32.and(c,255) <> reversed)

def encoded(mode: String, bytes: List<&2,U32>, limit: Nat) -> String:
  match mode:
    case "raw": result(Encode.compressRaw(bytes,limit))
    case _: result(Encode.compressZlib(bytes,limit))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "repeat" <> mode <> count <> limit <> bytes <> Nil{}: encoded(mode,repeat(Maybe.default(&2,Nat,Nat.read(count),0n),Bytes.bytes(bytes),Nil{}),Maybe.default(&2,Nat,Nat.read(limit),0n))
    case "random" <> mode <> count <> limit <> seed <> Nil{}: encoded(mode,random(Maybe.default(&2,Nat,Nat.read(count),0n),Maybe.default(&2,U32,U32.read(seed),1),Nil{}),Maybe.default(&2,Nat,Nat.read(limit),0n))
    case "raw" <> limit <> bytes <> Nil{}: result(Encode.compressRaw(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
    case "zlib" <> limit <> bytes <> Nil{}: result(Encode.compressZlib(Bytes.bytes(bytes),Maybe.default(&2,Nat,Nat.read(limit),0n)))
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

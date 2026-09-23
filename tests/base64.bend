import Base
import ../packages/runtime/src/base64.bend as Codec
import ./aes128-gcm.bend as Bytes

def encoded(result: Result<&2,&2,Codec.Error,String>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{value}: value

def decoded(result: Result<&2,&2,Codec.Error,List<&2,U32>>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{value}: Bytes.show(value)

def repeatedBytes(count: Nat, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: reversed
    case 1n+rest: repeatedBytes(rest,120 <> reversed)

def runSmall(+text: String) -> String:
  Bool.pick(Unit -> String,String.starts_with(text,"e:"),
    unit => encoded(Codec.encode(Bytes.bytes(String.drop(text,2n)))),
    unit => decoded(Codec.decode(String.drop(text,2n))))(Unit{})

def run(text: String) -> String:
  match text:
    case "large": encoded(Codec.encode(repeatedBytes(196608n,Nil{})))
    case "large-invalid": encoded(Codec.encode(repeatedBytes(196608n,256 <> Nil{})))
    case other: runSmall(other)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(head))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

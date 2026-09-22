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

def run(+text: String) -> String:
  Bool.pick(Unit -> String,String.starts_with(text,"e:"),
    unit => encoded(Codec.encode(Bytes.bytes(String.drop(text,2n)))),
    unit => decoded(Codec.decode(String.drop(text,2n))))(Unit{})

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

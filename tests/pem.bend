import Base
import ../packages/runtime/src/pem.bend as PEM
import ./aes128-gcm.bend as Bytes

def blocks(values: List<&2,PEM.Block>, reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2,String,reversed),"|")
    case PEM.Block{label,bytes} <> rest: blocks(rest,(label ++ ":" ++ Bytes.show(bytes)) <> reversed)

def result(parsed: Result<&2,&2,PEM.Error,List<&2,PEM.Block>>) -> String:
  match parsed:
    case Fail{_}: "error"
    case Done{values}: blocks(values,Nil{})

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(result(PEM.decode(head)))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

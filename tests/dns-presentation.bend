import Base
import ../packages/runtime/src/dns-presentation.bend as Presentation
import ../packages/runtime/src/dns-name.bend as Name

def csv(bytes: List<&2, U32>, acc: String) -> String:
  match bytes:
    case Nil{}: acc
    case byte <> rest: csv(rest, acc ++ U32.show(byte) ++ ",")

def wire(result: Result<&2, &2, Name.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{_}: "invalid-wire"
    case Done{bytes}: csv(bytes, "")

def show(value: Result<&2, &2, Presentation.Error, Presentation.Parsed>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{Presentation.Parsed{name, absolute}}: Bool.pick(String, absolute, "1:", "0:") ++ wire(Name.encode(name))

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(show(Presentation.parse(text)))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(Presentation.parseBytes(0 <> Nil{})))
    IO.print(show(Presentation.parseBytes(256 <> Nil{})))
    IO.print(show(Presentation.parseBytes(4294967295 <> Nil{})))
    args : List<String> <- IO.args()
    run(args)

import Base
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/src/dns-message.bend as Name

def csv(bytes: List<&2, U32>, acc: String) -> String:
  match bytes:
    case Nil{}: acc
    case byte <> rest: csv(rest, acc ++ U32.show(byte) ++ ",")

def wire(result: Result<&2, &2, Name.DomainNameError, List<&2, U32>>) -> String:
  match result:
    case Fail{_}: "invalid-wire"
    case Done{bytes}: csv(bytes, "")

def show(value: Result<&2, &2, Presentation.PresentationError, Presentation.PresentationParsed>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{Presentation.PresentationParsed{name, absolute}}: Bool.pick(String, absolute, "1:", "0:") ++ wire(Name.encodeName(name))

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(show(Presentation.parsePresentation(text)))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(Presentation.parseBytes(0 <> Nil{})))
    IO.print(show(Presentation.parseBytes(256 <> Nil{})))
    IO.print(show(Presentation.parseBytes(4294967295 <> Nil{})))
    args : List<String> <- IO.args()
    run(args)

import Base
import ../src/utf8.bend as Utf8

# Test-only decimal protocol: d<chunks>, b<complete bytes>, e<scalars>.
def decimal(text: String, value: U32) -> U32:
  match text:
    case SNil{}: value
    case SCon{Chr{digit}, rest}: decimal(rest, (value * 10 + digit - 48 : U32))

def numbers(parts: List<&2, String>) -> List<&2, U32>:
  match parts:
    case Nil{}: Nil{}
    case SNil{} <> rest: numbers(rest)
    case head <> rest: decimal(head, 0) <> numbers(rest)

def parseNumbers(text: String) -> List<&2, U32>:
  numbers(String.split(text, ','))

def showNumbers(values: List<&2, U32>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: U32.show(head) <> showNumbers(rest)

def scalars(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{code}, rest}: code <> scalars(rest)

def showText(text: String) -> String:
  String.join(showNumbers(scalars(text)), ",")

def fromScalars(values: List<&2, U32>) -> String:
  match values:
    case Nil{}: ""
    case head <> rest: SCon{Chr{head}, fromScalars(rest)}

def finished(result: Utf8.Decoded) -> String:
  match result:
    case Utf8.Decoded{_, text}: showText(text)

def streaming(parts: List<&2, String>, result: Utf8.Decoded) -> List<&2, String>:
  match parts result:
    case Nil{} Utf8.Decoded{decoder, text}: showText(text) <> finished(Utf8.finish(decoder)) <> Nil{}
    case part <> rest Utf8.Decoded{decoder, text}: showText(text) <> streaming(rest, Utf8.decode(decoder, parseNumbers(part)))

def decodeInput(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}: ""
    case part <> rest: String.join(streaming(rest, Utf8.decode(Utf8.create(), parseNumbers(part))), "|")

def run(argument: String) -> IO(Unit):
  match argument:
    case SCon{Chr{98}, text}: IO.print(showText(Utf8.decodeBytes(parseNumbers(text))))
    case SCon{Chr{100}, text}: IO.print(decodeInput(String.split(text, '|')))
    case SCon{Chr{101}, text}: IO.print(String.join(showNumbers(Utf8.encode(fromScalars(parseNumbers(text)))), ","))
    case _: IO.pure(Unit, Unit{})

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(head)
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)

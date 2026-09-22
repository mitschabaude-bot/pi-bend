import Base
import ../src/sse.bend as Lines
import ./utf8-runner.bend as H

def showLines(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case head <> tail: ("[" ++ H.showText(head) ++ "]") <> showLines(tail)

def instruction(decoder: Lines.LineDecoder, operation: String) -> Lines.Decoded:
  match operation:
    case SCon{Chr{98}, bytes}: Lines.decode(decoder, H.parseNumbers(bytes))
    case SCon{Chr{116}, scalars}: Lines.decodeText(decoder, H.fromScalars(H.parseNumbers(scalars)))
    case SCon{Chr{110}, _}: Lines.decodeOptional(decoder, None{})
    case SCon{Chr{102}, _}: Lines.flush(decoder)
    case _: Lines.decode(decoder, Nil{})

def execute(operations: List<&2, String>, result: Lines.Decoded) -> List<&2, String>:
  match operations result:
    case Nil{} Lines.Decoded{_, lines}: String.join(showLines(lines), ";") <> Nil{}
    case operation <> rest Lines.Decoded{decoder, lines}: String.join(showLines(lines), ";") <> execute(rest, instruction(decoder, operation))

def start(operations: List<&2, String>) -> String:
  match operations:
    case Nil{}: ""
    case operation <> rest: String.join(execute(rest, instruction(Lines.create(), operation)), "|")

def showIndex(index: Maybe<&2, Nat>) -> String:
  match index:
    case None{}: "-1"
    case Some{value}: Nat.show(value)

def run(argument: String) -> IO(Unit):
  match argument:
    case SCon{Chr{108}, text}: IO.print(start(String.split(text, '|')))
    case SCon{Chr{105}, text}: IO.print(showIndex(Lines.findDoubleNewlineIndex(H.parseNumbers(text))))
    case _: IO.pure(Unit, Unit{})

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        run(head)
        all(tail)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)

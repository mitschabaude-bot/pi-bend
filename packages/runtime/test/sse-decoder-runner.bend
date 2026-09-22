import Base
import ../src/sse.bend as SSE
import ./utf8-runner.bend as H

def showName(name: Maybe<&2, String>) -> String:
  match name:
    case None{}: "N"
    case Some{text}: "S" ++ H.showText(text)

def showRaw(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case head <> tail: ("[" ++ H.showText(head) ++ "]") <> showRaw(tail)

def showEvent(event: Maybe<&2, SSE.ServerSentEvent>) -> String:
  match event:
    case None{}: "-"
    case Some{SSE.ServerSentEvent{name, data, raw}}: showName(name) ++ "/" ++ H.showText(data) ++ "/" ++ String.join(showRaw(raw), ";")

def execute(lines: List<&2, String>, result: SSE.DecoderDecoded) -> List<&2, String>:
  match lines result:
    case Nil{} SSE.DecoderDecoded{_, event}: showEvent(event) <> Nil{}
    case line <> rest SSE.DecoderDecoded{decoder, event}: showEvent(event) <> execute(rest, SSE.decoderStep(decoder, H.fromScalars(H.parseNumbers(line))))

def start(lines: List<&2, String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> rest: String.join(execute(rest, SSE.decoderStep(SSE.createDecoder(), H.fromScalars(H.parseNumbers(line)))), "|")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case SCon{Chr{115}, text} <> rest:
      do IO<Unit>:
        IO.print(start(String.split(text, '|')))
        all(rest)
    case _ <> rest: all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)

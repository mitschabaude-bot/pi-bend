import Base
import ../src/http-message.bend as Body
import ../src/http-message.bend as Framing
import ../src/http-message.bend as Headers
import ../src/http-message.bend as H
import ./utf8-runner.bend as Text

def input(value: String) -> Body.Input:
  match value:
    case "absent": Body.Absent{}
    case "empty": Body.Text{""}
    case _: Body.Text{"abc"}

def set(headers: Headers.Headers, name: String, value: String) -> Headers.Headers:
  match value:
    case SCon{Chr{43}, rest}: Headers.appendField(headers, H.Header{name, H.trimHeader(Text.fromScalars(Text.parseNumbers(rest)))})
    case _: headers

def field(value: Result<&2, &2, H.HeaderHeaderError, Maybe<&2, String>>) -> String:
  match value:
    case Done{Some{text}}: "+" ++ Text.showText(text)
    case _: "-"

def show(value: Result<&2, &2, Framing.FramingError, Framing.BufferedFramingPrepared>) -> String:
  match value:
    case Fail{_}: "error"
    case Done{Framing.BufferedFramingPrepared{Body.Prepared{_, +headers, content}, encoding}}: field(Headers.get(headers, "content-length")) ++ ";" ++ field(Headers.get(headers, "transfer-encoding")) ++ ";" ++ String.join(Text.showNumbers(Framing.wireContent(content, encoding)), ",")

def prepared(value: Result<&2, &2, Body.BufferedBodyBodyError, Body.Prepared>) -> String:
  match value:
    case Fail{_}: "error"
    case Done{request}: show(Framing.prepareBufferedFraming(request))

def run(parts: List<&2, String>) -> String:
  match parts:
    case method <> body <> length <> transfer <> Nil{}:
      prepared(Body.prepare(method, set(set(Headers.new(), "content-length", length), "transfer-encoding", transfer), input(body)))
    case _: "bad-fixture"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print(run(String.split(first, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)

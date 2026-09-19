import Base
import ../src/http-buffered-body.bend as Body
import ../src/headers.bend as Headers
import ../src/http-header.bend as H
import ./utf8-runner.bend as Text
import ../src/big-nat.bend as N

def zeros(count: Nat) -> List<&2, U32>:
  match count:
    case Zero{}: Nil{}
    case Succ{rest}: 0 <> zeros(rest)

def input(kind: String, value: String) -> Body.Input:
  match kind:
    case "absent": Body.Absent{}
    case "repeat": Body.Bytes{zeros(U32.to_nat(Text.decimal(value, 0)))}
    case "text": Body.Text{Text.fromScalars(Text.parseNumbers(value))}
    case _: Body.Bytes{Text.parseNumbers(value)}

def headers(value: String) -> Headers.Headers:
  match value:
    case SCon{Chr{43}, rest}: Headers.appendField(Headers.new(), H.Header{"content-type", Text.fromScalars(Text.parseNumbers(rest))})
    case _: Headers.new()

def content(value: Maybe<&2, Body.Content>) -> String:
  match value:
    case None{}: "absent"
    case Some{Body.Content{bytes, length}}: N.toDecimal(length) ++ ":" ++ String.join(Text.showNumbers(bytes), ",")

def field(value: Result<&2, &2, H.HeaderError, Maybe<&2, String>>) -> String:
  match value:
    case Done{Some{text}}: "+" ++ Text.showText(text)
    case _: "-"

def show(value: Result<&2, &2, Body.BodyError, Body.Prepared>) -> String:
  match value:
    case Fail{Body.InvalidByte{byte}}: "invalid-byte:" ++ U32.show(byte)
    case Fail{_}: "error"
    case Done{Body.Prepared{method, headers, body}}: Text.showText(method) ++ ";" ++ field(Headers.get(headers, "content-type")) ++ ";" ++ content(body)

def run(parts: List<&2, String>) -> String:
  match parts:
    case method <> kind <> value <> fields <> Nil{}: show(Body.prepare(Text.fromScalars(Text.parseNumbers(method)), headers(fields), input(kind, value)))
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

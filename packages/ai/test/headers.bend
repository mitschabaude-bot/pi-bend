import Base
import ../../runtime/src/http-message.bend as Native
import ../../runtime/src/http-message.bend as H
import ../../runtime/src/record.bend as R
import ../../runtime/test/utf8-runner.bend as T
import ../src/utils/headers.bend as AI

def decode(text: String) -> String: T.fromScalars(T.parseNumbers(text))

def showEntries(items: List<&2, H.Header>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case H.Header{name, value} <> rest: (T.showText(name) ++ ";" ++ T.showText(value)) <> showEntries(rest)

def showValues(items: List<&2, String>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case value <> rest: T.showText(value) <> showValues(rest)

def showRecord(items: List<&2, R.Property<String>>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (T.showText(name) ++ ";" ++ T.showText(value)) <> showRecord(rest)

def snapshot(+headers: Native.Headers) -> String:
  String.join(showEntries(Native.entries(headers)), "|") ++ "/" ++ String.join(showValues(Native.getSetCookie(headers)), "|") ++ "/" ++ String.join(showRecord(R.entries(String, AI.headersToRecord(headers))), "|")

type Step is Data:
  Step{headers: Native.Headers, result: String}

def updated(original: Native.Headers, result: Result<&2, &2, H.HeaderHeaderError, Native.Headers>) -> Step:
  match result:
    case Fail{_}: Step{original, "error"}
    case Done{headers}: Step{headers, "ok"}

def showGet(result: Result<&2, &2, H.HeaderHeaderError, Maybe<&2, String>>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{None{}}: "none"
    case Done{Some{value}}: "some:" ++ T.showText(value)

def showHas(result: Result<&2, &2, H.HeaderHeaderError, Bool>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{True{}}: "true"
    case Done{False{}}: "false"

def operation(parts: List<&2, String>, +headers: Native.Headers) -> Step:
  match parts:
    case "a" <> name <> value <> Nil{}: updated(headers, Native.append(headers, decode(name), decode(value)))
    case "s" <> name <> value <> Nil{}: updated(headers, Native.set(headers, decode(name), decode(value)))
    case "d" <> name <> Nil{}: updated(headers, Native.delete(headers, decode(name)))
    case "g" <> name <> Nil{}: Step{headers, showGet(Native.get(headers, decode(name)))}
    case "h" <> name <> Nil{}: Step{headers, showHas(Native.has(headers, decode(name)))}
    case _: Step{headers, "bad-fixture"}

def trace(before: String, step: Step) -> String:
  match step:
    case Step{headers, result}: before ++ ">" ++ result ++ ">" ++ snapshot(headers)

def next(step: Step) -> Native.Headers:
  match step:
    case Step{headers, _}: headers

def run(operations: List<&2, String>, +headers: Native.Headers) -> List<&2, String>:
  match operations:
    case Nil{}: Nil{}
    case op <> rest:
      +step = operation(String.split(op, ';'), headers)
      trace(snapshot(headers), step) <> run(rest, next(step))

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(String.join(run(String.split(head, '|'), Native.new()), "~"))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)

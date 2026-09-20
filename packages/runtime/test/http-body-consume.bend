import Base
import ../src/http-body-consume.bend as Consume
import ../src/http-body-buffer.bend as Buffer
import ../src/http-response.bend as Response
import ../src/http-response-progress.bend as Progress
import ../src/utf8-strict.bend as UTF8
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ../src/u64.bend as W
import ./http-response.bend as Input
import ./utf8-runner.bend as Text

def primary(value: Buffer.PrimaryError<String>) -> String:
  match value:
    case Buffer.ReadFailure{cause}: Input.error(cause)
    case Buffer.ByteLimitExceeded{}: "limit"

def failure(value: Buffer.Error<String>) -> String:
  match value:
    case Buffer.PrimaryFailure{cause}: primary(cause)
    case Buffer.CleanupFailure{cause}: Input.error(cause)
    case Buffer.FailureWithCleanup{cause, cleanup}: primary(cause) ++ "+" ++ Input.error(cleanup)

def textFailure(value: Consume.TextError<String>) -> String:
  match value:
    case Consume.BodyFailure{cause}: failure(cause)
    case Consume.InvalidUTF8{UTF8.InvalidByte{offset, byte}}: "byte:" ++ Nat.show(offset) ++ ":" ++ U32.show(byte)
    case Consume.InvalidUTF8{UTF8.InvalidSequence{offset, byte}}: "utf8:" ++ Nat.show(offset) ++ ":" ++ U32.show(byte)
    case Consume.InvalidUTF8{UTF8.IncompleteSequence{offset}}: "incomplete:" ++ Nat.show(offset)

def shownBytes(value: Result<&2, &2, Buffer.Error<String>, List<&2, U32>>) -> String:
  match value:
    case Fail{cause}: "error:" ++ failure(cause)
    case Done{bytes}: "bytes:" ++ String.join(Text.showNumbers(bytes), ",")

def shownText(value: Result<&2, &2, Consume.TextError<String>, String>) -> String:
  match value:
    case Fail{cause}: "error:" ++ textFailure(cause)
    case Done{text}: "text:" ++ Text.showText(text)

def number(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ "," ++ U32.show(low)

type Part is Data:
  ValuePart{value: V.Value}
  ArrayPart{values: List<&2, V.Value>}
  ObjectPart{values: List<&2, R.Property<V.Value>>}
  Literal{text: String}

# Test-only traversal/rendering of nested values; no production JSON encoding.
@unsafe def render(parts: List<&2, Part>, output: String) -> String:
  match parts:
    case Nil{}: output
    case Literal{text} <> rest: render(rest, output ++ text)
    case ValuePart{V.Null{}} <> rest: render(rest, output ++ "null")
    case ValuePart{V.Boolean{flag}} <> rest: render(rest, output ++ Bool.pick(String, flag, "true", "false"))
    case ValuePart{V.Number{value}} <> rest: render(rest, output ++ "n" ++ number(F.toBits(value)))
    case ValuePart{V.Text{text}} <> rest: render(rest, output ++ "s" ++ Text.showText(text))
    case ValuePart{V.ArrayValue{values}} <> rest: render(ArrayPart{values} <> Literal{"]"} <> rest, output ++ "[")
    case ValuePart{V.ObjectValue{fields}} <> rest: render(ObjectPart{R.entries(V.Value, fields)} <> Literal{"}"} <> rest, output ++ "{")
    case ArrayPart{Nil{}} <> rest: render(rest, output)
    case ArrayPart{first <> tail} <> rest: render(ValuePart{first} <> Literal{";"} <> ArrayPart{tail} <> rest, output)
    case ObjectPart{Nil{}} <> rest: render(rest, output)
    case ObjectPart{R.Property{key, value} <> tail} <> rest: render(ValuePart{value} <> Literal{";"} <> ObjectPart{tail} <> rest, output ++ Text.showText(key) ++ "=")

def show(value: V.Value) -> String:
  render(ValuePart{value} <> Nil{}, "")

def shownJSON(value: Result<&2, &2, Consume.JSONError<String>, V.Value>) -> String:
  match value:
    case Fail{Consume.TextFailure{cause}}: "error:" ++ textFailure(cause)
    case Fail{Consume.InvalidJSON{_}}: "error:json"
    case Done{value}: "json:" ++ show(value)

def consume(mode: String, limit: Nat, body: Response.Body<Input.State>) -> IO(Unit):
  match mode:
    case "text":
      do IO<Unit>:
        result : Result<&2, &2, Consume.TextError<String>, String> <- Consume.textWith(String, Input.State, Input.read, Input.close, limit, body)
        IO.print(shownText(result))
    case "json":
      do IO<Unit>:
        result : Result<&2, &2, Consume.JSONError<String>, V.Value> <- Consume.jsonWith(String, Input.State, Input.read, Input.close, limit, body)
        IO.print(shownJSON(result))
    case _:
      do IO<Unit>:
        result : Result<&2, &2, Buffer.Error<String>, List<&2, U32>> <- Consume.bytesWith(String, Input.State, Input.read, Input.close, limit, body)
        IO.print(shownBytes(result))

def started(mode: String, limit: Nat, value: Result<&2, &1, Progress.Error<String>, Response.Response<Input.State>>) -> IO(Unit):
  match value:
    case Fail{cause}: IO.print("start-error:" ++ Input.error(cause))
    case Done{Response.Response{_, body}}: consume(mode, limit, body)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case fails <> mode <> limit <> events:
      do IO<Unit>:
        value : Result<&2, &1, Progress.Error<String>, Response.Response<Input.State>> <- Response.startWith(String, Input.State, Input.read, Input.close, Input.State{events, String.eq(fails, "1")})
        started(mode, U32.to_nat(Text.decimal(limit, 0)), value)
    case _: IO.die(Unit, 1, "expected cleanup mode budget events")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print("case")
        run(String.split(first, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)

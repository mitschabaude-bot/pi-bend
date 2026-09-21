import Base
import ../packages/ai/src/api/openai-responses-stream-error.bend as Format
import ../packages/runtime/src/json-parse.bend as Parse
import ../packages/runtime/src/json-decode.bend as Decode
import ../packages/runtime/src/json-string.bend as Quote
import ../packages/runtime/src/schema-value.bend as V
import ../packages/ai/src/utils/error-body.bend as Body

def display(result: Format.Formatted()) -> IO(Unit):
  match result:
    case Done{text}: IO.print(Quote.quote(text))
    case Fail{Body.NonJsonBody{}}: IO.print("encoding failure")
    case Fail{Body.NumberFormattingFailure{}}: IO.print("number formatting failure")

def parsed(result: Result<&2, &2, Parse.Error, V.Value>) -> IO(Unit):
  match result:
    case Done{value}: display(Format.api(value))
    case Fail{_}: IO.die(Unit, 1, "invalid fixture JSON")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case "api" <> text <> Nil{}: parsed(Parse.parse(text))
    case "protocol" <> Nil{}:
      do IO<Unit>:
        display(Done{Format.protocol(Decode.MissingField{Nil{}})})
        display(Done{Format.protocol(Decode.WrongType{Decode.Field{"a.b[\"😀\"]"} <> Decode.Index{2n} <> Decode.Field{"0"} <> Nil{}, "string"})})
        display(Done{Format.protocol(Decode.InvalidValue{Decode.Index{0n} <> Nil{}, "finite number"})})
    case _: IO.die(Unit, 1, "expected api JSON or protocol")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

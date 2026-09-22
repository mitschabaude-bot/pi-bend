import Base
import ../src/types.bend as T
import ../src/utils/headers.bend as Provider
import ../src/utils/headers.bend as Projection
import ../src/api/openai-responses.bend as Responses
import ../../runtime/src/headers.bend as Native
import ../../runtime/src/http-header.bend as Field
import ../../runtime/src/record.bend as R
import ./provider-headers.bend as Input
import ./headers.bend as Output
import ../../runtime/test/utf8-runner.bend as Text

def configuration(encoded: String) -> T.ProviderHeaders():
  Input.build(String.split(encoded, '|'), R.new(T.Nullable<String>))

def strings(encoded: String) -> Maybe<&2, R.Record<String>>:
  Projection.providerHeadersToRecord(Some{configuration(encoded)})

def session(encoded: String) -> Maybe<&2, String>:
  match encoded:
    case "n": None{}
    case SCon{_, rest}: Some{Input.text(rest)}
    case _: None{}

def affinity(encoded: String) -> T.SessionAffinityFormat:
  match encoded:
    case "router": T.OpenRouterSession{}
    case "none": T.OpenAINoSession{}
    case _: T.OpenAISession{}

def showValue(value: T.Nullable<String>) -> String:
  match value:
    case T.NullValue{}: "~"
    case T.PresentValue{text}: Text.showText(text)

def showProperties(properties: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, String>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest:
      (Text.showText(name) ++ ";" ++ showValue(value)) <> showProperties(rest)

def applyDefaults(defaults: T.ProviderHeaders(), base: Result<&2, &2, Field.HeaderError, Native.Headers>) -> Result<&2, &2, Field.HeaderError, Native.Headers>:
  match base:
    case Fail{error}: Fail{error}
    case Done{headers}: Provider.apply(headers, Some{defaults})

def showApplied(result: Result<&2, &2, Field.HeaderError, Native.Headers>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{headers}: "ok:" ++ Output.snapshot(headers)

def render(+defaults: T.ProviderHeaders(), base: T.ProviderHeaders()) -> String:
  String.join(showProperties(R.entries(T.Nullable<String>, defaults)), "|") ++ "#" ++ showApplied(applyDefaults(defaults, Provider.apply(Native.new(), Some{base})))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case agent <> model <> copilot <> format <> sid <> options <> base <> Nil{}:
      IO.print(render(Responses.defaultHeaders(Input.text(agent), strings(model), strings(copilot), affinity(format), session(sid), Some{configuration(options)}), configuration(base)))
    case _: IO.die(Unit, 1, "invalid request headers fixture")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(String.split(head, '#'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)

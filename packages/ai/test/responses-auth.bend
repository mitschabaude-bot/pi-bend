import Base
import ../src/api/openai-responses.bend as Auth
import ../src/types.bend as T
import ../../runtime/test/utf8-runner.bend as Text
import ./provider-headers.bend as Input
import ./request-headers.bend as Request

def result(value: Result<&2, &2, String, String>) -> String:
  match value:
    case Done{key}: "ok:" ++ Text.showText(key)
    case Fail{provider}: "error:" ++ Text.showText("No API key for provider: " ++ provider)

def optionalHeaders(text: String) -> Maybe<&2, T.ProviderHeaders()>:
  match text:
    case "n": None{}
    case SCon{_, rest}: Some{Request.configuration(rest)}
    case _: None{}

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case provider <> key <> headers <> Nil{}:
      IO.print(result(Auth.getClientApiKey(Input.text(provider), Request.session(key), optionalHeaders(headers))))
    case _: IO.die(Unit, 1, "invalid auth fixture")

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

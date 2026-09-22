import Base
import ../packages/ai/test/openai-responses-request.bend as Fixture
import ../packages/ai/test/openai-responses-policy-runner.bend as P
import ../packages/ai/src/api/openai-responses.bend as Request
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/test/utf8-runner.bend as H

def checkCase(mode: String, +flags: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Request.BuildError,T.JsonValue> <- Request.buildParams(~Unit,~Unit,~Unit,~Unit,~Unit,Fixture.model(P.compat(String.split(flags,'.'))),Fixture.context(H.decimal(mode,0)),Fixture.settings(),Request.getCodexCompat("openai-codex","https://example.test",P.compat(String.split(flags,'.'))),R.new(String),T.CacheLong{},Request.CodexEndpoint{})
    Fixture.check(Fixture.output(result),Json.parse(H.fromScalars(H.parseNumbers(expected))))

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS Codex request")
    case mode <> flags <> expected <> rest:
      do IO<Unit>:
        checkCase(mode,flags,expected)
        cases(rest)
    case _: IO.die(Unit,1,"invalid Codex request fixture")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)

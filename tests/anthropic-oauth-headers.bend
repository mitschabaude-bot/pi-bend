import Base
import ../packages/ai/src/api/anthropic-messages-client.bend as Client
import ../packages/runtime/src/http-message.bend as Headers

# Claude Code identity is required for OAuth requests, and must not leak into
# ordinary API-key requests. Every upstream client sends
# anthropic-dangerous-direct-browser-access.
def same(actual: Maybe<&2,String>,want: Maybe<&2,String>) -> Bool:
  match actual want:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a,b)
    case _ _: False{}
def checkFound(result: Result<&2,&2,Headers.HeaderSyntaxError,Maybe<&2,String>>,name: String,want: Maybe<&2,String>) -> IO(Unit):
  match result:
    case Done{actual}:
      Bool.pick(Unit -> IO(Unit),same(actual,want),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"wrong Anthropic header: " ++ name))(Unit{})
    case Fail{_}: IO.die(Unit,1,"invalid Anthropic header: " ++ name)
def check(headers: Headers.Headers,+name: String,want: Maybe<&2,String>) -> IO(Unit):
  checkFound(Headers.get(headers,name),name,want)
def checkAuth(+headers: Headers.Headers,oauth: Bool) -> IO(Unit):
  match oauth:
    case True{}:
      do IO<Unit>:
        check(headers,"authorization",Some{"Bearer sk-ant-oat-test"})
        check(headers,"user-agent",Some{"claude-cli/2.1.280"})
        check(headers,"x-app",Some{"cli"})
        check(headers,"anthropic-dangerous-direct-browser-access",Some{"true"})
    case False{}:
      do IO<Unit>:
        check(headers,"x-api-key",Some{"test-key"})
        check(headers,"x-app",None{})
def checked(result: Result<&2,&2,Headers.HeaderSyntaxError,Headers.Headers>,oauth: Bool) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"invalid request headers")
    case Done{+headers}:
      do IO<Unit>:
        check(headers,"anthropic-version",Some{"2023-06-01"})
        check(headers,"anthropic-dangerous-direct-browser-access",Some{"true"})
        checkAuth(headers,oauth)
def main() -> IO(Unit):
  do IO<Unit>:
    checked(Client.requestHeaders(Some{"sk-ant-oat-test"},None{},None{}),True{})
    checked(Client.requestHeaders(Some{"test-key"},None{},None{}),False{})

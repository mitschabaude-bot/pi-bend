import Base
import ../packages/runtime/src/pi-user-agent.bend as UserAgent

def report(value: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match value:
    case Fail{(code, _)}: IO.print("error:" ++ U32.show(code))
    case Done{agent}: IO.print(agent)

def main() -> IO(Unit):
  do IO<Unit>:
    identity : Result<&1, &1, U32 & String, String> <- UserAgent.get()
    report(identity)

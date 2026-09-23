import Base
import ../packages/coding-agent/src/cli/auth-login.bend as Login
import ../packages/ai/src/auth/oauth/openai-codex.bend as Codex

def run(args: List<&2, String>) -> IO(Unit):
  match args:
    case +base <> Nil{}:
      Login.runWithEndpoints(Codex.DeviceEndpoints{base ++ "/usercode", base ++ "/token", base ++ "/exchange", base ++ "/codex/device"})
    case _: IO.die(Unit, 1, "expected local mock origin")

def shared(values: List<&1, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> shared(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(shared(args))

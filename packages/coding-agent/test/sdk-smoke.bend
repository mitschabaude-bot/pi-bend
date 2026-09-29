import Base
import ../src/core/sdk.bend as Sdk

# Package-local entrypoint keeps SDK assembly typechecked despite BEND-056
# affecting the broader tests/ fixture. Pass a fresh directory with PI_OFFLINE=1.

def finished(result: Sdk.Outcome()) -> IO(Unit):
  match result:
    case Done{session}:
      do IO<Unit>:
        Sdk.dispose(session)
        IO.print("sdk session created and disposed")
    case Fail{message}: IO.die(Unit, 1, message)

def run(args: List<String>) -> IO(Unit):
  match args:
    case +directory <> Nil{}:
      do IO<Unit>:
        result : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, None{}, None{}, None{}, Nil{}, None{}, None{}, None{}, None{}, None{}, None{}, Nil{}})
        finished(result)
    case _: IO.die(Unit, 1, "expected isolated directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

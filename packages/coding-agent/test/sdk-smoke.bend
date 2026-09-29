import Base
import ../src/core/sdk.bend as Sdk
import ../src/core/agent-session.bend as Session
import ../src/core/extensions/types.bend as Ext

# Package-local entrypoint keeps SDK assembly typechecked despite BEND-056
# affecting the broader tests/ fixture. Pass a fresh directory with PI_OFFLINE=1.

def isRequestedStart(event: Ext.SessionStartEvent) -> Bool:
  match event:
    case Ext.SessionStartEvent{Ext.ResumeStart{}, Some{previous}}: String.eq(previous, "previous.jsonl")
    case _: False{}

def checkedSession(pair: Sdk.CreateAgentSessionResult & Session.AgentSession) -> IO(Unit):
  match pair:
    case Tuple{owner, live}:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit), isRequestedStart(Session.initialStartEvent(live)), _ => IO.pure(Unit, Unit{}), _ => IO.die(Unit, 1, "SDK lost the supplied session start event"))(Unit{})
        Sdk.dispose(owner)
        IO.print("sdk session created, retained start event, and disposed")

def finishedSession(result: Sdk.CreateAgentSessionResult) -> IO(Unit): checkedSession(Sdk.sessionOf(result))

def finished(result: Sdk.Outcome()) -> IO(Unit):
  match result:
    case Done{session}: finishedSession(session)
    case Fail{message}: IO.die(Unit, 1, message)

def run(args: List<String>) -> IO(Unit):
  match args:
    case +directory <> Nil{}:
      do IO<Unit>:
        result : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, None{}, None{}, None{}, Nil{}, None{}, None{}, None{}, None{}, None{}, None{}, Nil{}, Some{Ext.SessionStartEvent{Ext.ResumeStart{}, Some{"previous.jsonl"}}}})
        finished(result)
    case _: IO.die(Unit, 1, "expected isolated directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

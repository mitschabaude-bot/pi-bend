import Base
import ./agent-session.bend as Faux
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Stored
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ./rpc-host-fixture.bend as RpcHost
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/callback.bend as Callback

def capture(lines: Ref.Ref<List<&2,String>>,line: String) -> IO(Unit):
  Ref.modify(List<&2,String>,Unit,lines,current => (List.append(&2,String,current,line <> Nil{}),Unit{}))
def output(lines: List<&2,String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case line <> rest:
      do IO<Unit>:
        IO.write(line)
        output(rest)
def runCommands(pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        Rpc.feed(handle,"{\"id\":\"compaction\",\"type\":\"set_auto_compaction\",\"enabled\":false}\n")
        Rpc.feed(handle,"{\"id\":\"retry\",\"type\":\"set_auto_retry\",\"enabled\":false}\n")
        Rpc.feed(handle,"{\"id\":\"run\",\"type\":\"bash\",\"command\":\"printf fixture\",\"excludeFromContext\":true}\n")
        Rpc.feed(handle,"{\"id\":\"prompt\",\"type\":\"prompt\",\"message\":\"hello\"}\n")
        Rpc.stop(owner)
def inspect(pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        Rpc.feed(handle,"{\"id\":\"state\",\"type\":\"get_state\"}\n")
        Rpc.feed(handle,"{\"id\":\"messages\",\"type\":\"get_messages\"}\n")
        Rpc.feed(handle,"{\"id\":\"entries\",\"type\":\"get_entries\"}\n")
        Rpc.stop(owner)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> +agentDir <> Nil{}:
      do IO<Unit>:
        created : Stored.Outcome(Session.Session()) <- Session.createSession(cwd,Some{cwd},agentDir,Stored.noOptions())
        stored : Session.Session() <- Faux.requireSession(created)
        +fixture : Faux.Fixture <- Faux.fixture(stored,cwd,agentDir,"answer#42" <> Nil{},Nil{})
        +session : Session.AgentSession <- IO.pure(Session.AgentSession,Faux.sessionOf(fixture))
        +lines : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
        +sink : Callback.Callback<String,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~String,~Unit,~capture,lines)
        +host : Rpc.Host <- RpcHost.create()
        first : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink,None{},host)
        runCommands(first)
        second : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink,None{},host)
        inspect(second)
        captured : List<&2,String> <- Ref.dispose(List<&2,String>,lines)
        output(captured)
        Callback.dispose(String,Unit,sink)
        Faux.teardown(fixture)
    case _: IO.die(Unit,1,"usage: rpc-controls <cwd> <agentDir>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

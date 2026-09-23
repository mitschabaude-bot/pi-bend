import Base
import ./agent-session.bend as Faux
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Stored
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/callback.bend as Callback

def capture(lines: Ref.Ref<List<&2,String>>,line: String) -> IO(Unit):
  Ref.modify(List<&2,String>,Unit,lines,current => (List.append(&2,String,current,line <> Nil{}),Unit{}))
def quiet(value: Faux.Fixture) -> IO(Unit):
  match value:
    case Faux.Fixture{session,listener,_,_,_,_,_}: Session.unsubscribe(session,listener)
def output(lines: List<&2,String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case line <> rest:
      do IO<Unit>:
        IO.write(line)
        output(rest)
def execute(pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case Tuple{owner,+handle}:
      do IO<Unit>:
        Rpc.feed(handle,"{\"id\":\"e\",\"type\":\"get_entries\"}\n")
        Rpc.feed(handle,"{\"id\":\"missing\",\"type\":\"get_entries\",\"since\":\"nowhere\"}\n")
        Rpc.feed(handle,"{\"id\":\"p\",\"type\":\"prompt\",\"message\":\"hello\",\"images\":[{\"type\":\"image\",\"data\":\"AA==\",\"mimeType\":\"image/png\"}]}\n")
        Rpc.feed(handle,"{\"id\":\"u\",\"type\":\"unknown\"}\n")
        Rpc.feed(handle,"{\"id\":\"bad\",\"type\":\"prompt\",\"message\":17}\n")
        Rpc.feed(handle,"{\"id\":\"image-bad\",\"type\":\"steer\",\"message\":\"x\",\"images\":[{\"type\":\"image\",\"data\":3,\"mimeType\":\"image/png\"}]}\n")
        Rpc.feed(handle,"{\"id\":\"tail\",\"type\":\"unknown\"}")
        Rpc.finish(handle)
        Rpc.stop(owner)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> agentDir <> Nil{}:
      do IO<Unit>:
        created : Stored.Outcome(Session.Session()) <- Session.memorySession(cwd,Stored.noOptions())
        stored : Session.Session() <- Faux.requireSession(created)
        +fixture : Faux.Fixture <- Faux.fixture(stored,cwd,agentDir,"answer" <> Nil{},Nil{})
        quiet(fixture)
        +session : Session.AgentSession <- IO.pure(Session.AgentSession,Faux.sessionOf(fixture))
        +lines : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
        +sink : Callback.Callback<String,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~String,~Unit,~capture,lines)
        pair : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink)
        execute(pair)
        captured : List<&2,String> <- Ref.dispose(List<&2,String>,lines)
        output(captured)
        Callback.dispose(String,Unit,sink)
        Faux.teardown(fixture)
    case _: IO.die(Unit,1,"usage: rpc-session <cwd> <agentDir>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

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
        Rpc.feed(handle,"{\"id\":\"levels\",\"type\":\"get_available_thinking_levels\"}\n")
        Rpc.feed(handle,"{\"id\":\"cycle\",\"type\":\"cycle_thinking_level\"}\n")
        Rpc.feed(handle,"{\"id\":\"steering-mode\",\"type\":\"set_steering_mode\",\"mode\":\"all\"}\n")
        Rpc.feed(handle,"{\"id\":\"follow-mode\",\"type\":\"set_follow_up_mode\",\"mode\":\"one-at-a-time\"}\n")
        Rpc.feed(handle,"{\"id\":\"steered\",\"type\":\"steer\",\"message\":\"queued steer\"}\n")
        Rpc.feed(handle,"{\"id\":\"followed\",\"type\":\"follow_up\",\"message\":\"queued follow\"}\n")
        Rpc.feed(handle,"{\"id\":\"queue\",\"type\":\"clear_queue\"}\n")
        Rpc.feed(handle,"{\"id\":\"e\",\"type\":\"get_entries\"}\n")
        Rpc.feed(handle,"{\"id\":\"missing\",\"type\":\"get_entries\",\"since\":\"nowhere\"}\n")
        Rpc.feed(handle,"{\"id\":\"name\",\"type\":\"set_session_name\",\"name\":\"rpc tree\"}\n")
        Rpc.feed(handle,"{\"id\":\"name2\",\"type\":\"set_session_name\",\"name\":\"rpc nested\"}\n")
        Rpc.feed(handle,"{\"id\":\"state\",\"type\":\"get_state\"}\n")
        Rpc.feed(handle,"{\"id\":\"empty-stats\",\"type\":\"get_session_stats\"}\n")
        Rpc.feed(handle,"{\"id\":\"export-missing\",\"type\":\"export_html\"}\n")
        Rpc.feed(handle,"{\"id\":\"tree\",\"type\":\"get_tree\"}\n")
        Rpc.feed(handle,"{\"id\":\"forks\",\"type\":\"get_fork_messages\"}\n")
        Rpc.feed(handle,"{\"id\":\"p\",\"type\":\"prompt\",\"message\":\"hello\",\"images\":[{\"type\":\"image\",\"data\":\"AA==\",\"mimeType\":\"image/png\"}]}\n")
        Rpc.feed(handle,"{\"id\":\"u\",\"type\":\"unknown\"}\n")
        Rpc.feed(handle,"{\"id\":\"bad\",\"type\":\"prompt\",\"message\":17}\n")
        Rpc.feed(handle,"{\"id\":\"image-bad\",\"type\":\"steer\",\"message\":\"x\",\"images\":[{\"type\":\"image\",\"data\":3,\"mimeType\":\"image/png\"}]}\n")
        Rpc.feed(handle,"{\"id\":\"tail\",\"type\":\"unknown\"}")
        Rpc.finish(handle)
        Rpc.stop(owner)
def finalQueries(pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case Tuple{owner,handle}:
      do IO<Unit>:
        Rpc.feed(handle,"{\"id\":\"final-stats\",\"type\":\"get_session_stats\"}\n{\"id\":\"final-forks\",\"type\":\"get_fork_messages\"}\n{\"id\":\"export\",\"type\":\"export_html\",\"outputPath\":\"build/rpc-export.html\"}\n")
        Rpc.stop(owner)
def missingAssets(pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case Tuple{owner,handle}:
      do IO<Unit>:
        Rpc.feed(handle,"{\"id\":\"asset-error\",\"type\":\"export_html\"}\n")
        Rpc.stop(owner)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> +agentDir <> Nil{}:
      do IO<Unit>:
        created : Stored.Outcome(Session.Session()) <- Session.createSession(cwd,Some{cwd},agentDir,Stored.noOptions())
        stored : Session.Session() <- Faux.requireSession(created)
        +fixture : Faux.Fixture <- Faux.fixture(stored,cwd,agentDir,"answer#42" <> Nil{},Nil{})
        quiet(fixture)
        +session : Session.AgentSession <- IO.pure(Session.AgentSession,Faux.sessionOf(fixture))
        +lines : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
        +sink : Callback.Callback<String,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~String,~Unit,~capture,lines)
        +host : Rpc.Host <- RpcHost.create()
        pair : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink,None{},host)
        execute(pair)
        settled : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink,Some{"packages/coding-agent/src/core/export-html"},host)
        finalQueries(settled)
        missing : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink,Some{"build/missing-export-assets"},host)
        missingAssets(missing)
        captured : List<&2,String> <- Ref.dispose(List<&2,String>,lines)
        output(captured)
        Callback.dispose(String,Unit,sink)
        Faux.teardown(fixture)
    case _: IO.die(Unit,1,"usage: rpc-session <cwd> <agentDir>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

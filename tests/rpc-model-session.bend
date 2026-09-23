import Base
import ./agent-session.bend as Faux
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Stored
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/callback.bend as Callback

def secondModel() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"faux-two", "Faux Two", Ai.OpenAIResponsesApi{}, "faux", "https://faux.invalid", True{}, None{}, Ai.InputText{} <> Ai.InputImage{} <> Nil{}, None{}, Ai.ModelCost{U32.to_f64(1), U32.to_f64(2), U32.to_f64(3), U32.to_f64(4), None{}}, None{}, U32.to_f64(64000), U32.to_f64(2048), None{}, None{}, None{}}
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
def modelCommands(pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case Tuple{owner,+handle}:
      do IO<Unit>:
        Rpc.feed(handle,"{\"id\":\"available\",\"type\":\"get_available_models\"}\n")
        Rpc.feed(handle,"{\"id\":\"missing-provider\",\"type\":\"set_model\",\"modelId\":\"faux-two\"}\n")
        Rpc.feed(handle,"{\"id\":\"unknown\",\"type\":\"set_model\",\"provider\":\"faux\",\"modelId\":\"missing\"}\n")
        Rpc.feed(handle,"{\"id\":\"set\",\"type\":\"set_model\",\"provider\":\"faux\",\"modelId\":\"faux-two\"}\n")
        Rpc.feed(handle,"{\"id\":\"state-set\",\"type\":\"get_state\"}\n")
        Rpc.feed(handle,"{\"id\":\"cycle\",\"type\":\"cycle_model\"}\n")
        Rpc.feed(handle,"{\"id\":\"state-cycle\",\"type\":\"get_state\"}\n")
        Rpc.stop(owner)
def oneModel(pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case Tuple{owner,handle}:
      do IO<Unit>:
        Rpc.feed(handle,"{\"id\":\"single\",\"type\":\"cycle_model\"}\n")
        Rpc.stop(owner)
def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> +agentDir <> Nil{}:
      do IO<Unit>:
        created : Stored.Outcome(Session.Session()) <- Session.createSession(cwd,Some{cwd},agentDir,Stored.noOptions())
        stored : Session.Session() <- Faux.requireSession(created)
        +fixture : Faux.Fixture <- Faux.fixture(stored,cwd,agentDir,Nil{},Nil{})
        quiet(fixture)
        +session : Session.AgentSession <- IO.pure(Session.AgentSession,Faux.sessionOf(fixture))
        +lines : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
        +sink : Callback.Callback<String,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~String,~Unit,~capture,lines)
        first : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink,None{},[Faux.fauxModel(),secondModel()])
        modelCommands(first)
        single : Rpc.Owner & Rpc.Handle <- Rpc.start(session,sink,None{},[Faux.fauxModel()])
        oneModel(single)
        captured : List<&2,String> <- Ref.dispose(List<&2,String>,lines)
        output(captured)
        Callback.dispose(String,Unit,sink)
        Faux.teardown(fixture)
    case _: IO.die(Unit,1,"usage: rpc-model-session <cwd> <agentDir>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

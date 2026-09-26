import Base
import ./agent-session.bend as Faux
import ./rpc-host-fixture.bend as RpcHost
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/session-persistence.bend as Stored
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/schema-value.bend as V

# upstream rpc-prompt-response-semantics.test.ts and
# suite/regressions/5868-rpc-unknown-command-id.test.ts. Both drive runRpcMode
# with mocked stdin/stdout: here Rpc.feed is the line handler and a capturing
# sink replaces writeRawStdout. The session is in memory, as upstream's
# SessionManager.inMemory(), over the faux provider of tests/agent-session.bend.
# Upstream's response delays (100 ms, 500 ms) keep a prompt streaming while
# later commands arrive; a faux gate holds the response open for exactly that
# span instead, and is released where upstream's timer would fire.
#
# usage: rpc-mode <cwd> <agentDir>

def report(+name: String,passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit),passed,IO.print("PASS " ++ name),IO.print("FAIL " ++ name))

def capture(lines: Ref.Ref<List<&2,String>>,line: String) -> IO(Unit):
  Ref.modify(List<&2,String>,Unit,lines,current => (List.append(&2,String,current,[line]),Unit{}))
def parsedLine(result: Result<&2,&2,Decode.ParseError,V.Value>) -> List<&2,V.Value>:
  match result:
    case Done{value}: [value]
    case Fail{_}: Nil{}

# Output records
# --------------

def parsedRecords(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: List.append(&2,V.Value,parsedLine(Decode.parse(String.trim(line))),parsedRecords(rest))
def textValue(value: Maybe<&2,V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""
def fieldOf(value: V.Value,key: String) -> Maybe<&2,V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value,fields,key)
    case _: None{}
def textOf(+value: V.Value,key: String) -> String: textValue(fieldOf(value,key))
def successOf(value: Maybe<&2,V.Value>) -> Maybe<&2,Bool>:
  match value:
    case Some{V.Boolean{flag}}: Some{flag}
    case _: None{}
# upstream getPromptResponses: records with this id, type response, command prompt.
def isPromptResponse(+record: V.Value,+id: String) -> Bool:
  String.eq(textOf(record,"id"),id) && String.eq(textOf(record,"type"),"response") && String.eq(textOf(record,"command"),"prompt")
def promptResponses(records: List<&2,V.Value>,+id: String) -> List<&2,V.Value>:
  match records:
    case Nil{}: Nil{}
    case +record <> +rest: Bool.pick(List<&2,V.Value>,isPromptResponse(record,id),record <> promptResponses(rest,id),promptResponses(rest,id))
def countType(records: List<&2,V.Value>,+kind: String) -> Nat:
  match records:
    case Nil{}: 0n
    case record <> rest: Bool.pick(Nat,String.eq(textOf(record,"type"),kind),1n,0n) + countType(rest,kind)
def containsLine(lines: List<&2,String>,+expected: String) -> Bool:
  match lines:
    case Nil{}: False{}
    case line <> rest: String.eq(line,expected) || containsLine(rest,expected)

# vi.waitFor: poll the captured output until the condition holds, for at most
# about two seconds.
type Await is Data:
  Responded{id: String}
  QueueCleared{}
  UnknownReplied{}
def responded(+id: String,lines: List<&2,String>) -> Bool:
  Nat.is_gt(List.length(&2,V.Value,promptResponses(parsedRecords(lines),id)),0n)

# The single prompt response for `id`, with its success and error.
type Single is Data:
  Single{count: Nat,success: Maybe<&2,Bool>,error: String}
def singleOf(responses: List<&2,V.Value>) -> Single:
  match responses:
    case Nil{}: Single{0n,None{},""}
    case +first <> rest: Single{1n + List.length(&2,V.Value,rest),successOf(fieldOf(first,"success")),textOf(first,"error")}
def single(+id: String,lines: List<&2,String>) -> Single:
  singleOf(promptResponses(parsedRecords(lines),id))
def succeeded(value: Single) -> Bool:
  match value:
    case Single{count,success,_}: Nat.is_eq(count,1n) && Maybe.default(&2,Bool,success,False{})
def failedWith(value: Single,+prefix: String) -> Bool:
  match value:
    case Single{count,success,error}: Nat.is_eq(count,1n) && Bool.not(Maybe.default(&2,Bool,success,True{})) && String.contains(error,prefix)

# Fixtures
# --------

type Endpoint is Data:
  Endpoint{fixture: Faux.Fixture,lines: Ref.Ref<List<&2,String>>,sink: Callback.Callback<String,Unit>}
def fakeModel() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"fake-model","Fake Model",Ai.OpenAICompletionsApi{},"fake-provider","https://example.invalid",False{},None{},Nil{},None{},Ai.ModelCost{U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),U32.to_f64(0),None{}},None{},U32.to_f64(0),U32.to_f64(0),None{},None{},None{}}
def emptyLoadout() -> Runtime.Loadout:
  Runtime.Loadout{R.new(String),Nil{},Nil{},Nil{},None{},Nil{},None{},Nil{}}
def requireSession(result: Stored.Outcome(Session.Session())) -> IO(Session.Session()): Faux.requireSession(result)
def quiet(value: Faux.Fixture) -> IO(Unit):
  match value:
    case Faux.Fixture{session,listener,_,_,_,_,_}: Session.unsubscribe(session,listener)
# createRuntimeHost: an in-memory session over the faux provider. withAuth
# selects the faux model (whose key PI_FAUX_API_KEY is set); without it the
# model is upstream's fake-provider model, which has no credentials.
def endpoint(+cwd: String,+agentDir: String,withAuth: Bool,gates: List<&2,Faux.Gate>) -> IO(Endpoint):
  do IO<Endpoint>:
    uuids : Uuid.Generator <- Uuid.generator()
    created : Stored.Outcome(Session.Session()) <- Stored.inMemory(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,~Session.readUnit,~Session.readDetails,~Session.readRaw,uuids,cwd,Stored.noOptions(),None{})
    stored : Session.Session() <- requireSession(created)
    +fixture : Faux.Fixture <- Faux.fixtureWithModel(stored,cwd,agentDir,["done","done"],gates,emptyLoadout(),Some{Bool.pick(Ai.Model<Ai.JsonValue>,withAuth,Faux.fauxModel(),fakeModel())},Faux.fauxSources())
    quiet(fixture)
    +lines : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    sink : Callback.Callback<String,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~String,~Unit,~capture,lines)
    return Endpoint{fixture,lines,sink}
def started(+value: Endpoint) -> IO(Rpc.Owner & Rpc.Handle):
  match value:
    case Endpoint{fixture,_,sink}:
      do IO<Rpc.Owner & Rpc.Handle>:
        host : Rpc.Host <- RpcHost.create()
        Rpc.start(Faux.sessionOf(fixture),sink,None{},host)
def linesOf(value: Endpoint) -> Ref.Ref<List<&2,String>>:
  match value:
    case Endpoint{_,lines,_}: lines
def send(handle: Rpc.Handle,line: String) -> IO(Unit): Rpc.feed(handle,line ++ "\n")
# cleanup: stop the endpoint (upstream aborts the session), then release it.
def cleanup(value: Endpoint,owner: Rpc.Owner) -> IO(List<&2,String>):
  match value:
    case Endpoint{fixture,lines,sink}:
      do IO<List<&2,String>>:
        Rpc.stop(owner)
        captured : List<&2,String> <- Ref.dispose(List<&2,String>,lines)
        Callback.dispose(String,Unit,sink)
        Faux.teardown(fixture)
        return captured
def clearLines(lines: Ref.Ref<List<&2,String>>) -> IO(Unit): Ref.write(List<&2,String>,lines,Nil{})
def release(gate: Faux.Gate) -> IO(Unit):
  match gate:
    case Faux.Gate{_,release}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit,release,Unit{})
        return Unit{}
def newGate() -> IO(Faux.Gate):
  do IO<Faux.Gate>:
    started : Chan(Unit) <- Chan.new(Unit,1)
    release : Chan(Unit) <- Chan.new(Unit,1)
    return Faux.Gate{started,release}

def clearedData(+lines: List<&2,String>) -> Bool:
  containsLine(lines,"{\"id\":\"clear\",\"type\":\"response\",\"command\":\"clear_queue\",\"success\":true,\"data\":{\"steering\":[\"Change direction\"],\"followUp\":[\"Summarize when finished\"]}}\n")
def unknownReply(lines: List<&2,String>) -> Bool:
  containsLine(lines,"{\"id\":\"test\",\"type\":\"response\",\"command\":\"foobar\",\"success\":false,\"error\":\"Unknown command: foobar\"}\n")
def holds(condition: Await,lines: List<&2,String>) -> Bool:
  match condition:
    case Responded{id}: responded(id,lines)
    case QueueCleared{}: clearedData(lines)
    case UnknownReplied{}: unknownReply(lines)
def waitFor(+lines: Ref.Ref<List<&2,String>>,+condition: Await,fuel: Nat) -> IO(List<&2,String>):
  match fuel:
    case 0n: Ref.read(List<&2,String>,lines)
    case 1n+rest:
      do IO<List<&2,String>>:
        +current : List<&2,String> <- Ref.read(List<&2,String>,lines)
        Bool.pick(Unit -> IO(List<&2,String>),holds(condition,current),_ => IO.pure(List<&2,String>,current),_ => IO.bind(Unit,List<&2,String>,IO.sleep(10),done => waitFor(lines,condition,rest)))(Unit{})
def rejected(+value: Endpoint,pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        send(handle,"{\"id\":\"b1\",\"type\":\"prompt\",\"message\":\"Hello\"}")
        lines : List<&2,String> <- waitFor(linesOf(value),Responded{"b1"},200n)
        captured : List<&2,String> <- cleanup(value,owner)
        report("RPC prompt response semantics > emits one failure response when prompt preflight rejects",failedWith(single("b1",captured),"No API key found for fake-provider.\n\nUse /login to log into a provider via OAuth or API key. See:"))

# RPC prompt response semantics
# -----------------------------

def preflightRejects(+cwd: String,+agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +value : Endpoint <- endpoint(cwd,agentDir,False{},Nil{})
    pair : Rpc.Owner & Rpc.Handle <- started(value)
    rejected(value,pair)
def accepted(+value: Endpoint,pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        send(handle,"{\"id\":\"b2\",\"type\":\"prompt\",\"message\":\"Hello\"}")
        lines : List<&2,String> <- waitFor(linesOf(value),Responded{"b2"},200n)
        captured : List<&2,String> <- cleanup(value,owner)
        report("RPC prompt response semantics > emits one success response when prompt preflight succeeds",succeeded(single("b2",captured)))

def preflightSucceeds(+cwd: String,+agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +value : Endpoint <- endpoint(cwd,agentDir,True{},Nil{})
    pair : Rpc.Owner & Rpc.Handle <- started(value)
    accepted(value,pair)
def queued(+value: Endpoint,gate: Faux.Gate,pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        send(handle,"{\"id\":\"b3-start\",\"type\":\"prompt\",\"message\":\"Start\"}")
        first : List<&2,String> <- waitFor(linesOf(value),Responded{"b3-start"},200n)
        clearLines(linesOf(value))
        send(handle,"{\"id\":\"b3\",\"type\":\"prompt\",\"message\":\"Queue this\",\"streamingBehavior\":\"followUp\"}")
        +lines : List<&2,String> <- waitFor(linesOf(value),Responded{"b3"},200n)
        release(gate)
        captured : List<&2,String> <- cleanup(value,owner)
        report("RPC prompt response semantics > emits one success response when prompt is queued during streaming",succeeded(single("b3",lines)))

def queuedDuringStreaming(+cwd: String,+agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +gate : Faux.Gate <- newGate()
    +value : Endpoint <- endpoint(cwd,agentDir,True{},[gate])
    pair : Rpc.Owner & Rpc.Handle <- started(value)
    queued(value,gate,pair)
def clearing(+value: Endpoint,gate: Faux.Gate,pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        send(handle,"{\"id\":\"clear-start\",\"type\":\"prompt\",\"message\":\"Start\"}")
        started : List<&2,String> <- waitFor(linesOf(value),Responded{"clear-start"},200n)
        send(handle,"{\"id\":\"clear-steering\",\"type\":\"prompt\",\"message\":\"Change direction\",\"streamingBehavior\":\"steer\"}")
        steered : List<&2,String> <- waitFor(linesOf(value),Responded{"clear-steering"},200n)
        send(handle,"{\"id\":\"clear-follow-up\",\"type\":\"prompt\",\"message\":\"Summarize when finished\",\"streamingBehavior\":\"followUp\"}")
        followed : List<&2,String> <- waitFor(linesOf(value),Responded{"clear-follow-up"},200n)
        send(handle,"{\"id\":\"clear\",\"type\":\"clear_queue\"}")
        +lines : List<&2,String> <- waitFor(linesOf(value),QueueCleared{},200n)
        release(gate)
        +captured : List<&2,String> <- cleanup(value,owner)
        report("RPC prompt response semantics > returns and clears queued steering and follow-up messages",clearedData(lines) && Nat.is_eq(countType(parsedRecords(captured),"agent_start"),1n))
def clearsQueues(+cwd: String,+agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +gate : Faux.Gate <- newGate()
    +value : Endpoint <- endpoint(cwd,agentDir,True{},[gate])
    pair : Rpc.Owner & Rpc.Handle <- started(value)
    clearing(value,gate,pair)
def unknown(+value: Endpoint,pair: Rpc.Owner & Rpc.Handle) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        send(handle,"{\"id\":\"test\",\"type\":\"foobar\"}")
        lines : List<&2,String> <- waitFor(linesOf(value),UnknownReplied{},200n)
        captured : List<&2,String> <- cleanup(value,owner)
        report("RPC unknown command responses (#5868) > preserves the request id on unknown command errors",unknownReply(captured))

# RPC unknown command responses (#5868)
# -------------------------------------

def unknownCommand(+cwd: String,+agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +value : Endpoint <- endpoint(cwd,agentDir,True{},Nil{})
    pair : Rpc.Owner & Rpc.Handle <- started(value)
    unknown(value,pair)

def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> +agentDir <> Nil{}:
      do IO<Unit>:
        preflightRejects(cwd,agentDir)
        preflightSucceeds(cwd,agentDir)
        queuedDuringStreaming(cwd,agentDir)
        clearsQueues(cwd,agentDir)
        unknownCommand(cwd,agentDir)
    case _: IO.die(Unit,1,"usage: rpc-mode <cwd> <agentDir>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

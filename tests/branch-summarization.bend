import Base
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/coding-agent/src/core/compaction/branch-summarization.bend as Branch
import ../packages/coding-agent/src/core/session-manager.bend as Session
import ../packages/coding-agent/src/core/messages.bend as Messages
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as Rec

def State() -> Data: Session.SessionManager<Unit,Unit,Value.Value>
def user(text: String) -> Agent.AgentMessage<Unit,Unit,Messages.CodingMessage<Value.Value>>:
  Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},F.fromU32(1)}}}
def fixture() -> Result<&2,&2,Session.Error,State()>:
  do Result<&2,&2,Session.Error,State()>:
    first : State() <- Session.inMemory(Unit,Unit,Value.Value,Session.SessionHeader{Some{3n},"session","2025-01-01T00:00:00Z","/tmp",None{}})
    second : State() <- Session.appendMessage(Unit,Unit,Value.Value,first,Session.EntryStamp{"u1","2025-01-01T00:00:01Z"},user("first"))
    third : State() <- Session.appendMessage(Unit,Unit,Value.Value,second,Session.EntryStamp{"u2","2025-01-01T00:00:02Z"},user("second"))
    branched : State() <- Session.branch(Unit,Unit,Value.Value,third,"u1")
    Session.appendMessage(Unit,Unit,Value.Value,branched,Session.EntryStamp{"u3","2025-01-01T00:00:03Z"},user("third"))
def entryIds(entries: List<&2,Session.SessionEntry<Unit,Unit,Value.Value>>) -> List<&2,String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: Session.baseId(Session.entryBase(Unit,Unit,Value.Value,entry)) <> entryIds(rest)
def verifyPrepared(+entries: List<&2,Session.SessionEntry<Unit,Unit,Value.Value>>,+common: Maybe<&2,String>,prepared: Branch.Prepared<Unit,Unit,Value.Value>) -> IO(Unit):
  match prepared:
    case Branch.Prepared{+messages,_,_}:
      Bool.pick(Unit -> IO(Unit),String.eq(Maybe.default(&2,String,common,""),"u1") && Nat.is_eq(List.length(&2,Session.SessionEntry<Unit,Unit,Value.Value>,entries),1n) && Nat.is_eq(List.length(&2,Agent.AgentMessage<Unit,Unit,Messages.CodingMessage<Value.Value>>,messages),1n),_ => IO.print(Maybe.default(&2,String,common,"-") ++ "|" ++ String.join(entryIds(entries),",") ++ "|" ++ Nat.show(List.length(&2,Agent.AgentMessage<Unit,Unit,Messages.CodingMessage<Value.Value>>,messages))),_ => IO.die(Unit,1,"wrong branch entries or ancestor"))(Unit{})
def verifyResult(result: Result<&2,&2,Session.Error,Branch.Collected<Unit,Unit,Value.Value>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot collect abandoned branch")
    case Done{Branch.Collected{+entries,common}}:
      verifyPrepared(entries,common,Branch.prepare(Unit,Unit,entries,F.fromU32(100)))
def verify(state: State()) -> IO(Unit):
  verifyResult(Branch.collect(Unit,Unit,Value.Value,state,Some{"u3"},"u2"))
def finish(result: Result<&2,&2,Session.Error,State()>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot build branch fixture")
    case Done{value}:
      do IO<Unit>:
        verify(value)
        return Unit{}

# branch-summarization.test.ts: generateBranchSummary over one abandoned
# user entry and a summarizer answering with a scripted reply (text, a tool
# call, or text stopped at the length limit). Prints the request's output cap
# and the result.
def replyContent(+kind: String) -> List<&2, Ai.AssistantContent<Value.Value>>:
  Bool.pick(List<&2, Ai.AssistantContent<Value.Value>>, String.eq(kind, "tool"), Ai.AssistantToolCall{Ai.ToolCall{"tool-call-1", "read", Value.ObjectValue{Rec.Record{Rec.Property{"path", Value.Text{"README.md"}} <> Nil{}}}, None{}, None{}}} <> Nil{}, Ai.AssistantText{Ai.TextContent{Bool.pick(String, String.eq(kind, "length"), "partial", "summary"), None{}}} <> Nil{})

def replyStop(+kind: String) -> Ai.StopReason:
  Bool.pick(Ai.StopReason, String.eq(kind, "tool"), Ai.ToolUse{}, Bool.pick(Ai.StopReason, String.eq(kind, "length"), Ai.Length{}, Ai.Stop{}))

def zeroUsage() -> Ai.Usage: Ai.Usage{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(0), Ai.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}

type ReplyEnv is Data:
  ReplyEnv{kind: String, caps: R.Ref<List<&2, F64>>}

def scripted(env: ReplyEnv, request: Compaction.SummaryRequest<Unit, Unit>) -> IO(Ai.AssistantMessage<Value.Value, Unit>):
  match env request:
    case ReplyEnv{+kind, caps} Compaction.SummaryRequest{_, maxTokens}:
      do IO<Ai.AssistantMessage<Value.Value, Unit>>:
        R.modify(List<&2, F64>, Unit, caps, old => (List.append(&2, F64, old, maxTokens <> Nil{}), Unit{}))
        return Ai.AssistantMessage{replyContent(kind), "anthropic-messages", "anthropic", "test-model", None{}, None{}, None{}, None{}, zeroUsage(), replyStop(kind), None{}, None{}, None{}, None{}, F.fromU32(1)}

def testModel(maxTokens: U32) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"test-model", "Test Model", Ai.AnthropicMessagesApi{}, "anthropic", "https://api.anthropic.com", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(200000), U32.to_f64(maxTokens), None{}, None{}, None{}}

def abandoned() -> List<&2, Session.SessionEntry<Unit, Unit, Value.Value>>:
  Session.SessionMessageEntry{Session.SessionEntryBase{"branch-user", None{}, "1970-01-01T00:00:00.001Z"}, Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"Abandoned request"}, F.fromU32(1)}}}} <> Nil{}

def capsText(caps: List<&2, F64>) -> String:
  match caps:
    case Nil{}: ""
    case cap <> +rest: Nat.show(Result.default(&2, &2, F.Error, Nat, F.convert(cap), 0n)) ++ Bool.pick(String, List.is_empty(&2, F64, rest), "", "," ++ capsText(rest))

def reportGenerated(caps: List<&2, F64>, result: Result<&2, &2, String, Branch.Summary>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("{\"caps\":[" ++ capsText(caps) ++ "],\"error\":null}")
    case Fail{error}: IO.print("{\"caps\":[" ++ capsText(caps) ++ "],\"error\":" ++ Json.quote(error) ++ "}")

def generateScenario(+kind: String, maxTokens: U32) -> IO(Unit):
  do IO<Unit>:
    +caps : R.Ref<List<&2, F64>> <- R.new(List<&2, F64>, Nil{})
    +summarizer : Compaction.Summarizer(Unit, Unit) <- C.create(~ReplyEnv, ~Compaction.SummaryRequest<Unit, Unit>, ~Ai.AssistantMessage<Value.Value, Unit>, ~scripted, ReplyEnv{kind, caps})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    result : Result<&2, &2, String, Branch.Summary> <- Branch.generate(~Unit, ~Unit, summarizer, abandoned(), testModel(maxTokens), F.fromU32(16384), Abort.signal(Unit, controller), None{}, False{}, None{}, None{})
    C.dispose(Compaction.SummaryRequest<Unit, Unit>, Ai.AssistantMessage<Value.Value, Unit>, summarizer)
    Abort.dispose(Unit, controller)
    seen : List<&2, F64> <- R.dispose(List<&2, F64>, caps)
    reportGenerated(seen, result)

def number(+text: String) -> U32: U32.from_nat(Maybe.default(&2, Nat, Nat.read(text), 0n))

def collectionCheck() -> IO(Unit):
  do IO<Unit>:
    +prompt : String <- IO.pure(String,Branch.promptText(Unit,Unit,Value.Value,Nil{},None{},False{}))
    +prepared : Branch.Prepared<Unit,Unit,Value.Value> <- IO.pure(Branch.Prepared<Unit,Unit,Value.Value>,Branch.prepare(Unit,Unit,Nil{},F.fromU32(100)))
    Bool.pick(Unit -> IO(Unit),String.contains(prompt,"## Goal") && String.contains(prompt,"## Next Steps"),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"branch summary prompt mismatch"))(Unit{})
    finish(fixture())

def selected(args: List<String>) -> IO(Unit):
  match args:
    case "generate" <> kind <> maxTokens <> Nil{}: generateScenario(kind, number(maxTokens))
    case _: collectionCheck()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    selected(args)

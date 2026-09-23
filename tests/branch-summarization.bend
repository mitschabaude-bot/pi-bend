import Base
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/coding-agent/src/core/compaction/branch-summarization.bend as Branch
import ../packages/coding-agent/src/core/session-manager.bend as Session
import ../packages/coding-agent/src/core/messages.bend as Messages
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai

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

def main() -> IO(Unit):
  do IO<Unit>:
    +prompt : String <- IO.pure(String,Branch.promptText(Unit,Unit,Value.Value,Nil{},None{},False{}))
    +prepared : Branch.Prepared<Unit,Unit,Value.Value> <- IO.pure(Branch.Prepared<Unit,Unit,Value.Value>,Branch.prepare(Unit,Unit,Nil{},F.fromU32(100)))
    Bool.pick(Unit -> IO(Unit),String.contains(prompt,"## Goal") && String.contains(prompt,"## Next Steps"),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"branch summary prompt mismatch"))(Unit{})
    finish(fixture())

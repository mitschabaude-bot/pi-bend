import Base
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/messages.bend as M
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as W

def E() -> Data: S.SessionEntry<Unit,Unit,String>
def AM() -> Data: Agent.AgentMessage<Unit,Unit,M.CodingMessage<String>>
def text(value: String) -> String: W.fromScalars(W.parseNumbers(value))
def optional(value: String) -> Maybe<&2,String>:
  match value:
    case "-": None{}
    case other: Some{text(other)}
def base(id: String, parent: String, timestamp: String) -> S.SessionEntryBase:
  S.SessionEntryBase{text(id),optional(parent),text(timestamp)}
def usage() -> Ai.Usage:
  Ai.Usage{F.fromU32(1),F.fromU32(1),F.fromU32(0),F.fromU32(0),None{},None{},F.fromU32(2),Ai.UsageCost{F.fromU32(0),F.fromU32(0),F.fromU32(0),F.fromU32(0),F.fromU32(0)}}
def assistant(content: String, provider: String, model: String) -> AM():
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{[Ai.AssistantText{Ai.TextContent{content,None{}}}],"anthropic-messages",provider,model,None{},None{},None{},None{},usage(),Ai.Stop{},None{},None{},None{},None{},F.fromU32(1)}}}
def system(content: String) -> Ai.SystemMessage<V.Value>:
  Ai.SystemMessage{Ai.SystemText{content},None{},None{},None{},F.fromU32(1)}
def maybeSystem(value: String) -> Maybe<&2,Ai.SystemMessage<V.Value>>:
  match value:
    case "-": None{}
    case other: Some{system(text(other))}
def payload(metadata: S.SessionEntryBase, fields: List<&2,String>) -> Maybe<&2,E()>:
  match fields:
    case "u" <> value <> Nil{}: Some{S.SessionMessageEntry{metadata,Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text(value)},F.fromU32(1)}}}}}
    case "a" <> value <> provider <> model <> Nil{}: Some{S.SessionMessageEntry{metadata,assistant(text(value),text(provider),text(model))}}
    case "s" <> value <> Nil{}: Some{S.SessionMessageEntry{metadata,Agent.LlmMessage{Ai.System{system(text(value))}}}}
    case "t" <> level <> Nil{}: Some{S.ThinkingLevelChangeEntry{metadata,text(level)}}
    case "m" <> provider <> model <> Nil{}: Some{S.ModelChangeEntry{metadata,text(provider),text(model)}}
    case "c" <> summary <> keep <> tokens <> snapshot <> Nil{}: Some{S.Compaction{S.CompactionEntry{metadata,text(summary),text(keep),U32.to_nat(W.decimal(tokens,0)),None{},Some{usage()},Some{True{}},maybeSystem(snapshot)}}}
    case "b" <> summary <> from <> Nil{}: Some{S.BranchSummaryEntry{metadata,text(from),text(summary),None{},Some{usage()},Some{True{}}}}
    case "x" <> kind <> details <> Nil{}: Some{S.CustomEntry{metadata,text(kind),optional(details)}}
    case "v" <> kind <> content <> display <> details <> Nil{}: Some{S.CustomMessageEntry{metadata,text(kind),Ai.UserText{text(content)},optional(details),Strings.equal(display,"1")}}
    case "l" <> target <> label <> Nil{}: Some{S.LabelEntry{metadata,text(target),optional(label)}}
    case "i" <> name <> Nil{}: Some{S.SessionInfoEntry{metadata,optional(name)}}
    case _: None{}
def entry(fields: List<&2,String>) -> Maybe<&2,E()>:
  match fields:
    case id <> parent <> timestamp <> rest: payload(base(id,parent,timestamp),rest)
    case _: None{}
def entries(fields: List<&2,String>, state: Maybe<&2,List<&2,E()>>) -> Maybe<&2,List<&2,E()>>:
  match fields state:
    case _ None{}: None{}
    case Nil{} Some{reversed}: Some{List.reverse(&2,E(),reversed)}
    case "" <> rest previous: entries(rest,previous)
    case field <> rest Some{reversed}: entries(rest,Maybe.map(&2,E(),List<&2,E()>,value => value <> reversed,entry(Strings.split(field,':'))))
def selection(value: String) -> S.LeafSelection:
  match value:
    case "latest": S.Latest{}
    case "root": S.Root{}
    case id: S.Leaf{text(id)}
def error(cause: S.Error) -> String:
  match cause:
    case S.DuplicateId{id}: "duplicate:" ++ W.showText(id)
    case S.EmptyId{}: "empty-id"
    case S.EntryNotFound{id}: "missing:" ++ W.showText(id)
    case S.InvalidMessage{}: "invalid-message"
    case S.LabelIdCount{}: "label-id-count"
    case S.Cycle{id}: "cycle:" ++ W.showText(id)
    case S.InvalidTimestamp{id,_}: "timestamp:" ++ W.showText(id)
def ids(values: List<&2,E()>, reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2,String,reversed),";")
    case value <> rest: ids(rest,W.showText(S.entryId(Unit,Unit,String,value)) <> reversed)
def entryResult(value: Result<&2,&2,S.Error,List<&2,E()>>) -> String:
  match value:
    case Fail{cause}: "error|" ++ error(cause)
    case Done{values}: "entries|" ++ ids(values,Nil{})
def number(value: F64) -> String: Maybe.default(&2,String,F.toDecimal(value),"invalid")
def maybeText(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "-"
    case Some{value}: W.showText(value)
def bool(value: Bool) -> String: Bool.pick(String,value,"1","0")
def custom(message: M.CodingMessage<String>) -> String:
  match message:
    case M.CompactionSummary{M.CompactionSummaryMessage{summary,tokens,timestamp}}: "compaction:" ++ W.showText(summary) ++ ":" ++ Nat.show(tokens) ++ ":" ++ number(timestamp)
    case M.BranchSummary{M.BranchSummaryMessage{summary,from,timestamp}}: "branch:" ++ W.showText(summary) ++ ":" ++ maybeText(from) ++ ":" ++ number(timestamp)
    case M.Custom{M.CustomMessage{kind,Ai.UserText{content},display,details,timestamp}}: "custom:" ++ W.showText(kind) ++ ":" ++ W.showText(content) ++ ":" ++ bool(display) ++ ":" ++ maybeText(details) ++ ":" ++ number(timestamp)
    case _: "other-custom"
def assistantBody(values: List<&2,Ai.AssistantContent<V.Value>>, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case Ai.AssistantText{Ai.TextContent{content,_}} <> rest: assistantBody(rest,String.reverse.go(content,reversed))
    case _ <> rest: assistantBody(rest,reversed)
def message(value: AM()) -> String:
  match value:
    case Agent.CustomMessage{value}: custom(value)
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{value},_}}}: "user:" ++ W.showText(value)
    case Agent.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{value},_,_,_,_}}}: "system:" ++ W.showText(value)
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content,_,provider,model,_,_,_,_,_,_,_,_,_,_,_}}}: "assistant:" ++ W.showText(assistantBody(content,"")) ++ ":" ++ W.showText(provider) ++ ":" ++ W.showText(model)
    case _: "other-message"
def messages(values: List<&2,AM()>, reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2,String,reversed),";")
    case value <> rest: messages(rest,message(value) <> reversed)
def model(value: Maybe<&2,S.SessionModel>) -> String:
  match value:
    case None{}: "-"
    case Some{S.SessionModel{provider,id}}: W.showText(provider) ++ ":" ++ W.showText(id)
def context(value: Result<&2,&2,S.Error,S.SessionContext<Unit,Unit,String>>) -> String:
  match value:
    case Fail{cause}: "error|" ++ error(cause)
    case Done{S.SessionContext{values,level,selected}}: "context|" ++ W.showText(level) ++ "|" ++ model(selected) ++ "|" ++ messages(values,Nil{})
def runEntries(kind: String, leaf: S.LeafSelection, value: Maybe<&2,List<&2,E()>>) -> IO(Unit):
  match kind value:
    case _ None{}: IO.die(Unit,1,"invalid fixture entry")
    case "path" Some{values}: IO.print(entryResult(S.buildSessionPath(Unit,Unit,String,values,leaf)))
    case "entries" Some{values}: IO.print(entryResult(S.buildContextEntries(Unit,Unit,String,values,leaf)))
    case "context" Some{values}: IO.print(context(S.buildSessionContext(Unit,Unit,String,values,leaf)))
    case _ _: IO.die(Unit,1,"invalid fixture operation")
def chain(+remaining: Nat, parent: Maybe<&2,String>, reversed: List<&2,E()>) -> List<&2,E()>:
  match remaining:
    case 0n: List.reverse(&2,E(),reversed)
    case 1n+rest:
      +id = Nat.show(remaining)
      chain(rest,Some{id},S.SessionMessageEntry{S.SessionEntryBase{id,parent,"2025-01-01T00:00:00Z"},Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"body"},F.fromU32(1)}}}} <> reversed)
def messageCount(values: List<&2,AM()>, count: Nat) -> Nat:
  match values:
    case Nil{}: count
    case _ <> rest: messageCount(rest,1n + count)
def longResult(result: Result<&2,&2,S.Error,S.SessionContext<Unit,Unit,String>>) -> String:
  match result:
    case Done{S.SessionContext{values,"high",None{}}}: "long|" ++ Nat.show(messageCount(values,0n))
    case _: "long-failed"

def run(fields: List<&2,String>) -> IO(Unit):
  match fields:
    case "long" <> Nil{}: IO.print(longResult(S.buildSessionContext(Unit,Unit,String,chain(10000n,Some{"root"},[S.ThinkingLevelChangeEntry{S.SessionEntryBase{"root",None{},"2025-01-01T00:00:00Z"},"high"}]),S.Latest{})))
    case kind <> leaf <> serialized <> Nil{}: runEntries(kind,selection(leaf),entries(Strings.split(serialized,';'),Some{Nil{}}))
    case _: IO.die(Unit,1,"invalid fixture command")
def all(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        run(Strings.split(arg,'|'))
        all(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    all(args)

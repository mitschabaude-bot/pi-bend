import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/estimate.bend as Estimate
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/schema-value.bend as V
import ../../../ai/src/utils/message-json.bend as Json
import ./session-manager.bend as S
import ./session-persistence.bend as Persistence
import ./tools/index.bend as Tools
import ./messages.bend as Messages
import ./compaction/compaction.bend as Compaction

# Counts and billable usage cover every stored entry, including entries no
# longer in the active context after branching or compaction.
type Totals is Data:
  Totals{users: Nat,assistants: Nat,calls: Nat,results: Nat,messages: Nat,input: F64,output: F64,cacheRead: F64,cacheWrite: F64,cost: F64}
type ContextUsage is Data:
  ContextUsage{tokens: Maybe<&2,F64>,window: F64,percent: Maybe<&2,F64>}
type Stats is Data:
  Stats{sessionFile: Maybe<&2,String>,sessionId: String,totals: Totals,context: Maybe<&2,ContextUsage>}

def zero() -> F64: F.fromU32(0)
def empty() -> Totals: Totals{0n,0n,0n,0n,0n,zero(),zero(),zero(),zero(),zero()}
def addUsage(usage: Ai.Usage,totals: Totals) -> Totals:
  match usage totals:
    case Ai.Usage{input,output,cacheRead,cacheWrite,_,_,_,Ai.UsageCost{_,_,_,_,cost}} Totals{users,assistants,calls,results,messages,priorInput,priorOutput,priorRead,priorWrite,priorCost}:
      Totals{users,assistants,calls,results,messages,F.add(priorInput,input),F.add(priorOutput,output),F.add(priorRead,cacheRead),F.add(priorWrite,cacheWrite),F.add(priorCost,cost)}
def countCalls(values: List<&2,Ai.AssistantContent<V.Value>>) -> Nat:
  match values:
    case Nil{}: 0n
    case Ai.AssistantToolCall{_} <> rest: 1n + countCalls(rest)
    case _ <> rest: countCalls(rest)
def addOptionalUsage(value: Maybe<&2,Ai.Usage>,totals: Totals) -> Totals:
  match value:
    case None{}: totals
    case Some{usage}: addUsage(usage,totals)
def addMessage(message: Agent.AgentMessage<Unit,Tools.ToolDetails,Messages.CodingMessage<V.Value>>,totals: Totals) -> Totals:
  match message totals:
    case Agent.LlmMessage{Ai.User{_}} Totals{users,assistants,calls,results,messages,input,output,read,write,cost}:
      Totals{Nat.add(1n,users),assistants,calls,results,Nat.add(1n,messages),input,output,read,write,cost}
    case Agent.LlmMessage{Ai.Assistant{+assistant}} Totals{users,assistants,calls,results,messages,input,output,read,write,cost}:
      addUsage(Ai.assistantUsage(V.Value,Unit,assistant),Totals{users,Nat.add(1n,assistants),Nat.add(calls,countCalls(Ai.assistantContent(V.Value,Unit,assistant))),results,Nat.add(1n,messages),input,output,read,write,cost})
    case Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_,_,_,_,usage,_,_}}} Totals{users,assistants,calls,results,messages,input,output,read,write,cost}:
      addOptionalUsage(usage,Totals{users,assistants,calls,Nat.add(1n,results),Nat.add(1n,messages),input,output,read,write,cost})
    case _ Totals{users,assistants,calls,results,messages,input,output,read,write,cost}:
      Totals{users,assistants,calls,results,Nat.add(1n,messages),input,output,read,write,cost}
def addEntry(entry: S.SessionEntry<Unit,Tools.ToolDetails,V.Value>,totals: Totals) -> Totals:
  match entry:
    case S.SessionMessageEntry{_,message}: addMessage(message,totals)
    case S.Compaction{S.CompactionEntry{_,_,_,_,_,usage,_,_}}: addOptionalUsage(usage,totals)
    case S.BranchSummaryEntry{_,_,_,_,usage,_}: addOptionalUsage(usage,totals)
    case _: totals
def aggregate(entries: List<&2,S.SessionEntry<Unit,Tools.ToolDetails,V.Value>>,totals: Totals) -> Totals:
  match entries:
    case Nil{}: totals
    case entry <> rest: aggregate(rest,addEntry(entry,totals))

def Entry() -> Data: S.SessionEntry<Unit,Tools.ToolDetails,V.Value>
def Projected() -> Data: S.ProjectedSessionEntry<Unit,Tools.ToolDetails,V.Value>
def Projection() -> Data: S.SessionProjection<Unit,Tools.ToolDetails,V.Value>
def Message() -> Data: Agent.AgentMessage<Unit,Tools.ToolDetails,Messages.CodingMessage<V.Value>>
def validUsage(stop: Ai.StopReason,usage: Ai.Usage) -> Bool:
  match stop:
    case Ai.Aborted{}: False{}
    case Ai.Error{}: False{}
    case _: F.isGreater(F.compare(Compaction.calculateContextTokens(usage),zero()))
def assistantHasUsage(message: Message()) -> Bool:
  match message:
    case Agent.LlmMessage{Ai.Assistant{+assistant}}:
      validUsage(Ai.assistantStopReason(V.Value,Unit,assistant),Ai.assistantUsage(V.Value,Unit,assistant))
    case _: False{}
def anyAssistant(messages: List<&2,Message()>) -> Bool:
  match messages:
    case Nil{}: False{}
    case message <> rest: assistantHasUsage(message) || anyAssistant(rest)
def projectedSource(entries: List<&2,Projected()>,+id: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case S.ProjectedSessionEntry{sourceEntry,messages} <> rest:
      (String.eq(S.entryId(Unit,Tools.ToolDetails,V.Value,sourceEntry),id) && anyAssistant(messages)) || projectedSource(rest,id)
def afterCompaction(branch: List<&2,Entry()>,+compactionId: String) -> List<&2,Entry()>:
  match branch:
    case Nil{}: Nil{}
    case entry <> +rest:
      Bool.pick(List<&2,Entry()>,String.eq(S.entryId(Unit,Tools.ToolDetails,V.Value,entry),compactionId),rest,afterCompaction(rest,compactionId))
def hasProjectedUsage(branch: List<&2,Entry()>,+projected: List<&2,Projected()>) -> Bool:
  match branch:
    case Nil{}: False{}
    case entry <> rest: projectedSource(projected,S.entryId(Unit,Tools.ToolDetails,V.Value,entry)) || hasProjectedUsage(rest,projected)
def knownContext(projection: Projection(),branch: List<&2,Entry()>,+window: F64) -> ContextUsage:
  +tokens = Compaction.estimateTokensOf(Compaction.estimateProjectedContextTokens(Unit,Tools.ToolDetails,V.Value,projection,branch))
  ContextUsage{Some{tokens},window,Some{F.multiply(F.divide(tokens,window),F.fromU32(100))}}
def contextFromLatest(+projection: Projection(),+branch: List<&2,Entry()>,+window: F64,latest: Maybe<&2,S.CompactionEntry<V.Value>>) -> ContextUsage:
  match projection latest:
    case S.SessionProjection{+projected,_,_,_} Some{S.CompactionEntry{S.SessionEntryBase{compactionId,_,_},_,_,_,_,_,_,_}}:
      Bool.pick(ContextUsage,hasProjectedUsage(afterCompaction(branch,compactionId),projected),knownContext(projection,branch,window),ContextUsage{None{},window,None{}})
    case _ None{}: knownContext(projection,branch,window)
def contextFrom(projection: Projection(),+branch: List<&2,Entry()>,window: F64) -> ContextUsage:
  contextFromLatest(projection,branch,window,S.getLatestCompactionEntry(Unit,Tools.ToolDetails,V.Value,branch))
def fromProjection(projection: Result<&2,&2,S.Error,Projection()>,branch: Result<&2,&2,S.Error,List<&2,Entry()>>,window: F64) -> Result<&2,&2,S.Error,ContextUsage>:
  match projection branch:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{projected} Done{entries}: Done{contextFrom(projected,entries,window)}
def context(+manager: S.SessionManager<Unit,Tools.ToolDetails,V.Value>,+window: F64) -> Result<&2,&2,S.Error,Maybe<&2,ContextUsage>>:
  Bool.pick(Result<&2,&2,S.Error,Maybe<&2,ContextUsage>>,F.isGreater(F.compare(window,zero())),
    Result.map(&2,&2,S.Error,ContextUsage,Maybe<&2,ContextUsage>,usage => Some{usage},fromProjection(S.buildSessionProjection(Unit,Tools.ToolDetails,V.Value,S.getEntries(Unit,Tools.ToolDetails,V.Value,manager),S.Latest{}),S.getBranch(Unit,Tools.ToolDetails,V.Value,manager,S.Latest{}),window)),Done{None{}})
def withContext(path: Maybe<&2,String>,id: String,totals: Totals,value: Result<&2,&2,S.Error,Maybe<&2,ContextUsage>>) -> Result<&2,&2,S.Error,Stats>:
  match value:
    case Fail{reason}: Fail{reason}
    case Done{usage}: Done{Stats{path,id,totals,usage}}
def stats(+stored: Persistence.Session<Unit,Tools.ToolDetails,V.Value>,model: Maybe<&2,Ai.Model<Ai.JsonValue>>) -> Result<&2,&2,S.Error,Stats>:
  +manager = Persistence.stateOf(Unit,Tools.ToolDetails,V.Value,stored)
  +window = Maybe.default(&2,F64,Maybe.map(&2,Ai.Model<Ai.JsonValue>,F64,Ai.modelContextWindow,model),zero())
  withContext(Persistence.getSessionFile(Unit,Tools.ToolDetails,V.Value,stored),S.getSessionId(Unit,Tools.ToolDetails,V.Value,manager),aggregate(S.getEntries(Unit,Tools.ToolDetails,V.Value,manager),empty()),context(manager,window))

def contextValue(value: ContextUsage) -> V.Value:
  match value:
    case ContextUsage{tokens,window,percent}:
      Json.object(Json.field("tokens",Maybe.default(&2,V.Value,Maybe.map(&2,F64,V.Value,x => V.Number{x},tokens),V.Null{}),Json.field("contextWindow",V.Number{window},Json.field("percent",Maybe.default(&2,V.Value,Maybe.map(&2,F64,V.Value,x => V.Number{x},percent),V.Null{}),Nil{}))))
def value(stats: Stats) -> V.Value:
  match stats:
    case Stats{path,id,Totals{users,assistants,calls,results,messages,+input,+output,+read,+write,cost},ctx}:
      +tokenFields = Json.field("input",V.Number{input},Json.field("output",V.Number{output},Json.field("cacheRead",V.Number{read},Json.field("cacheWrite",V.Number{write},Json.field("total",V.Number{F.add(F.add(input,output),F.add(read,write))},Nil{})))))
      +tail = Json.field("tokens",Json.object(tokenFields),Json.field("cost",V.Number{cost},Json.optional("contextUsage",Maybe.map(&2,ContextUsage,V.Value,contextValue,ctx),Nil{})))
      +counts = Json.field("userMessages",Json.natural(users),Json.field("assistantMessages",Json.natural(assistants),Json.field("toolCalls",Json.natural(calls),Json.field("toolResults",Json.natural(results),Json.field("totalMessages",Json.natural(messages),tail)))))
      Json.object(Json.optionalText("sessionFile",path,Json.field("sessionId",Json.text(id),counts)))

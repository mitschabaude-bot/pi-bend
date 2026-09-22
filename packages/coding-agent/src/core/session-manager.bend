import Base
import ./messages.bend as Messages
import ../../../agent/src/types.bend as Agent
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/string.bend as Strings

def CURRENT_SESSION_VERSION() -> Nat: 3n

type SessionHeader is Data:
  SessionHeader{version: Maybe<&2,Nat>, id: String, timestamp: String, cwd: String, parentSession: Maybe<&2,String>}
type NewSessionOptions is Data:
  NewSessionOptions{id: Maybe<&2,String>, parentSession: Maybe<&2,String>}
type SessionEntryBase is Data:
  SessionEntryBase{id: String, parentId: Maybe<&2,String>, timestamp: String}

# Compaction has its own public record because latest-compaction lookup and
# subsequent compaction APIs require this narrower type.
type CompactionEntry<-C: Data> is Data:
  CompactionEntry{base: SessionEntryBase, summary: String, firstKeptEntryId: String, tokensBefore: Nat, details: Maybe<&2,C>, usage: Maybe<&2,Ai.Usage>, fromHook: Maybe<&2,Bool>, systemMessage: Maybe<&2,Ai.SystemMessage<Value.Value>>}

# The discriminator is a sum constructor. Extension payloads remain typed;
# message details use the same three parameters as the native agent stack.
type SessionEntry<-D: Data,-T: Data,-C: Data> is Data:
  SessionMessageEntry{base: SessionEntryBase, message: Agent.AgentMessage<D,T,Messages.CodingMessage<C>>}
  ThinkingLevelChangeEntry{base: SessionEntryBase, thinkingLevel: String}
  ModelChangeEntry{base: SessionEntryBase, provider: String, modelId: String}
  Compaction{entry: CompactionEntry<C>}
  BranchSummaryEntry{base: SessionEntryBase, fromId: String, summary: String, details: Maybe<&2,C>, usage: Maybe<&2,Ai.Usage>, fromHook: Maybe<&2,Bool>}
  CustomEntry{base: SessionEntryBase, customType: String, data: Maybe<&2,C>}
  CustomMessageEntry{base: SessionEntryBase, customType: String, content: Ai.UserContent, details: Maybe<&2,C>, display: Bool}
  LabelEntry{base: SessionEntryBase, targetId: String, label: Maybe<&2,String>}
  SessionInfoEntry{base: SessionEntryBase, name: Maybe<&2,String>}
type FileEntry<-D: Data,-T: Data,-C: Data> is Data:
  Header{value: SessionHeader}
  Entry{value: SessionEntry<D,T,C>}
type SessionTreeNode<-D: Data,-T: Data,-C: Data> is Data:
  SessionTreeNode{entry: SessionEntry<D,T,C>, children: List<&2,SessionTreeNode<D,T,C>>, label: Maybe<&2,String>, labelTimestamp: Maybe<&2,String>}
type SessionModel is Data:
  SessionModel{provider: String, modelId: String}
type SessionContext<-D: Data,-T: Data,-C: Data> is Data:
  SessionContext{messages: List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>, thinkingLevel: String, model: Maybe<&2,SessionModel>}
type SessionInfo is Data:
  SessionInfo{path: String, id: String, cwd: String, name: Maybe<&2,String>, parentSessionPath: Maybe<&2,String>, created: F64, modified: F64, messageCount: Nat, firstMessage: String, allMessagesText: String}

type LeafSelection is Data:
  Latest{}
  Root{}
  Leaf{id: String}
type Error is Data:
  DuplicateId{id: String}
  EmptyId{}
  Cycle{id: String}
  InvalidTimestamp{id: String, cause: Date.ParseError}

def entryBase(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>) -> SessionEntryBase:
  match entry:
    case SessionMessageEntry{base,_}: base
    case ThinkingLevelChangeEntry{base,_}: base
    case ModelChangeEntry{base,_,_}: base
    case Compaction{CompactionEntry{base,_,_,_,_,_,_,_}}: base
    case BranchSummaryEntry{base,_,_,_,_,_}: base
    case CustomEntry{base,_,_}: base
    case CustomMessageEntry{base,_,_,_,_}: base
    case LabelEntry{base,_,_}: base
    case SessionInfoEntry{base,_}: base

def baseId(base: SessionEntryBase) -> String:
  match base:
    case SessionEntryBase{id,_,_}: id

def entryId(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>) -> String:
  baseId(entryBase(D,T,C,entry))

type EntryIndex<-D: Data,-T: Data,-C: Data> is Data:
  EntryIndex{byId: Map<&2,Maybe<&2,SessionEntry<D,T,C>>>, latest: Maybe<&2,SessionEntry<D,T,C>>, count: Nat}

def lookupValue(-A: Data, result: Map<&2,A> & A) -> A:
  match result:
    case Tuple{_,value}: value

def lookup(-D: Data,-T: Data,-C: Data, index: Map<&2,Maybe<&2,SessionEntry<D,T,C>>>, key: String) -> Maybe<&2,SessionEntry<D,T,C>>:
  lookupValue(Maybe<&2,SessionEntry<D,T,C>>,Map.get(Maybe<&2,SessionEntry<D,T,C>>,None{},index,key))

def insertEntry(-D: Data,-T: Data,-C: Data, +entry: SessionEntry<D,T,C>, state: EntryIndex<D,T,C>, +id: String) -> Result<&2,&2,Error,EntryIndex<D,T,C>>:
  match state id:
    case _ SNil{}: Fail{EmptyId{}}
    case EntryIndex{+index,_,count} _:
      Bool.pick(Unit -> Result<&2,&2,Error,EntryIndex<D,T,C>>,Maybe.is_none(&2,SessionEntry<D,T,C>,lookup(D,T,C,index,id)),
        _ => Done{EntryIndex{Map.set(&2,Maybe<&2,SessionEntry<D,T,C>>,index,id,Some{entry}),Some{entry},1n + count}},
        _ => Fail{DuplicateId{id}})(Unit{})

def indexEntries(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, state: Result<&2,&2,Error,EntryIndex<D,T,C>>) -> Result<&2,&2,Error,EntryIndex<D,T,C>>:
  match entries state:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{index}: Done{index}
    case +entry <> rest Done{index}: indexEntries(D,T,C,rest,insertEntry(D,T,C,entry,index,entryId(D,T,C,entry)))

def buildEntryIndex(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,EntryIndex<D,T,C>>:
  indexEntries(D,T,C,entries,Done{EntryIndex{Map.new(&2,Maybe<&2,SessionEntry<D,T,C>>),None{},0n}})

def parentEntry(-D: Data,-T: Data,-C: Data, index: Map<&2,Maybe<&2,SessionEntry<D,T,C>>>, base: SessionEntryBase) -> Maybe<&2,SessionEntry<D,T,C>>:
  match base:
    case SessionEntryBase{_,None{},_}: None{}
    case SessionEntryBase{_,Some{SNil{}},_}: None{}
    case SessionEntryBase{_,Some{parent},_}: lookup(D,T,C,index,parent)

# A valid chain cannot visit more entries than the checked index contains.
# This detects cycles without a second visited-key set or unbounded recursion.
def walkPath(-D: Data,-T: Data,-C: Data, fuel: Nat, +index: Map<&2,Maybe<&2,SessionEntry<D,T,C>>>, current: Maybe<&2,SessionEntry<D,T,C>>, path: List<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,List<&2,SessionEntry<D,T,C>>>:
  match fuel current:
    case _ None{}: Done{path}
    case 0n Some{entry}: Fail{Cycle{entryId(D,T,C,entry)}}
    case 1n+remaining Some{+entry}: walkPath(D,T,C,remaining,index,parentEntry(D,T,C,index,entryBase(D,T,C,entry)),entry <> path)

def selectedLeaf(-D: Data,-T: Data,-C: Data, +index: Map<&2,Maybe<&2,SessionEntry<D,T,C>>>, latest: Maybe<&2,SessionEntry<D,T,C>>, selection: LeafSelection) -> Maybe<&2,SessionEntry<D,T,C>>:
  match selection:
    case Root{}: None{}
    case Latest{}: latest
    case Leaf{id}: Maybe.or(&2,SessionEntry<D,T,C>,lookup(D,T,C,index,id),latest)

def indexedPath(-D: Data,-T: Data,-C: Data, selection: LeafSelection, indexed: Result<&2,&2,Error,EntryIndex<D,T,C>>) -> Result<&2,&2,Error,List<&2,SessionEntry<D,T,C>>>:
  match indexed:
    case Fail{cause}: Fail{cause}
    case Done{EntryIndex{+index,latest,count}}: walkPath(D,T,C,count,index,selectedLeaf(D,T,C,index,latest,selection),Nil{})

def buildSessionPath(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, leaf: LeafSelection) -> Result<&2,&2,Error,List<&2,SessionEntry<D,T,C>>>:
  indexedPath(D,T,C,leaf,buildEntryIndex(D,T,C,entries))

def latestCompaction(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, found: Maybe<&2,CompactionEntry<C>>) -> Maybe<&2,CompactionEntry<C>>:
  match entries:
    case Nil{}: found
    case Compaction{entry} <> rest: latestCompaction(D,T,C,rest,Some{entry})
    case _ <> rest: latestCompaction(D,T,C,rest,found)

def getLatestCompactionEntry(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>) -> Maybe<&2,CompactionEntry<C>>:
  latestCompaction(D,T,C,entries,None{})

def keptEntry(-D: Data,-T: Data,-C: Data, +entry: SessionEntry<D,T,C>, keep: Bool, reversed: List<&2,SessionEntry<D,T,C>>) -> List<&2,SessionEntry<D,T,C>>:
  match entry keep:
    case _ False{}: reversed
    case SessionMessageEntry{_,Agent.LlmMessage{Ai.System{_}}} True{}: reversed
    case _ True{}: entry <> reversed

def compactPath(-D: Data,-T: Data,-C: Data, path: List<&2,SessionEntry<D,T,C>>, +compaction: CompactionEntry<C>, +compactionId: String, +firstKept: String, keep: Bool, +reversed: List<&2,SessionEntry<D,T,C>>) -> List<&2,SessionEntry<D,T,C>>:
  match path:
    case Nil{}: Compaction{compaction} <> List.reverse(&2,SessionEntry<D,T,C>,reversed)
    case +entry <> +rest:
      +keeping = keep || Strings.equal(entryId(D,T,C,entry),firstKept)
      Bool.pick(Unit -> List<&2,SessionEntry<D,T,C>>,Strings.equal(entryId(D,T,C,entry),compactionId),
        _ => Compaction{compaction} <> List.reverse.go(&2,SessionEntry<D,T,C>,reversed,rest),
        _ => compactPath(D,T,C,rest,compaction,compactionId,firstKept,keeping,keptEntry(D,T,C,entry,keeping,reversed)))(Unit{})

def contextForCompaction(-D: Data,-T: Data,-C: Data, path: List<&2,SessionEntry<D,T,C>>, +entry: CompactionEntry<C>) -> List<&2,SessionEntry<D,T,C>>:
  match entry:
    case CompactionEntry{base,_,firstKept,_,_,_,_,_}: compactPath(D,T,C,path,entry,baseId(base),firstKept,False{},Nil{})

def contextEntriesFrom(-D: Data,-T: Data,-C: Data, path: List<&2,SessionEntry<D,T,C>>, compaction: Maybe<&2,CompactionEntry<C>>) -> List<&2,SessionEntry<D,T,C>>:
  match compaction:
    case Some{entry}: contextForCompaction(D,T,C,path,entry)
    case None{}: path

def contextEntries(-D: Data,-T: Data,-C: Data, +path: List<&2,SessionEntry<D,T,C>>) -> List<&2,SessionEntry<D,T,C>>:
  contextEntriesFrom(D,T,C,path,getLatestCompactionEntry(D,T,C,path))

def buildContextEntries(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, leaf: LeafSelection) -> Result<&2,&2,Error,List<&2,SessionEntry<D,T,C>>>:
  Result.map(&2,&2,Error,List<&2,SessionEntry<D,T,C>>,List<&2,SessionEntry<D,T,C>>,path => contextEntries(D,T,C,path),buildSessionPath(D,T,C,entries,leaf))

def dated(-A: Data, id: String, result: Result<&2,&2,Date.ParseError,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{cause}: Fail{InvalidTimestamp{id,cause}}
    case Done{value}: Done{value}

def compactionMessages(-D: Data,-T: Data,-C: Data, summary: Messages.CompactionSummaryMessage, system: Maybe<&2,Ai.SystemMessage<Value.Value>>) -> List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>:
  match system:
    case None{}: [Agent.CustomMessage{Messages.CompactionSummary{summary}}]
    case Some{message}: [Agent.LlmMessage{Ai.System{message}},Agent.CustomMessage{Messages.CompactionSummary{summary}}]

def sessionEntryToContextMessages(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>) -> Result<&2,&2,Error,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>>:
  match entry:
    case SessionMessageEntry{_,message}: Done{[message]}
    case CustomMessageEntry{SessionEntryBase{id,_,timestamp},customType,content,details,display}:
      Result.map(&2,&2,Error,Messages.CustomMessage<C>,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>,value => [Agent.CustomMessage{Messages.Custom{value}}],dated(Messages.CustomMessage<C>,id,Messages.createCustomMessage(C,customType,content,display,details,timestamp)))
    case BranchSummaryEntry{_,_,SNil{},_,_,_}: Done{Nil{}}
    case BranchSummaryEntry{SessionEntryBase{id,_,timestamp},from,summary,_,_,_}:
      Result.map(&2,&2,Error,Messages.BranchSummaryMessage,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>,value => [Agent.CustomMessage{Messages.BranchSummary{value}}],dated(Messages.BranchSummaryMessage,id,Messages.createBranchSummaryMessage(summary,from,timestamp)))
    case Compaction{CompactionEntry{SessionEntryBase{id,_,timestamp},summary,_,tokens,_,_,_,system}}:
      Result.map(&2,&2,Error,Messages.CompactionSummaryMessage,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>,value => compactionMessages(D,T,C,value,system),dated(Messages.CompactionSummaryMessage,id,Messages.createCompactionSummaryMessage(summary,tokens,timestamp)))
    case _: Done{Nil{}}

type Settings is Data:
  Settings{thinkingLevel: String, model: Maybe<&2,SessionModel>}

def nextSettings(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>, settings: Settings) -> Settings:
  match entry settings:
    case ThinkingLevelChangeEntry{_,level} Settings{_,model}: Settings{level,model}
    case ModelChangeEntry{_,provider,model} Settings{level,_}: Settings{level,Some{SessionModel{provider,model}}}
    case SessionMessageEntry{_,Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_,_,provider,model,_,_,_,_,_,_,_,_,_,_,_}}}} Settings{level,_}: Settings{level,Some{SessionModel{provider,model}}}
    case _ previous: previous

def getSessionContextSettingsFrom(-D: Data,-T: Data,-C: Data, path: List<&2,SessionEntry<D,T,C>>, state: Settings) -> Settings:
  match path:
    case Nil{}: state
    case entry <> rest: getSessionContextSettingsFrom(D,T,C,rest,nextSettings(D,T,C,entry,state))

def getSessionContextSettings(-D: Data,-T: Data,-C: Data, path: List<&2,SessionEntry<D,T,C>>) -> Settings:
  getSessionContextSettingsFrom(D,T,C,path,Settings{"off",None{}})

def messagesFrom(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, reversed: List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>) -> Result<&2,&2,Error,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>>:
  match entries:
    case Nil{}: Done{List.reverse(&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>,reversed)}
    case entry <> rest:
      Result.bind(&2,&2,Error,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>,sessionEntryToContextMessages(D,T,C,entry),values => messagesFrom(D,T,C,rest,List.reverse.go(&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>,values,reversed)))

def contextResult(-D: Data,-T: Data,-C: Data, settings: Settings, messages: Result<&2,&2,Error,List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>>) -> Result<&2,&2,Error,SessionContext<D,T,C>>:
  match settings messages:
    case _ Fail{cause}: Fail{cause}
    case Settings{level,model} Done{values}: Done{SessionContext{values,level,model}}

def contextFromPath(-D: Data,-T: Data,-C: Data, +path: List<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,SessionContext<D,T,C>>:
  contextResult(D,T,C,getSessionContextSettings(D,T,C,path),messagesFrom(D,T,C,contextEntries(D,T,C,path),Nil{}))

def buildSessionContext(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, leaf: LeafSelection) -> Result<&2,&2,Error,SessionContext<D,T,C>>:
  Result.bind(&2,&2,Error,List<&2,SessionEntry<D,T,C>>,SessionContext<D,T,C>,buildSessionPath(D,T,C,entries,leaf),path => contextFromPath(D,T,C,path))

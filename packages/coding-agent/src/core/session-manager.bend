import Base
import ../../../ai/src/utils/transcript.bend as Transcript
import ../../../runtime/src/stable-sort.bend as Sort
import ../../../runtime/src/number-string.bend as NumberString
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

# Replacement content for an edited entry: upstream's union of the editable
# roles' content. Text is kept as text; blocks are fitted to the target's role
# when projected (a text block for assistant and tool-result text).
type EditableBlock is Data:
  EditableText{value: Ai.TextContent}
  EditableImage{value: Ai.ImageContent}
  EditableThinking{value: Ai.ThinkingContent}
  EditableToolCall{value: Ai.ToolCall<Value.Value>}
type ContextEditableContent is Data:
  ContentText{text: String}
  ContentBlocks{blocks: List<&2,EditableBlock>}

# The discriminator is a sum constructor. Extension payloads remain typed;
# message details use the same three parameters as the native agent stack.
type SessionEntry<-D: Data,-T: Data,-C: Data> is Data:
  SessionMessageEntry{base: SessionEntryBase, message: Agent.AgentMessage<D,T,Messages.CodingMessage<C>>}
  ThinkingLevelChangeEntry{base: SessionEntryBase, thinkingLevel: String}
  ModelChangeEntry{base: SessionEntryBase, provider: String, modelId: String}
  # Model-attributed usage that is not an assistant message and does not
  # participate in LLM context. `kind` is an arbitrary category, such as
  # "cache_warm"; `note` is an optional qualifier for usage notices.
  UsageEntry{base: SessionEntryBase, kind: String, provider: String, model: String, usage: Ai.Usage, note: Maybe<&2,String>}
  Compaction{entry: CompactionEntry<C>}
  BranchSummaryEntry{base: SessionEntryBase, fromId: String, summary: String, details: Maybe<&2,C>, usage: Maybe<&2,Ai.Usage>, fromHook: Maybe<&2,Bool>}
  CustomEntry{base: SessionEntryBase, customType: String, data: Maybe<&2,C>}
  CustomMessageEntry{base: SessionEntryBase, customType: String, content: Ai.UserContent, details: Maybe<&2,C>, display: Bool}
  LabelEntry{base: SessionEntryBase, targetId: String, label: Maybe<&2,String>}
  SessionInfoEntry{base: SessionEntryBase, name: Maybe<&2,String>}
  # Append-only change to one earlier entry's contribution to model context:
  # None omits the target, a value replaces only its content.
  ContextEditEntry{base: SessionEntryBase, targetId: String, replacement: Maybe<&2,ContextEditableContent>}
type FileEntry<-D: Data,-T: Data,-C: Data> is Data:
  Header{value: SessionHeader}
  Entry{value: SessionEntry<D,T,C>}
type SessionTreeNode<-D: Data,-T: Data,-C: Data> is Data:
  SessionTreeNode{entry: SessionEntry<D,T,C>, children: List<&2,SessionTreeNode<D,T,C>>, label: Maybe<&2,String>, labelTimestamp: Maybe<&2,String>}
type SessionModel is Data:
  SessionModel{provider: String, modelId: String}
type SessionContext<-D: Data,-T: Data,-C: Data> is Data:
  SessionContext{messages: List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>, thinkingLevel: String, model: Maybe<&2,SessionModel>}
type ProjectedSessionEntry<-D: Data,-T: Data,-C: Data> is Data:
  ProjectedSessionEntry{sourceEntry: SessionEntry<D,T,C>, messages: List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>}
type SessionProjection<-D: Data,-T: Data,-C: Data> is Data:
  SessionProjection{entries: List<&2,ProjectedSessionEntry<D,T,C>>, messages: List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>, thinkingLevel: String, model: Maybe<&2,SessionModel>}
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
  EntryNotFound{id: String}
  InvalidMessage{}
  LabelIdCount{}
  InvalidTimestamp{id: String, cause: Date.ParseError}
  NotOnActiveBranch{id: String}
  NotEditable{id: String}
  # Typed messages cannot hold content blocks their role does not allow.
  UnfitContextEdit{id: String}

def entryBase(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>) -> SessionEntryBase:
  match entry:
    case SessionMessageEntry{base,_}: base
    case ThinkingLevelChangeEntry{base,_}: base
    case ModelChangeEntry{base,_,_}: base
    case UsageEntry{base,_,_,_,_,_}: base
    case Compaction{CompactionEntry{base,_,_,_,_,_,_,_}}: base
    case BranchSummaryEntry{base,_,_,_,_,_}: base
    case CustomEntry{base,_,_}: base
    case CustomMessageEntry{base,_,_,_,_}: base
    case LabelEntry{base,_,_}: base
    case SessionInfoEntry{base,_}: base
    case ContextEditEntry{base,_,_}: base

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

def Msg(-D: Data,-T: Data,-C: Data) -> Data: Agent.AgentMessage<D,T,Messages.CodingMessage<C>>

def userBlocks(blocks: List<&2,EditableBlock>) -> Maybe<&2,List<&2,Ai.TextImageContent>>:
  match blocks:
    case Nil{}: Some{Nil{}}
    case EditableText{value} <> rest: Maybe.map(&2,List<&2,Ai.TextImageContent>,List<&2,Ai.TextImageContent>,tail => Ai.TextImageText{value} <> tail,userBlocks(rest))
    case EditableImage{value} <> rest: Maybe.map(&2,List<&2,Ai.TextImageContent>,List<&2,Ai.TextImageContent>,tail => Ai.TextImageImage{value} <> tail,userBlocks(rest))
    case _ <> _: None{}

def assistantBlocks(blocks: List<&2,EditableBlock>) -> Maybe<&2,List<&2,Ai.AssistantContent<Value.Value>>>:
  match blocks:
    case Nil{}: Some{Nil{}}
    case EditableText{value} <> rest: Maybe.map(&2,List<&2,Ai.AssistantContent<Value.Value>>,List<&2,Ai.AssistantContent<Value.Value>>,tail => Ai.AssistantText{value} <> tail,assistantBlocks(rest))
    case EditableThinking{value} <> rest: Maybe.map(&2,List<&2,Ai.AssistantContent<Value.Value>>,List<&2,Ai.AssistantContent<Value.Value>>,tail => Ai.AssistantThinking{value} <> tail,assistantBlocks(rest))
    case EditableToolCall{value} <> rest: Maybe.map(&2,List<&2,Ai.AssistantContent<Value.Value>>,List<&2,Ai.AssistantContent<Value.Value>>,tail => Ai.AssistantToolCall{value} <> tail,assistantBlocks(rest))
    case EditableImage{_} <> _: None{}

def textBlock(text: String) -> EditableBlock: EditableText{Ai.TextContent{text,None{}}}

def userContent(content: ContextEditableContent) -> Maybe<&2,Ai.UserContent>:
  match content:
    case ContentText{text}: Some{Ai.UserText{text}}
    case ContentBlocks{blocks}: Maybe.map(&2,List<&2,Ai.TextImageContent>,Ai.UserContent,values => Ai.UserBlocks{values},userBlocks(blocks))

def resultContent(content: ContextEditableContent) -> Maybe<&2,List<&2,Ai.TextImageContent>>:
  match content:
    case ContentText{text}: userBlocks([textBlock(text)])
    case ContentBlocks{blocks}: userBlocks(blocks)

def assistantContent(content: ContextEditableContent) -> Maybe<&2,List<&2,Ai.AssistantContent<Value.Value>>>:
  match content:
    case ContentText{text}: assistantBlocks([textBlock(text)])
    case ContentBlocks{blocks}: assistantBlocks(blocks)

# Replaces only the content of the editable roles; metadata is kept.
def editedMessage(-D: Data,-T: Data,-C: Data, +content: ContextEditableContent, message: Msg(D,T,C)) -> Maybe<&2,Msg(D,T,C)>:
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{_,timestamp}}}: Maybe.map(&2,Ai.UserContent,Msg(D,T,C),value => Agent.LlmMessage{Ai.User{Ai.UserMessage{value,timestamp}}},userContent(content))
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_,api,provider,model,responseModel,responseId,level,diagnostics,usage,reason,deferred,error,rawReason,endTurn,timestamp}}}:
      Maybe.map(&2,List<&2,Ai.AssistantContent<Value.Value>>,Msg(D,T,C),value => Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{value,api,provider,model,responseModel,responseId,level,diagnostics,usage,reason,deferred,error,rawReason,endTurn,timestamp}}},assistantContent(content))
    case Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id,name,_,details,usage,isError,timestamp}}}:
      Maybe.map(&2,List<&2,Ai.TextImageContent>,Msg(D,T,C),value => Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id,name,value,details,usage,isError,timestamp}}},resultContent(content))
    case Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{kind,_,display,details,timestamp}}}:
      Maybe.map(&2,Ai.UserContent,Msg(D,T,C),value => Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{kind,value,display,details,timestamp}}},userContent(content))
    case other: Some{other}

def editedMessages(-D: Data,-T: Data,-C: Data, +content: ContextEditableContent, messages: List<&2,Msg(D,T,C)>) -> Maybe<&2,List<&2,Msg(D,T,C)>>:
  match messages:
    case Nil{}: Some{Nil{}}
    case message <> rest: Maybe.bind(&2,Msg(D,T,C),List<&2,Msg(D,T,C)>,editedMessage(D,T,C,content,message),head => Maybe.map(&2,List<&2,Msg(D,T,C)>,List<&2,Msg(D,T,C)>,tail => head <> tail,editedMessages(D,T,C,content,rest)))

# The latest edit of an entry on the context path, by target id.
type ContextEdit is Data:
  ContextEdit{id: String, replacement: Maybe<&2,ContextEditableContent>}

def collectEdits(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, edits: Map<&2,Maybe<&2,ContextEdit>>) -> Map<&2,Maybe<&2,ContextEdit>>:
  match entries:
    case Nil{}: edits
    case ContextEditEntry{SessionEntryBase{id,_,_},target,change} <> rest: collectEdits(D,T,C,rest,Map.set(&2,Maybe<&2,ContextEdit>,edits,target,Some{ContextEdit{id,change}}))
    case _ <> rest: collectEdits(D,T,C,rest,edits)

def appliedEdit(-D: Data,-T: Data,-C: Data, edit: Maybe<&2,ContextEdit>, messages: List<&2,Msg(D,T,C)>) -> Result<&2,&2,Error,List<&2,Msg(D,T,C)>>:
  match edit:
    case None{}: Done{messages}
    case Some{ContextEdit{_,None{}}}: Done{Nil{}}
    case Some{ContextEdit{id,Some{content}}}: Maybe.default(&2,Result<&2,&2,Error,List<&2,Msg(D,T,C)>>,Maybe.map(&2,List<&2,Msg(D,T,C)>,Result<&2,&2,Error,List<&2,Msg(D,T,C)>>,values => Done{values},editedMessages(D,T,C,content,messages)),Fail{UnfitContextEdit{id}})

def projectContextEntry(-D: Data,-T: Data,-C: Data, +entry: SessionEntry<D,T,C>, edit: Maybe<&2,ContextEdit>) -> Result<&2,&2,Error,List<&2,Msg(D,T,C)>>:
  Result.bind(&2,&2,Error,List<&2,Msg(D,T,C)>,List<&2,Msg(D,T,C)>,sessionEntryToContextMessages(D,T,C,entry),messages => appliedEdit(D,T,C,edit,messages))

def editOf(edits: Map<&2,Maybe<&2,ContextEdit>>, id: String) -> Maybe<&2,ContextEdit>:
  lookupValue(Maybe<&2,ContextEdit>,Map.get(Maybe<&2,ContextEdit>,None{},edits,id))

# buildContextEntries can retain an older compaction whose raw id lies in the
# newest retained range. Only the newest compaction, first in the list,
# contributes its checkpoint and summary.
def projectedMessages(-D: Data,-T: Data,-C: Data, first: Bool, +entry: SessionEntry<D,T,C>, edits: Map<&2,Maybe<&2,ContextEdit>>) -> Result<&2,&2,Error,List<&2,Msg(D,T,C)>>:
  match first entry:
    case False{} Compaction{_}: Done{Nil{}}
    case _ entry: projectContextEntry(D,T,C,entry,editOf(edits,entryId(D,T,C,entry)))

def projectEntries(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, first: Bool, +edits: Map<&2,Maybe<&2,ContextEdit>>, reversed: List<&2,ProjectedSessionEntry<D,T,C>>) -> Result<&2,&2,Error,List<&2,ProjectedSessionEntry<D,T,C>>>:
  match entries:
    case Nil{}: Done{List.reverse(&2,ProjectedSessionEntry<D,T,C>,reversed)}
    case +entry <> rest: Result.bind(&2,&2,Error,List<&2,Msg(D,T,C)>,List<&2,ProjectedSessionEntry<D,T,C>>,projectedMessages(D,T,C,first,entry,edits),messages => projectEntries(D,T,C,rest,False{},edits,ProjectedSessionEntry{entry,messages} <> reversed))

def projectedMessagesOf(-D: Data,-T: Data,-C: Data, entries: List<&2,ProjectedSessionEntry<D,T,C>>) -> List<&2,Msg(D,T,C)>:
  match entries:
    case Nil{}: Nil{}
    case ProjectedSessionEntry{_,messages} <> rest: List.append(&2,Msg(D,T,C),messages,projectedMessagesOf(D,T,C,rest))

def projection(-D: Data,-T: Data,-C: Data, settings: Settings, +entries: List<&2,ProjectedSessionEntry<D,T,C>>) -> SessionProjection<D,T,C>:
  match settings:
    case Settings{level,model}: SessionProjection{entries,projectedMessagesOf(D,T,C,entries),level,model}

def projectionFromPath(-D: Data,-T: Data,-C: Data, +path: List<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,SessionProjection<D,T,C>>:
  +entries = contextEntries(D,T,C,path)
  Result.map(&2,&2,Error,List<&2,ProjectedSessionEntry<D,T,C>>,SessionProjection<D,T,C>,projected => projection(D,T,C,getSessionContextSettings(D,T,C,path),projected),projectEntries(D,T,C,entries,True{},collectEdits(D,T,C,entries,Map.new(&2,Maybe<&2,ContextEdit>)),Nil{}))

# Provenance-preserving, compaction-aware model context.
def buildSessionProjection(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, leaf: LeafSelection) -> Result<&2,&2,Error,SessionProjection<D,T,C>>:
  Result.bind(&2,&2,Error,List<&2,SessionEntry<D,T,C>>,SessionProjection<D,T,C>,buildSessionPath(D,T,C,entries,leaf),path => projectionFromPath(D,T,C,path))

def projectionContext(-D: Data,-T: Data,-C: Data, value: SessionProjection<D,T,C>) -> SessionContext<D,T,C>:
  match value:
    case SessionProjection{_,messages,level,model}: SessionContext{messages,level,model}

def contextFromPath(-D: Data,-T: Data,-C: Data, +path: List<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,SessionContext<D,T,C>>:
  Result.map(&2,&2,Error,SessionProjection<D,T,C>,SessionContext<D,T,C>,value => projectionContext(D,T,C,value),projectionFromPath(D,T,C,path))

# The finalized model context of the canonical projection.
def buildSessionContext(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, leaf: LeafSelection) -> Result<&2,&2,Error,SessionContext<D,T,C>>:
  Result.map(&2,&2,Error,SessionProjection<D,T,C>,SessionContext<D,T,C>,value => projectionContext(D,T,C,value),buildSessionProjection(D,T,C,entries,leaf))

# Immutable in-memory session. Supplied stamps keep randomness/time at the IO
# boundary. History is reversed for constant-time append; the selected leaf is
# independent of the most recently appended entry.
type EntryStamp is Data:
  EntryStamp{id: String, timestamp: String}
type ResolvedLabel is Data:
  ResolvedLabel{label: String, timestamp: String, position: Nat}
type LabelPosition is Data:
  LabelPosition{targetId: String, position: Nat}
type SessionManager<-D: Data,-T: Data,-C: Data> is Data:
  SessionManager{header: SessionHeader, reversed: List<&2,SessionEntry<D,T,C>>, index: EntryIndex<D,T,C>, leafId: Maybe<&2,String>, labels: Map<&2,Maybe<&2,ResolvedLabel>>, labelOrder: List<&2,LabelPosition>, nextLabel: Nat}

def inMemory(-D: Data,-T: Data,-C: Data, +header: SessionHeader) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match header:
    case SessionHeader{_,SNil{},_,_,_}: Fail{EmptyId{}}
    case SessionHeader{_,id,timestamp,_,_}:
      Result.map(&2,&2,Error,F64,SessionManager<D,T,C>,_ => SessionManager{header,Nil{},EntryIndex{Map.new(&2,Maybe<&2,SessionEntry<D,T,C>>),None{},0n},None{},Map.new(&2,Maybe<&2,ResolvedLabel>),Nil{},0n},dated(F64,id,Date.parseIso(timestamp)))

# A persisted fork records the file it was branched from in its header.
def withParentSession(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, parent: Maybe<&2,String>) -> SessionManager<D,T,C>:
  match state:
    case SessionManager{SessionHeader{version,id,timestamp,cwd,_},reversed,index,leaf,labels,order,next}: SessionManager{SessionHeader{version,id,timestamp,cwd,parent},reversed,index,leaf,labels,order,next}

def withVersion(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, version: Nat) -> SessionManager<D,T,C>:
  match state:
    case SessionManager{SessionHeader{_,id,timestamp,cwd,parent},reversed,index,leaf,labels,order,next}: SessionManager{SessionHeader{Some{version},id,timestamp,cwd,parent},reversed,index,leaf,labels,order,next}

def getHeader(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> SessionHeader:
  match state:
    case SessionManager{header,_,_,_,_,_,_}: header

def getSessionId(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> String:
  match state:
    case SessionManager{SessionHeader{_,id,_,_,_},_,_,_,_,_,_}: id

def getCwd(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> String:
  match state:
    case SessionManager{SessionHeader{_,_,_,cwd,_},_,_,_,_,_,_}: cwd

def newSession(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, stamp: EntryStamp, parentSession: Maybe<&2,String>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match stamp:
    case EntryStamp{id,timestamp}: inMemory(D,T,C,SessionHeader{Some{CURRENT_SESSION_VERSION()},id,timestamp,getCwd(D,T,C,state),parentSession})

def getEntries(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> List<&2,SessionEntry<D,T,C>>:
  match state:
    case SessionManager{_,reversed,_,_,_,_,_}: List.reverse(&2,SessionEntry<D,T,C>,reversed)

def getLeafId(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> Maybe<&2,String>:
  match state:
    case SessionManager{_,_,_,leaf,_,_,_}: leaf

def getEntry(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, id: String) -> Maybe<&2,SessionEntry<D,T,C>>:
  match state:
    case SessionManager{_,_,EntryIndex{index,_,_},_,_,_,_}: lookup(D,T,C,index,id)

def getLeafEntry(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> Maybe<&2,SessionEntry<D,T,C>>:
  match state:
    case SessionManager{_,_,EntryIndex{index,_,_},leaf,_,_,_}: Maybe.bind(&2,String,SessionEntry<D,T,C>,leaf,id => lookup(D,T,C,index,id))

def getBranch(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, selection: LeafSelection) -> Result<&2,&2,Error,List<&2,SessionEntry<D,T,C>>>:
  match state selection:
    case _ Root{}: Done{Nil{}}
    case SessionManager{_,_,EntryIndex{+index,_,count},leaf,_,_,_} Latest{}: walkPath(D,T,C,count,index,Maybe.bind(&2,String,SessionEntry<D,T,C>,leaf,id => lookup(D,T,C,index,id)),Nil{})
    case SessionManager{_,_,EntryIndex{+index,_,count},_,_,_,_} Leaf{id}: walkPath(D,T,C,count,index,lookup(D,T,C,index,id),Nil{})

def sessionContext(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> Result<&2,&2,Error,SessionContext<D,T,C>>:
  Result.bind(&2,&2,Error,List<&2,SessionEntry<D,T,C>>,SessionContext<D,T,C>,getBranch(D,T,C,state,Latest{}),path => contextFromPath(D,T,C,path))

def sessionProjection(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> Result<&2,&2,Error,SessionProjection<D,T,C>>:
  Result.bind(&2,&2,Error,List<&2,SessionEntry<D,T,C>>,SessionProjection<D,T,C>,getBranch(D,T,C,state,Latest{}),path => projectionFromPath(D,T,C,path))

def sessionContextEntries(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> Result<&2,&2,Error,List<&2,SessionEntry<D,T,C>>>:
  Result.map(&2,&2,Error,List<&2,SessionEntry<D,T,C>>,List<&2,SessionEntry<D,T,C>>,path => contextEntries(D,T,C,path),getBranch(D,T,C,state,Latest{}))

def branch(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, +id: String) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match state:
    case SessionManager{header,reversed,EntryIndex{+index,latest,count},_,labels,order,next}:
      Bool.pick(Result<&2,&2,Error,SessionManager<D,T,C>>,Maybe.is_some(&2,SessionEntry<D,T,C>,lookup(D,T,C,index,id)),Done{SessionManager{header,reversed,EntryIndex{index,latest,count},Some{id},labels,order,next}},Fail{EntryNotFound{id}})

def resetLeaf(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> SessionManager<D,T,C>:
  match state:
    case SessionManager{header,reversed,index,_,labels,order,next}: SessionManager{header,reversed,index,None{},labels,order,next}

def stampBase(stamp: EntryStamp, parent: Maybe<&2,String>) -> SessionEntryBase:
  match stamp:
    case EntryStamp{id,time}: SessionEntryBase{id,parent,time}

def labelAt(labels: Map<&2,Maybe<&2,ResolvedLabel>>, id: String) -> Maybe<&2,ResolvedLabel>:
  lookupValue(Maybe<&2,ResolvedLabel>,Map.get(Maybe<&2,ResolvedLabel>,None{},labels,id))

def labelText(value: ResolvedLabel) -> String:
  match value:
    case ResolvedLabel{text,_,_}: text

def getLabel(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, id: String) -> Maybe<&2,String>:
  match state:
    case SessionManager{_,_,_,_,labels,_,_}: Maybe.map(&2,ResolvedLabel,String,labelText,labelAt(labels,id))

def labelPosition(value: ResolvedLabel) -> Nat:
  match value:
    case ResolvedLabel{_,_,position}: position

# An order ticket is created only on insertion. Clearing then re-adding moves
# a label to the end; old tickets are ignored when enumerating resolved labels.
def updateLabel(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, +target: String, label: Maybe<&2,String>, timestamp: String) -> SessionManager<D,T,C>:
  match state label:
    case SessionManager{header,reversed,index,leaf,labels,order,next} None{}:
      SessionManager{header,reversed,index,leaf,Map.set(&2,Maybe<&2,ResolvedLabel>,labels,target,None{}),order,next}
    case SessionManager{header,reversed,index,leaf,labels,order,next} Some{SNil{}}:
      SessionManager{header,reversed,index,leaf,Map.set(&2,Maybe<&2,ResolvedLabel>,labels,target,None{}),order,next}
    case SessionManager{header,reversed,index,leaf,+labels,+order,+next} Some{text}:
      +previous = labelAt(labels,target)
      +position = Maybe.default(&2,Nat,Maybe.map(&2,ResolvedLabel,Nat,labelPosition,previous),next)
      SessionManager{header,reversed,index,leaf,Map.set(&2,Maybe<&2,ResolvedLabel>,labels,target,Some{ResolvedLabel{text,timestamp,position}}),Bool.pick(List<&2,LabelPosition>,Maybe.is_none(&2,ResolvedLabel,previous),LabelPosition{target,next} <> order,order),next + 1n}

def acceptEntry(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, +entry: SessionEntry<D,T,C>, checked: Result<&2,&2,Error,EntryIndex<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match state checked:
    case _ Fail{cause}: Fail{cause}
    case SessionManager{header,reversed,_,_,labels,order,next} Done{index}:
      Done{SessionManager{header,entry <> reversed,index,Some{entryId(D,T,C,entry)},labels,order,next}}

def appendChecked(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, +entry: SessionEntry<D,T,C>, metadata: SessionEntryBase) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match state metadata:
    case SessionManager{_,_,index,_,_,_,_} SessionEntryBase{+id,_,timestamp}:
      Result.bind(&2,&2,Error,F64,SessionManager<D,T,C>,dated(F64,id,Date.parseIso(timestamp)),_ => acceptEntry(D,T,C,state,entry,insertEntry(D,T,C,entry,index,id)))

# Restoring stored entries keeps their own ids, parent links and order; only
# id uniqueness and timestamp syntax are checked, as the index and label maps
# are rebuilt from them (upstream's _buildIndex). The leaf is the last entry.
def restoreLabel(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, entry: SessionEntry<D,T,C>) -> SessionManager<D,T,C>:
  match entry:
    case LabelEntry{SessionEntryBase{_,_,timestamp},target,label}: updateLabel(D,T,C,state,target,label,timestamp)
    case _: state

def restoreEntry(-D: Data,-T: Data,-C: Data, state: Result<&2,&2,Error,SessionManager<D,T,C>>, +entry: SessionEntry<D,T,C>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match state:
    case Fail{cause}: Fail{cause}
    case Done{+current}: Result.map(&2,&2,Error,SessionManager<D,T,C>,SessionManager<D,T,C>,next => restoreLabel(D,T,C,next,entry),appendChecked(D,T,C,current,entry,entryBase(D,T,C,entry)))

def restoreEntries(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, state: Result<&2,&2,Error,SessionManager<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match entries:
    case Nil{}: state
    case entry <> rest: restoreEntries(D,T,C,rest,restoreEntry(D,T,C,state,entry))

def restore(-D: Data,-T: Data,-C: Data, header: SessionHeader, entries: List<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  restoreEntries(D,T,C,entries,inMemory(D,T,C,header))

def appendMessage(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, message: Agent.AgentMessage<D,T,Messages.CodingMessage<C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match message:
    case Agent.CustomMessage{Messages.BranchSummary{_}}: Fail{InvalidMessage{}}
    case Agent.CustomMessage{Messages.CompactionSummary{_}}: Fail{InvalidMessage{}}
    case message:
      +base = stampBase(stamp,getLeafId(D,T,C,state))
      appendChecked(D,T,C,state,SessionMessageEntry{base,message},base)

def appendThinkingLevelChange(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, level: String) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  +base = stampBase(stamp,getLeafId(D,T,C,state))
  appendChecked(D,T,C,state,ThinkingLevelChangeEntry{base,level},base)

def appendModelChange(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, provider: String, model: String) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  +base = stampBase(stamp,getLeafId(D,T,C,state))
  appendChecked(D,T,C,state,ModelChangeEntry{base,provider,model},base)

def presentNote(note: Maybe<&2,String>) -> Maybe<&2,String>:
  match note:
    case None{}: None{}
    case Some{SNil{}}: None{}
    case Some{SCon{first,rest}}: Some{SCon{first,rest}}

# Append model-attributed usage that does not participate in LLM context. An
# empty note is omitted, as upstream's `...(note ? { note } : {})`.
def appendUsage(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, kind: String, provider: String, model: String, usage: Ai.Usage, note: Maybe<&2,String>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  +base = stampBase(stamp,getLeafId(D,T,C,state))
  appendChecked(D,T,C,state,UsageEntry{base,kind,provider,model,usage,presentNote(note)},base)

def appendCustomEntry(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, kind: String, data: Maybe<&2,C>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  +base = stampBase(stamp,getLeafId(D,T,C,state))
  appendChecked(D,T,C,state,CustomEntry{base,kind,data},base)

def appendCustomMessageEntry(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, kind: String, content: Ai.UserContent, display: Bool, details: Maybe<&2,C>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  +base = stampBase(stamp,getLeafId(D,T,C,state))
  appendChecked(D,T,C,state,CustomMessageEntry{base,kind,content,details,display},base)

def trimNameStart(value: String) -> String:
  match value:
    case SNil{}: ""
    case SCon{Chr{+char},+rest}: Bool.pick(Unit -> String,NumberString.whitespace(char),_ => trimNameStart(rest),_ => SCon{Chr{char},rest})(Unit{})

def trimName(value: String) -> String:
  String.reverse(trimNameStart(String.reverse(trimNameStart(value))))

def sanitizeName(name: String, inBreak: Bool, +reversed: String) -> String:
  match name:
    case SNil{}: trimName(String.reverse(reversed))
    case SCon{+char,rest}:
      +isBreak = Char.is_eq(char,'\r') || Char.is_eq(char,'\n')
      sanitizeName(rest,isBreak,Bool.pick(String,isBreak,Bool.pick(String,inBreak,reversed,SCon{' ',reversed}),SCon{char,reversed}))

def appendSessionInfo(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, name: String) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  +base = stampBase(stamp,getLeafId(D,T,C,state))
  appendChecked(D,T,C,state,SessionInfoEntry{base,Some{sanitizeName(name,False{},"")}},base)

def findSessionName(-D: Data,-T: Data,-C: Data, reversed: List<&2,SessionEntry<D,T,C>>) -> Maybe<&2,String>:
  match reversed:
    case SessionInfoEntry{_,None{}} <> _: None{}
    case SessionInfoEntry{_,Some{name}} <> _:
      +trimmed = trimName(name)
      Bool.pick(Maybe<&2,String>,String.is_empty(trimmed),None{},Some{trimmed})
    case _ <> rest: findSessionName(D,T,C,rest)
    case Nil{}: None{}

def getSessionName(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> Maybe<&2,String>:
  match state:
    case SessionManager{_,reversed,_,_,_,_,_}: findSessionName(D,T,C,reversed)

def appendLabelChange(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, +stamp: EntryStamp, +target: String, +label: Maybe<&2,String>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match stamp:
    case EntryStamp{_,+timestamp}:
      +base = stampBase(stamp,getLeafId(D,T,C,state))
      Bool.pick(Unit -> Result<&2,&2,Error,SessionManager<D,T,C>>,Maybe.is_some(&2,SessionEntry<D,T,C>,getEntry(D,T,C,state,target)),
        _ => Result.map(&2,&2,Error,SessionManager<D,T,C>,SessionManager<D,T,C>,next => updateLabel(D,T,C,next,target,label,timestamp),appendChecked(D,T,C,state,LabelEntry{base,target,label},base)),
        _ => Fail{EntryNotFound{target}})(Unit{})

def branchWithSummary(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, target: Maybe<&2,String>, summary: String, details: Maybe<&2,C>, fromHook: Maybe<&2,Bool>, usage: Maybe<&2,Ai.Usage>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match target:
    case None{}:
      from = Maybe.default(&2,String,getLeafId(D,T,C,state),"root")
      +base = stampBase(stamp,None{})
      appendChecked(D,T,C,resetLeaf(D,T,C,state),BranchSummaryEntry{base,from,summary,details,usage,fromHook},base)
    case Some{+id}:
      from = Maybe.default(&2,String,getLeafId(D,T,C,state),"root")
      +base = stampBase(stamp,Some{id})
      Result.bind(&2,&2,Error,SessionManager<D,T,C>,SessionManager<D,T,C>,branch(D,T,C,state,id),next => appendChecked(D,T,C,next,BranchSummaryEntry{base,from,summary,details,usage,fromHook},base))

def llmMessages(-D: Data,-T: Data,-C: Data, messages: List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>, reversed: List<&2,Ai.Message<Value.Value,Value.Value,D,T>>) -> List<&2,Ai.Message<Value.Value,Value.Value,D,T>>:
  match messages:
    case Nil{}: List.reverse(&2,Ai.Message<Value.Value,Value.Value,D,T>,reversed)
    case Agent.LlmMessage{value} <> rest: llmMessages(D,T,C,rest,value <> reversed)
    case _ <> rest: llmMessages(D,T,C,rest,reversed)

def systemTimestamp(timestamp: F64, value: Ai.SystemMessage<Value.Value>) -> Ai.SystemMessage<Value.Value>:
  match value:
    case Ai.SystemMessage{content,sections,tools,changes,_}: Ai.SystemMessage{content,sections,tools,changes,timestamp}

def appendCompactionFromContext(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, +base: SessionEntryBase, summary: String, keep: String, tokens: Nat, details: Maybe<&2,C>, fromHook: Maybe<&2,Bool>, usage: Maybe<&2,Ai.Usage>, context: SessionContext<D,T,C>, time: F64) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match context:
    case SessionContext{messages,_,_}:
      snapshot = Maybe.map(&2,Ai.SystemMessage<Value.Value>,Ai.SystemMessage<Value.Value>,value => systemTimestamp(time,value),Transcript.getCurrentSystemMessage(Value.Value,Value.Value,D,T,llmMessages(D,T,C,messages,Nil{})))
      appendChecked(D,T,C,state,Compaction{CompactionEntry{base,summary,keep,tokens,details,usage,fromHook,snapshot}},base)

# Without a first kept entry the compaction keeps itself: nothing before it
# stays in context.
def appendCompaction(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, +stamp: EntryStamp, summary: String, firstKept: Maybe<&2,String>, tokens: Nat, details: Maybe<&2,C>, fromHook: Maybe<&2,Bool>, usage: Maybe<&2,Ai.Usage>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match stamp:
    case EntryStamp{+id,timestamp}:
      base = stampBase(stamp,getLeafId(D,T,C,state))
      keep = Maybe.default(&2,String,firstKept,id)
      Result.bind(&2,&2,Error,F64,SessionManager<D,T,C>,dated(F64,id,Date.parseIso(timestamp)),time => Result.bind(&2,&2,Error,SessionContext<D,T,C>,SessionManager<D,T,C>,sessionContext(D,T,C,state),context => appendCompactionFromContext(D,T,C,state,base,summary,keep,tokens,details,fromHook,usage,context,time)))

def onBranch(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, +id: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case entry <> rest: Strings.equal(entryId(D,T,C,entry),id) || onBranch(D,T,C,rest,id)

# Assistant and tool-result content is an array, so text becomes a text block.
def editTarget(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>, +edit: Maybe<&2,ContextEditableContent>) -> Maybe<&2,Maybe<&2,ContextEditableContent>>:
  match entry edit:
    case CustomMessageEntry{_,_,_,_,_} value: Some{value}
    case SessionMessageEntry{_,Agent.LlmMessage{Ai.User{_}}} value: Some{value}
    case SessionMessageEntry{_,Agent.LlmMessage{Ai.Assistant{_}}} Some{ContentText{text}}: Some{Some{ContentBlocks{[textBlock(text)]}}}
    case SessionMessageEntry{_,Agent.LlmMessage{Ai.Assistant{_}}} value: Some{value}
    case SessionMessageEntry{_,Agent.LlmMessage{Ai.ToolResult{_}}} Some{ContentText{text}}: Some{Some{ContentBlocks{[textBlock(text)]}}}
    case SessionMessageEntry{_,Agent.LlmMessage{Ai.ToolResult{_}}} value: Some{value}
    case _ _: None{}

def fitsMessages(-D: Data,-T: Data,-C: Data, +content: ContextEditableContent, messages: Result<&2,&2,Error,List<&2,Msg(D,T,C)>>) -> Bool:
  match messages:
    case Fail{_}: True{}
    case Done{values}: Maybe.is_some(&2,List<&2,Msg(D,T,C)>,editedMessages(D,T,C,content,values))

def fits(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>, edit: Maybe<&2,ContextEditableContent>) -> Bool:
  match edit:
    case None{}: True{}
    case Some{content}: fitsMessages(D,T,C,content,sessionEntryToContextMessages(D,T,C,entry))

def appendEdit(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, +stamp: EntryStamp, +target: String, entry: SessionEntry<D,T,C>, normalized: Maybe<&2,Maybe<&2,ContextEditableContent>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match stamp normalized:
    case _ None{}: Fail{NotEditable{target}}
    case EntryStamp{+id,_} Some{+edit}:
      +base = stampBase(stamp,getLeafId(D,T,C,state))
      Bool.pick(Unit -> Result<&2,&2,Error,SessionManager<D,T,C>>,fits(D,T,C,entry,edit),
        _ => appendChecked(D,T,C,state,ContextEditEntry{base,target,edit},base),
        _ => Fail{UnfitContextEdit{id}})(Unit{})

def appendBranchEdit(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, +target: String, +entry: SessionEntry<D,T,C>, edit: Maybe<&2,ContextEditableContent>, branch: Result<&2,&2,Error,List<&2,SessionEntry<D,T,C>>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match branch:
    case Fail{cause}: Fail{cause}
    case Done{path}: Bool.pick(Unit -> Result<&2,&2,Error,SessionManager<D,T,C>>,onBranch(D,T,C,path,target),
      _ => appendEdit(D,T,C,state,stamp,target,entry,editTarget(D,T,C,entry,edit)),
      _ => Fail{NotOnActiveBranch{target}})(Unit{})

# Append a branch-local edit to an earlier model-visible entry.
def appendTargetEdit(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, +target: String, edit: Maybe<&2,ContextEditableContent>, found: Maybe<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match found:
    case None{}: Fail{EntryNotFound{target}}
    case Some{entry}: appendBranchEdit(D,T,C,state,stamp,target,entry,edit,getBranch(D,T,C,state,Latest{}))

def appendContextEdit(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, stamp: EntryStamp, +target: String, edit: Maybe<&2,ContextEditableContent>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  appendTargetEdit(D,T,C,state,stamp,target,edit,getEntry(D,T,C,state,target))

def sameParent(left: Maybe<&2,String>, right: Maybe<&2,String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: Strings.equal(a,b)
    case _ _: False{}

def baseParent(base: SessionEntryBase) -> Maybe<&2,String>:
  match base:
    case SessionEntryBase{_,parent,_}: parent

def entryParent(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>) -> Maybe<&2,String>:
  baseParent(entryBase(D,T,C,entry))

def childrenFrom(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, +parent: String, +children: List<&2,SessionEntry<D,T,C>>) -> List<&2,SessionEntry<D,T,C>>:
  match entries:
    case Nil{}: children
    case +entry <> rest: childrenFrom(D,T,C,rest,parent,Bool.pick(List<&2,SessionEntry<D,T,C>>,sameParent(entryParent(D,T,C,entry),Some{parent}),entry <> children,children))

def getChildren(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, parent: String) -> List<&2,SessionEntry<D,T,C>>:
  match state:
    case SessionManager{_,reversed,_,_,_,_,_}: childrenFrom(D,T,C,reversed,parent,Nil{})

# Appends can only reference existing parents. Reverse insertion order is thus
# a topological order: assemble each subtree once, without recursive descent.
type TimedNode<-D: Data,-T: Data,-C: Data> is Data:
  TimedNode{node: SessionTreeNode<D,T,C>, time: F64}
def nodeBefore(-D: Data,-T: Data,-C: Data, left: TimedNode<D,T,C>, right: TimedNode<D,T,C>) -> Bool:
  match left right:
    case TimedNode{_,a} TimedNode{_,b}: F64.is_le(a,b)
# Sort.sort requires static type/comparator arguments; this tree carries erased
# D/T/C parameters. Keep the dynamic merge here until the shared sorter accepts
# ordinary comparator closures without changing these public session APIs.
def mergeNodes(-D: Data,-T: Data,-C: Data, left: List<&2,TimedNode<D,T,C>>, right: List<&2,TimedNode<D,T,C>>, +reversed: List<&2,TimedNode<D,T,C>>) -> List<&2,TimedNode<D,T,C>>:
  match left right:
    case Nil{} right: List.reverse.go(&2,TimedNode<D,T,C>,reversed,right)
    case left Nil{}: List.reverse.go(&2,TimedNode<D,T,C>,reversed,left)
    case +a <> +left +b <> +right:
      Bool.pick(Unit -> List<&2,TimedNode<D,T,C>>,nodeBefore(D,T,C,a,b),_ => mergeNodes(D,T,C,left,b <> right,a <> reversed),_ => mergeNodes(D,T,C,a <> left,right,b <> reversed))(Unit{})

def mergeNodeRuns(-D: Data,-T: Data,-C: Data, runs: List<&2,List<&2,TimedNode<D,T,C>>>, reversed: List<&2,List<&2,TimedNode<D,T,C>>>) -> List<&2,List<&2,TimedNode<D,T,C>>>:
  match runs:
    case Nil{}: List.reverse(&2,List<&2,TimedNode<D,T,C>>,reversed)
    case last <> Nil{}: List.reverse(&2,List<&2,TimedNode<D,T,C>>,last <> reversed)
    case left <> right <> rest: mergeNodeRuns(D,T,C,rest,mergeNodes(D,T,C,left,right,Nil{}) <> reversed)

def sortNodeRuns(-D: Data,-T: Data,-C: Data, fuel: Nat, runs: List<&2,List<&2,TimedNode<D,T,C>>>) -> List<&2,TimedNode<D,T,C>>:
  match fuel runs:
    case _ Nil{}: Nil{}
    case _ last <> Nil{}: last
    case 1n+fuel first <> second <> rest: sortNodeRuns(D,T,C,fuel,mergeNodeRuns(D,T,C,first <> second <> rest,Nil{}))
    case 0n _: Nil{}

def nodeValue(-D: Data,-T: Data,-C: Data, value: TimedNode<D,T,C>) -> SessionTreeNode<D,T,C>:
  match value:
    case TimedNode{node,_}: node

def nodeValues(-D: Data,-T: Data,-C: Data, values: List<&2,TimedNode<D,T,C>>, reversed: List<&2,SessionTreeNode<D,T,C>>) -> List<&2,SessionTreeNode<D,T,C>>:
  match values:
    case Nil{}: List.reverse(&2,SessionTreeNode<D,T,C>,reversed)
    case value <> rest: nodeValues(D,T,C,rest,nodeValue(D,T,C,value) <> reversed)

def nodeLabel(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>, children: List<&2,SessionTreeNode<D,T,C>>, label: Maybe<&2,ResolvedLabel>) -> SessionTreeNode<D,T,C>:
  match label:
    case None{}: SessionTreeNode{entry,children,None{},None{}}
    case Some{ResolvedLabel{text,timestamp,_}}: SessionTreeNode{entry,children,Some{text},Some{timestamp}}

type ForestStep<-D: Data,-T: Data,-C: Data> is Data:
  ForestStep{children: Map<&2,List<&2,TimedNode<D,T,C>>>, roots: List<&2,SessionTreeNode<D,T,C>>}

def addTreeNode(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>, labels: Map<&2,Maybe<&2,ResolvedLabel>>, +children: Map<&2,List<&2,TimedNode<D,T,C>>>, roots: List<&2,SessionTreeNode<D,T,C>>, metadata: SessionEntryBase) -> Result<&2,&2,Error,ForestStep<D,T,C>>:
  match metadata:
    case SessionEntryBase{+id,None{},_}:
      +group = lookupValue(List<&2,TimedNode<D,T,C>>,Map.get(List<&2,TimedNode<D,T,C>>,Nil{},children,id))
      node = nodeLabel(D,T,C,entry,nodeValues(D,T,C,sortNodeRuns(D,T,C,Sort.length(TimedNode<D,T,C>,group,0n),Sort.runs(TimedNode<D,T,C>,group,Nil{})),Nil{}),labelAt(labels,id))
      Done{ForestStep{children,node <> roots}}
    case SessionEntryBase{+id,Some{+parent},timestamp}:
      +group = lookupValue(List<&2,TimedNode<D,T,C>>,Map.get(List<&2,TimedNode<D,T,C>>,Nil{},children,id))
      node = nodeLabel(D,T,C,entry,nodeValues(D,T,C,sortNodeRuns(D,T,C,Sort.length(TimedNode<D,T,C>,group,0n),Sort.runs(TimedNode<D,T,C>,group,Nil{})),Nil{}),labelAt(labels,id))
      Result.map(&2,&2,Error,F64,ForestStep<D,T,C>,time => ForestStep{Map.set(&2,List<&2,TimedNode<D,T,C>>,children,parent,TimedNode{node,time} <> lookupValue(List<&2,TimedNode<D,T,C>>,Map.get(List<&2,TimedNode<D,T,C>>,Nil{},children,parent))),roots},dated(F64,id,Date.parseIso(timestamp)))

def forest(-D: Data,-T: Data,-C: Data, entries: List<&2,SessionEntry<D,T,C>>, +labels: Map<&2,Maybe<&2,ResolvedLabel>>, state: Result<&2,&2,Error,ForestStep<D,T,C>>) -> Result<&2,&2,Error,List<&2,SessionTreeNode<D,T,C>>>:
  match entries state:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{ForestStep{_,roots}}: Done{roots}
    case +entry <> rest Done{ForestStep{children,roots}}: forest(D,T,C,rest,labels,addTreeNode(D,T,C,entry,labels,children,roots,entryBase(D,T,C,entry)))

def getTree(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>) -> Result<&2,&2,Error,List<&2,SessionTreeNode<D,T,C>>>:
  match state:
    case SessionManager{_,reversed,_,_,labels,_,_}: forest(D,T,C,reversed,labels,Done{ForestStep{Map.new(&2,List<&2,TimedNode<D,T,C>>),Nil{}}})

# Forks remove label entries, reconnect the path, and reproduce only resolved
# labels on retained targets. Replacement links also repair compactions whose
# first kept entry was a removed label.
def reparentBase(base: SessionEntryBase, parent: Maybe<&2,String>) -> SessionEntryBase:
  match base:
    case SessionEntryBase{id,_,timestamp}: SessionEntryBase{id,parent,timestamp}

def linkedId(links: Map<&2,Maybe<&2,String>>, +id: String) -> String:
  Maybe.default(&2,String,lookupValue(Maybe<&2,String>,Map.get(Maybe<&2,String>,None{},links,id)),id)

def reparent(-D: Data,-T: Data,-C: Data, entry: SessionEntry<D,T,C>, parent: Maybe<&2,String>, replacements: Map<&2,Maybe<&2,String>>) -> SessionEntry<D,T,C>:
  match entry:
    case SessionMessageEntry{base,message}: SessionMessageEntry{reparentBase(base,parent),message}
    case ThinkingLevelChangeEntry{base,level}: ThinkingLevelChangeEntry{reparentBase(base,parent),level}
    case ModelChangeEntry{base,provider,model}: ModelChangeEntry{reparentBase(base,parent),provider,model}
    case UsageEntry{base,kind,provider,model,usage,note}: UsageEntry{reparentBase(base,parent),kind,provider,model,usage,note}
    case Compaction{CompactionEntry{base,summary,keep,tokens,details,usage,hook,system}}: Compaction{CompactionEntry{reparentBase(base,parent),summary,linkedId(replacements,keep),tokens,details,usage,hook,system}}
    case BranchSummaryEntry{base,from,summary,details,usage,hook}: BranchSummaryEntry{reparentBase(base,parent),from,summary,details,usage,hook}
    case CustomEntry{base,kind,data}: CustomEntry{reparentBase(base,parent),kind,data}
    case CustomMessageEntry{base,kind,content,details,display}: CustomMessageEntry{reparentBase(base,parent),kind,content,details,display}
    case LabelEntry{base,target,label}: LabelEntry{reparentBase(base,parent),target,label}
    case SessionInfoEntry{base,name}: SessionInfoEntry{reparentBase(base,parent),name}
    case ContextEditEntry{base,target,change}: ContextEditEntry{reparentBase(base,parent),target,change}

def replacePending(pending: List<&2,String>, +next: String, links: Map<&2,Maybe<&2,String>>) -> Map<&2,Maybe<&2,String>>:
  match pending:
    case Nil{}: links
    case id <> rest: replacePending(rest,next,Map.set(&2,Maybe<&2,String>,links,id,Some{next}))

def forkPath(-D: Data,-T: Data,-C: Data, path: List<&2,SessionEntry<D,T,C>>, pending: List<&2,String>, replacements: Map<&2,Maybe<&2,String>>, state: Result<&2,&2,Error,SessionManager<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match path state:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{state}: Done{state}
    case LabelEntry{SessionEntryBase{id,_,_},_,_} <> rest Done{state}: forkPath(D,T,C,rest,id <> pending,replacements,Done{state})
    case reference <> rest Done{+state}:
      +entry = {reference : SessionEntry<D,T,C>}
      +links = replacePending(pending,entryId(D,T,C,entry),replacements)
      +updated = reparent(D,T,C,entry,getLeafId(D,T,C,state),links)
      forkPath(D,T,C,rest,Nil{},links,appendChecked(D,T,C,state,updated,entryBase(D,T,C,updated)))

def currentLabel(labels: Map<&2,Maybe<&2,ResolvedLabel>>, +target: String, position: Nat) -> Maybe<&2,ResolvedLabel>:
  previous = labelAt(labels,target)
  Maybe.bind(&2,ResolvedLabel,ResolvedLabel,previous,+value => Bool.pick(Maybe<&2,ResolvedLabel>,Nat.is_eq(labelPosition(value),position),Some{value},None{}))

def forkLabel(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, id: String, target: String, label: ResolvedLabel) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match label:
    case ResolvedLabel{text,timestamp,_}: appendLabelChange(D,T,C,state,EntryStamp{id,timestamp},target,Some{text})

type ForkLabelsState<-D: Data,-T: Data,-C: Data> is Data:
  ForkLabelsState{session: SessionManager<D,T,C>, ids: List<&2,String>}

def copyLabel(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, ids: List<&2,String>, target: String, label: Maybe<&2,ResolvedLabel>) -> Result<&2,&2,Error,ForkLabelsState<D,T,C>>:
  match ids label:
    case ids None{}: Done{ForkLabelsState{state,ids}}
    case Nil{} Some{_}: Fail{LabelIdCount{}}
    case id <> rest Some{value}: Result.map(&2,&2,Error,SessionManager<D,T,C>,ForkLabelsState<D,T,C>,next => ForkLabelsState{next,rest},forkLabel(D,T,C,state,id,target,value))

def forkLabels(-D: Data,-T: Data,-C: Data, tickets: List<&2,LabelPosition>, +labels: Map<&2,Maybe<&2,ResolvedLabel>>, +retained: SessionManager<D,T,C>, progress: Result<&2,&2,Error,ForkLabelsState<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match tickets progress:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{ForkLabelsState{state,Nil{}}}: Done{state}
    case Nil{} Done{ForkLabelsState{_,_}}: Fail{LabelIdCount{}}
    case LabelPosition{+target,position} <> rest Done{ForkLabelsState{+state,ids}}:
      label = Bool.pick(Maybe<&2,ResolvedLabel>,Maybe.is_some(&2,SessionEntry<D,T,C>,getEntry(D,T,C,retained,target)),currentLabel(labels,target,position),None{})
      forkLabels(D,T,C,rest,labels,retained,copyLabel(D,T,C,state,ids,target,label))

def forkResolvedLabels(-D: Data,-T: Data,-C: Data, order: List<&2,LabelPosition>, labels: Map<&2,Maybe<&2,ResolvedLabel>>, ids: List<&2,String>, result: Result<&2,&2,Error,SessionManager<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{+state}: forkLabels(D,T,C,List.reverse(&2,LabelPosition,order),labels,state,Done{ForkLabelsState{state,ids}})

def forkSelected(-D: Data,-T: Data,-C: Data, state: SessionManager<D,T,C>, leaf: String, stamp: EntryStamp, ids: List<&2,String>, path: List<&2,SessionEntry<D,T,C>>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  match state stamp path:
    case _ _ Nil{}: Fail{EntryNotFound{leaf}}
    case SessionManager{SessionHeader{_,_,_,cwd,_},_,_,_,labels,order,_} EntryStamp{id,timestamp} path:
      initial = inMemory(D,T,C,SessionHeader{Some{CURRENT_SESSION_VERSION()},id,timestamp,cwd,None{}})
      forkResolvedLabels(D,T,C,order,labels,ids,forkPath(D,T,C,path,Nil{},Map.new(&2,Maybe<&2,String>),initial))

def createBranchedSession(-D: Data,-T: Data,-C: Data, +state: SessionManager<D,T,C>, +leaf: String, stamp: EntryStamp, labelIds: List<&2,String>) -> Result<&2,&2,Error,SessionManager<D,T,C>>:
  Result.bind(&2,&2,Error,List<&2,SessionEntry<D,T,C>>,SessionManager<D,T,C>,getBranch(D,T,C,state,Leaf{leaf}),path => forkSelected(D,T,C,state,leaf,stamp,labelIds,path))

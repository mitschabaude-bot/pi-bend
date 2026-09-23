import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/retry.bend as Retry
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/string.bend as Strings
import ../messages.bend as Messages
import ../session-manager.bend as Session
import ./compaction.bend as Compaction
import ./utils.bend as Utils

# pi compaction/branch-summarization.ts: preserve only the abandoned path,
# then summarize its newest context as a separate model request.
def Entry(-D: Data,-T: Data,-C: Data) -> Data: Session.SessionEntry<D,T,C>
def Message(-D: Data,-T: Data,-C: Data) -> Data: Agent.AgentMessage<D,T,Messages.CodingMessage<C>>

type Collected<-D: Data,-T: Data,-C: Data> is Data:
  Collected{entries: List<&2,Session.SessionEntry<D,T,C>>,commonAncestorId: Maybe<&2,String>}
type Prepared<-D: Data,-T: Data,-C: Data> is Data:
  Prepared{messages: List<&2,Agent.AgentMessage<D,T,Messages.CodingMessage<C>>>,fileOps: Utils.FileOperations,totalTokens: F64}
type Summary is Data:
  Summary{text: String,usage: Maybe<&2,Ai.Usage>,details: Value.Value}

def idOf(-D: Data,-T: Data,-C: Data,entry: Entry(D,T,C)) -> String:
  Session.baseId(Session.entryBase(D,T,C,entry))
def oldBranch(-D: Data,-T: Data,-C: Data,state: Session.SessionManager<D,T,C>,oldLeafId: Maybe<&2,String>) -> Result<&2,&2,Session.Error,List<&2,Entry(D,T,C)>>:
  match oldLeafId:
    case None{}: Done{Nil{}}
    case Some{id}: Session.getBranch(D,T,C,state,Session.Leaf{id})
def commonTail(-D: Data,-T: Data,-C: Data,oldPath: List<&2,Entry(D,T,C)>,targetPath: List<&2,Entry(D,T,C)>,common: Maybe<&2,String>) -> Collected<D,T,C>:
  match oldPath targetPath:
    case +old <> +oldRest target <> targetRest:
      Bool.pick(Unit -> Collected<D,T,C>,String.eq(idOf(D,T,C,old),idOf(D,T,C,target)),_ => commonTail(D,T,C,oldRest,targetRest,Some{idOf(D,T,C,old)}),_ => Collected{old <> oldRest,common})(Unit{})
    case _ _: Collected{oldPath,common}
def collect(-D: Data,-T: Data,-C: Data,+state: Session.SessionManager<D,T,C>,oldLeafId: Maybe<&2,String>,targetId: String) -> Result<&2,&2,Session.Error,Collected<D,T,C>>:
  Result.bind(&2,&2,Session.Error,List<&2,Entry(D,T,C)>,Collected<D,T,C>,oldBranch(D,T,C,state,oldLeafId),oldPath =>
    Result.map(&2,&2,Session.Error,List<&2,Entry(D,T,C)>,Collected<D,T,C>,targetPath => commonTail(D,T,C,oldPath,targetPath,None{}),Session.getBranch(D,T,C,state,Session.Leaf{targetId})))

def content(-D: Data,-T: Data,-C: Data,+entry: Entry(D,T,C)) -> List<&2,Message(D,T,C)>:
  match entry:
    case Session.SessionMessageEntry{_,Agent.LlmMessage{Ai.ToolResult{_}}}: Nil{}
    case Session.SessionMessageEntry{_,_}: Result.default(&2,&2,Session.Error,List<&2,Message(D,T,C)>,Session.sessionEntryToContextMessages(D,T,C,entry),Nil{})
    case Session.CustomMessageEntry{_,_,_,_,_}: Result.default(&2,&2,Session.Error,List<&2,Message(D,T,C)>,Session.sessionEntryToContextMessages(D,T,C,entry),Nil{})
    case Session.BranchSummaryEntry{_,_,_,_,_,_}: Result.default(&2,&2,Session.Error,List<&2,Message(D,T,C)>,Session.sessionEntryToContextMessages(D,T,C,entry),Nil{})
    case Session.Compaction{_}: Result.default(&2,&2,Session.Error,List<&2,Message(D,T,C)>,Session.sessionEntryToContextMessages(D,T,C,entry),Nil{})
    case _: Nil{}
def textValues(values: List<&2,Value.Value>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case Value.Text{text} <> rest: text <> textValues(rest)
    case _ <> rest: textValues(rest)
def detailArray(value: Maybe<&2,Value.Value>) -> List<&2,String>:
  match value:
    case Some{Value.ArrayValue{values}}: textValues(values)
    case _: Nil{}
def detailFiles(value: Maybe<&2,Value.Value>,name: String) -> List<&2,String>:
  match value:
    case Some{Value.ObjectValue{properties}}: detailArray(Record.get(Value.Value,properties,name))
    case _: Nil{}
def recordFiles(files: List<&2,String>,ops: Utils.FileOperations,+kind: String) -> Utils.FileOperations:
  match files:
    case Nil{}: ops
    case file <> rest: recordFiles(rest,Utils.recordPath(ops,kind,file),kind)
def detailsOps(-D: Data,-T: Data,entry: Entry(D,T,Value.Value),ops: Utils.FileOperations) -> Utils.FileOperations:
  match entry:
    case Session.BranchSummaryEntry{_,_,_,details,_,Some{True{}}}: ops
    case Session.BranchSummaryEntry{_,_,_,+details,_,_}:
      recordFiles(detailFiles(details,"modifiedFiles"),recordFiles(detailFiles(details,"readFiles"),ops,"read"),"edit")
    case _: ops
def allOps(-D: Data,-T: Data,entries: List<&2,Entry(D,T,Value.Value)>,ops: Utils.FileOperations) -> Utils.FileOperations:
  match entries:
    case Nil{}: ops
    case +entry <> rest:
      allOps(D,T,rest,detailsOps(D,T,entry,Utils.extractFileOpsFromMessages(D,T,Messages.CodingMessage<Value.Value>,content(D,T,Value.Value,entry),ops)))

def isSummary(-D: Data,-T: Data,-C: Data,entry: Entry(D,T,C)) -> Bool:
  match entry:
    case Session.Compaction{_}: True{}
    case Session.BranchSummaryEntry{_,_,_,_,_,_}: True{}
    case _: False{}
def addMessages(-D: Data,-T: Data,-C: Data,messages: List<&2,Message(D,T,C)>,older: List<&2,Message(D,T,C)>) -> List<&2,Message(D,T,C)>:
  List.append(&2,Message(D,T,C),messages,older)
def preparedNewest(-D: Data,-T: Data,-C: Data,entries: List<&2,Entry(D,T,C)>,+budget: F64,+total: F64,+messages: List<&2,Message(D,T,C)>,+ops: Utils.FileOperations) -> Prepared<D,T,C>:
  match entries:
    case Nil{}: Prepared{messages,ops,total}
    case +entry <> rest:
      +next = content(D,T,C,entry)
      +tokens = Compaction.estimateMessagesTokens(D,T,C,next,F.fromU32(0))
      +over = F.isGreater(F.compare(F.add(total,tokens),budget)) && F.isGreater(F.compare(budget,F.fromU32(0)))
      Bool.pick(Unit -> Prepared<D,T,C>,over,
        _ => Bool.pick(Prepared<D,T,C>,isSummary(D,T,C,entry) && F.isGreater(F.compare(F.multiply(budget,F.fromU32(9)),F.multiply(total,F.fromU32(10)))),Prepared{addMessages(D,T,C,next,messages),ops,F.add(total,tokens)},Prepared{messages,ops,total}),
        _ => preparedNewest(D,T,C,rest,budget,F.add(total,tokens),addMessages(D,T,C,next,messages),ops))(Unit{})
def prepare(-D: Data,-T: Data,+entries: List<&2,Entry(D,T,Value.Value)>,budget: F64) -> Prepared<D,T,Value.Value>:
  +ops = allOps(D,T,entries,Utils.createFileOps())
  preparedNewest(D,T,Value.Value,List.reverse(&2,Entry(D,T,Value.Value),entries),budget,F.fromU32(0),Nil{},ops)

def BRANCH_SUMMARY_PREAMBLE() -> String:
  "The user explored a different conversation branch before returning here.\nSummary of that exploration:\n\n"
def BRANCH_SUMMARY_PROMPT() -> String:
  "Create a structured summary of this conversation branch for context when returning later.\n\nUse this EXACT format:\n\n## Goal\n[What was the user trying to accomplish in this branch?]\n\n## Constraints & Preferences\n- [Any constraints, preferences, or requirements mentioned]\n- [Or \"(none)\" if none were mentioned]\n\n## Progress\n### Done\n- [x] [Completed tasks/changes]\n\n### In Progress\n- [ ] [Work that was started but not finished]\n\n### Blocked\n- [Issues preventing progress, if any]\n\n## Key Decisions\n- **[Decision]**: [Brief rationale]\n\n## Next Steps\n1. [What should happen next to continue this work]\n\nKeep each section concise. Preserve exact file paths, function names, and error messages."
def instructions(custom: Maybe<&2,String>,replace: Bool) -> String:
  match custom replace:
    case Some{text} True{}: text
    case Some{text} False{}: BRANCH_SUMMARY_PROMPT() ++ "\n\nAdditional focus: " ++ text
    case None{} _: BRANCH_SUMMARY_PROMPT()
def promptText(-D: Data,-T: Data,-C: Data,messages: List<&2,Message(D,T,C)>,custom: Maybe<&2,String>,replace: Bool) -> String:
  Compaction.conversationBlock(D,T,C,messages) ++ instructions(custom,replace)
def fileValues(files: List<&2,String>) -> List<&2,Value.Value>:
  match files:
    case Nil{}: Nil{}
    case file <> rest: Value.Text{file} <> fileValues(rest)
def detailValue(readFiles: List<&2,String>,modifiedFiles: List<&2,String>) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"readFiles",Value.ArrayValue{fileValues(readFiles)}} <> Record.Property{"modifiedFiles",Value.ArrayValue{fileValues(modifiedFiles)}} <> Nil{}}}
def resultWithFiles(summary: Compaction.Summary,files: Utils.FileLists) -> Summary:
  match summary files:
    case Compaction.Summary{text,usage} Utils.FileLists{+readFiles,+modifiedFiles}:
      Summary{BRANCH_SUMMARY_PREAMBLE() ++ text ++ Utils.formatFileOperations(readFiles,modifiedFiles),Some{usage},detailValue(readFiles,modifiedFiles)}
def result(summary: Compaction.Summary,ops: Utils.FileOperations) -> Summary:
  resultWithFiles(summary,Utils.computeFileLists(ops))
def generatePrepared(~D: Data,~T: Data,summarizer: Compaction.Summarizer(D,T),prepared: Prepared<D,T,Value.Value>,+model: Ai.Model<Ai.JsonValue>,+signal: Abort.AbortSignal<Unit>,custom: Maybe<&2,String>,replace: Bool,retry: Maybe<&2,Retry.RetryPolicy>,callbacks: Maybe<&2,Retry.RetryCallbacks()>) -> IO(Result<&2,&2,String,Summary>):
  match prepared:
    case Prepared{Nil{},ops,_}: IO.pure(Result<&2,&2,String,Summary>,Done{Summary{"No content to summarize",None{},detailValue(Nil{},Nil{})}})
    case Prepared{messages,ops,_}:
      do IO<Result<&2,&2,String,Summary>>:
        produced : Result<&2,&2,String,Compaction.Summary> <- Compaction.summarize(~D,~T,summarizer,promptText(D,T,Value.Value,messages,custom,replace),F.minimum(F.fromU32(4096),Bool.pick(F64,F.isGreater(F.compare(Ai.modelMaxTokens(model),F.fromU32(0))),Ai.modelMaxTokens(model),F.infinity(False{}))),"Branch summarization",Some{signal},retry,callbacks)
        aborted : Bool <- Abort.aborted(Unit,signal)
        return Bool.pick(Result<&2,&2,String,Summary>,aborted,Fail{"Branch summarization aborted"},Result.map(&2,&2,String,Compaction.Summary,Summary,value => result(value,ops),produced))
def generate(~D: Data,~T: Data,summarizer: Compaction.Summarizer(D,T),entries: List<&2,Entry(D,T,Value.Value)>,model: Ai.Model<Ai.JsonValue>,reserveTokens: F64,signal: Abort.AbortSignal<Unit>,custom: Maybe<&2,String>,replace: Bool,retry: Maybe<&2,Retry.RetryPolicy>,callbacks: Maybe<&2,Retry.RetryCallbacks()>) -> IO(Result<&2,&2,String,Summary>):
  generatePrepared(~D,~T,summarizer,prepare(D,T,entries,F.subtract(Ai.modelContextWindow(model),reserveTokens)),model,signal,custom,replace,retry,callbacks)

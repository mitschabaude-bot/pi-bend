import Base
import ./session-context.bend as C
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/messages.bend as M
import ../packages/agent/src/types.bend as A
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/src/number-string.bend as Number
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/test/utf8-runner.bend as W

def State() -> Data: S.SessionManager<Unit,Unit,String>
def StateResult() -> Data: Result<&2,&2,S.Error,State()>
def text(value: String) -> String: C.text(value)
def optional(value: String) -> Maybe<&2,String>: C.optional(value)
def show(value: String) -> String: W.showText(value)
def opt(value: Maybe<&2,String>) -> String: C.maybeText(value)
def stamp(base: S.SessionEntryBase) -> S.EntryStamp:
  match base:
    case S.SessionEntryBase{id,_,timestamp}: S.EntryStamp{id,timestamp}
def readUsage(fields: List<&2,String>) -> Maybe<&2,Ai.Usage>:
  match fields:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> Nil{}: Some{Ai.Usage{Number.toNumber(a),Number.toNumber(b),Number.toNumber(c),Number.toNumber(d),None{},None{},Number.toNumber(e),Ai.UsageCost{Number.toNumber(f),Number.toNumber(g),Number.toNumber(h),Number.toNumber(i),Number.toNumber(j)}}}
    case _: None{}
def readHook(value: String) -> Maybe<&2,Bool>:
  match value:
    case "1": Some{True{}}
    case "0": Some{False{}}
    case _: None{}
def append(state: State(), entry: C.E(), usage: Maybe<&2,Ai.Usage>, hook: Maybe<&2,Bool>, details: Maybe<&2,String>) -> StateResult():
  match entry:
    case S.SessionMessageEntry{base,message}: S.appendMessage(Unit,Unit,String,state,stamp(base),message)
    case S.ThinkingLevelChangeEntry{base,value}: S.appendThinkingLevelChange(Unit,Unit,String,state,stamp(base),value)
    case S.ModelChangeEntry{base,provider,model}: S.appendModelChange(Unit,Unit,String,state,stamp(base),provider,model)
    case S.Compaction{S.CompactionEntry{base,summary,keep,tokens,_,_,_,_}}: S.appendCompaction(Unit,Unit,String,state,stamp(base),summary,Some{keep},tokens,details,hook,usage)
    case S.BranchSummaryEntry{+base,_,summary,_,_,_}: S.branchWithSummary(Unit,Unit,String,state,stamp(base),S.baseParent(base),summary,details,hook,usage)
    case S.CustomEntry{base,kind,data}: S.appendCustomEntry(Unit,Unit,String,state,stamp(base),kind,data)
    case S.CustomMessageEntry{base,kind,content,data,display}: S.appendCustomMessageEntry(Unit,Unit,String,state,stamp(base),kind,content,display,data)
    case S.LabelEntry{base,target,label}: S.appendLabelChange(Unit,Unit,String,state,stamp(base),target,label)
    case S.SessionInfoEntry{base,name}: S.appendSessionInfo(Unit,Unit,String,state,stamp(base),Maybe.default(&2,String,name,""))
    case S.ContextEditEntry{base,target,change}: S.appendContextEdit(Unit,Unit,String,state,stamp(base),target,change)
def appendParsed(state: State(), entry: Maybe<&2,C.E()>, usage: String, hook: String, details: String) -> StateResult():
  match entry:
    case None{}: Fail{S.InvalidMessage{}}
    case Some{entry}: append(state,entry,readUsage(Strings.split(usage,',')),readHook(hook),optional(details))
def names(values: List<&2,String>, reversed: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,reversed)
    case "" <> rest: names(rest,reversed)
    case value <> rest: names(rest,text(value) <> reversed)
def operate(state: State(), fields: List<&2,String>) -> StateResult():
  match fields:
    case "a" <> entry <> usage <> hook <> details <> Nil{}: appendParsed(state,C.entry(Strings.split(entry,':')),usage,hook,details)
    case "b" <> id <> Nil{}: S.branch(Unit,Unit,String,state,text(id))
    case "r" <> Nil{}: Done{S.resetLeaf(Unit,Unit,String,state)}
    case "f" <> leaf <> id <> time <> ids <> Nil{}: S.createBranchedSession(Unit,Unit,String,state,text(leaf),S.EntryStamp{text(id),text(time)},names(Strings.split(ids,'/'),Nil{}))
    case _: Fail{S.InvalidMessage{}}
def usageText(value: Maybe<&2,Ai.Usage>) -> String:
  match value:
    case None{}: "-"
    case Some{Ai.Usage{a,b,c,d,_,_,e,Ai.UsageCost{f,g,h,i,j}}}: String.join([C.number(a),C.number(b),C.number(c),C.number(d),C.number(e),C.number(f),C.number(g),C.number(h),C.number(i),C.number(j)],",")
def hookText(value: Maybe<&2,Bool>) -> String:
  match value:
    case None{}: "-"
    case Some{value}: C.bool(value)
def baseText(base: S.SessionEntryBase) -> String:
  match base:
    case S.SessionEntryBase{id,parent,time}: show(id) ++ ":" ++ opt(parent) ++ ":" ++ show(time)
def systemText(value: Maybe<&2,Ai.SystemMessage<Value.Value>>) -> String:
  match value:
    case None{}: "-"
    case Some{Ai.SystemMessage{Ai.SystemText{content},_,_,_,time}}: show(content) ++ ":" ++ C.number(time)
    case _: "other-system"
def body(entry: C.E()) -> String:
  match entry:
    case S.SessionMessageEntry{_,value}: "msg:" ++ C.message(value)
    case S.ThinkingLevelChangeEntry{_,value}: "thinking:" ++ show(value)
    case S.ModelChangeEntry{_,provider,id}: "model:" ++ show(provider) ++ ":" ++ show(id)
    case S.Compaction{S.CompactionEntry{_,summary,keep,tokens,details,usage,hook,system}}: "compact:" ++ show(summary) ++ ":" ++ show(keep) ++ ":" ++ Nat.show(tokens) ++ ":" ++ opt(details) ++ ":" ++ usageText(usage) ++ ":" ++ hookText(hook) ++ ":" ++ systemText(system)
    case S.BranchSummaryEntry{_,from,summary,details,usage,hook}: "summary:" ++ show(from) ++ ":" ++ show(summary) ++ ":" ++ opt(details) ++ ":" ++ usageText(usage) ++ ":" ++ hookText(hook)
    case S.CustomEntry{_,kind,data}: "custom:" ++ show(kind) ++ ":" ++ opt(data)
    case S.CustomMessageEntry{_,kind,Ai.UserText{content},details,display}: "visible:" ++ show(kind) ++ ":" ++ show(content) ++ ":" ++ opt(details) ++ ":" ++ C.bool(display)
    case S.CustomMessageEntry{_,_,_,_,_}: "blocks"
    case S.LabelEntry{_,target,label}: "label:" ++ show(target) ++ ":" ++ opt(label)
    case S.SessionInfoEntry{_,name}: "info:" ++ opt(name)
    case S.ContextEditEntry{_,target,None{}}: "edit:" ++ show(target) ++ ":omit"
    case S.ContextEditEntry{_,target,Some{_}}: "edit:" ++ show(target) ++ ":replace"
def entriesText(entries: List<&2,C.E()>, reversed: List<&2,String>) -> String:
  match entries:
    case Nil{}: String.join(List.reverse(&2,String,reversed),";")
    case +entry <> rest: entriesText(rest,(baseText(S.entryBase(Unit,Unit,String,entry)) ++ ":" ++ body(entry)) <> reversed)
type Visit is Data: Visit{depth: Nat, nodes: List<&2,S.SessionTreeNode<Unit,Unit,String>>}
def treeText(fuel: Nat, pending: List<&2,Visit>, reversed: List<&2,String>) -> String:
  match fuel pending:
    case _ Nil{}: String.join(List.reverse(&2,String,reversed),";")
    case 1n+fuel Visit{_,Nil{}} <> rest: treeText(fuel,rest,reversed)
    case 1n+fuel Visit{+depth,S.SessionTreeNode{entry,children,label,time} <> siblings} <> rest:
      treeText(fuel,Visit{depth + 1n,children} <> Visit{depth,siblings} <> rest,(Nat.show(depth) ++ ":" ++ show(S.entryId(Unit,Unit,String,entry)) ++ ":" ++ opt(label) ++ ":" ++ opt(time)) <> reversed)
    case 0n _: "tree-too-large"
def treeResult(value: Result<&2,&2,S.Error,List<&2,S.SessionTreeNode<Unit,Unit,String>>>) -> String:
  match value:
    case Fail{cause}: C.error(cause)
    case Done{nodes}: treeText(100000n,[Visit{0n,nodes}],Nil{})
def pathResult(value: Result<&2,&2,S.Error,List<&2,C.E()>>) -> String:
  match value:
    case Fail{cause}: C.error(cause)
    case Done{entries}: C.ids(entries,Nil{})
def queries(+state: State(), entries: List<&2,C.E()>, reversed: List<&2,String>) -> String:
  match entries:
    case Nil{}: String.join(List.reverse(&2,String,reversed),"!")
    case entry <> rest:
      +id = S.entryId(Unit,Unit,String,entry)
      queries(state,rest,(show(id) ++ "=" ++ C.ids(S.getChildren(Unit,Unit,String,state,id),Nil{}) ++ "=" ++ pathResult(S.getBranch(Unit,Unit,String,state,S.Leaf{id}))) <> reversed)
def snapshot(+state: State(), status: String) -> String:
  status ++ "|" ++ opt(S.getLeafId(Unit,Unit,String,state)) ++ "|" ++ opt(S.getSessionName(Unit,Unit,String,state)) ++ "|" ++ entriesText(S.getEntries(Unit,Unit,String,state),Nil{}) ++ "|" ++ pathResult(S.getBranch(Unit,Unit,String,state,S.Latest{})) ++ "|" ++ treeResult(S.getTree(Unit,Unit,String,state)) ++ "|" ++ queries(state,S.getEntries(Unit,Unit,String,state),Nil{}) ++ "|" ++ C.context(S.sessionContext(Unit,Unit,String,state))
def report(+previous: State(), result: StateResult()) -> IO(State()):
  match result:
    case Done{+state}:
      do IO<State()>:
        IO.print(snapshot(state,"ok"))
        return state
    case Fail{cause}:
      do IO<State()>:
        IO.print(snapshot(previous,"error:" ++ C.error(cause)))
        return previous
def steps(operations: List<&2,String>, +state: State()) -> IO(Unit):
  match operations:
    case Nil{}: IO.pure(Unit,Unit{})
    case operation <> rest:
      do IO<Unit>:
        state : State() <- report(state,operate(state,Strings.split(operation,'@')))
        steps(rest,state)
def requireState(result: StateResult()) -> IO(State()):
  match result:
    case Fail{cause}: IO.die(State(),1,C.error(cause))
    case Done{state}: IO.pure(State(),state)
def initial(fields: List<&2,String>, operations: List<&2,String>) -> IO(Unit):
  match fields:
    case id <> time <> cwd <> Nil{}:
      do IO<Unit>:
        state : State() <- requireState(S.inMemory(Unit,Unit,String,S.SessionHeader{Some{3n},text(id),text(time),text(cwd),None{}}))
        steps(operations,state)
    case _: IO.die(Unit,1,"bad header")
def largeBuild(count: Nat, +wide: Bool, state: StateResult()) -> StateResult():
  match count state:
    case _ Fail{cause}: Fail{cause}
    case 0n Done{state}: Done{state}
    case 1n+(+count) Done{+state}:
      selected = Bool.pick(StateResult(),wide,S.branch(Unit,Unit,String,state,"root"),Done{state})
      largeBuild(count,wide,Result.bind(&2,&2,S.Error,State(),State(),selected,next => S.appendCustomEntry(Unit,Unit,String,next,S.EntryStamp{Nat.show(count + 1n),"2025-01-01T00:00:00Z"},"node",None{})))
def wideNodes(values: List<&2,S.SessionTreeNode<Unit,Unit,String>>, expected: Nat, valid: Bool) -> Bool:
  match values expected:
    case Nil{} 0n: valid
    case S.SessionTreeNode{entry,Nil{},None{},None{}} <> rest 1n+(+expected): wideNodes(rest,expected,valid && Strings.equal(S.entryId(Unit,Unit,String,entry),Nat.show(expected + 1n)))
    case _ _: False{}
def deepNodes(fuel: Nat, values: List<&2,S.SessionTreeNode<Unit,Unit,String>>, expected: Nat, valid: Bool) -> Bool:
  match fuel values expected:
    case _ Nil{} 0n: valid
    case 1n+fuel S.SessionTreeNode{entry,children,None{},None{}} <> Nil{} 1n+(+expected): deepNodes(fuel,children,expected,valid && Strings.equal(S.entryId(Unit,Unit,String,entry),Nat.show(expected + 1n)))
    case _ _ _: False{}
def largeTree(wide: Bool, result: Result<&2,&2,S.Error,List<&2,S.SessionTreeNode<Unit,Unit,String>>>) -> Bool:
  match result:
    case Done{S.SessionTreeNode{_,+children,None{},None{}} <> Nil{}}: Bool.pick(Bool,wide,wideNodes(children,10000n,True{}),deepNodes(10001n,children,10000n,True{}))
    case _: False{}
def largeCheck(+wide: Bool, result: StateResult()) -> String:
  match result:
    case Fail{cause}: C.error(cause)
    case Done{+state}:
      valid = largeTree(wide,S.getTree(Unit,Unit,String,state))
      Bool.pick(String,valid,"large-ok","large-failed")
def large(+wide: Bool) -> String:
  start = S.inMemory(Unit,Unit,String,S.SessionHeader{Some{3n},"large","2025-01-01T00:00:00Z","/work",None{}})
  root = Result.bind(&2,&2,S.Error,State(),State(),start,state => S.appendCustomEntry(Unit,Unit,String,state,S.EntryStamp{"root","2025-01-01T00:00:00Z"},"root",None{}))
  largeCheck(wide,largeBuild(10000n,wide,root))

def run(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case "wide" <> Nil{}: IO.print(large(True{}))
    case "deep" <> Nil{}: IO.print(large(False{}))
    case header <> operations: initial(Strings.split(header,':'),operations)
    case _: IO.die(Unit,1,"bad command")
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

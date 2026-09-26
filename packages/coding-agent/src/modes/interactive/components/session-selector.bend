import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../agent/src/types.bend as Agent
import ../../../../../ai/src/types.bend as Ai
import ../../../../../runtime/src/text.bend as Text
import ../../../../../runtime/src/case-map.bend as CaseMap
import ../../../../../runtime/src/schema-value.bend as V
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/utils.bend as Utils
import ../../../core/agent-session.bend as Session
import ../../../core/session-manager.bend as Tree
import ../../../core/tools/index.bend as Tools
import ../theme/theme.bend as Theme
import ./user-message-selector.bend as UserPicker

# The selector keeps the session graph, rather than flattening it to an
# unrelated menu. Its visible rows retain branch connectors and the active
# path; the filter changes which entries are visible, not their IDs.
def Entry() -> Data: Tree.SessionEntry<Unit,Tools.ToolDetails,V.Value>
def Node() -> Data: Tree.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>

type Mode is Data: TreeMode{} ForkMode{}
type Filter is Data: Default{} NoTools{} UserOnly{} LabeledOnly{} All{}
type Action is Data: Continue{} Cancel{} Chosen{id: String}
type Row is Data:
  Row{id: String,parent: Maybe<&2,String>,label: Maybe<&2,String>,text: String,prefix: String,connector: String,active: Bool,user: Bool,tool: Bool,bookkeeping: Bool,usage: Bool}
type State is Data:
  State{all: List<&2,Row>,visible: List<&2,Row>,selected: Nat,filter: Filter,search: String,leaf: Maybe<&2,String>,folded: List<&2,String>,height: Nat}

def contentText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{blocks}: Session.blockText(blocks)
def messageText(message: Session.Message()) -> String:
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{content,_}}}: "user: " ++ contentText(content)
    case Agent.LlmMessage{Ai.Assistant{assistant}}: "assistant: " ++ Session.assistantTextOf(assistant)
    case Agent.LlmMessage{Ai.ToolResult{_}}: "[tool result]"
    case _: "[message]"
def entryText(entry: Entry()) -> String:
  match entry:
    case Tree.SessionMessageEntry{_,message}: messageText(message)
    case Tree.CustomMessageEntry{_,_,content,_,_}: "custom: " ++ contentText(content)
    case Tree.Compaction{_}: "[compaction]"
    case Tree.BranchSummaryEntry{_,_,summary,_,_,_}: "[branch summary] " ++ summary
    case Tree.ModelChangeEntry{_,provider,id}: "[model: " ++ provider ++ "/" ++ id ++ "]"
    case Tree.UsageEntry{_,kind,_,_,_,_}: "[usage: " ++ kind ++ "]"
    case Tree.ThinkingLevelChangeEntry{_,level}: "[thinking: " ++ level ++ "]"
    case Tree.SessionInfoEntry{_,name}: "[session: " ++ Maybe.default(&2,String,name,"") ++ "]"
    case Tree.LabelEntry{_,_,_}: "[label]"
    case Tree.ContextEditEntry{_,_,_}: "[context edit]"
    case Tree.CustomEntry{_,kind,_}: "[" ++ kind ++ "]"
def isUser(entry: Entry()) -> Bool:
  match entry:
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.User{_}}}: True{}
    case _: False{}
def isTool(entry: Entry()) -> Bool:
  match entry:
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.ToolResult{_}}}: True{}
    case _: False{}
def isBookkeeping(entry: Entry()) -> Bool:
  match entry:
    case Tree.ModelChangeEntry{_,_,_}: True{}
    case Tree.ThinkingLevelChangeEntry{_,_}: True{}
    case Tree.SessionInfoEntry{_,_}: True{}
    case Tree.LabelEntry{_,_,_}: True{}
    case Tree.ContextEditEntry{_,_,_}: True{}
    case Tree.CustomEntry{_,_,_}: True{}
    case _: False{}
# Usage entries (cache refreshes) are hidden from the tree in every filter
# mode, as upstream's TreeList.
def isUsage(entry: Entry()) -> Bool:
  match entry:
    case Tree.UsageEntry{_,_,_,_,_,_}: True{}
    case _: False{}
def rowOf(node: Node(),prefix: String,connector: String,active: Bool) -> Row:
  match node:
    case Tree.SessionTreeNode{+entry,_,label,_}:
      +base = Tree.entryBase(Unit,Tools.ToolDetails,V.Value,entry)
      Row{Tree.baseId(base),Tree.baseParent(base),label,entryText(entry),prefix,connector,active,isUser(entry),isTool(entry),isBookkeeping(entry),isUsage(entry)}

@unsafe def containsWork(nodes: List<&2,Node()>,+leaf: Maybe<&2,String>) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Tree.SessionTreeNode{entry,children,_,_} <> rest:
      +id = Tree.baseId(Tree.entryBase(Unit,Tools.ToolDetails,V.Value,entry))
      Bool.pick(Bool,Maybe.default(&2,Bool,Maybe.map(&2,String,Bool,other => String.eq(other,id),leaf),False{}),True{},containsWork(List.append(&2,Node(),children,rest),leaf))
def contains(node: Node(),leaf: Maybe<&2,String>) -> Bool: containsWork(node <> Nil{},leaf)
def nodeFrom(entry: Entry(),children: List<&2,Node()>,label: Maybe<&2,String>,stamp: Maybe<&2,String>) -> Node():
  Tree.SessionTreeNode{entry,children,label,stamp}

def selectedFirst(nodes: List<&2,Node()>,+leaf: Maybe<&2,String>,+active: List<&2,Node()>,+other: List<&2,Node()>) -> List<&2,Node()>:
  match nodes:
    case Nil{}: List.append(&2,Node(),List.reverse(&2,Node(),active),List.reverse(&2,Node(),other))
    case +node <> +rest:
      Bool.pick(Unit -> List<&2,Node()>,contains(node,leaf),
        _ => selectedFirst(rest,leaf,node <> active,other),
        _ => selectedFirst(rest,leaf,active,node <> other))(Unit{})

@unsafe def flattenNodes(nodes: List<&2,Node()>,+leaf: Maybe<&2,String>,+prefix: String,+branch: Bool,+reversed: List<&2,Row>) -> List<&2,Row>:
  match nodes:
    case Nil{}: reversed
    case Tree.SessionTreeNode{entry,+children,label,stamp} <> +rest:
      +last = List.is_empty(&2,Node(),rest)
      +connector = Bool.pick(String,branch,Bool.pick(String,last,"└─ ","├─ "),"")
      +continuation = Bool.pick(String,branch,Bool.pick(String,last,"   ","│  "),"")
      +copied = nodeFrom(entry,children,label,stamp)
      +row = rowOf(copied,prefix,connector,contains(copied,leaf))
      +ordered = selectedFirst(children,leaf,Nil{},Nil{})
      +descended = flattenNodes(ordered,leaf,prefix ++ continuation,List.length(&2,Node(),ordered) > 1n,row <> reversed)
      flattenNodes(rest,leaf,prefix,branch,descended)
def allRows(nodes: List<&2,Node()>,+leaf: Maybe<&2,String>) -> List<&2,Row>:
  +ordered = selectedFirst(nodes,leaf,Nil{},Nil{})
  List.reverse(&2,Row,flattenNodes(ordered,leaf,"",List.length(&2,Node(),ordered) > 1n,Nil{}))

def spaceSeparated(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+code},rest}:
      spaceSeparated(rest,SCon{Bool.pick(Char,Text.whitespace(code),' ',Chr{code}),reversed})
def everyToken(tokens: List<&2,String>,+haystack: String) -> Bool:
  match tokens:
    case Nil{}: True{}
    case +token <> rest:
      String.is_empty(token) || (String.contains(haystack,token) && everyToken(rest,haystack))
def matchesSearch(text: String,label: Maybe<&2,String>,search: String) -> Bool:
  +haystack = CaseMap.lower(text ++ " " ++ Maybe.default(&2,String,label,""))
  everyToken(String.split(CaseMap.lower(spaceSeparated(search,"")),' '),haystack)
def shown(row: Row,filter: Filter,search: String) -> Bool:
  match row filter:
    case Row{_,_,label,text,_,_,_,user,tool,bookkeeping,_} Default{}: Bool.not(bookkeeping) && matchesSearch(text,label,search)
    case Row{_,_,label,text,_,_,_,user,tool,bookkeeping,_} NoTools{}: Bool.not(bookkeeping || tool) && matchesSearch(text,label,search)
    case Row{_,_,label,text,_,_,_,user,tool,bookkeeping,_} UserOnly{}: user && matchesSearch(text,label,search)
    case Row{_,_,Some{label},text,_,_,_,_,_,_,_} LabeledOnly{}: matchesSearch(text,Some{label},search)
    case _ LabeledOnly{}: False{}
    case Row{_,_,label,text,_,_,_,_,_,_,_} All{}: matchesSearch(text,label,search)
def usageRow(row: Row) -> Bool:
  match row: case Row{_,_,_,_,_,_,_,_,_,_,usage}: usage
def passes(+row: Row,filter: Filter,search: String) -> Bool:
  Bool.not(usageRow(row)) && shown(row,filter,search)
def filtered(rows: List<&2,Row>,+filter: Filter,+search: String) -> List<&2,Row>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +tail = filtered(rest,filter,search)
      Bool.pick(List<&2,Row>,passes(row,filter,search),row <> tail,tail)
def indexOf(rows: List<&2,Row>,+id: String,+index: Nat) -> Maybe<&2,Nat>:
  match rows:
    case Nil{}: None{}
    case Row{found,_,_,_,_,_,_,_,_,_,_} <> rest: Bool.pick(Maybe<&2,Nat>,String.eq(found,id),Some{index},indexOf(rest,id,index + 1n))
def rowId(row: Row) -> String:
  match row: case Row{id,_,_,_,_,_,_,_,_,_,_}: id
def rowParent(row: Row) -> Maybe<&2,String>:
  match row: case Row{_,parent,_,_,_,_,_,_,_,_,_}: parent
def parentOf(rows: List<&2,Row>,+id: String) -> Maybe<&2,String>:
  match rows:
    case Nil{}: None{}
    case +row <> rest:
      Bool.pick(Maybe<&2,String>,String.eq(rowId(row),id),rowParent(row),parentOf(rest,id))
@unsafe def initialNear(+all: List<&2,Row>,+visible: List<&2,Row>,leaf: Maybe<&2,String>,fuel: Nat) -> Nat:
  match leaf fuel:
    case None{} _: List.length(&2,Row,visible) - 1n
    case _ Zero{}: List.length(&2,Row,visible) - 1n
    case Some{+id} Succ{remaining}:
      +found = indexOf(visible,id,0n)
      Bool.pick(Unit -> Nat,Maybe.is_some(&2,Nat,found),_ => Maybe.default(&2,Nat,found,0n),_ => initialNear(all,visible,parentOf(all,id),remaining))(Unit{})
def createWithFilter(nodes: List<&2,Node()>,+leaf: Maybe<&2,String>,height: Nat,+filter: Filter) -> State:
  +all = allRows(nodes,leaf)
  +visible = filtered(all,filter,"")
  State{all,visible,initialNear(all,visible,leaf,List.length(&2,Row,all)),filter,"",leaf,Nil{},Nat.max(5n,height / 2n)}
def create(nodes: List<&2,Node()>,leaf: Maybe<&2,String>,height: Nat) -> State:
  createWithFilter(nodes,leaf,height,Default{})

def hasRows(state: State) -> Bool:
  match state: case State{_,visible,_,_,_,_,_,_}: Bool.not(List.is_empty(&2,Row,visible))
def at(rows: List<&2,Row>,index: Nat) -> Maybe<&2,Row>:
  match rows index:
    case row <> _ Zero{}: Some{row}
    case _ <> rest Succ{remaining}: at(rest,remaining)
    case Nil{} _: None{}
def selectedRow(state: State) -> Maybe<&2,Row>:
  match state: case State{_,visible,index,_,_,_,_,_}: at(visible,index)
def selectedId(state: State) -> Maybe<&2,String>:
  Maybe.map(&2,Row,String,row => rowId(row),selectedRow(state))
def containsId(ids: List<&2,String>,+id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case head <> rest: String.eq(head,id) || containsId(rest,id)
@unsafe def hiddenBy(+rows: List<&2,Row>,+folded: List<&2,String>,parent: Maybe<&2,String>,fuel: Nat) -> Bool:
  match parent fuel:
    case None{} _: False{}
    case _ Zero{}: False{}
    case Some{+id} Succ{remaining}:
      Bool.pick(Unit -> Bool,containsId(folded,id),_ => True{},_ => hiddenBy(rows,folded,parentOf(rows,id),remaining))(Unit{})
def filterVisible(+all: List<&2,Row>,rows: List<&2,Row>,+filter: Filter,+search: String,+folded: List<&2,String>) -> List<&2,Row>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +tail = filterVisible(all,rest,filter,search,folded)
      Bool.pick(List<&2,Row>,passes(row,filter,search) && Bool.not(hiddenBy(all,folded,rowParent(row),List.length(&2,Row,all))),row <> tail,tail)
@unsafe def nearest(+rows: List<&2,Row>,+visible: List<&2,Row>,id: Maybe<&2,String>,fuel: Nat) -> Nat:
  match id fuel:
    case None{} _: List.length(&2,Row,visible) - 1n
    case _ Zero{}: List.length(&2,Row,visible) - 1n
    case Some{+value} Succ{remaining}:
      +found = indexOf(visible,value,0n)
      Bool.pick(Unit -> Nat,Maybe.is_some(&2,Nat,found),_ => Maybe.default(&2,Nat,found,0n),_ => nearest(rows,visible,parentOf(rows,value),remaining))(Unit{})
def refresh(state: State,+filter: Filter,+search: String,+folded: List<&2,String>) -> State:
  match state:
    case State{+all,+previous,index,_,_,+leaf,_,height}:
      +selected = Maybe.map(&2,Row,String,row => rowId(row),at(previous,index))
      +visible = filterVisible(all,all,filter,search,folded)
      State{all,visible,nearest(all,visible,selected,List.length(&2,Row,all)),filter,search,leaf,folded,height}
def move(state: State,up: Bool) -> State:
  match state:
    case State{all,+visible,+index,filter,search,leaf,folded,height}:
      +count = List.length(&2,Row,visible)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      State{all,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),filter,search,leaf,folded,height}
def page(state: State,up: Bool) -> State:
  match state:
    case State{all,+visible,+index,filter,search,leaf,folded,+height}:
      +count = List.length(&2,Row,visible)
      +next = Bool.pick(Nat,up,index - height,Nat.min(count - 1n,index + height))
      State{all,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),filter,search,leaf,folded,height}
def filterOf(state: State) -> Filter:
  match state: case State{_,_,_,filter,_,_,_,_}: filter
def searchOf(state: State) -> String:
  match state: case State{_,_,_,_,search,_,_,_}: search
def foldedOf(state: State) -> List<&2,String>:
  match state: case State{_,_,_,_,_,_,folded,_}: folded
def equalFilter(left: Filter,right: Filter) -> Bool:
  match left right:
    case Default{} Default{}: True{}
    case NoTools{} NoTools{}: True{}
    case UserOnly{} UserOnly{}: True{}
    case LabeledOnly{} LabeledOnly{}: True{}
    case All{} All{}: True{}
    case _ _: False{}
def toggled(current: Filter,+wanted: Filter) -> Filter:
  Bool.pick(Filter,equalFilter(current,wanted),Default{},wanted)
def nextFilter(filter: Filter) -> Filter:
  match filter:
    case Default{}: NoTools{}
    case NoTools{}: UserOnly{}
    case UserOnly{}: LabeledOnly{}
    case LabeledOnly{}: All{}
    case All{}: Default{}
def previousFilter(filter: Filter) -> Filter:
  match filter:
    case Default{}: All{}
    case NoTools{}: Default{}
    case UserOnly{}: NoTools{}
    case LabeledOnly{}: UserOnly{}
    case All{}: LabeledOnly{}
def withFilter(+state: State,+wanted: Filter,toggle: Bool) -> State:
  +next = Bool.pick(Filter,toggle,toggled(filterOf(state),wanted),wanted)
  refresh(state,next,searchOf(state),Nil{})
def withSearch(+state: State,search: String) -> State:
  refresh(state,filterOf(state),search,Nil{})
def clearSearch(+state: State) -> State: withSearch(state,"")
def reversedWithoutFirst(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{_,rest}: String.reverse(rest)
def withoutLast(text: String) -> String: reversedWithoutFirst(String.reverse(text))
def printableTail(data: String) -> Bool:
  match data:
    case SNil{}: True{}
    case SCon{Chr{+code},rest}: U32.is_ge(code,32) && Bool.not(U32.is_eq(code,127)) && Bool.not(U32.is_ge(code,128) && U32.is_le(code,159)) && printableTail(rest)
def printable(data: String) -> Bool:
  match data:
    case SNil{}: False{}
    case SCon{Chr{+code},rest}: U32.is_ge(code,32) && Bool.not(U32.is_eq(code,127)) && Bool.not(U32.is_ge(code,128) && U32.is_le(code,159)) && printableTail(rest)
def foldedNext(folded: List<&2,String>,+id: String,+fold: Bool) -> List<&2,String>:
  match folded:
    case Nil{}: Bool.pick(List<&2,String>,fold,id <> Nil{},Nil{})
    case +head <> +rest:
      Bool.pick(Unit -> List<&2,String>,String.eq(head,id),_ => Bool.pick(List<&2,String>,fold,head <> rest,rest),_ => head <> foldedNext(rest,id,fold))(Unit{})
def sameParent(parent: Maybe<&2,String>,id: String) -> Bool:
  match parent:
    case Some{value}: String.eq(value,id)
    case None{}: False{}
@unsafe def visibleParent(+all: List<&2,Row>,+visible: List<&2,Row>,parent: Maybe<&2,String>,fuel: Nat) -> Maybe<&2,String>:
  match parent fuel:
    case None{} _: None{}
    case _ Zero{}: None{}
    case Some{+id} Succ{remaining}:
      Bool.pick(Unit -> Maybe<&2,String>,Maybe.is_some(&2,Nat,indexOf(visible,id,0n)),_ => Some{id},_ => visibleParent(all,visible,parentOf(all,id),remaining))(Unit{})
def visibleParentOf(+all: List<&2,Row>,visible: List<&2,Row>,id: String) -> Maybe<&2,String>:
  visibleParent(all,visible,parentOf(all,id),List.length(&2,Row,all))
def childCountIn(+all: List<&2,Row>,+visible: List<&2,Row>,remaining: List<&2,Row>,+parent: String) -> Nat:
  match remaining:
    case Nil{}: 0n
    case row <> rest: Bool.pick(Nat,sameParent(visibleParentOf(all,visible,rowId(row)),parent),1n,0n) + childCountIn(all,visible,rest,parent)
def childCount(+all: List<&2,Row>,+visible: List<&2,Row>,+parent: String) -> Nat:
  childCountIn(all,visible,visible,parent)
def firstChildIn(+all: List<&2,Row>,+visible: List<&2,Row>,remaining: List<&2,Row>,+parent: String) -> Maybe<&2,String>:
  match remaining:
    case Nil{}: None{}
    case +row <> rest:
      Bool.pick(Unit -> Maybe<&2,String>,sameParent(visibleParentOf(all,visible,rowId(row)),parent),_ => Some{rowId(row)},_ => firstChildIn(all,visible,rest,parent))(Unit{})
def firstChild(+all: List<&2,Row>,+visible: List<&2,Row>,+parent: String) -> Maybe<&2,String>:
  firstChildIn(all,visible,visible,parent)
def selectedIndex(rows: List<&2,Row>,id: String,fallback: Nat) -> Nat:
  Maybe.default(&2,Nat,indexOf(rows,id,0n),fallback)
@unsafe def segmentUp(+all: List<&2,Row>,+rows: List<&2,Row>,+id: String,+original: Nat,fuel: Nat) -> Nat:
  match fuel:
    case Zero{}: selectedIndex(rows,id,original)
    case Succ{remaining}:
      +parent = visibleParentOf(all,rows,id)
      +current = selectedIndex(rows,id,original)
      +ancestor = Maybe.default(&2,String,parent,"")
      Bool.pick(Unit -> Nat,Maybe.is_none(&2,String,parent),_ => current,
        _ => Bool.pick(Unit -> Nat,Nat.is_gt(childCount(all,rows,ancestor),1n) && Nat.is_lt(current,original),_ => current,_ => segmentUp(all,rows,ancestor,original,remaining))(Unit{}))(Unit{})
@unsafe def segmentDown(+all: List<&2,Row>,+rows: List<&2,Row>,+id: String,fuel: Nat) -> Nat:
  match fuel:
    case Zero{}: selectedIndex(rows,id,0n)
    case Succ{remaining}:
      +child = firstChild(all,rows,id)
      +next = Maybe.default(&2,String,child,"")
      Bool.pick(Unit -> Nat,Maybe.is_none(&2,String,child),_ => selectedIndex(rows,id,0n),
        _ => Bool.pick(Unit -> Nat,Nat.is_gt(childCount(all,rows,id),1n),_ => selectedIndex(rows,next,0n),_ => segmentDown(all,rows,next,remaining))(Unit{}))(Unit{})
def foldable(+all: List<&2,Row>,+rows: List<&2,Row>,id: String,+parent: Maybe<&2,String>) -> Bool:
  Nat.is_gt(childCount(all,rows,id),0n) && Bool.pick(Bool,Maybe.is_none(&2,String,parent),True{},Nat.is_gt(childCount(all,rows,Maybe.default(&2,String,parent,"")),1n))
def setIndex(state: State,index: Nat) -> State:
  match state:
    case State{all,visible,_,filter,search,leaf,folded,height}: State{all,visible,index,filter,search,leaf,folded,height}
def visibleOf(state: State) -> List<&2,Row>:
  match state: case State{_,visible,_,_,_,_,_,_}: visible
def allOf(state: State) -> List<&2,Row>:
  match state: case State{all,_,_,_,_,_,_,_}: all
def indexOfState(state: State) -> Nat:
  match state: case State{_,_,index,_,_,_,_,_}: index
def selectedFold(+state: State,+row: Row,collapse: Bool) -> State:
  +visible = visibleOf(state)
  +all = allOf(state)
  +index = indexOfState(state)
  +filter = filterOf(state)
  +search = searchOf(state)
  +folded = foldedOf(state)
  +id = rowId(row)
  +parent = visibleParentOf(all,visible,id)
  Bool.pick(Unit -> State,collapse,
    _ => Bool.pick(Unit -> State,foldable(all,visible,id,parent) && Bool.not(containsId(folded,id)),_ => refresh(state,filter,search,foldedNext(folded,id,True{})),_ => setIndex(state,segmentUp(all,visible,id,index,List.length(&2,Row,visible))))(Unit{}),
    _ => Bool.pick(Unit -> State,containsId(folded,id),_ => refresh(state,filter,search,foldedNext(folded,id,False{})),_ => setIndex(state,segmentDown(all,visible,id,List.length(&2,Row,visible))))(Unit{}))(Unit{})
def foldFound(state: State,selected: Maybe<&2,Row>,collapse: Bool) -> State:
  match selected:
    case None{}: state
    case Some{row}: selectedFold(state,row,collapse)
def fold(+state: State,collapse: Bool) -> State:
  foldFound(state,selectedRow(state),collapse)
def controlInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.default"),_ => (withFilter(state,Default{},False{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.noTools"),_ => (withFilter(state,NoTools{},True{}),Continue{}),
      _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.userOnly"),_ => (withFilter(state,UserOnly{},True{}),Continue{}),
        _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.labeledOnly"),_ => (withFilter(state,LabeledOnly{},True{}),Continue{}),
          _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.all"),_ => (withFilter(state,All{},True{}),Continue{}),
            _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.cycleForward"),_ => (withFilter(state,nextFilter(filterOf(state)),False{}),Continue{}),
              _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.cycleBackward"),_ => (withFilter(state,previousFilter(filterOf(state)),False{}),Continue{}),
                _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.editor.deleteCharBackward"),_ => (withSearch(state,withoutLast(searchOf(state))),Continue{}),
                  _ => Bool.pick(Unit -> State & Action,printable(data),_ => (withSearch(state,searchOf(state) ++ data),Continue{}),_ => (state,Continue{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def confirmInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => (state,Maybe.default(&2,Action,Maybe.map(&2,String,Action,id => Chosen{id},selectedId(state)),Continue{})),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => Bool.pick(State & Action,String.is_empty(searchOf(state)),(state,Cancel{}),(clearSearch(state),Continue{})),_ => controlInput(state,bindings,keyboard,data))(Unit{}))(Unit{})
def pageInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.pageUp") || Bindings.matches(bindings,keyboard,data,"tui.editor.cursorLeft"),_ => (page(state,True{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.pageDown") || Bindings.matches(bindings,keyboard,data,"tui.editor.cursorRight"),_ => (page(state,False{}),Continue{}),_ => confirmInput(state,bindings,keyboard,data))(Unit{}))(Unit{})
def foldInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.foldOrUp"),_ => (fold(state,True{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.unfoldOrDown"),_ => (fold(state,False{}),Continue{}),_ => pageInput(state,bindings,keyboard,data))(Unit{}))(Unit{})
def input(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => (move(state,True{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => (move(state,False{}),Continue{}),_ => foldInput(state,bindings,keyboard,data))(Unit{}))(Unit{})

def paint(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,value),value)
def shade(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.background(theme,key,value),value)
def flattenText(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: Text.trim(String.reverse(reversed))
    case SCon{+char,rest}: flattenText(rest,Bool.pick(String,Char.is_eq(char,'\n') || Char.is_eq(char,'\t'),SCon{' ',reversed},SCon{char,reversed}))
def singleLine(text: String) -> String: flattenText(text,"")
def filterStatus(filter: Filter) -> String:
  match filter:
    case Default{}: ""
    case NoTools{}: " [no-tools]"
    case UserOnly{}: " [user]"
    case LabeledOnly{}: " [labeled]"
    case All{}: " [all]"
def line(row: Row,+selected: Bool,folded: List<&2,String>,+theme: Theme.Theme,width: Nat) -> String:
  match row:
    case Row{+id,_,label,text,prefix,connector,active,user,_,_,_}:
      +gutter = Bool.pick(String,selected,paint(theme,"accent","› "),"  ")
      +foldMarker = Bool.pick(String,containsId(folded,id),paint(theme,"accent","⊞ "),"")
      +path = Bool.pick(String,active,paint(theme,"accent","• "),"")
      +name = Maybe.default(&2,String,Maybe.map(&2,String,String,value => paint(theme,"warning","[" ++ value ++ "] "),label),"")
      +role = Bool.pick(String,user,"accent","success")
      +raw = gutter ++ paint(theme,"dim",prefix ++ connector) ++ foldMarker ++ path ++ name ++ paint(theme,role,singleLine(text))
      +styled = Bool.pick(String,selected,shade(theme,"selectedBg",raw),raw)
      Utils.truncateToWidth(styled,width,"",False{})
def visibleLines(rows: List<&2,Row>,+start: Nat,+count: Nat,+index: Nat,+selected: Nat,+folded: List<&2,String>,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match rows:
    case Nil{}: Nil{}
    case row <> +rest:
      Bool.pick(Unit -> List<&2,String>,Nat.is_ge(index,start + count),_ => Nil{},
        _ => Bool.pick(Unit -> List<&2,String>,Nat.is_lt(index,start),
          _ => visibleLines(rest,start,count,index + 1n,selected,folded,theme,width),
          _ => line(row,Nat.is_eq(index,selected),folded,theme,width) <> visibleLines(rest,start,count,index + 1n,selected,folded,theme,width))(Unit{}))(Unit{})
def rowsOrEmpty(+visible: List<&2,Row>,start: Nat,height: Nat,index: Nat,folded: List<&2,String>,+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  Bool.pick(List<&2,String>,List.is_empty(&2,Row,visible),paint(theme,"muted","  No entries found") <> Nil{},visibleLines(visible,start,height,0n,index,folded,theme,width))
def render(state: State,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match state:
    case State{_,+visible,+index,filter,+search,_,folded,+height}:
      +count = List.length(&2,Row,visible)
      +start = Nat.min(index - height / 2n,count - Nat.min(count,height))
      +position = Bool.pick(Nat,Nat.is_eq(count,0n),0n,index + 1n)
      "" <> paint(theme,"accent","  Session Tree") <> paint(theme,"muted","  ↑/↓ select · PgUp/PgDn page · Ctrl+←/→ fold · Ctrl+O filter · Enter select · Esc cancel") <> (paint(theme,"muted","  Type to search:") ++ Bool.pick(String,String.is_empty(search),""," " ++ paint(theme,"accent",search))) <> paint(theme,"dim",Utils.spaces(width,"")) <> List.append(&2,String,rowsOrEmpty(visible,start,height,index,folded,theme,width),paint(theme,"muted","  (" ++ Nat.show(position) ++ "/" ++ Nat.show(count) ++ ")" ++ filterStatus(filter)) <> Nil{})

# A selector temporarily occupies the editor's stable component ID. The live
# editor remains mounted and resumes its own input and focus on dismissal.

type Modal is Data: Closed{} Open{state: State} ForkOpen{component: UserPicker.UserMessageSelectorComponent}
type Choice is Data: Choice{mode: Mode,id: String}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}

def drawCurrent(current: Modal,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}:
      do IO<List<&2,String>>:
        chosen : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return render(state,chosen,width)
    case ForkOpen{component}:
      do IO<List<&2,String>>:
        chosen : Theme.Theme <- Ref.read(Theme.Theme,theme)
        UserPicker.render(component,chosen,width)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,editor,theme,_,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        drawCurrent(current,editor,theme,width)
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,pair: State & Action) -> IO(Unit):
  match pair:
    case (next,Continue{}): Ref.write(Modal,modal,Open{next})
    case (_,Cancel{}): Ref.write(Modal,modal,Closed{})
    case (next,Chosen{id}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{TreeMode{},id})
def receiveFork(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,pair: UserPicker.UserMessageList & UserPicker.Action) -> IO(Unit):
  match pair:
    case (next,UserPicker.Continue{}): Ref.write(Modal,modal,ForkOpen{UserPicker.UserMessageSelectorComponent{next}})
    case (_,UserPicker.Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,UserPicker.Chosen{id}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{ForkMode{},id})
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}: receiveOpen(modal,chosen,input(state,bindings,keyboard,data))
    case ForkOpen{component}: receiveFork(modal,chosen,UserPicker.handleInput(UserPicker.getMessageList(component),bindings,keyboard,data))
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,_,bindings,keyboard,chosen}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,modal,editor,bindings,keyboard,chosen,data)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouseCurrent(current: Modal,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def hostMouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{modal,editor,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,editor,event)
def hostInvalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_}: Component.invalidate(editor)
def hostFocus(host: Host,focused: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_}: Component.setFocused(editor,focused)
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    +componentId : Component.ComponentId <- IO.pure(Component.ComponentId,Component.id(editor))
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,bindings,keyboard,chosen})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~hostMouse,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~hostInvalidate,host)
    +focusCallback : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~hostFocus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{componentId,renderCallback,Some{inputCallback},Some{mouseCallback},invalidateCallback,Some{focusCallback},False{}})
    return Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}
def borrowHost(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}: (Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback},host,component)
def open(host: Host,state: State) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_}: Ref.write(Modal,modal,Open{state})
def openFork(host: Host,component: UserPicker.UserMessageSelectorComponent) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_}: Ref.write(Modal,modal,ForkOpen{component})
def close(host: Host) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_}: Ref.write(Modal,modal,Closed{})
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,_,_},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)

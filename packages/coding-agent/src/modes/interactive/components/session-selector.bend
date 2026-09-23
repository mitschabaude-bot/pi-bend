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
import ../../../core/session-persistence.bend as Persistence
import ../../../core/tools/index.bend as Tools
import ../theme/theme.bend as Theme

# The selector keeps the session graph, rather than flattening it to an
# unrelated menu. Its visible rows retain branch connectors and the active
# path; the filter changes which entries are visible, not their IDs.
def Entry() -> Data: Tree.SessionEntry<Unit,Tools.ToolDetails,V.Value>
def Node() -> Data: Tree.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>

type Mode is Data: TreeMode{} ForkMode{}
type Filter is Data: Default{} NoTools{} UserOnly{} LabeledOnly{} All{}
type Action is Data: Continue{} Cancel{} Chosen{id: String}
type Row is Data:
  Row{id: String,parent: Maybe<&2,String>,label: Maybe<&2,String>,text: String,prefix: String,connector: String,active: Bool,user: Bool,tool: Bool,bookkeeping: Bool}
type State is Data:
  State{mode: Mode,all: List<&2,Row>,visible: List<&2,Row>,selected: Nat,filter: Filter,search: String,leaf: Maybe<&2,String>,height: Nat}

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
def rowOf(node: Node(),prefix: String,connector: String,active: Bool) -> Row:
  match node:
    case Tree.SessionTreeNode{+entry,_,label,_}:
      +base = Tree.entryBase(Unit,Tools.ToolDetails,V.Value,entry)
      Row{Tree.baseId(base),Tree.baseParent(base),label,entryText(entry),prefix,connector,active,isUser(entry),isTool(entry),isBookkeeping(entry)}

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

def passes(row: Row,mode: Mode,filter: Filter,search: String) -> Bool:
  match row mode filter:
    case Row{_,_,label,text,_,_,_,user,tool,bookkeeping} ForkMode{} _: user && String.contains(CaseMap.lower(text),CaseMap.lower(search))
    case Row{_,_,label,text,_,_,_,user,tool,bookkeeping} TreeMode{} Default{}: Bool.not(bookkeeping) && String.contains(CaseMap.lower(text),CaseMap.lower(search))
    case Row{_,_,label,text,_,_,_,user,tool,bookkeeping} TreeMode{} NoTools{}: Bool.not(bookkeeping || tool) && String.contains(CaseMap.lower(text),CaseMap.lower(search))
    case Row{_,_,label,text,_,_,_,user,tool,bookkeeping} TreeMode{} UserOnly{}: user && String.contains(CaseMap.lower(text),CaseMap.lower(search))
    case Row{_,_,Some{_},text,_,_,_,_,_,_} TreeMode{} LabeledOnly{}: String.contains(CaseMap.lower(text),CaseMap.lower(search))
    case _ TreeMode{} LabeledOnly{}: False{}
    case Row{_,_,_,text,_,_,_,_,_,_} TreeMode{} All{}: String.contains(CaseMap.lower(text),CaseMap.lower(search))
def filtered(rows: List<&2,Row>,+mode: Mode,+filter: Filter,+search: String) -> List<&2,Row>:
  match rows:
    case Nil{}: Nil{}
    case +row <> +rest:
      Bool.pick(List<&2,Row>,passes(row,mode,filter,search),row <> filtered(rest,mode,filter,search),filtered(rest,mode,filter,search))
def indexOf(rows: List<&2,Row>,+id: String,+index: Nat) -> Maybe<&2,Nat>:
  match rows:
    case Nil{}: None{}
    case Row{found,_,_,_,_,_,_,_,_,_} <> rest: Bool.pick(Maybe<&2,Nat>,String.eq(found,id),Some{index},indexOf(rest,id,index + 1n))
def initial(+rows: List<&2,Row>,leaf: Maybe<&2,String>) -> Nat:
  match leaf:
    case None{}: List.length(&2,Row,rows) - 1n
    case Some{id}: Maybe.default(&2,Nat,indexOf(rows,id,0n),List.length(&2,Row,rows) - 1n)
def create(nodes: List<&2,Node()>,+leaf: Maybe<&2,String>,+mode: Mode,height: Nat) -> State:
  +all = allRows(nodes,leaf)
  +visible = filtered(all,mode,Default{},"")
  State{mode,all,visible,initial(visible,leaf),Default{},"",leaf,Nat.max(5n,height / 2n)}

def forkRows(entries: List<&2,Entry()>) -> List<&2,Row>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest:
      +tail = forkRows(rest)
      Bool.pick(List<&2,Row>,isUser(entry),rowOf(Tree.SessionTreeNode{entry,Nil{},None{},None{}},"","",False{}) <> tail,tail)
def createFork(entries: List<&2,Entry()>,height: Nat) -> State:
  +all = forkRows(entries)
  +visible = filtered(all,ForkMode{},Default{},"")
  State{ForkMode{},all,visible,List.length(&2,Row,visible) - 1n,Default{},"",None{},Nat.min(10n,Nat.max(5n,height / 2n))}
def hasRows(state: State) -> Bool:
  match state: case State{_,_,visible,_,_,_,_,_}: Bool.not(List.is_empty(&2,Row,visible))
def at(rows: List<&2,Row>,index: Nat) -> Maybe<&2,Row>:
  match rows index:
    case row <> _ Zero{}: Some{row}
    case _ <> rest Succ{remaining}: at(rest,remaining)
    case Nil{} _: None{}
def rowId(row: Row) -> String:
  match row: case Row{id,_,_,_,_,_,_,_,_,_}: id
def selectedRow(state: State) -> Maybe<&2,Row>:
  match state: case State{_,_,visible,index,_,_,_,_}: at(visible,index)
def selectedId(state: State) -> Maybe<&2,String>:
  Maybe.map(&2,Row,String,row => rowId(row),selectedRow(state))
def refresh(state: State,+filter: Filter,+search: String) -> State:
  match state:
    case State{+mode,+all,_,_,_,_,+leaf,height}:
      +visible = filtered(all,mode,filter,search)
      State{mode,all,visible,initial(visible,leaf),filter,search,leaf,height}
def move(state: State,up: Bool) -> State:
  match state:
    case State{mode,all,+visible,+index,filter,search,leaf,height}:
      +count = List.length(&2,Row,visible)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      State{mode,all,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),filter,search,leaf,height}
def filterKey(state: State,filter: Filter) -> State: refresh(state,filter,"")
def filterInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.default"),_ => (filterKey(state,Default{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.noTools"),_ => (filterKey(state,NoTools{}),Continue{}),
      _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.userOnly"),_ => (filterKey(state,UserOnly{}),Continue{}),
        _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.labeledOnly"),_ => (filterKey(state,LabeledOnly{}),Continue{}),
          _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tree.filter.all"),_ => (filterKey(state,All{}),Continue{}),_ => (state,Continue{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})

def input(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.up"),
    _ => (move(state,True{}),Continue{}),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.down"),
      _ => (move(state,False{}),Continue{}),
      _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),
        _ => (state,Maybe.default(&2,Action,Maybe.map(&2,String,Action,id => Chosen{id},selectedId(state)),Continue{})),
        _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),
          _ => (state,Cancel{}),
          _ => filterInput(state,bindings,keyboard,data))(Unit{}))(Unit{}))(Unit{}))(Unit{})

def paint(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,value),value)
def flattenText(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: Text.trim(String.reverse(reversed))
    case SCon{+char,rest}: flattenText(rest,Bool.pick(String,Char.is_eq(char,'\n') || Char.is_eq(char,'\t'),SCon{' ',reversed},SCon{char,reversed}))
def singleLine(text: String) -> String: flattenText(text,"")
def line(row: Row,selected: Bool,+theme: Theme.Theme,width: Nat) -> String:
  match row:
    case Row{_,_,label,text,prefix,connector,active,user,_,_}:
      +gutter = Bool.pick(String,selected,paint(theme,"accent","› "),"  ")
      +path = Bool.pick(String,active,paint(theme,"accent","• "),"")
      +name = Maybe.default(&2,String,Maybe.map(&2,String,String,value => paint(theme,"warning","[" ++ value ++ "] "),label),"")
      +role = Bool.pick(String,user,"accent","success")
      Utils.truncateToWidth(gutter ++ paint(theme,"dim",prefix ++ connector) ++ path ++ name ++ paint(theme,role,singleLine(text)),width,"",False{})
def visibleLines(rows: List<&2,Row>,+start: Nat,+count: Nat,+index: Nat,+selected: Nat,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match rows:
    case Nil{}: Nil{}
    case row <> +rest:
      Bool.pick(List<&2,String>,Nat.is_lt(index,start),visibleLines(rest,start,count,index + 1n,selected,theme,width),
        Bool.pick(List<&2,String>,Nat.is_ge(index,start + count),Nil{},line(row,Nat.is_eq(index,selected),theme,width) <> visibleLines(rest,start,count,index + 1n,selected,theme,width)))
def title(mode: Mode) -> String:
  match mode:
    case TreeMode{}: "  Session Tree"
    case ForkMode{}: "  Fork from Message"
def render(state: State,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match state:
    case State{mode,_,+visible,+index,filter,search,_,+height}:
      +count = List.length(&2,Row,visible)
      +start = Nat.min(index - height / 2n,count - Nat.min(count,height))
      "" <> paint(theme,"accent",title(mode)) <> paint(theme,"muted","  ↑/↓ select • Enter confirm • Esc cancel") <> paint(theme,"dim",Utils.spaces(width,"")) <> List.append(&2,String,visibleLines(visible,start,height,0n,index,theme,width),paint(theme,"muted","  (" ++ Nat.show(index + 1n) ++ "/" ++ Nat.show(count) ++ ")") <> Nil{})

# A selector temporarily occupies the editor's stable component ID. The live
# editor remains mounted and resumes its own input and focus on dismissal.

type Modal is Data: Closed{} Open{state: State}
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
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,editor,theme,_,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        drawCurrent(current,editor,theme,width)
def modeOf(state: State) -> Mode:
  match state: case State{mode,_,_,_,_,_,_,_}: mode
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,pair: State & Action) -> IO(Unit):
  match pair:
    case (next,Continue{}): Ref.write(Modal,modal,Open{next})
    case (_,Cancel{}): Ref.write(Modal,modal,Closed{})
    case (next,Chosen{id}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{modeOf(next),id})
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}: receiveOpen(modal,chosen,input(state,bindings,keyboard,data))
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
    case Open{_}: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
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

import Base
import ../core/session-manager.bend as Session
import ../core/session-persistence.bend as Persistence
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/string.bend as Strings
import ../../../tui/src/component.bend as Component
import ../../../tui/src/keys.bend as Keys
import ../../../tui/src/fuzzy.bend as Fuzzy
import ../../../tui/src/tui-base.bend as Tui
import ../../../tui/src/tui-main-screen.bend as Screen
import ../../../tui/src/tui-process.bend as Process
import ../../../tui/src/terminal.bend as Terminal
import ../../../tui/src/utils.bend as Utils

# The startup picker has one focusable component. The TUI process owns raw
# terminal state and ordered redraws; this state owns only selection semantics.
type Choice is Data: Pending{} Cancelled{} Chosen{path: String}
type Scope is Data: Current{} All{}
type Sort is Data: Threaded{} Recent{} Relevance{}
type Controls is Data: Controls{sort: Sort,named: Bool}
type Action is Data:
  Cancel{} Confirm{} SwitchScope{} SwitchSort{} SwitchNamed{} MoveUp{} MoveDown{} PageUp{} PageDown{} Erase{} TypeText{text: String} Ignore{}
type State is Data:
  State{current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: String,index: Nat,choice: Choice,controls: Controls}
type Input is Data:
  Input{state: Ref.Ref<State>,stop: Deferred.Deferred<Unit>}
type Owner is Data:
  Owner{state: Ref.Ref<State>,stop: Deferred.Deferred<Unit>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>}
def Outcome() -> Data: Result<&2,&2,String,Maybe<&2,String>>

def searchText(info: Session.SessionInfo) -> String:
  match info:
    case Session.SessionInfo{_,id,cwd,name,_,_,_,_,_,messages}:
      id ++ " " ++ Maybe.default(&2,String,name,"") ++ " " ++ messages ++ " " ++ cwd
def infoPath(info: Session.SessionInfo) -> String:
  match info: case Session.SessionInfo{path,_,_,_,_,_,_,_,_,_}: path

def scopeSessions(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope) -> List<&2,Session.SessionInfo>:
  match scope:
    case Current{}: current
    case All{}: all

def isAll(scope: Scope) -> Bool:
  match scope: case All{}: True{} case Current{}: False{}

def named(info: Session.SessionInfo) -> Bool:
  match info: case Session.SessionInfo{_,_,_,name,_,_,_,_,_,_}: Bool.not(String.is_empty(String.trim(Maybe.default(&2,String,name,""))))
def namedOnly(items: List<&2,Session.SessionInfo>,+namedFilter: Bool) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest: Bool.pick(Unit -> List<&2,Session.SessionInfo>,Bool.not(namedFilter) || named(info),_ => info <> namedOnly(rest,namedFilter),_ => namedOnly(rest,namedFilter))(Unit{})

def parentPath(info: Session.SessionInfo) -> Maybe<&2,String>:
  match info: case Session.SessionInfo{_,_,_,_,parent,_,_,_,_,_}: parent
def hasPath(items: List<&2,Session.SessionInfo>,+path: String) -> Bool:
  match items:
    case Nil{}: False{}
    case info <> rest: Strings.equal(infoPath(info),path) || hasPath(rest,path)
def rootParent(parent: Maybe<&2,String>,items: List<&2,Session.SessionInfo>) -> Bool:
  match parent:
    case None{}: True{}
    case Some{path}: Bool.not(hasPath(items,path))
def isRoot(info: Session.SessionInfo,items: List<&2,Session.SessionInfo>) -> Bool:
  rootParent(parentPath(info),items)
def roots(items: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest: Bool.pick(Unit -> List<&2,Session.SessionInfo>,isRoot(info,all),_ => info <> roots(rest,all),_ => roots(rest,all))(Unit{})
def matchesParent(found: Maybe<&2,String>,parent: String) -> Bool:
  match found: case None{}: False{} case Some{path}: Strings.equal(path,parent)
def childOf(info: Session.SessionInfo,parent: String) -> Bool:
  matchesParent(parentPath(info),parent)
def children(items: List<&2,Session.SessionInfo>,+parent: String) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest: Bool.pick(Unit -> List<&2,Session.SessionInfo>,childOf(info,parent),_ => info <> children(rest,parent),_ => children(rest,parent))(Unit{})
def visited(paths: List<&2,String>,+path: String) -> Bool:
  match paths: case Nil{}: False{} case first <> rest: Strings.equal(first,path) || visited(rest,path)
def branch(fuel: Nat,items: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>,+seen: List<&2,String>) -> List<&2,Session.SessionInfo>:
  match fuel items:
    case Zero{} _: Nil{}
    case _ Nil{}: Nil{}
    case Succ{+left} +info <> +rest:
      +path = infoPath(info)
      Bool.pick(Unit -> List<&2,Session.SessionInfo>,visited(seen,path),_ => branch(left,rest,all,seen),
        _ => List.append(&2,Session.SessionInfo,info <> branch(left,children(all,path),all,path <> seen),branch(left,rest,all,seen)))(Unit{})
def unreached(items: List<&2,Session.SessionInfo>,+ordered: List<&2,Session.SessionInfo>) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest: Bool.pick(Unit -> List<&2,Session.SessionInfo>,hasPath(ordered,infoPath(info)),_ => unreached(rest,ordered),_ => info <> unreached(rest,ordered))(Unit{})
def threaded(+items: List<&2,Session.SessionInfo>) -> List<&2,Session.SessionInfo>:
  +rootItems = roots(items,items)
  +ordered = branch(List.length(&2,Session.SessionInfo,items) + 1n,rootItems,items,Nil{})
  List.append(&2,Session.SessionInfo,ordered,unreached(items,ordered))
def sortLabel(sort: Sort) -> String:
  match sort: case Threaded{}: "Threaded" case Recent{}: "Recent" case Relevance{}: "Fuzzy"
def threadedMode(sort: Sort,query: String) -> Bool:
  match sort:
    case Threaded{}: String.is_empty(String.trim(query))
    case _: False{}
def nextSort(sort: Sort) -> Sort:
  match sort: case Threaded{}: Recent{} case Recent{}: Relevance{} case Relevance{}: Threaded{}
def cycledSort(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter}: Controls{nextSort(sort),namedFilter}
def toggledNamed(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter}: Controls{sort,Bool.not(namedFilter)}
def matching(info: Session.SessionInfo,tokens: List<&2,String>) -> Bool:
  Maybe.is_some(&2,F64,Fuzzy.tokenScore(tokens,searchText(info),Some{U32.to_f64(0)}))
def recentFiltered(items: List<&2,Session.SessionInfo>,+tokens: List<&2,String>) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest: Bool.pick(Unit -> List<&2,Session.SessionInfo>,matching(info,tokens),_ => info <> recentFiltered(rest,tokens),_ => recentFiltered(rest,tokens))(Unit{})
def arranged(+items: List<&2,Session.SessionInfo>,+query: String,sort: Sort) -> List<&2,Session.SessionInfo>:
  match sort:
    case Threaded{}: Bool.pick(Unit -> List<&2,Session.SessionInfo>,String.is_empty(String.trim(query)),_ => threaded(items),_ => Fuzzy.fuzzyFilter(~Session.SessionInfo,~searchText,items,query))(Unit{})
    case Recent{}: Bool.pick(Unit -> List<&2,Session.SessionInfo>,String.is_empty(String.trim(query)),_ => items,_ => recentFiltered(items,Fuzzy.tokens(query,"",Nil{})))(Unit{})
    case Relevance{}: Bool.pick(Unit -> List<&2,Session.SessionInfo>,String.is_empty(String.trim(query)),_ => items,_ => Fuzzy.fuzzyFilter(~Session.SessionInfo,~searchText,items,query))(Unit{})

def visible(state: State) -> List<&2,Session.SessionInfo>:
  match state:
    case State{current,all,scope,query,_,_,Controls{sort,namedFilter}}:
      +items = scopeSessions(current,all,scope)
      arranged(namedOnly(items,namedFilter),query,sort)

def infoLabel(info: Session.SessionInfo,all: Bool) -> String:
  match info:
    case Session.SessionInfo{_,_,cwd,name,_,_,_,count,first,_}:
      +title = Maybe.default(&2,String,name,first)
      title ++ "  (" ++ Nat.show(count) ++ ")" ++ Bool.pick(String,all,"  " ++ cwd,"")

def findPath(items: List<&2,Session.SessionInfo>,+path: String) -> Maybe<&2,Session.SessionInfo>:
  match items:
    case Nil{}: None{}
    case +info <> rest: Bool.pick(Maybe<&2,Session.SessionInfo>,Strings.equal(infoPath(info),path),Some{info},findPath(rest,path))
def lastPath(items: List<&2,Session.SessionInfo>) -> Maybe<&2,String>:
  match items:
    case Nil{}: None{}
    case info <> Nil{}: Some{infoPath(info)}
    case _ <> rest: lastPath(rest)
def lastInParent(parentPathValue: Maybe<&2,String>,info: Session.SessionInfo,items: List<&2,Session.SessionInfo>) -> Bool:
  match parentPathValue:
    case None{}: True{}
    case Some{parent}: Maybe.default(&2,Bool,Maybe.map(&2,String,Bool,path => Strings.equal(path,infoPath(info)),lastPath(children(items,parent))),True{})
def isLast(+info: Session.SessionInfo,items: List<&2,Session.SessionInfo>) -> Bool:
  lastInParent(parentPath(info),info,items)
def hasParent(value: Maybe<&2,String>) -> Bool: Maybe.is_some(&2,String,value)
def ancestorFlags(fuel: Nat,parent: Maybe<&2,String>,+items: List<&2,Session.SessionInfo>,+flags: List<&2,Bool>) -> List<&2,Bool>:
  match fuel parent:
    case Zero{} _: flags
    case _ None{}: flags
    case Succ{left} Some{path}:
      Maybe.default(&2,List<&2,Bool>,Maybe.map(&2,Session.SessionInfo,List<&2,Bool>,+info => ancestorFlags(left,parentPath(info),items,(hasParent(parentPath(info)) && Bool.not(isLast(info,items))) <> flags),findPath(items,path)),flags)
def rooted(fuel: Nat,parent: Maybe<&2,String>,+items: List<&2,Session.SessionInfo>) -> Bool:
  match fuel parent:
    case _ None{}: True{}
    case Zero{} _: False{}
    case Succ{left} Some{path}: Maybe.default(&2,Bool,Maybe.map(&2,Session.SessionInfo,Bool,info => rooted(left,parentPath(info),items),findPath(items,path)),False{})
def rails(flags: List<&2,Bool>) -> String:
  match flags:
    case Nil{}: ""
    case True{} <> rest: "│  " ++ rails(rest)
    case False{} <> rest: "   " ++ rails(rest)
def prefixFor(parent: Maybe<&2,String>,info: Session.SessionInfo,+items: List<&2,Session.SessionInfo>) -> String:
  match parent:
    case None{}: ""
    case Some{+path}:
      Bool.pick(Unit -> String,rooted(List.length(&2,Session.SessionInfo,items),Some{path},items),
        _ => rails(ancestorFlags(List.length(&2,Session.SessionInfo,items),Some{path},items,Nil{})) ++ Bool.pick(String,isLast(info,items),"└─ ","├─ "),
        _ => "")(Unit{})
def treePrefix(+info: Session.SessionInfo,items: List<&2,Session.SessionInfo>) -> String:
  prefixFor(parentPath(info),info,items)

def label(+info: Session.SessionInfo,index: Nat,chosen: Nat,all: Bool,thread: Bool,items: List<&2,Session.SessionInfo>,width: Nat) -> String:
  +prefix = Bool.pick(String,thread,treePrefix(info,items),"")
  Utils.truncateToWidth(Bool.pick(String,Nat.is_eq(index,chosen),"› ","  ") ++ prefix ++ infoLabel(info,all),width,"…",False{})

def listLines(items: List<&2,Session.SessionInfo>,+index: Nat,+chosen: Nat,+all: Bool,+thread: Bool,+allItems: List<&2,Session.SessionInfo>,+width: Nat,count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match items count:
    case _ Zero{}: List.reverse(&2,String,reversed)
    case Nil{} _: List.reverse(&2,String,reversed)
    case +info <> rest Succ{left}: listLines(rest,index + 1n,chosen,all,thread,allItems,width,left,label(info,index,chosen,all,thread,allItems,width) <> reversed)

def window(items: List<&2,Session.SessionInfo>,+selected: Nat) -> List<&2,Session.SessionInfo>:
  List.drop(&2,Session.SessionInfo,items,Bool.pick(Nat,Nat.is_gt(selected,8n),selected - 8n,0n))

def renderState(+state: State,+width: Nat) -> List<&2,String>:
  match state:
    case State{_,_,scope,query,index,_,Controls{sort,namedFilter}}:
      +items = visible(state)
      +all = isAll(scope)
      +start = Bool.pick(Nat,Nat.is_gt(index,8n),index - 8n,0n)
      +title = Bool.pick(String,all,"Resume Session (All)","Resume Session (Current Folder)") ++ "  ·  " ++ sortLabel(sort) ++ Bool.pick(String,namedFilter," · Named","")
      +thread = threadedMode(sort,query)
      +body = listLines(window(items,index),start,index,all,thread,items,width,10n,Nil{})
      List.append(&2,String,[Utils.truncateToWidth(title,width,"…",False{}),
       Utils.truncateToWidth("Search: " ++ query,width,"…",False{}),
       Utils.truncateToWidth("Tab scope · Ctrl+S sort · Ctrl+N named · ↑↓ move · Enter open · Esc cancel",width,"…",False{})],
       Bool.pick(List<&2,String>,List.is_empty(&2,Session.SessionInfo,items),["  No sessions found"],body))

def paint(state: Ref.Ref<State>,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    value : State <- Ref.read(State,state)
    return renderState(value,width)
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def ignoreFocus(_: Unit,_: Bool) -> IO(Unit): IO.pure(Unit,Unit{})

def chosenAt(found: Maybe<&2,Session.SessionInfo>) -> Choice:
  match found:
    case None{}: Pending{}
    case Some{info}: Chosen{infoPath(info)}
def chosen(items: List<&2,Session.SessionInfo>,index: Nat) -> Choice:
  chosenAt(List.get(&2,Session.SessionInfo,items,index))

def lastRemoved(reversed: String) -> String:
  match reversed:
    case SNil{}: ""
    case SCon{_,rest}: String.reverse(rest)
def withoutLast(text: String) -> String: lastRemoved(String.reverse(text))

def printableTail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{char,rest}: Nat.is_ge(U32.to_nat(Char.to_u32(char)),32n) && printableTail(rest)
def printable(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{char,rest}: Nat.is_ge(U32.to_nat(Char.to_u32(char)),32n) && printableTail(rest)

def decoded(key: Maybe<&2,Keys.KeyId>,+data: String) -> Action:
  match key:
    case Some{Keys.KeyId{Keys.Escape{},_}}: Cancel{}
    case Some{Keys.KeyId{Keys.Printable{'c'},Keys.Modifiers{False{},False{},True{},False{}}}}: Cancel{}
    case Some{Keys.KeyId{Keys.Enter{},_}}: Confirm{}
    case Some{Keys.KeyId{Keys.Tab{},_}}: SwitchScope{}
    case Some{Keys.KeyId{Keys.Printable{'s'},Keys.Modifiers{False{},False{},True{},False{}}}}: SwitchSort{}
    case Some{Keys.KeyId{Keys.Printable{'n'},Keys.Modifiers{False{},False{},True{},False{}}}}: SwitchNamed{}
    case Some{Keys.KeyId{Keys.Up{},_}}: MoveUp{}
    case Some{Keys.KeyId{Keys.Down{},_}}: MoveDown{}
    case Some{Keys.KeyId{Keys.PageUp{},_}}: PageUp{}
    case Some{Keys.KeyId{Keys.PageDown{},_}}: PageDown{}
    case Some{Keys.KeyId{Keys.Backspace{},_}}: Erase{}
    case Some{Keys.KeyId{Keys.Space{},Keys.Modifiers{_,False{},False{},False{}}}}: TypeText{" "}
    case Some{Keys.KeyId{Keys.Printable{_},Keys.Modifiers{_,False{},False{},False{}}}}: TypeText{data}
    case None{}: Bool.pick(Action,printable(data),TypeText{data},Ignore{})
    case _: Ignore{}
def action(+data: String) -> Action: decoded(Keys.parseKey(Keys.defaults(),data),data)

def revised(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: String,index: Nat,choice: Choice,controls: Controls) -> State:
  State{current,all,scope,query,index,choice,controls}
def toggled(scope: Scope) -> Scope:
  match scope: case Current{}: All{} case All{}: Current{}
def advanced(+index: Nat,count: Nat,down: Bool) -> Nat:
  match count:
    case Zero{}: 0n
    case Succ{last}: Bool.pick(Nat,down,Nat.min(index + 1n,last),Bool.pick(Nat,Nat.is_eq(index,0n),0n,index - 1n))

def selected(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: String,index: Nat,choice: Choice,controls: Controls) -> State & Bool:
  match choice:
    case Pending{}: (revised(current,all,scope,query,index,Pending{},controls),False{})
    case value: (revised(current,all,scope,query,index,value,controls),True{})

def pending(+current: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>,+scope: Scope,+query: String,+index: Nat,+controls: Controls,action: Action) -> State & Bool:
  match action:
    case Cancel{}: (revised(current,all,scope,query,index,Cancelled{},controls),True{})
    case Confirm{}:
      +items = visible(revised(current,all,scope,query,index,Pending{},controls))
      selected(current,all,scope,query,index,chosen(items,index),controls)
    case SwitchScope{}: (revised(current,all,toggled(scope),query,0n,Pending{},controls),False{})
    case SwitchSort{}: (revised(current,all,scope,query,0n,Pending{},cycledSort(controls)),False{})
    case SwitchNamed{}: (revised(current,all,scope,query,0n,Pending{},toggledNamed(controls)),False{})
    case MoveUp{}:
      +count = List.length(&2,Session.SessionInfo,visible(revised(current,all,scope,query,index,Pending{},controls)))
      (revised(current,all,scope,query,advanced(index,count,False{}),Pending{},controls),False{})
    case MoveDown{}:
      +count = List.length(&2,Session.SessionInfo,visible(revised(current,all,scope,query,index,Pending{},controls)))
      (revised(current,all,scope,query,advanced(index,count,True{}),Pending{},controls),False{})
    case PageUp{}: (revised(current,all,scope,query,index - 10n,Pending{},controls),False{})
    case PageDown{}:
      +count = List.length(&2,Session.SessionInfo,visible(revised(current,all,scope,query,index,Pending{},controls)))
      (revised(current,all,scope,query,Nat.min(index + 10n,count - 1n),Pending{},controls),False{})
    case Erase{}: (revised(current,all,scope,withoutLast(query),0n,Pending{},controls),False{})
    case TypeText{text}: (revised(current,all,scope,query ++ text,0n,Pending{},controls),False{})
    case Ignore{}: (revised(current,all,scope,query,index,Pending{},controls),False{})

def transition(state: State,data: String) -> State & Bool:
  match state:
    case State{current,all,scope,query,index,Pending{},controls}: pending(current,all,scope,query,index,controls,action(data))
    case state: (state,False{})

def received(input: Input,data: String) -> IO(Unit):
  match input:
    case Input{state,stop}:
      do IO<Unit>:
        done : Bool <- Ref.modify(State,Bool,state,current => transition(current,data))
        Bool.pick(Unit -> IO(Unit),done,_ => do IO<Unit>:
          resolved : Bool <- Deferred.resolve(Unit,stop,Unit{})
          return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})

def made(state: Ref.Ref<State>,stop: Deferred.Deferred<Unit>,+render: Callback.Callback<Nat,List<&2,String>>,+input: Callback.Callback<String,Unit>,+invalidate: Callback.Callback<Unit,Unit>,+focus: Callback.Callback<Bool,Unit>) -> Owner:
  Owner{state,stop,Component.Component{Component.ComponentId{1n},render,Some{input},None{},invalidate,Some{focus},False{}},render,input,invalidate,focus}
def create(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<State> <- Ref.new(State,State{current,all,Current{},"",0n,Pending{},Controls{Threaded{},False{}}})
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Ref.Ref<State>,~Nat,~List<&2,String>,~paint,state)
    +input : Callback.Callback<String,Unit> <- Callback.create(~Input,~String,~Unit,~received,Input{state,stop})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Unit,~Bool,~Unit,~ignoreFocus,Unit{})
    return made(state,stop,render,input,invalidate,focus)

def result(state: State) -> Outcome():
  match state:
    case State{_,_,_,_,_,Chosen{path},_}: Done{Some{path}}
    case _: Done{None{}}
def failed(error: Terminal.Error) -> Outcome():
  match error:
    case Terminal.System{operation,_,message}: Fail{"Terminal " ++ operation ++ ": " ++ message}
    case _: Fail{"Cannot start session selector terminal"}
def settled(outcome: Result<&2,&2,Terminal.Error,Process.Active>,final: State) -> Outcome():
  match outcome:
    case Fail{error}: failed(error)
    case Done{_}: result(final)
def finish(owner: Owner,outcome: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Outcome()):
  match owner:
    case Owner{state,stop,_,render,input,invalidate,focus}:
      do IO<Outcome()>:
        final : State <- Ref.dispose(State,state)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
        Deferred.dispose(Unit,stop)
        return settled(outcome,final)

def runMounted(owner: Owner,mounted: Tui.ResultOf(Tui.TuiBase)) -> IO(Outcome()):
  match owner mounted:
    case Owner{state,stop,component,render,input,invalidate,focus} Fail{_}:
      finish(Owner{state,stop,component,render,input,invalidate,focus},Fail{Terminal.Closed{}})
    case Owner{state,+stop,+component,render,input,invalidate,focus} Done{base}:
      do IO<Outcome()>:
        outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcess(Process.active(Process.Session{base,Screen.initial()},[component],[Component.ComponentId{1n}]),stop,False{})
        finish(Owner{state,stop,component,render,input,invalidate,focus},outcome)

def run(owner: Owner) -> IO(Outcome()):
  match owner:
    case Owner{state,stop,+component,render,input,invalidate,focus}:
      do IO<Outcome()>:
        mounted : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),[component],[Component.ComponentId{1n}],Some{Component.ComponentId{1n}})
        runMounted(Owner{state,stop,component,render,input,invalidate,focus},mounted)

def selectSession(cwd: String,+sessionDir: Maybe<&2,String>,agentDir: String,sessionsDir: String) -> IO(Outcome()):
  do IO<Outcome()>:
    current : List<&2,Session.SessionInfo> <- Persistence.list(cwd,sessionDir,agentDir)
    all : List<&2,Session.SessionInfo> <- Persistence.listAll(sessionDir,sessionsDir)
    owner : Owner <- create(current,all)
    run(owner)

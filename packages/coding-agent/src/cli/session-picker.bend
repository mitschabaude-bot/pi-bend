import Base
import ../core/session-manager.bend as Session
import ../core/session-persistence.bend as Persistence
import ../core/keybindings.bend as AppKeys
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/child-process.bend as Child
import ../../../runtime/src/regex.bend as Regex
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/string.bend as Strings
import ../../../tui/src/component.bend as Component
import ../../../tui/src/keys.bend as Keys
import ../../../tui/src/keybindings.bend as Bindings
import ../../../tui/src/fuzzy.bend as Fuzzy
import ../../../tui/src/tui-base.bend as Tui
import ../../../tui/src/tui.bend as Ui
import ../../../tui/src/tui-main-screen.bend as Screen
import ../../../tui/src/tui-process.bend as Process
import ../../../tui/src/terminal.bend as Terminal
import ../../../tui/src/utils.bend as Utils

# The startup picker has one focusable component. The TUI process owns raw
# terminal state and ordered redraws; this state owns only selection semantics.
type Choice is Data: Pending{} Cancelled{} Chosen{path: String}
type Scope is Data: Current{} All{}
type Sort is Data: Threaded{} Recent{} Relevance{}
type Controls is Data: Controls{sort: Sort,named: Bool,showPath: Bool,deleting: Maybe<&2,String>,status: Maybe<&2,String>}
type Action is Data:
  Cancel{} Confirm{} SwitchScope{} SwitchSort{} SwitchNamed{} TogglePath{} Delete{} DeleteAlias{} MoveUp{} MoveDown{} PageUp{} PageDown{} Erase{} TypeText{text: String} Ignore{}
type State is Data:
  State{current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: String,index: Nat,choice: Choice,controls: Controls}
type Count is Data: Count{loaded: Nat,total: Nat}
type Loads is Data: Loads{current: Maybe<&2,Count>,all: Maybe<&2,Count>}
type Input is Data:
  Input{state: Ref.Ref<State>,stop: Deferred.Deferred<Unit>,allRequested: Deferred.Deferred<Unit>,bindings: Bindings.KeybindingsManager}
type Paint is Data: Paint{state: Ref.Ref<State>,loads: Ref.Ref<Loads>,normalHint: String,deleteHint: String}
type Owner is Data:
  Owner{state: Ref.Ref<State>,loads: Ref.Ref<Loads>,stop: Deferred.Deferred<Unit>,allRequested: Deferred.Deferred<Unit>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>}
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
  match controls: case Controls{sort,namedFilter,path,_,_}: Controls{nextSort(sort),namedFilter,path,None{},None{}}
def toggledNamed(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,path,_,_}: Controls{sort,Bool.not(namedFilter),path,None{},None{}}
def toggledPath(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,path,_,_}: Controls{sort,namedFilter,Bool.not(path),None{},None{}}
def confirming(controls: Controls,path: String) -> Controls:
  match controls: case Controls{sort,namedFilter,showPath,_,_}: Controls{sort,namedFilter,showPath,Some{path},None{}}
def cleared(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,showPath,_,_}: Controls{sort,namedFilter,showPath,None{},None{}}
def withStatus(controls: Controls,message: String) -> Controls:
  match controls: case Controls{sort,namedFilter,showPath,_,_}: Controls{sort,namedFilter,showPath,None{},Some{message}}
type SearchToken is Data: Word{text: String} Phrase{text: String}
type Search is Data: Tokens{tokens: List<&2,SearchToken>,fuzzy: String} Pattern{regex: Regex.Regex} Invalid{message: String}
def pushed(buffer: String,quoted: Bool,+tokens: List<&2,SearchToken>) -> List<&2,SearchToken>:
  +word = String.trim(buffer)
  Bool.pick(List<&2,SearchToken>,String.is_empty(word),tokens,Bool.pick(SearchToken,quoted,Phrase{word},Word{word}) <> tokens)
def scan(text: String,+quoted: Bool,+buffer: String,+tokens: List<&2,SearchToken>) -> List<&2,SearchToken> & Bool:
  match text:
    case SNil{}: (List.reverse(&2,SearchToken,pushed(buffer,quoted,tokens)),quoted)
    case SCon{'"',rest}: scan(rest,Bool.not(quoted),"",pushed(buffer,quoted,tokens))
    case SCon{' ',+rest}: Bool.pick(Unit -> List<&2,SearchToken> & Bool,quoted,_ => scan(rest,quoted,buffer ++ " ",tokens),_ => scan(rest,quoted,"",pushed(buffer,False{},tokens)))(Unit{})
    case SCon{'\t',+rest}: Bool.pick(Unit -> List<&2,SearchToken> & Bool,quoted,_ => scan(rest,quoted,buffer ++ " ",tokens),_ => scan(rest,quoted,"",pushed(buffer,False{},tokens)))(Unit{})
    case SCon{char,rest}: scan(rest,quoted,buffer ++ SCon{char,SNil{}},tokens)
def plainTokens(words: List<&2,String>) -> List<&2,SearchToken>:
  match words: case Nil{}: Nil{} case word <> rest: Word{word} <> plainTokens(rest)
def fuzzyWords(tokens: List<&2,SearchToken>) -> List<&2,String>:
  match tokens:
    case Nil{}: Nil{}
    case Word{text} <> rest: text <> fuzzyWords(rest)
    case Phrase{_} <> rest: fuzzyWords(rest)
# Reject malformed regex visibly; upstream silently reduces it to no matches.
def regexSearch(compiled: Result<&2,&2,Regex.Error,Regex.Regex>) -> Search:
  match compiled:
    case Done{regex}: Pattern{regex}
    case Fail{Regex.Syntax{message}}: Invalid{"Invalid regex: " ++ message}
    case Fail{_}: Invalid{"Invalid regex"}
def regexQuery(+pattern: String) -> Search:
  Bool.pick(Unit -> Search,String.is_empty(pattern),_ => Invalid{"Empty regex"},_ => regexSearch(Regex.compile(pattern,True{})))(Unit{})
def tokensSearch(scanned: List<&2,SearchToken> & Bool,+trimmed: String) -> Search:
  match scanned:
    case (unused,True{}):
      +fallback = plainTokens(Fuzzy.tokens(trimmed,"",Nil{}))
      Tokens{fallback,String.join(fuzzyWords(fallback)," ")}
    case (+tokens,False{}): Tokens{tokens,String.join(fuzzyWords(tokens)," ")}
def parsedSearch(query: String) -> Search:
  +trimmed = String.trim(query)
  Bool.pick(Unit -> Search,String.starts_with(trimmed,"re:"),
    _ => regexQuery(String.trim(String.drop(trimmed,3n))),
    _ => tokensSearch(scan(trimmed,False{},"",Nil{}),trimmed))(Unit{})
def tokenMatches(tokens: List<&2,SearchToken>,+text: String) -> Bool:
  match tokens:
    case Nil{}: True{}
    case Word{word} <> rest: Maybe.is_some(&2,F64,Fuzzy.tokenScore([word],text,Some{U32.to_f64(0)})) && tokenMatches(rest,text)
    case Phrase{phrase} <> rest: String.contains(String.to_lower(text),String.to_lower(phrase)) && tokenMatches(rest,text)
def searchMatches(info: Session.SessionInfo,search: Search) -> Bool:
  match search:
    case Tokens{tokens,_}: tokenMatches(tokens,searchText(info))
    case Pattern{regex}: Regex.isMatch(regex,searchText(info))
    case Invalid{_}: False{}
def recentFiltered(items: List<&2,Session.SessionInfo>,+search: Search) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest: Bool.pick(Unit -> List<&2,Session.SessionInfo>,searchMatches(info,search),_ => info <> recentFiltered(rest,search),_ => recentFiltered(rest,search))(Unit{})
def searched(+items: List<&2,Session.SessionInfo>,search: Search,sort: Sort) -> List<&2,Session.SessionInfo>:
  match search sort:
    case Invalid{_} _: Nil{}
    case Pattern{regex} _: recentFiltered(items,Pattern{regex})
    case Tokens{tokens,fuzzy} Recent{}: recentFiltered(items,Tokens{tokens,fuzzy})
    case Tokens{+tokens,+fuzzy} _:
      +ranked = Bool.pick(List<&2,Session.SessionInfo>,String.is_empty(fuzzy),items,Fuzzy.fuzzyFilter(~Session.SessionInfo,~searchText,items,fuzzy))
      recentFiltered(ranked,Tokens{tokens,fuzzy})
def searchProblem(search: Search) -> Maybe<&2,String>:
  match search:
    case Invalid{message}: Some{message}
    case _: None{}
def unsought(items: List<&2,Session.SessionInfo>,sort: Sort) -> List<&2,Session.SessionInfo>:
  match sort: case Threaded{}: threaded(items) case _: items
def arranged(+items: List<&2,Session.SessionInfo>,+query: String,+sort: Sort) -> List<&2,Session.SessionInfo>:
  Bool.pick(Unit -> List<&2,Session.SessionInfo>,String.is_empty(String.trim(query)),_ =>
    unsought(items,sort),
    _ => searched(items,parsedSearch(query),sort))(Unit{})

def visible(state: State) -> List<&2,Session.SessionInfo>:
  match state:
    case State{current,all,scope,query,_,_,Controls{sort,namedFilter,_,_,_}}:
      +items = scopeSessions(current,all,scope)
      arranged(namedOnly(items,namedFilter),query,sort)

def safeText(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{+char,rest}:
      +point = U32.to_nat(Char.to_u32(char))
      Bool.pick(String,Nat.is_lt(point,32n) || Nat.is_eq(point,127n)," ",SCon{char,SNil{}}) ++ safeText(rest)
def infoLabel(info: Session.SessionInfo,all: Bool,showPath: Bool) -> String:
  match info:
    case Session.SessionInfo{path,_,cwd,name,_,_,_,count,first,_}:
      +title = Maybe.default(&2,String,name,first)
      safeText(title) ++ "  (" ++ Nat.show(count) ++ ")" ++ Bool.pick(String,all,"  " ++ safeText(cwd),"") ++ Bool.pick(String,showPath,"  " ++ safeText(path),"")

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

def label(+info: Session.SessionInfo,index: Nat,chosen: Nat,all: Bool,thread: Bool,showPath: Bool,items: List<&2,Session.SessionInfo>,width: Nat) -> String:
  +prefix = Bool.pick(String,thread,treePrefix(info,items),"")
  Utils.truncateToWidth(Bool.pick(String,Nat.is_eq(index,chosen),"› ","  ") ++ prefix ++ infoLabel(info,all,showPath),width,"…",False{})

def listLines(items: List<&2,Session.SessionInfo>,+index: Nat,+chosen: Nat,+all: Bool,+thread: Bool,+showPath: Bool,+allItems: List<&2,Session.SessionInfo>,+width: Nat,count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match items count:
    case _ Zero{}: List.reverse(&2,String,reversed)
    case Nil{} _: List.reverse(&2,String,reversed)
    case +info <> rest Succ{left}: listLines(rest,index + 1n,chosen,all,thread,showPath,allItems,width,left,label(info,index,chosen,all,thread,showPath,allItems,width) <> reversed)

def window(items: List<&2,Session.SessionInfo>,+selected: Nat) -> List<&2,Session.SessionInfo>:
  List.drop(&2,Session.SessionInfo,items,Bool.pick(Nat,Nat.is_gt(selected,8n),selected - 8n,0n))
def hint(deleting: Maybe<&2,String>,status: Maybe<&2,String>,problem: Maybe<&2,String>,normal: String,confirm: String) -> String:
  match deleting:
    case Some{_}: "Trash this session? Falls back to permanent deletion · " ++ confirm
    case None{}: Maybe.default(&2,String,problem,Maybe.default(&2,String,status,normal))
def countHint(count: Maybe<&2,Count>) -> Maybe<&2,String>:
  match count:
    case None{}: None{}
    case Some{Count{loaded,total}}: Some{"Loading sessions " ++ Nat.show(loaded) ++ "/" ++ Nat.show(total)}
def loadingHint(scope: Scope,loads: Loads) -> Maybe<&2,String>:
  match scope loads:
    case Current{} Loads{current,_}: countHint(current)
    case All{} Loads{_,all}: countHint(all)
def emptyRow(loading: Maybe<&2,String>) -> List<&2,String>:
  match loading:
    case Some{_}: ["  Loading sessions..."]
    case None{}: ["  No sessions found"]

def renderState(+state: State,+width: Nat,normalHint: String,deleteHint: String,loads: Loads) -> List<&2,String>:
  match state:
    case State{_,_,scope,query,index,_,Controls{sort,namedFilter,showPath,deleting,status}}:
      +items = visible(state)
      +all = isAll(scope)
      +start = Bool.pick(Nat,Nat.is_gt(index,8n),index - 8n,0n)
      +title = Bool.pick(String,all,"Resume Session (All)","Resume Session (Current Folder)") ++ "  ·  " ++ sortLabel(sort) ++ Bool.pick(String,namedFilter," · Named","") ++ Bool.pick(String,showPath," · Path on","")
      +thread = threadedMode(sort,query)
      +body = listLines(window(items,index),start,index,all,thread,showPath,items,width,10n,Nil{})
      +loading = loadingHint(scope,loads)
      +help = hint(deleting,Maybe.or(&2,String,status,loading),searchProblem(parsedSearch(query)),normalHint,deleteHint)
      List.append(&2,String,[Utils.truncateToWidth(title,width,"…",False{}),
       Utils.truncateToWidth("Search: " ++ safeText(query),width,"…",False{}),
       Utils.truncateToWidth(help,width,"…",False{})],
       Bool.pick(List<&2,String>,List.is_empty(&2,Session.SessionInfo,items),emptyRow(loading),body))

def paint(environment: Paint,width: Nat) -> IO(List<&2,String>):
  match environment:
    case Paint{state,loads,normal,confirm}:
      do IO<List<&2,String>>:
        value : State <- Ref.read(State,state)
        loading : Loads <- Ref.read(Loads,loads)
        return renderState(value,width,normal,confirm,loading)
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

type Binding is Data: Binding{name: String,action: Action}
def selectorBindings() -> List<&2,Binding>:
  [Binding{"tui.select.cancel",Cancel{}},Binding{"tui.select.confirm",Confirm{}},Binding{"tui.input.tab",SwitchScope{}},
   Binding{"app.session.toggleSort",SwitchSort{}},Binding{"app.session.toggleNamedFilter",SwitchNamed{}},
   Binding{"app.session.togglePath",TogglePath{}},Binding{"app.session.delete",Delete{}},
   Binding{"app.session.deleteNoninvasive",DeleteAlias{}},Binding{"tui.select.up",MoveUp{}},
   Binding{"tui.select.down",MoveDown{}},Binding{"tui.select.pageUp",PageUp{}},Binding{"tui.select.pageDown",PageDown{}}]
def bound(items: List<&2,Binding>,+bindings: Bindings.KeybindingsManager,+data: String) -> Maybe<&2,Action>:
  match items:
    case Nil{}: None{}
    case Binding{name,action} <> rest:
      Bool.pick(Unit -> Maybe<&2,Action>,Bindings.matches(bindings,Keys.defaults(),data,name),_ => Some{action},_ => bound(rest,bindings,data))(Unit{})
def typed(key: Maybe<&2,Keys.KeyId>,+data: String) -> Action:
  match key:
    case Some{Keys.KeyId{Keys.Backspace{},_}}: Erase{}
    case Some{Keys.KeyId{Keys.Space{},Keys.Modifiers{_,False{},False{},False{}}}}: TypeText{" "}
    case Some{Keys.KeyId{Keys.Printable{_},Keys.Modifiers{_,False{},False{},False{}}}}: TypeText{data}
    case None{}: Bool.pick(Action,printable(data),TypeText{data},Ignore{})
    case _: Ignore{}
def action(+bindings: Bindings.KeybindingsManager,+data: String) -> Action:
  Maybe.default(&2,Action,bound(selectorBindings(),bindings,data),typed(Keys.parseKey(Keys.defaults(),data),data))

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
def deletingSelected(+current: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>,+scope: Scope,+query: String,+index: Nat,+controls: Controls) -> State & Bool:
  +items = visible(revised(current,all,scope,query,index,Pending{},controls))
  +next = Maybe.default(&2,Controls,Maybe.map(&2,Session.SessionInfo,Controls,info => confirming(controls,infoPath(info)),List.get(&2,Session.SessionInfo,items,index)),controls)
  (revised(current,all,scope,query,index,Pending{},next),False{})

def pending(+current: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>,+scope: Scope,+query: String,+index: Nat,+controls: Controls,action: Action) -> State & Bool:
  match action:
    case Cancel{}: (revised(current,all,scope,query,index,Cancelled{},controls),True{})
    case Confirm{}:
      +items = visible(revised(current,all,scope,query,index,Pending{},controls))
      selected(current,all,scope,query,index,chosen(items,index),controls)
    case SwitchScope{}: (revised(current,all,toggled(scope),query,0n,Pending{},controls),False{})
    case SwitchSort{}: (revised(current,all,scope,query,0n,Pending{},cycledSort(controls)),False{})
    case SwitchNamed{}: (revised(current,all,scope,query,0n,Pending{},toggledNamed(controls)),False{})
    case TogglePath{}: (revised(current,all,scope,query,index,Pending{},toggledPath(controls)),False{})
    case Delete{}: deletingSelected(current,all,scope,query,index,controls)
    case DeleteAlias{}:
      Bool.pick(Unit -> State & Bool,String.is_empty(query),_ => deletingSelected(current,all,scope,query,index,controls),_ => (revised(current,all,scope,withoutLast(query),0n,Pending{},controls),False{}))(Unit{})
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

def duringConfirmation(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: String,index: Nat,controls: Controls,action: Action) -> State & Bool:
  match action:
    case Cancel{}: (revised(current,all,scope,query,index,Pending{},cleared(controls)),False{})
    case _: (revised(current,all,scope,query,index,Pending{},controls),False{})
def transition(state: State,data: String,bindings: Bindings.KeybindingsManager) -> State & Bool:
  match state:
    case State{current,all,scope,query,index,Pending{},Controls{sort,namedFilter,showPath,Some{path},status}}:
      duringConfirmation(current,all,scope,query,index,Controls{sort,namedFilter,showPath,Some{path},status},action(bindings,data))
    case State{current,all,scope,query,index,Pending{},controls}: pending(current,all,scope,query,index,cleared(controls),action(bindings,data))
    case state: (state,False{})

def withoutPath(items: List<&2,Session.SessionInfo>,+path: String) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest: Bool.pick(Unit -> List<&2,Session.SessionInfo>,Strings.equal(infoPath(info),path),_ => withoutPath(rest,path),_ => info <> withoutPath(rest,path))(Unit{})
def removalError(error: FS.Error) -> String:
  match error:
    case FS.System{_,message}: "Failed to delete session: " ++ message
    case _: "Failed to delete session"
def unlinked(result: Result<&2,&2,FS.Error,Unit>) -> Result<&2,&2,String,String>:
  match result:
    case Done{_}: Done{"Session deleted"}
    case Fail{error}: Fail{removalError(error)}
def unlinkSession(path: String) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    result : Result<&2,&2,FS.Error,Unit> <- FS.remove(path,False{},False{})
    return unlinked(result)
def afterTrash(+path: String,completion: Child.Completed) -> IO(Result<&2,&2,String,String>):
  match completion:
    case Child.Completed{Done{0},_,_}: IO.pure(Result<&2,&2,String,String>,Done{"Session moved to trash"})
    case _:
      do IO<Result<&2,&2,String,String>>:
        exists : Bool <- FS.accessible(path,0)
        Bool.pick(Unit -> IO(Result<&2,&2,String,String>),exists,_ => unlinkSession(path),_ => IO.pure(Result<&2,&2,String,String>,Done{"Session moved to trash"}))(Unit{})
def removeSession(+path: String) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    environment : List<String> <- IO.environment()
    completion : Child.Completed <- Child.spawnSync("gio",["trash",path],"/",environment,Nil{})
    outcome : Result<&2,&2,String,String> <- afterTrash(path,completion)
    return outcome
def removed(state: State,+path: String,result: Result<&2,&2,String,String>) -> State:
  match state result:
    case State{current,all,+scope,+query,+index,+choice,+controls} Done{message}:
      +newCurrent = withoutPath(current,path)
      +newAll = withoutPath(all,path)
      +remaining = visible(revised(newCurrent,newAll,scope,query,index,choice,controls))
      revised(newCurrent,newAll,scope,query,Nat.min(index,List.length(&2,Session.SessionInfo,remaining) - 1n),choice,withStatus(controls,message))
    case State{current,all,scope,query,index,choice,controls} Fail{message}:
      revised(current,all,scope,query,index,choice,withStatus(controls,message))
def isConfirm(action: Action) -> Bool:
  match action: case Confirm{}: True{} case _: False{}
def deleteFor(state: Ref.Ref<State>,value: State,data: String,bindings: Bindings.KeybindingsManager) -> IO(Bool):
  match value:
    case State{_,_,_,_,_,Pending{},Controls{_,_,_,Some{+path},_}}:
      Bool.pick(Unit -> IO(Bool),isConfirm(action(bindings,data)),_ => do IO<Bool>:
        result : Result<&2,&2,String,String> <- removeSession(path)
        next : Unit <- Ref.modify(State,Unit,state,current => (removed(current,path,result),Unit{}))
        return True{},_ => IO.pure(Bool,False{}))(Unit{})
    case _: IO.pure(Bool,False{})
def deleteIfConfirmed(input: Input,data: String) -> IO(Bool):
  match input:
    case Input{+state,_,_,bindings}:
      do IO<Bool>:
        value : State <- Ref.read(State,state)
        handled : Bool <- deleteFor(state,value,data,bindings)
        return handled

def stateIsAll(state: State) -> Bool:
  match state: case State{_,_,All{},_,_,_,_}: True{} case _: False{}
def resolvedAll(request: Deferred.Deferred<Unit>,all: Bool) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),all,_ => do IO<Unit>:
    resolved : Bool <- Deferred.resolve(Unit,request,Unit{})
    return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})
def requestAll(state: Ref.Ref<State>,request: Deferred.Deferred<Unit>,selected: Action) -> IO(Unit):
  match selected:
    case SwitchScope{}:
      do IO<Unit>:
        current : State <- Ref.read(State,state)
        resolvedAll(request,stateIsAll(current))
    case _: IO.pure(Unit,Unit{})

def receivedShared(input: Input,+data: String) -> IO(Unit):
  match input:
    case Input{+state,+stop,+allRequested,+bindings}:
      do IO<Unit>:
        deleted : Bool <- deleteIfConfirmed(Input{state,stop,allRequested,bindings},data)
        Bool.pick(Unit -> IO(Unit),deleted,_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
          done : Bool <- Ref.modify(State,Bool,state,current => transition(current,data,bindings))
          requestAll(state,allRequested,action(bindings,data))
          Bool.pick(Unit -> IO(Unit),done,_ => do IO<Unit>:
            resolved : Bool <- Deferred.resolve(Unit,stop,Unit{})
            return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{})
def received(input: Input,data: String) -> IO(Unit): receivedShared(input,data)

def made(state: Ref.Ref<State>,loads: Ref.Ref<Loads>,stop: Deferred.Deferred<Unit>,allRequested: Deferred.Deferred<Unit>,+render: Callback.Callback<Nat,List<&2,String>>,+input: Callback.Callback<String,Unit>,+invalidate: Callback.Callback<Unit,Unit>,+focus: Callback.Callback<Bool,Unit>) -> Owner:
  Owner{state,loads,stop,allRequested,Component.Component{Component.ComponentId{1n},render,Some{input},None{},invalidate,Some{focus},False{}},render,input,invalidate,focus}
def formattedFirst(keys: List<&2,Keys.KeyId>,name: String) -> String:
  match keys:
    case Nil{}: name
    case key <> _: Keys.formatKeyId(key)
def firstKey(bindings: Bindings.KeybindingsManager,+name: String) -> String:
  formattedFirst(Bindings.getKeys(bindings,name),name)
def normalHint(+bindings: Bindings.KeybindingsManager) -> String:
  firstKey(bindings,"tui.input.tab") ++ " scope · " ++ firstKey(bindings,"app.session.toggleSort") ++ " sort · " ++
  firstKey(bindings,"app.session.toggleNamedFilter") ++ " named · " ++ firstKey(bindings,"app.session.togglePath") ++ " path · " ++
  firstKey(bindings,"app.session.delete") ++ " delete · ↑↓ move · " ++ firstKey(bindings,"tui.select.confirm") ++ " open · " ++ firstKey(bindings,"tui.select.cancel") ++ " cancel"
def deleteHint(+bindings: Bindings.KeybindingsManager) -> String:
  firstKey(bindings,"tui.select.confirm") ++ " confirm · " ++ firstKey(bindings,"tui.select.cancel") ++ " cancel"
def create(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,+bindings: Bindings.KeybindingsManager) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<State> <- Ref.new(State,State{current,all,Current{},"",0n,Pending{},Controls{Threaded{},False{},False{},None{},None{}}})
    +loads : Ref.Ref<Loads> <- Ref.new(Loads,Loads{Some{Count{0n,0n}},Some{Count{0n,0n}}})
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +allRequested : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Paint,~Nat,~List<&2,String>,~paint,Paint{state,loads,normalHint(bindings),deleteHint(bindings)})
    +input : Callback.Callback<String,Unit> <- Callback.create(~Input,~String,~Unit,~received,Input{state,stop,allRequested,bindings})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Unit,~Bool,~Unit,~ignoreFocus,Unit{})
    return made(state,loads,stop,allRequested,render,input,invalidate,focus)

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
    case Owner{state,loads,stop,allRequested,_,render,input,invalidate,focus}:
      do IO<Outcome()>:
        final : State <- Ref.dispose(State,state)
        oldLoads : Loads <- Ref.dispose(Loads,loads)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
        Deferred.dispose(Unit,allRequested)
        Deferred.dispose(Unit,stop)
        return settled(outcome,final)

type LoadContext is Data:
  LoadContext{cwd: String,sessionDir: Maybe<&2,String>,agentDir: String,sessionsDir: String}
type ProgressInput is Data:
  ProgressInput{state: Ref.Ref<State>,loads: Ref.Ref<Loads>,request: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,scope: Scope}
def findIndex(items: List<&2,Session.SessionInfo>,+path: String,+index: Nat) -> Maybe<&2,Nat>:
  match items:
    case Nil{}: None{}
    case info <> rest: Bool.pick(Maybe<&2,Nat>,Strings.equal(infoPath(info),path),Some{index},findIndex(rest,path,index + 1n))
def retainedPrevious(previous: Maybe<&2,Session.SessionInfo>,+next: State,position: Nat) -> Nat:
  match previous:
    case None{}: 0n
    case Some{info}: Maybe.default(&2,Nat,findIndex(visible(next),infoPath(info),0n),Nat.min(position,List.length(&2,Session.SessionInfo,visible(next)) - 1n))
def retainedIndex(previous: Maybe<&2,Session.SessionInfo>,+next: State,+position: Nat) -> Nat:
  Bool.pick(Unit -> Nat,Nat.is_eq(position,0n),_ => 0n,_ => retainedPrevious(previous,next,position))(Unit{})
def changedSessions(state: State,scope: Scope,+sessions: List<&2,Session.SessionInfo>) -> State:
  match state scope:
    case State{+current,+all,+activeScope,+query,+index,+choice,+controls} Current{}:
      +previous = List.get(&2,Session.SessionInfo,visible(State{current,all,activeScope,query,index,choice,controls}),index)
      +updated = {State{sessions,all,activeScope,query,index,choice,controls} : State}
      State{sessions,all,activeScope,query,retainedIndex(previous,updated,index),choice,controls}
    case State{+current,+all,+activeScope,+query,+index,+choice,+controls} All{}:
      +previous = List.get(&2,Session.SessionInfo,visible(State{current,all,activeScope,query,index,choice,controls}),index)
      +updated = {State{current,sessions,activeScope,query,index,choice,controls} : State}
      State{current,sessions,activeScope,query,retainedIndex(previous,updated,index),choice,controls}
def counted(loads: Loads,scope: Scope,count: Maybe<&2,Count>) -> Loads:
  match loads scope:
    case Loads{_,all} Current{}: Loads{count,all}
    case Loads{current,_} All{}: Loads{current,count}
def requestedProgress(callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ready}: Callback.call(Unit,Unit,ready,Unit{})
def requestProgress(request: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    callback : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Unit,Unit>>,request)
    requestedProgress(callback)
def partialProgress(state: Ref.Ref<State>,scope: Scope,sessions: Maybe<&2,List<&2,Session.SessionInfo>>) -> IO(Unit):
  match sessions:
    case None{}: IO.pure(Unit,Unit{})
    case Some{items}: Ref.modify(State,Unit,state,old => (changedSessions(old,scope,items),Unit{}))
def progress(input: ProgressInput,update: Persistence.ListProgress) -> IO(Unit):
  match input update:
    case ProgressInput{state,loads,request,+scope} Persistence.ListProgress{loaded,total,sessions}:
      do IO<Unit>:
        partialProgress(state,scope,sessions)
        Ref.modify(Loads,Unit,loads,old => (counted(old,scope,Some{Count{loaded,total}}),Unit{}))
        requestProgress(request)
def completedLoad(input: ProgressInput,sessions: List<&2,Session.SessionInfo>) -> IO(Unit):
  match input:
    case ProgressInput{state,loads,request,+scope}:
      do IO<Unit>:
        Ref.modify(State,Unit,state,old => (changedSessions(old,scope,sessions),Unit{}))
        Ref.modify(Loads,Unit,loads,old => (counted(old,scope,None{}),Unit{}))
        requestProgress(request)
def readyRequest(request: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,event: Process.QueryReady) -> IO(Unit):
  match event:
    case Process.QueryReady{_,_,_,redraw}: Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,request,Some{redraw})
type Stopping is Data: Stopping{request: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,cancel: Abort.AbortController<Unit>,allRequested: Deferred.Deferred<Unit>,currentDone: Deferred.Deferred<Unit>,allDone: Deferred.Deferred<Unit>}
def stoppingRequest(context: Stopping,_: Unit) -> IO(Unit):
  match context:
    case Stopping{request,cancel,allRequested,currentDone,allDone}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,request,None{})
        stopped : Bool <- Abort.abort(Unit,cancel,None{})
        woken : Bool <- Deferred.resolve(Unit,allRequested,Unit{})
        Deferred.result(Unit,currentDone)
        Deferred.result(Unit,allDone)
def loadCurrent(context: LoadContext,signal: Abort.AbortSignal<Unit>,current: ProgressInput,callback: Callback.Callback<Persistence.ListProgress,Unit>) -> IO(Unit):
  match context:
    case LoadContext{cwd,sessionDir,agentDir,_}:
      do IO<Unit>:
        sessions : List<&2,Session.SessionInfo> <- Persistence.listProgress(cwd,sessionDir,agentDir,signal,callback)
        completedLoad(current,sessions)
def loadRequested(context: LoadContext,+signal: Abort.AbortSignal<Unit>,request: Deferred.Deferred<Unit>,all: ProgressInput,callback: Callback.Callback<Persistence.ListProgress,Unit>) -> IO(Unit):
  match context:
    case LoadContext{_,sessionDir,_,sessionsDir}:
      do IO<Unit>:
        wake : Unit <- Deferred.result(Unit,request)
        cancelled : Bool <- Abort.aborted(Unit,signal)
        Bool.pick(Unit -> IO(Unit),cancelled,_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
          everything : List<&2,Session.SessionInfo> <- Persistence.listAllProgress(sessionDir,sessionsDir,signal,callback)
          completedLoad(all,everything))(Unit{})
def currentTask(context: LoadContext,signal: Abort.AbortSignal<Unit>,current: ProgressInput,callback: Callback.Callback<Persistence.ListProgress,Unit>,done: Deferred.Deferred<Unit>) -> IO(Unit):
  do IO<Unit>:
    loadCurrent(context,signal,current,callback)
    settled : Bool <- Deferred.resolve(Unit,done,Unit{})
    return Unit{}
def allTask(context: LoadContext,signal: Abort.AbortSignal<Unit>,request: Deferred.Deferred<Unit>,all: ProgressInput,callback: Callback.Callback<Persistence.ListProgress,Unit>,done: Deferred.Deferred<Unit>) -> IO(Unit):
  do IO<Unit>:
    loadRequested(context,signal,request,all,callback)
    settled : Bool <- Deferred.resolve(Unit,done,Unit{})
    return Unit{}
def loadedProcess(owner: Owner,base: Tui.TuiBase,+context: LoadContext) -> IO(Outcome()):
  match owner:
    case Owner{+state,+loads,+stop,+allRequested,+component,render,input,invalidate,focus}:
      do IO<Outcome()>:
        +request : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
        +current : ProgressInput <- IO.pure(ProgressInput,ProgressInput{state,loads,request,Current{}})
        +all : ProgressInput <- IO.pure(ProgressInput,ProgressInput{state,loads,request,All{}})
        +currentCallback : Callback.Callback<Persistence.ListProgress,Unit> <- Callback.create(~ProgressInput,~Persistence.ListProgress,~Unit,~progress,current)
        +allCallback : Callback.Callback<Persistence.ListProgress,Unit> <- Callback.create(~ProgressInput,~Persistence.ListProgress,~Unit,~progress,all)
        +ready : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,~Process.QueryReady,~Unit,~readyRequest,request)
        +cancel : Abort.AbortController<Unit> <- Abort.new(Unit)
        +currentDone : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        +allDone : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        +stopping : Callback.Callback<Unit,Unit> <- Callback.create(~Stopping,~Unit,~Unit,~stoppingRequest,Stopping{request,cancel,allRequested,currentDone,allDone})
        currentWorker : Chan(Unit) <- IO.fork(Unit,currentTask(context,Abort.signal(Unit,cancel),current,currentCallback,currentDone))
        allWorker : Chan(Unit) <- IO.fork(Unit,allTask(context,Abort.signal(Unit,cancel),allRequested,all,allCallback,allDone))
        outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithLifecycle(Process.active(Process.Session{base,Screen.initial()},[component],[Component.ComponentId{1n}]),stop,False{},ready,stopping)
        aborted : Bool <- Abort.abort(Unit,cancel,None{})
        wake : Bool <- Deferred.resolve(Unit,allRequested,Unit{})
        IO.join(Unit,currentWorker)
        IO.join(Unit,allWorker)
        Deferred.dispose(Unit,currentDone)
        Deferred.dispose(Unit,allDone)
        Abort.dispose(Unit,cancel)
        Callback.dispose(Persistence.ListProgress,Unit,currentCallback)
        Callback.dispose(Persistence.ListProgress,Unit,allCallback)
        Callback.dispose(Process.QueryReady,Unit,ready)
        Callback.dispose(Unit,Unit,stopping)
        oldRequest : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,request)
        finish(Owner{state,loads,stop,allRequested,component,render,input,invalidate,focus},outcome)
def runMounted(owner: Owner,mounted: Tui.ResultOf(Tui.TuiBase),context: LoadContext) -> IO(Outcome()):
  match mounted:
    case Fail{_}: finish(owner,Fail{Terminal.Closed{}})
    case Done{base}: loadedProcess(owner,base,context)
def run(owner: Owner,context: LoadContext) -> IO(Outcome()):
  match owner:
    case Owner{state,loads,stop,allRequested,+component,render,input,invalidate,focus}:
      do IO<Outcome()>:
        mounted : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),[component],[Component.ComponentId{1n}],Some{Component.ComponentId{1n}})
        runMounted(Owner{state,loads,stop,allRequested,component,render,input,invalidate,focus},mounted,context)
def loadedBindings(context: LoadContext,loaded: Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager>) -> IO(Outcome()):
  match loaded:
    case Fail{_}: IO.pure(Outcome(),Fail{"Cannot load session selector keybindings"})
    case Done{AppKeys.KeybindingsManager{bindings,_,_}}:
      do IO<Outcome()>:
        owner : Owner <- create(Nil{},Nil{},bindings)
        run(owner,context)
def selectSession(cwd: String,+sessionDir: Maybe<&2,String>,+agentDir: String,sessionsDir: String) -> IO(Outcome()):
  do IO<Outcome()>:
    bindings : Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager> <- AppKeys.create(AppKeys.Environment{"linux",None{},None{}},agentDir)
    loadedBindings(LoadContext{cwd,sessionDir,agentDir,sessionsDir},bindings)

# The same picker can occupy the interactive editor without starting a second
# terminal process. Both entry points share filtering, ordering and keybindings.
type Modal is Data: Closed{} Open{state: State}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,chosen: Callback.Callback<String,Unit>}
type HostOwner is Type:
  HostOwner{host: Host,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>}
def drawModalCurrent(current: Modal,editor: Component.Component,+bindings: Bindings.KeybindingsManager,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}: IO.pure(List<&2,String>,renderState(state,width,normalHint(bindings),deleteHint(bindings),Loads{None{},None{}}))
def drawModal(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,editor,bindings,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        drawModalCurrent(current,editor,bindings,width)
def afterTransition(modal: Ref.Ref<Modal>,chosen: Callback.Callback<String,Unit>,next: State) -> IO(Unit):
  match next:
    case State{_,_,_,_,_,Chosen{path},_}:
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(String,Unit,chosen,path)
    case State{_,_,_,_,_,Cancelled{},_}: Ref.write(Modal,modal,Closed{})
    case other: Ref.write(Modal,modal,Open{other})
def modalTransitionPair(modal: Ref.Ref<Modal>,chosen: Callback.Callback<String,Unit>,pair: State & Bool) -> IO(Unit):
  match pair:
    case (next,_): afterTransition(modal,chosen,next)
def modalTransition(modal: Ref.Ref<Modal>,bindings: Bindings.KeybindingsManager,chosen: Callback.Callback<String,Unit>,state: State,data: String) -> IO(Unit):
  modalTransitionPair(modal,chosen,transition(state,data,bindings))
def modalDeleteAction(modal: Ref.Ref<Modal>,bindings: Bindings.KeybindingsManager,chosen: Callback.Callback<String,Unit>,state: State,+path: String,data: String,selected: Action) -> IO(Unit):
  match selected:
    case Confirm{}:
      do IO<Unit>:
        result : Result<&2,&2,String,String> <- removeSession(path)
        Ref.write(Modal,modal,Open{removed(state,path,result)})
    case _: modalTransition(modal,bindings,chosen,state,data)
def receivedModalOpen(modal: Ref.Ref<Modal>,+bindings: Bindings.KeybindingsManager,chosen: Callback.Callback<String,Unit>,+state: State,+data: String) -> IO(Unit):
  match state:
    case State{_,_,_,_,_,Pending{},Controls{_,_,_,Some{+path},_}}:
      modalDeleteAction(modal,bindings,chosen,state,path,data,action(bindings,data))
    case _: modalTransition(modal,bindings,chosen,state,data)
def receivedModalCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,chosen: Callback.Callback<String,Unit>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}: receivedModalOpen(modal,bindings,chosen,state,data)
def receivedModal(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,bindings,handler}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receivedModalCurrent(current,modal,editor,bindings,handler,data)
def mouseCurrent(current: Modal,mouse: Maybe<&2,Callback.Callback<Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>>,event: Ui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current mouse:
    case Closed{} Some{callback}: Callback.call(Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _ _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def modalMouse(host: Host,event: Ui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{+modal,Component.Component{_,_,_,mouse,_,_,_},_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,mouse,event)
def modalInvalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_}: Component.invalidate(editor)
def modalFocus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_}: Component.setFocused(editor,value)
def createHost(+editor: Component.Component,bindings: Bindings.KeybindingsManager,chosen: Callback.Callback<String,Unit>) -> IO(HostOwner):
  do IO<HostOwner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    +host : Host <- IO.pure(Host,Host{modal,editor,bindings,chosen})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~drawModal,host)
    +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receivedModal,host)
    +mouse : Callback.Callback<Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Ui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~modalMouse,host)
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~modalInvalidate,host)
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~modalFocus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),render,Some{input},Some{mouse},invalidate,Some{focus},False{}})
    return HostOwner{host,component,render,input,mouse,invalidate,focus}
def borrowHost(owner: HostOwner) -> HostOwner & Host & Component.Component:
  match owner: case HostOwner{+host,+component,render,input,mouse,invalidate,focus}: (HostOwner{host,component,render,input,mouse,invalidate,focus},host,component)
def openHost(host: Host,current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>) -> IO(Unit):
  match host:
    case Host{modal,_,_,_}: Ref.write(Modal,modal,Open{State{current,all,Current{},"",0n,Pending{},Controls{Threaded{},False{},False{},None{},None{}}}})
def disposeHost(owner: HostOwner) -> IO(Unit):
  match owner:
    case HostOwner{Host{modal,_,_,_},_,render,input,mouse,invalidate,focus}:
      do IO<Unit>:
        discarded : Modal <- Ref.dispose(Modal,modal)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)

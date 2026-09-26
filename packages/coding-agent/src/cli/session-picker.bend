import Base
import ../modes/interactive/components/keybinding-hints.bend as Hints
import ../../../runtime/src/stable-sort.bend as StableSort
import ../core/tools/index.bend as Tools
import ../../../runtime/src/schema-value.bend as V
import ../core/session-manager.bend as Session
import ../core/session-persistence.bend as Persistence
import ../core/agent-session.bend as AgentSession
import ../../../ai/src/utils/uuid.bend as Uuid
import ../core/keybindings.bend as AppKeys
import ../modes/interactive/theme/theme.bend as Theme
import ../modes/interactive/theme/color.bend as Color
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/child-process.bend as Child
import ../../../runtime/src/regex.bend as Regex
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/word-segmenter.bend as Words
import ../../../tui/src/component.bend as Component
import ../../../tui/src/components/input.bend as SearchInput
import ../../../tui/src/keys.bend as Keys
import ../../../tui/src/keybindings.bend as Bindings
import ../../../tui/src/word-navigation.bend as Word
import ../../../tui/src/fuzzy.bend as Fuzzy
import ../../../tui/src/tui-base.bend as Tui
import ../../../tui/src/tui.bend as Ui
import ../../../tui/src/tui-main-screen.bend as Screen
import ../../../tui/src/tui-process.bend as Process
import ../../../tui/src/terminal.bend as Terminal
import ../../../tui/src/utils.bend as Utils
import ../../../tui/src/terminal-image.bend as Image

# The startup picker has one focusable component. The TUI process owns raw
# terminal state and ordered redraws; this state owns only selection semantics.
type Choice is Data: Pending{} Cancelled{} Chosen{path: String}
type Scope is Data: Current{} All{}
type Sort is Data: Threaded{} Recent{} Relevance{}
type StatusMessage is Data: Info{text: String} Error{text: String}
type Controls is Data: Controls{sort: Sort,named: Bool,showPath: Bool,deleting: Maybe<&2,String>,status: Maybe<&2,StatusMessage>,active: List<&2,String>}
type Action is Data:
  Cancel{} Confirm{} SwitchScope{} SwitchSort{} SwitchNamed{} TogglePath{} Delete{} DeleteAlias{} Rename{} MoveUp{} MoveDown{} PageUp{} PageDown{} Edit{data: String}
type State is Data:
  State{current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: SearchInput.Input,index: Nat,choice: Choice,controls: Controls}
type Count is Data: Starting{} Count{loaded: Nat,total: Nat}
type Loads is Data: Loads{current: Maybe<&2,Count>,all: Maybe<&2,Count>}
type Input is Data:
  Input{state: Ref.Ref<State>,stop: Deferred.Deferred<Unit>,allRequested: Deferred.Deferred<Unit>,bindings: Bindings.KeybindingsManager,words: Ref.Ref<Words.Source>}
type Paint is Data: Paint{state: Ref.Ref<State>,loads: Ref.Ref<Loads>,bindings: Bindings.KeybindingsManager,theme: Theme.Theme}
type Visual is Data: Visual{themeName: Maybe<&2,String>,assetsRoot: String,agentDir: String,home: String,trueColor: Maybe<&2,Bool>}
def assetsOf(visual: Visual) -> String:
  match visual: case Visual{_,assets,_,_,_}: assets
type Owner is Data:
  Owner{state: Ref.Ref<State>,loads: Ref.Ref<Loads>,words: Ref.Ref<Words.Source>,stop: Deferred.Deferred<Unit>,allRequested: Deferred.Deferred<Unit>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>}
def Outcome() -> Data: Result<&2,&2,String,Maybe<&2,String>>
def queryText(query: SearchInput.Input) -> String: SearchInput.getValue(query)
def newQuery() -> SearchInput.Input: SearchInput.setFocused(SearchInput.new(None{}),True{})

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
type SessionTreeNode is Data:
  SessionTreeNode{session: Session.SessionInfo,children: List<&2,SessionTreeNode>,latestActivity: F64}
def newestNode(left: SessionTreeNode,right: SessionTreeNode) -> Bool:
  match left right:
    case SessionTreeNode{_,_,a} SessionTreeNode{_,_,b}: F64.is_ge(a,b)
def nodeActivity(nodes: List<&2,SessionTreeNode>,latest: F64) -> F64:
  match nodes:
    case Nil{}: latest
    case SessionTreeNode{_,_,stamp} <> rest: nodeActivity(rest,F64.max(latest,stamp))
def indexedSessions(items: List<&2,Session.SessionInfo>,index: Map<&2,Maybe<&2,Session.SessionInfo>>) -> Map<&2,Maybe<&2,Session.SessionInfo>>:
  match items:
    case Nil{}: index
    case +info <> rest: indexedSessions(rest,Map.set(&2,Maybe<&2,Session.SessionInfo>,index,infoPath(info),Some{info}))
def mapValue(-A: Data,pair: Map<&2,A> & A) -> A:
  match pair: case (_,value): value
def indexedChildren(items: List<&2,Session.SessionInfo>,+index: Map<&2,List<&2,String>>) -> Map<&2,List<&2,String>>:
  match items:
    case Nil{}: index
    case +info <> rest:
      +next = Maybe.map(&2,String,Map<&2,List<&2,String>>,+parent => Map.set(&2,List<&2,String>,index,parent,infoPath(info) <> mapValue(List<&2,String>,Map.get(List<&2,String>,Nil{},index,parent))),parentPath(info))
      indexedChildren(rest,Maybe.default(&2,Map<&2,List<&2,String>>,next,index))
def rankedTree(fuel: Nat,paths: List<&2,String>,+index: Map<&2,Maybe<&2,Session.SessionInfo>>,+edges: Map<&2,List<&2,String>>) -> List<&2,SessionTreeNode>:
  match fuel paths:
    case Zero{} _: Nil{}
    case _ Nil{}: Nil{}
    case Succ{+left} +path <> rest:
      +found = mapValue(Maybe<&2,Session.SessionInfo>,Map.get(Maybe<&2,Session.SessionInfo>,None{},index,path))
      +children = StableSort.sort(~SessionTreeNode,~newestNode,rankedTree(left,List.reverse(&2,String,mapValue(List<&2,String>,Map.get(List<&2,String>,Nil{},edges,path))),index,edges))
      +node = Maybe.map(&2,Session.SessionInfo,List<&2,SessionTreeNode>,+info => SessionTreeNode{info,children,nodeActivity(children,Persistence.infoModified(info))} <> Nil{},found)
      List.append(&2,SessionTreeNode,Maybe.default(&2,List<&2,SessionTreeNode>,node,Nil{}),rankedTree(left,rest,index,edges))
def rootPaths(items: List<&2,Session.SessionInfo>,+index: Map<&2,Maybe<&2,Session.SessionInfo>>) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest:
      +parent = Maybe.bind(&2,String,Session.SessionInfo,parentPath(info),path => mapValue(Maybe<&2,Session.SessionInfo>,Map.get(Maybe<&2,Session.SessionInfo>,None{},index,path)))
      Bool.pick(Unit -> List<&2,String>,Maybe.is_none(&2,Session.SessionInfo,parent),_ => infoPath(info) <> rootPaths(rest,index),_ => rootPaths(rest,index))(Unit{})
@unsafe def flattenedTree(nodes: List<&2,SessionTreeNode>,reversed: List<&2,Session.SessionInfo>) -> List<&2,Session.SessionInfo>:
  match nodes:
    case Nil{}: reversed
    case SessionTreeNode{info,children,_} <> rest: flattenedTree(rest,flattenedTree(children,info <> reversed))
def threaded(+items: List<&2,Session.SessionInfo>) -> List<&2,Session.SessionInfo>:
  +index = indexedSessions(items,Map.new(&2,Maybe<&2,Session.SessionInfo>))
  +edges = indexedChildren(items,Map.new(&2,List<&2,String>))
  +tree = StableSort.sort(~SessionTreeNode,~newestNode,rankedTree(List.length(&2,Session.SessionInfo,items) + 1n,rootPaths(items,index),index,edges))
  List.reverse(&2,Session.SessionInfo,flattenedTree(tree,Nil{}))
def sortLabel(sort: Sort) -> String:
  match sort: case Threaded{}: "Threaded" case Recent{}: "Recent" case Relevance{}: "Fuzzy"
def threadedMode(sort: Sort,query: String) -> Bool:
  match sort:
    case Threaded{}: String.is_empty(String.trim(query))
    case _: False{}
def nextSort(sort: Sort) -> Sort:
  match sort: case Threaded{}: Recent{} case Recent{}: Relevance{} case Relevance{}: Threaded{}
def cycledSort(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,path,_,status,active}: Controls{nextSort(sort),namedFilter,path,None{},status,active}
def toggledNamed(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,path,_,status,active}: Controls{sort,Bool.not(namedFilter),path,None{},status,active}
def toggledPath(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,path,_,status,active}: Controls{sort,namedFilter,Bool.not(path),None{},status,active}
def confirming(controls: Controls,path: String) -> Controls:
  match controls: case Controls{sort,namedFilter,showPath,_,status,active}: Controls{sort,namedFilter,showPath,Some{path},status,active}
def cleared(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,showPath,_,status,active}: Controls{sort,namedFilter,showPath,None{},status,active}
def dismissed(controls: Controls) -> Controls:
  match controls: case Controls{sort,namedFilter,showPath,_,_,active}: Controls{sort,namedFilter,showPath,None{},None{},active}
def withStatus(controls: Controls,message: StatusMessage) -> Controls:
  match controls: case Controls{sort,namedFilter,showPath,_,status,active}: Controls{sort,namedFilter,showPath,None{},Some{message},active}
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
    case State{current,all,scope,query,_,_,Controls{sort,namedFilter,_,_,_,_}}:
      +items = scopeSessions(current,all,scope)
      arranged(namedOnly(items,namedFilter),queryText(query),sort)

def safeText(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{+char,rest}:
      +point = U32.to_nat(Char.to_u32(char))
      Bool.pick(String,Nat.is_lt(point,32n) || Nat.is_eq(point,127n)," ",SCon{char,SNil{}}) ++ safeText(rest)
def shortened(+path: String,+home: String) -> String:
  Bool.pick(String,Bool.not(String.is_empty(home)) && String.starts_with(path,home),"~" ++ String.drop(path,String.length(home)),path)
def age(modified: F64,now: F64) -> String:
  +elapsed = F64.max(U32.to_f64(0),F64.sub(now,modified))
  +minutes = F64.to_u32(F64.floor(F64.div(elapsed,U32.to_f64(60000))))
  Bool.pick(Unit -> String,U32.is_lt(minutes,1),_ => "now",
    _ => Bool.pick(Unit -> String,U32.is_lt(minutes,60),_ => U32.show(minutes) ++ "m",
      _ => Bool.pick(Unit -> String,U32.is_lt(minutes,1440),_ => U32.show(U32.div(minutes,60)) ++ "h",
        _ => Bool.pick(Unit -> String,U32.is_lt(minutes,10080),_ => U32.show(U32.div(minutes,1440)) ++ "d",
          _ => Bool.pick(Unit -> String,U32.is_lt(minutes,43200),_ => U32.show(U32.div(minutes,10080)) ++ "w",
            _ => Bool.pick(String,U32.is_lt(minutes,525600),U32.show(U32.div(minutes,43200)) ++ "mo",U32.show(U32.div(minutes,525600)) ++ "y"))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def infoText(info: Session.SessionInfo) -> String:
  match info:
    case Session.SessionInfo{_,_,_,name,_,_,_,_,first,_}: String.trim(safeText(Maybe.default(&2,String,name,first)))
def infoRight(info: Session.SessionInfo,all: Bool,showPath: Bool,now: F64,+home: String) -> String:
  match info:
    case Session.SessionInfo{path,_,+cwd,_,_,_,modified,count,_,_}:
      Bool.pick(String,showPath,shortened(path,home) ++ " ","") ++ Bool.pick(String,all && Bool.not(String.is_empty(cwd)),shortened(cwd,home) ++ " ","") ++ Nat.show(count) ++ " " ++ age(modified,now)

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
def hasVisibleParent(value: Maybe<&2,String>,items: List<&2,Session.SessionInfo>) -> Bool:
  match value: case None{}: False{} case Some{path}: hasPath(items,path)
def ancestorFlags(fuel: Nat,parent: Maybe<&2,String>,+items: List<&2,Session.SessionInfo>,+flags: List<&2,Bool>) -> List<&2,Bool>:
  match fuel parent:
    case Zero{} _: flags
    case _ None{}: flags
    case Succ{left} Some{path}:
      Maybe.default(&2,List<&2,Bool>,Maybe.map(&2,Session.SessionInfo,List<&2,Bool>,+info => ancestorFlags(left,parentPath(info),items,(hasVisibleParent(parentPath(info),items) && Bool.not(isLast(info,items))) <> flags),findPath(items,path)),flags)
def rails(flags: List<&2,Bool>) -> String:
  match flags:
    case Nil{}: ""
    case True{} <> rest: "│  " ++ rails(rest)
    case False{} <> rest: "   " ++ rails(rest)
def prefixFor(parent: Maybe<&2,String>,info: Session.SessionInfo,+items: List<&2,Session.SessionInfo>) -> String:
  match parent:
    case None{}: ""
    case Some{+path}:
      Bool.pick(Unit -> String,hasPath(items,path),
        _ => rails(ancestorFlags(List.length(&2,Session.SessionInfo,items),Some{path},items,Nil{})) ++ Bool.pick(String,isLast(info,items),"└─ ","├─ "),
        _ => "")(Unit{})
def treePrefix(+info: Session.SessionInfo,items: List<&2,Session.SessionInfo>) -> String:
  prefixFor(parentPath(info),info,items)

def selectedBackground(+theme: Theme.Theme,+line: String,selected: Bool) -> String:
  Bool.pick(String,selected,Result.default(&2,&2,Theme.Error,String,Theme.background(theme,"selectedBg",line),line),line)
def hasName(info: Session.SessionInfo) -> Bool:
  match info:
    case Session.SessionInfo{_,_,_,name,_,_,_,_,_,_}: Bool.not(String.is_empty(Maybe.default(&2,String,name,"")))
def label(+info: Session.SessionInfo,index: Nat,chosen: Nat,all: Bool,thread: Bool,showPath: Bool,items: List<&2,Session.SessionInfo>,+width: Nat,now: F64,home: String,+theme: Theme.Theme,+deleting: Maybe<&2,String>,active: List<&2,String>) -> String:
  +prefix = Bool.pick(String,thread,treePrefix(info,items),"")
  +right = infoRight(info,all,showPath,now,home)
  +available = width - 2n - Utils.visibleWidth(prefix) - Utils.visibleWidth(right) - 2n
  +selected = Nat.is_eq(index,chosen)
  +title = Utils.truncateToWidth(infoText(info),Nat.max(10n,available),"…",False{})
  +confirming = matchesParent(deleting,infoPath(info))
  +current = visited(active,infoPath(info))
  +namedTitle = Bool.pick(String,confirming,Theme.fg(theme,"error",title),Bool.pick(String,current,Theme.fg(theme,"accent",title),Bool.pick(String,hasName(info),Theme.fg(theme,"warning",title),title)))
  +styledTitle = Bool.pick(String,selected,Theme.bold(namedTitle),namedTitle)
  +left = Bool.pick(String,selected,Theme.fg(theme,"accent","› "),"  ") ++ Theme.fg(theme,"dim",prefix) ++ styledTitle
  +line = left ++ Utils.spaces(Nat.max(1n,width - Utils.visibleWidth(left) - Utils.visibleWidth(right)),"") ++ Theme.fg(theme,Bool.pick(String,confirming,"error","dim"),right)
  Utils.truncateToWidth(selectedBackground(theme,line,selected),width,"...",False{})

def listLines(items: List<&2,Session.SessionInfo>,+index: Nat,+chosen: Nat,+all: Bool,+thread: Bool,+showPath: Bool,+allItems: List<&2,Session.SessionInfo>,+width: Nat,+now: F64,+home: String,+theme: Theme.Theme,+deleting: Maybe<&2,String>,+active: List<&2,String>,count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match items count:
    case _ Zero{}: List.reverse(&2,String,reversed)
    case Nil{} _: List.reverse(&2,String,reversed)
    case +info <> rest Succ{left}: listLines(rest,index + 1n,chosen,all,thread,showPath,allItems,width,now,home,theme,deleting,active,left,label(info,index,chosen,all,thread,showPath,allItems,width,now,home,theme,deleting,active) <> reversed)

def windowStart(items: List<&2,Session.SessionInfo>,selected: Nat) -> Nat:
  Nat.min(selected - 5n,List.length(&2,Session.SessionInfo,items) - 10n)
def scopeHint(+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager) -> String:
  Hints.keyHint(theme,bindings,"tui.input.tab","scope") ++ Theme.fg(theme,"muted"," · ") ++ Theme.fg(theme,"muted","re:<pattern> regex · \"phrase\" exact")
def normalHint(+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,showPath: Bool,canRename: Bool) -> String:
  +separator = Theme.fg(theme,"muted"," · ")
  Hints.keyHint(theme,bindings,"app.session.toggleSort","sort") ++ separator ++
  Hints.keyHint(theme,bindings,"app.session.toggleNamedFilter","named") ++ separator ++
  Hints.keyHint(theme,bindings,"app.session.delete","delete") ++ separator ++
  Hints.keyHint(theme,bindings,"app.session.togglePath","path" ++ Bool.pick(String,showPath," (on)"," (off)")) ++
  Bool.pick(String,canRename,separator ++ Hints.keyHint(theme,bindings,"app.session.rename","rename"),"")
def deleteHint(+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager) -> String:
  Hints.keyHint(theme,bindings,"tui.select.confirm","confirm") ++ " · " ++ Hints.keyHint(theme,bindings,"tui.select.cancel","cancel")
def hintMessage(message: Maybe<&2,StatusMessage>,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,showPath: Bool,canRename: Bool) -> String & String:
  match message:
    case Some{Info{value}}: (Theme.fg(theme,"accent",value),"")
    case Some{Error{value}}: (Theme.fg(theme,"error",value),"")
    case None{}: (scopeHint(theme,bindings),normalHint(theme,bindings,showPath,canRename))
def hintLines(deleting: Maybe<&2,String>,status: Maybe<&2,StatusMessage>,problem: Maybe<&2,String>,+theme: Theme.Theme,bindings: Bindings.KeybindingsManager,showPath: Bool,canRename: Bool) -> String & String:
  match deleting:
    case Some{_}: (Theme.fg(theme,"error","Delete session? " ++ deleteHint(theme,bindings)),"")
    case None{}: hintMessage(Maybe.or(&2,StatusMessage,Maybe.map(&2,String,StatusMessage,text => Error{text},problem),status),theme,bindings,showPath,canRename)
def countHint(count: Maybe<&2,Count>) -> Maybe<&2,String>:
  match count:
    case None{}: None{}
    case Some{Starting{}}: Some{"Loading ..."}
    case Some{Count{loaded,total}}: Some{"Loading " ++ Nat.show(loaded) ++ "/" ++ Nat.show(total)}
def loadingHint(scope: Scope,loads: Loads) -> Maybe<&2,String>:
  match scope loads:
    case Current{} Loads{current,_}: countHint(current)
    case All{} Loads{_,all}: countHint(all)
def emptyRow(+all: Bool,namedFilter: Bool,+theme: Theme.Theme,bindings: Bindings.KeybindingsManager,width: Nat) -> List<&2,String>:
  +toggle = Hints.keyText(bindings,"app.session.toggleNamedFilter")
  +message = Bool.pick(String,namedFilter,
    Bool.pick(String,all,"  No named sessions found. Press " ++ toggle ++ " to show all.","  No named sessions in current folder. Press " ++ toggle ++ " to show all, or Tab to view all."),
    Bool.pick(String,all,"  No sessions found","  No sessions in current folder. Press Tab to view all."))
  [Theme.fg(theme,"muted",Utils.truncateToWidth(message,width,"…",False{}))]
def rule(width: Nat) -> String:
  match width:
    case Zero{}: ""
    case Succ{rest}: "─" ++ rule(rest)
def idleScope(scope: Scope,+theme: Theme.Theme) -> String:
  match scope:
    case Current{}: Theme.fg(theme,"accent","◉ Current Folder") ++ Theme.fg(theme,"muted"," | ○ All")
    case All{}: Theme.fg(theme,"muted","○ Current Folder | ") ++ Theme.fg(theme,"accent","◉ All")
def scopeLabel(scope: Scope,loading: Maybe<&2,String>,+theme: Theme.Theme) -> String:
  match loading:
    case Some{progress}: Theme.fg(theme,"muted","○ Current Folder | ") ++ Theme.fg(theme,"accent",progress)
    case None{}: idleScope(scope,theme)
def heading(+scope: Scope,sort: Sort,namedFilter: Bool,loading: Maybe<&2,String>,+width: Nat,+theme: Theme.Theme) -> String:
  +left = Theme.bold(Bool.pick(String,isAll(scope),"Resume Session (All)","Resume Session (Current Folder)"))
  +right = scopeLabel(scope,loading,theme) ++ "  " ++ Theme.fg(theme,"muted","Name: ") ++ Theme.fg(theme,"accent",Bool.pick(String,namedFilter,"Named","All")) ++ "  " ++ Theme.fg(theme,"muted","Sort: ") ++ Theme.fg(theme,"accent",sortLabel(sort))
  +fitted = Utils.truncateToWidth(right,width,"",False{})
  +title = Utils.truncateToWidth(left,width - Utils.visibleWidth(fitted) - 1n,"",False{})
  title ++ Utils.spaces(width - Utils.visibleWidth(title) - Utils.visibleWidth(fitted),"") ++ fitted
def scrollLine(+start: Nat,count: Nat,+total: Nat,selected: Nat,+theme: Theme.Theme) -> List<&2,String>:
  Bool.pick(List<&2,String>,Nat.is_gt(start,0n) || Nat.is_lt(start + count,total),[Theme.fg(theme,"muted","  (" ++ Nat.show(selected + 1n) ++ "/" ++ Nat.show(total) ++ ")")],Nil{})
def hintRows(hints: String & String,+width: Nat) -> List<&2,String>:
  match hints:
    case (first,second): [Utils.truncateToWidth(first,width,"…",False{}),Utils.truncateToWidth(second,width,"…",False{})]
def renderedQuery(pair: SearchInput.Input & List<&2,String>) -> List<&2,String>:
  match pair: case (_,lines): lines
def renderState(+state: State,+width: Nat,+bindings: Bindings.KeybindingsManager,+theme: Theme.Theme,loads: Loads,now: F64,home: String,canRename: Bool) -> IO(List<&2,String>):
  match state:
    case State{_,_,scope,query,index,_,Controls{sort,namedFilter,showPath,+deleting,status,+active}}:
      +items = visible(state)
      +all = isAll(scope)
      +start = windowStart(items,index)
      +total = List.length(&2,Session.SessionInfo,items)
      +text = queryText(query)
      +thread = threadedMode(sort,text)
      +loading = loadingHint(scope,loads)
      +body = Bool.pick(List<&2,String>,List.is_empty(&2,Session.SessionInfo,items),emptyRow(all,namedFilter,theme,bindings,width),
        List.append(&2,String,listLines(List.drop(&2,Session.SessionInfo,items,start),start,index,all,thread,showPath,items,width,now,home,theme,deleting,active,10n,Nil{}),scrollLine(start,Nat.min(total - start,10n),total,index,theme)))
      do IO<List<&2,String>>:
        input : SearchInput.Input & List<&2,String> <- SearchInput.render(query,width)
        return List.concat(&2,String,[["",Theme.fg(theme,"accent",rule(width)),"",heading(scope,sort,namedFilter,loading,width,theme)],
          hintRows(hintLines(deleting,status,searchProblem(parsedSearch(text)),theme,bindings,showPath,canRename),width),
          [""],renderedQuery(input),[""],body,["",Theme.fg(theme,"accent",rule(width))]])

def paint(environment: Paint,width: Nat) -> IO(List<&2,String>):
  match environment:
    case Paint{state,loads,bindings,theme}:
      do IO<List<&2,String>>:
        value : State <- Ref.read(State,state)
        loading : Loads <- Ref.read(Loads,loads)
        now : F64 <- Date.now()
        home : Result<&2,&2,FS.Error,String> <- FS.homedir()
        renderState(value,width,bindings,theme,loading,now,Result.default(&2,&2,FS.Error,String,home,""),False{})
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def ignoreFocus(_: Unit,_: Bool) -> IO(Unit): IO.pure(Unit,Unit{})

def chosenAt(found: Maybe<&2,Session.SessionInfo>) -> Choice:
  match found:
    case None{}: Pending{}
    case Some{info}: Chosen{infoPath(info)}
def chosen(items: List<&2,Session.SessionInfo>,index: Nat) -> Choice:
  chosenAt(List.get(&2,Session.SessionInfo,items,index))

type Binding is Data: Binding{name: String,action: Action}
def selectorBindings() -> List<&2,Binding>:
  [Binding{"tui.select.cancel",Cancel{}},Binding{"tui.select.confirm",Confirm{}},Binding{"tui.input.tab",SwitchScope{}},
   Binding{"app.session.toggleSort",SwitchSort{}},Binding{"app.session.toggleNamedFilter",SwitchNamed{}},
   Binding{"app.session.togglePath",TogglePath{}},Binding{"app.session.delete",Delete{}},
   Binding{"app.session.deleteNoninvasive",DeleteAlias{}},Binding{"app.session.rename",Rename{}},Binding{"tui.select.up",MoveUp{}},
   Binding{"tui.select.down",MoveDown{}},Binding{"tui.select.pageUp",PageUp{}},Binding{"tui.select.pageDown",PageDown{}}]
def bound(items: List<&2,Binding>,+bindings: Bindings.KeybindingsManager,+data: String) -> Maybe<&2,Action>:
  match items:
    case Nil{}: None{}
    case Binding{name,action} <> rest:
      Bool.pick(Unit -> Maybe<&2,Action>,Bindings.matches(bindings,Keys.defaults(),data,name),_ => Some{action},_ => bound(rest,bindings,data))(Unit{})
def action(+bindings: Bindings.KeybindingsManager,+data: String) -> Action:
  Maybe.default(&2,Action,bound(selectorBindings(),bindings,data),Edit{data})

def revised(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: SearchInput.Input,index: Nat,choice: Choice,controls: Controls) -> State:
  State{current,all,scope,query,index,choice,controls}
def toggled(scope: Scope) -> Scope:
  match scope: case Current{}: All{} case All{}: Current{}
def advanced(+index: Nat,count: Nat,down: Bool) -> Nat:
  match count:
    case Zero{}: 0n
    case Succ{last}: Bool.pick(Nat,down,Nat.min(index + 1n,last),Bool.pick(Nat,Nat.is_eq(index,0n),0n,index - 1n))

def selected(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: SearchInput.Input,index: Nat,choice: Choice,controls: Controls) -> State & Bool:
  match choice:
    case Pending{}: (revised(current,all,scope,query,index,Pending{},controls),False{})
    case value: (revised(current,all,scope,query,index,value,dismissed(controls)),True{})
def deleteControls(+controls: Controls,+path: String) -> Controls:
  match controls:
    case Controls{_,_,_,_,_,active}: Bool.pick(Controls,visited(active,path),withStatus(controls,Error{"Cannot delete the currently active session"}),confirming(controls,path))
def deletingSelected(+current: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>,+scope: Scope,+query: SearchInput.Input,+index: Nat,+controls: Controls) -> State & Bool:
  +items = visible(revised(current,all,scope,query,index,Pending{},controls))
  +next = Maybe.default(&2,Controls,Maybe.map(&2,Session.SessionInfo,Controls,info => deleteControls(controls,infoPath(info)),List.get(&2,Session.SessionInfo,items,index)),controls)
  (revised(current,all,scope,query,index,Pending{},next),False{})

def clamped(+state: State) -> State:
  match state:
    case State{current,all,scope,query,index,choice,controls}:
      State{current,all,scope,query,Nat.min(index,List.length(&2,Session.SessionInfo,visible(state)) - 1n),choice,controls}
def findIndex(items: List<&2,Session.SessionInfo>,+path: String,+index: Nat) -> Maybe<&2,Nat>:
  match items:
    case Nil{}: None{}
    case info <> rest: Bool.pick(Maybe<&2,Nat>,Strings.equal(infoPath(info),path),Some{index},findIndex(rest,path,index + 1n))
def switchedScope(+state: State) -> State:
  match state:
    case State{+current,+all,+scope,+query,+index,+choice,+controls}:
      +previous = Maybe.map(&2,Session.SessionInfo,String,infoPath,List.get(&2,Session.SessionInfo,visible(state),index))
      +next = {State{current,all,toggled(scope),query,0n,choice,controls}: State}
      +position = Maybe.default(&2,Nat,Maybe.bind(&2,String,Nat,previous,path => findIndex(visible(next),path,0n)),0n)
      State{current,all,toggled(scope),query,position,choice,controls}
def pending(+current: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>,+scope: Scope,+query: SearchInput.Input,+index: Nat,+controls: Controls,action: Action) -> State & Bool:
  match action:
    case Cancel{}: (revised(current,all,scope,query,index,Cancelled{},dismissed(controls)),True{})
    case Confirm{}:
      +items = visible(revised(current,all,scope,query,index,Pending{},controls))
      selected(current,all,scope,query,index,chosen(items,index),controls)
    case SwitchScope{}: (switchedScope(revised(current,all,scope,query,index,Pending{},controls)),False{})
    case SwitchSort{}: (clamped(revised(current,all,scope,query,index,Pending{},cycledSort(controls))),False{})
    case SwitchNamed{}: (clamped(revised(current,all,scope,query,index,Pending{},toggledNamed(controls))),False{})
    case TogglePath{}: (revised(current,all,scope,query,index,Pending{},toggledPath(controls)),False{})
    case Delete{}: deletingSelected(current,all,scope,query,index,controls)
    case DeleteAlias{}:
      Bool.pick(Unit -> State & Bool,String.is_empty(queryText(query)),_ => deletingSelected(current,all,scope,query,index,controls),_ => (revised(current,all,scope,query,index,Pending{},controls),False{}))(Unit{})
    case Rename{}: (revised(current,all,scope,query,index,Pending{},controls),False{})
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
    case Edit{_}: (revised(current,all,scope,query,index,Pending{},controls),False{})

def duringConfirmation(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,scope: Scope,query: SearchInput.Input,index: Nat,controls: Controls,action: Action) -> State & Bool:
  match action:
    case Cancel{}: (revised(current,all,scope,query,index,Pending{},cleared(controls)),False{})
    case _: (revised(current,all,scope,query,index,Pending{},controls),False{})
def transition(state: State,data: String,bindings: Bindings.KeybindingsManager) -> State & Bool:
  match state:
    case State{current,all,scope,query,index,Pending{},Controls{sort,namedFilter,showPath,Some{path},status,active}}:
      duringConfirmation(current,all,scope,query,index,Controls{sort,namedFilter,showPath,Some{path},status,active},action(bindings,data))
    case State{current,all,scope,query,index,Pending{},controls}: pending(current,all,scope,query,index,cleared(controls),action(bindings,data))
    case state: (state,False{})
def editable(state: State,selected: Action) -> Bool:
  match state selected:
    case State{_,_,_,_,_,Pending{},Controls{_,_,_,Some{_},_,_}} _: False{}
    case State{_,_,_,_,_,Pending{},_} Edit{_}: True{}
    case State{_,_,_,query,_,Pending{},_} DeleteAlias{}: Bool.not(String.is_empty(queryText(query)))
    case _ _: False{}
def nonAtomic(_: Words.Source,_: String) -> Bool: False{}
def editedInput(query: SearchInput.Input,source: Words.Source,bindings: Bindings.KeybindingsManager,data: String) -> IO(Word.ResultOf(SearchInput.Input)):
  SearchInput.handleInput(~Words.Source,~Word.sourceSegments,~nonAtomic,source,query,bindings,Keys.defaults(),data)
def retriedInput(+query: SearchInput.Input,+words: Ref.Ref<Words.Source>,bindings: Bindings.KeybindingsManager,data: String,first: Word.ResultOf(SearchInput.Input)) -> IO(SearchInput.Input):
  match first:
    case Done{next}: IO.pure(SearchInput.Input,next)
    case Fail{Word.WordDataPending{}}:
      do IO<SearchInput.Input>:
        source : Words.Source <- Ref.read(Words.Source,words)
        +ready : Words.Source <- Words.readyFor(source,SearchInput.getValue(query))
        Ref.write(Words.Source,words,ready)
        result : Word.ResultOf(SearchInput.Input) <- editedInput(query,ready,bindings,data)
        return Result.default(&2,&2,Word.Error,SearchInput.Input,result,query)
    case Fail{_}: IO.pure(SearchInput.Input,query)
def editQuery(+query: SearchInput.Input,+words: Ref.Ref<Words.Source>,+bindings: Bindings.KeybindingsManager,+data: String) -> IO(SearchInput.Input):
  do IO<SearchInput.Input>:
    source : Words.Source <- Ref.read(Words.Source,words)
    first : Word.ResultOf(SearchInput.Input) <- editedInput(query,source,bindings,data)
    retriedInput(query,words,bindings,data,first)
def withQuery(state: State,+next: SearchInput.Input) -> State:
  match state:
    case State{current,all,scope,_,Zero{},choice,controls}:
      State{current,all,scope,next,0n,choice,cleared(controls)}
    case State{+current,+all,+scope,_,+index,+choice,+controls}:
      +candidate = {State{current,all,scope,next,index,choice,cleared(controls)} : State}
      +count = List.length(&2,Session.SessionInfo,visible(candidate))
      State{current,all,scope,next,Nat.min(index,count - 1n),choice,cleared(controls)}
def queryOf(state: State) -> SearchInput.Input:
  match state: case State{_,_,_,query,_,_,_}: query
def editedTransition(+state: Ref.Ref<State>,words: Ref.Ref<Words.Source>,+bindings: Bindings.KeybindingsManager,+data: String) -> IO(Bool):
  do IO<Bool>:
    +current : State <- Ref.read(State,state)
    Bool.pick(Unit -> IO(Bool),editable(current,action(bindings,data)),
      _ => do IO<Bool>:
        next : SearchInput.Input <- editQuery(queryOf(current),words,bindings,data)
        Ref.modify(State,Bool,state,value => (withQuery(value,next),False{})),
      _ => Ref.modify(State,Bool,state,value => transition(value,data,bindings)))(Unit{})

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
    completion : Child.Completed <- Child.spawnSync("trash",[path],"/",environment,Nil{})
    outcome : Result<&2,&2,String,String> <- afterTrash(path,completion)
    return outcome
def removed(state: State,+path: String,result: Result<&2,&2,String,String>) -> State:
  match state result:
    case State{current,all,+scope,+query,+index,+choice,+controls} Done{message}:
      +newCurrent = withoutPath(current,path)
      +newAll = withoutPath(all,path)
      +remaining = visible(revised(newCurrent,newAll,scope,query,index,choice,controls))
      revised(newCurrent,newAll,scope,query,Nat.min(index,List.length(&2,Session.SessionInfo,remaining) - 1n),choice,withStatus(controls,Info{message}))
    case State{current,all,scope,query,index,choice,controls} Fail{message}:
      revised(current,all,scope,query,index,choice,withStatus(controls,Error{"Failed to delete: " ++ message}))
def isConfirm(action: Action) -> Bool:
  match action: case Confirm{}: True{} case _: False{}
def deleteFor(state: Ref.Ref<State>,value: State,data: String,bindings: Bindings.KeybindingsManager) -> IO(Bool):
  match value:
    case State{_,_,_,_,_,Pending{},Controls{_,_,_,Some{+path},_,_}}:
      Bool.pick(Unit -> IO(Bool),isConfirm(action(bindings,data)),_ => do IO<Bool>:
        result : Result<&2,&2,String,String> <- removeSession(path)
        next : Unit <- Ref.modify(State,Unit,state,current => (removed(current,path,result),Unit{}))
        return True{},_ => IO.pure(Bool,False{}))(Unit{})
    case _: IO.pure(Bool,False{})
def deleteIfConfirmed(input: Input,data: String) -> IO(Bool):
  match input:
    case Input{+state,_,_,bindings,_}:
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
    case Input{+state,+stop,+allRequested,+bindings,+words}:
      do IO<Unit>:
        deleted : Bool <- deleteIfConfirmed(Input{state,stop,allRequested,bindings,words},data)
        Bool.pick(Unit -> IO(Unit),deleted,_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
          done : Bool <- editedTransition(state,words,bindings,data)
          requestAll(state,allRequested,action(bindings,data))
          Bool.pick(Unit -> IO(Unit),done,_ => do IO<Unit>:
            resolved : Bool <- Deferred.resolve(Unit,stop,Unit{})
            return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{})
def received(input: Input,data: String) -> IO(Unit): receivedShared(input,data)

def made(state: Ref.Ref<State>,loads: Ref.Ref<Loads>,words: Ref.Ref<Words.Source>,stop: Deferred.Deferred<Unit>,allRequested: Deferred.Deferred<Unit>,+render: Callback.Callback<Nat,List<&2,String>>,+input: Callback.Callback<String,Unit>,+invalidate: Callback.Callback<Unit,Unit>,+focus: Callback.Callback<Bool,Unit>) -> Owner:
  Owner{state,loads,words,stop,allRequested,Component.Component{Component.ComponentId{1n},render,Some{input},None{},invalidate,Some{focus},False{}},render,input,invalidate,focus}
def create(current: List<&2,Session.SessionInfo>,all: List<&2,Session.SessionInfo>,+bindings: Bindings.KeybindingsManager,theme: Theme.Theme,words: Words.Source) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<State> <- Ref.new(State,State{current,all,Current{},newQuery(),0n,Pending{},Controls{Threaded{},False{},False{},None{},None{},Nil{}}})
    +loads : Ref.Ref<Loads> <- Ref.new(Loads,Loads{Some{Starting{}},Some{Starting{}}})
    +wordRef : Ref.Ref<Words.Source> <- Ref.new(Words.Source,words)
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +allRequested : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Paint,~Nat,~List<&2,String>,~paint,Paint{state,loads,bindings,theme})
    +input : Callback.Callback<String,Unit> <- Callback.create(~Input,~String,~Unit,~received,Input{state,stop,allRequested,bindings,wordRef})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Unit,~Bool,~Unit,~ignoreFocus,Unit{})
    return made(state,loads,wordRef,stop,allRequested,render,input,invalidate,focus)

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
    case Owner{state,loads,words,stop,allRequested,_,render,input,invalidate,focus}:
      do IO<Outcome()>:
        final : State <- Ref.dispose(State,state)
        oldLoads : Loads <- Ref.dispose(Loads,loads)
        oldWords : Words.Source <- Ref.dispose(Words.Source,words)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
        Deferred.dispose(Unit,allRequested)
        Deferred.dispose(Unit,stop)
        return settled(outcome,final)

type LoadContext is Data:
  LoadContext{cwd: String,sessionDir: Maybe<&2,String>,agentDir: String,sessionsDir: String,assets: String}
def contextAssets(context: LoadContext) -> String:
  match context: case LoadContext{_,_,_,_,assets}: assets
type ProgressInput is Data:
  ProgressInput{state: Ref.Ref<State>,loads: Ref.Ref<Loads>,request: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,scope: Scope}
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
    case Process.QueryReady{_,_,_,redraw,_}: Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,request,Some{redraw})
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
# A cancelled listing (the picker closed) leaves the loaded rows as they are.
def completedListing(input: ProgressInput,listing: Persistence.Listing()) -> IO(Unit):
  match listing:
    case Done{sessions}: completedLoad(input,sessions)
    case Fail{_}: IO.pure(Unit,Unit{})
def loadCurrent(context: LoadContext,signal: Abort.AbortSignal<Unit>,current: ProgressInput,callback: Callback.Callback<Persistence.ListProgress,Unit>) -> IO(Unit):
  match context:
    case LoadContext{cwd,sessionDir,agentDir,_,assets}:
      do IO<Unit>:
        order : Persistence.FileOrder() <- Persistence.loadFileOrder(assets)
        listing : Persistence.Listing() <- Persistence.listProgress(cwd,sessionDir,agentDir,order,signal,callback)
        completedListing(current,listing)
def loadRequested(context: LoadContext,+signal: Abort.AbortSignal<Unit>,request: Deferred.Deferred<Unit>,all: ProgressInput,callback: Callback.Callback<Persistence.ListProgress,Unit>) -> IO(Unit):
  match context:
    case LoadContext{_,sessionDir,_,sessionsDir,assets}:
      do IO<Unit>:
        wake : Unit <- Deferred.result(Unit,request)
        cancelled : Bool <- Abort.aborted(Unit,signal)
        Bool.pick(Unit -> IO(Unit),cancelled,_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
          order : Persistence.FileOrder() <- Persistence.loadFileOrder(assets)
          listing : Persistence.Listing() <- Persistence.listAllProgress(sessionDir,sessionsDir,order,signal,callback)
          completedListing(all,listing))(Unit{})
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
    case Owner{+state,+loads,+words,+stop,+allRequested,+component,render,input,invalidate,focus}:
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
        outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithLifecycle(Process.active(Process.Session{base,Process.Main{Screen.initial()}},[component],[Component.ComponentId{1n}]),stop,False{},ready,stopping)
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
        finish(Owner{state,loads,words,stop,allRequested,component,render,input,invalidate,focus},outcome)
def runMounted(owner: Owner,mounted: Tui.ResultOf(Tui.TuiBase),context: LoadContext) -> IO(Outcome()):
  match mounted:
    case Fail{_}: finish(owner,Fail{Terminal.Closed{}})
    case Done{base}: loadedProcess(owner,base,context)
def run(owner: Owner,context: LoadContext) -> IO(Outcome()):
  match owner:
    case Owner{state,loads,words,stop,allRequested,+component,render,input,invalidate,focus}:
      do IO<Outcome()>:
        mounted : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),[component],[Component.ComponentId{1n}],Some{Component.ComponentId{1n}})
        runMounted(Owner{state,loads,words,stop,allRequested,component,render,input,invalidate,focus},mounted,context)
def loadedBindings(+context: LoadContext,theme: Theme.Theme,loaded: Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager>) -> IO(Outcome()):
  match loaded:
    case Fail{_}: IO.pure(Outcome(),Fail{"Cannot load session selector keybindings"})
    case Done{AppKeys.KeybindingsManager{bindings,_,_}}:
      do IO<Outcome()>:
        owner : Owner <- create(Nil{},Nil{},bindings,theme,Words.Pending{Path.join(contextAssets(context),"packages/runtime/data")})
        run(owner,context)
def visualTheme(visual: Visual) -> IO(Result<&2,&2,Theme.LoadError,Theme.Theme>):
  match visual:
    case Visual{name,assets,agentDir,home,trueColor}:
      do IO<Result<&2,&2,Theme.LoadError,Theme.Theme>>:
        environment : Image.Environment <- Image.processEnvironment("linux",home)
        Theme.loadByName(Maybe.default(&2,String,name,"dark"),Path.join(assets,"packages/coding-agent/src/modes/interactive/theme"),Path.join(agentDir,"themes"),Color.modeFor(Image.trueColor(environment,trueColor)))
def selectedTheme(context: LoadContext,loaded: Result<&2,&2,Theme.LoadError,Theme.Theme>,bindings: Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager>) -> IO(Outcome()):
  match loaded:
    case Fail{_}: IO.pure(Outcome(),Fail{"Cannot load session selector theme"})
    case Done{theme}: loadedBindings(context,theme,bindings)
def selectSession(cwd: String,+sessionDir: Maybe<&2,String>,+agentDir: String,sessionsDir: String,+visual: Visual) -> IO(Outcome()):
  match visual:
    case Visual{_,+assets,_,_,_}:
      do IO<Outcome()>:
        bindings : Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager> <- AppKeys.create(AppKeys.Environment{"linux",None{},None{}},agentDir)
        loaded : Result<&2,&2,Theme.LoadError,Theme.Theme> <- visualTheme(visual)
        selectedTheme(LoadContext{cwd,sessionDir,agentDir,sessionsDir,assets},loaded,bindings)

# The same picker can occupy the interactive editor without starting a second
# terminal process. Both entry points share filtering, ordering and keybindings.
def sameFile(+path: String,+canonical: String) -> IO(Bool):
  do IO<Bool>:
    result : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
    return String.eq(Result.default(&2,&2,FS.Error,String,result,Path.normalize(path)),canonical)
def activePaths(items: List<&2,Session.SessionInfo>,+canonical: String,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match items:
    case Nil{}: IO.pure(List<&2,String>,reversed)
    case info <> rest:
      do IO<List<&2,String>>:
        +path : String = infoPath(info)
        same : Bool <- sameFile(path,canonical)
        activePaths(rest,canonical,Bool.pick(List<&2,String>,same,path <> reversed,reversed))
def protectedPaths(items: List<&2,Session.SessionInfo>,path: Maybe<&2,String>) -> IO(List<&2,String>):
  match path:
    case None{}: IO.pure(List<&2,String>,Nil{})
    case Some{+file}:
      do IO<List<&2,String>>:
        canonical : Result<&2,&2,FS.Error,String> <- FS.realpath(file)
        activePaths(items,Result.default(&2,&2,FS.Error,String,canonical,Path.normalize(file)),Nil{})
type Modal is Data: Closed{} Open{state: State} Renaming{state: State,target: Session.SessionInfo,input: SearchInput.Input}
type ModalProgress is Data:
  ModalProgress{modal: Ref.Ref<Modal>,loads: Ref.Ref<Loads>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,scope: Scope,active: Maybe<&2,String>,touched: Ref.Ref<Bool>}
type Loading is Data:
  Loading{cancel: Abort.AbortController<Unit>,requested: Deferred.Deferred<Unit>,current: Chan(Unit),all: Chan(Unit),currentCallback: Callback.Callback<Persistence.ListProgress,Unit>,allCallback: Callback.Callback<Persistence.ListProgress,Unit>}
type HostLoader is Data:
  HostLoader{loads: Ref.Ref<Loads>,worker: Ref.Ref<Maybe<&2,Loading>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,touched: Ref.Ref<Bool>}
def sameScope(left: Scope,right: Scope) -> Bool:
  match left right: case Current{} Current{}: True{} case All{} All{}: True{} case _ _: False{}
def revisedRows(state: State,scope: Scope,query: SearchInput.Input,index: Nat,choice: Choice,controls: Controls) -> State:
  match state: case State{current,all,_,_,_,_,_}: State{current,all,scope,query,index,choice,controls}
def mergedActive(previous: List<&2,String>,+next: List<&2,String>) -> List<&2,String>:
  match previous:
    case Nil{}: next
    case +path <> rest: mergedActive(rest,Bool.pick(List<&2,String>,visited(next,path),next,path <> next))
def loadedState(+state: State,+scope: Scope,+items: List<&2,Session.SessionInfo>,+active: List<&2,String>,+touched: Bool) -> State:
  match state:
    case State{_,_,+activeScope,+query,+index,+choice,Controls{+sort,+loadedNamed,+path,+deleting,+status,+previousActive}}:
      +previous = List.get(&2,Session.SessionInfo,visible(state),index)
      +updated = changedSessions(state,scope,items)
      +nextActive = mergedActive(previousActive,active)
      +position = Bool.pick(Unit -> Nat,sameScope(activeScope,scope),_ => Bool.pick(Unit -> Nat,touched,_ => retainedPrevious(previous,updated,index),_ => 0n)(Unit{}),_ => index)(Unit{})
      revisedRows(updated,activeScope,query,position,choice,Controls{sort,loadedNamed,path,deleting,status,nextActive})
def loadedModal(modal: Modal,+scope: Scope,+items: List<&2,Session.SessionInfo>,+active: List<&2,String>,+touched: Bool) -> Modal:
  match modal:
    case Closed{}: Closed{}
    case Open{state}: Open{loadedState(state,scope,items,active,touched)}
    case Renaming{state,target,input}: Renaming{loadedState(state,scope,items,active,touched),target,input}
def modalRows(input: ModalProgress,items: Maybe<&2,List<&2,Session.SessionInfo>>) -> IO(Unit):
  match input items:
    case _ None{}: IO.pure(Unit,Unit{})
    case ModalProgress{modal,_,_,+scope,path,touched} Some{+rows}:
      do IO<Unit>:
        +active : List<&2,String> <- protectedPaths(rows,path)
        +selected : Bool <- Ref.read(Bool,touched)
        Ref.modify(Modal,Unit,modal,old => (loadedModal(old,scope,rows,active,selected),Unit{}))
def modalProgressCopied(+input: ModalProgress,update: Persistence.ListProgress) -> IO(Unit):
  match input update:
    case ModalProgress{_,loads,redraw,+scope,_,_} Persistence.ListProgress{loaded,total,items}:
      do IO<Unit>:
        modalRows(input,items)
        Ref.modify(Loads,Unit,loads,old => (counted(old,scope,Some{Count{loaded,total}}),Unit{}))
        requestProgress(redraw)
def modalProgress(input: ModalProgress,update: Persistence.ListProgress) -> IO(Unit): modalProgressCopied(input,update)
def modalCompleted(+input: ModalProgress,listing: Persistence.Listing()) -> IO(Unit):
  match input listing:
    case ModalProgress{_,loads,redraw,+scope,_,_} Done{items}:
      do IO<Unit>:
        modalRows(input,Some{items})
        Ref.modify(Loads,Unit,loads,old => (counted(old,scope,None{}),Unit{}))
        requestProgress(redraw)
    case _ Fail{_}: IO.pure(Unit,Unit{})
def modalList(+context: LoadContext,+signal: Abort.AbortSignal<Unit>,+input: ModalProgress,+callback: Callback.Callback<Persistence.ListProgress,Unit>,scope: Scope) -> IO(Unit):
  match context scope:
    case LoadContext{cwd,sessionDir,agentDir,_,assets} Current{}:
      do IO<Unit>:
        order : Persistence.FileOrder() <- Persistence.loadFileOrder(assets)
        listing : Persistence.Listing() <- Persistence.listProgress(cwd,sessionDir,agentDir,order,signal,callback)
        modalCompleted(input,listing)
    case LoadContext{_,sessionDir,_,sessionsDir,assets} All{}:
      do IO<Unit>:
        order : Persistence.FileOrder() <- Persistence.loadFileOrder(assets)
        listing : Persistence.Listing() <- Persistence.listAllProgress(sessionDir,sessionsDir,order,signal,callback)
        modalCompleted(input,listing)
def modalAll(context: LoadContext,+signal: Abort.AbortSignal<Unit>,request: Deferred.Deferred<Unit>,input: ModalProgress,callback: Callback.Callback<Persistence.ListProgress,Unit>) -> IO(Unit):
  do IO<Unit>:
    wake : Unit <- Deferred.result(Unit,request)
    cancelled : Bool <- Abort.aborted(Unit,signal)
    Bool.pick(Unit -> IO(Unit),cancelled,_ => IO.pure(Unit,Unit{}),_ => modalList(context,signal,input,callback,All{}))(Unit{})
def stopLoading(value: Maybe<&2,Loading>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Loading{+cancel,+requested,current,all,currentCallback,allCallback}}:
      do IO<Unit>:
        stopped : Bool <- Abort.abort(Unit,cancel,None{})
        wake : Bool <- Deferred.resolve(Unit,requested,Unit{})
        IO.join(Unit,current)
        IO.join(Unit,all)
        Callback.dispose(Persistence.ListProgress,Unit,currentCallback)
        Callback.dispose(Persistence.ListProgress,Unit,allCallback)
        Deferred.dispose(Unit,requested)
        Abort.dispose(Unit,cancel)
def stopHostLoading(loader: HostLoader) -> IO(Unit):
  match loader:
    case HostLoader{loads,worker,_,_}:
      do IO<Unit>:
        old : Maybe<&2,Loading> <- Ref.modify(Maybe<&2,Loading>,Maybe<&2,Loading>,worker,value => (None{},value))
        stopLoading(old)
        Ref.write(Loads,loads,Loads{None{},None{}})
def requestLoadedAll(value: Maybe<&2,Loading>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Loading{_,request,_,_,_,_}}:
      do IO<Unit>:
        requested : Bool <- Deferred.resolve(Unit,request,Unit{})
        return Unit{}
def enteredScope(current: Modal,+loads: Loads) -> Loads:
  match current loads:
    case Open{State{_,_,Current{},_,_,_,_}} Loads{count,_}:
      counted(loads,Current{},Maybe.map(&2,Count,Count,_ => Starting{},count))
    case Open{State{_,_,All{},_,_,_,_}} Loads{_,count}:
      counted(loads,All{},Maybe.map(&2,Count,Count,_ => Starting{},count))
    case _ _: loads
def resetScopeProgress(modal: Ref.Ref<Modal>,loads: Ref.Ref<Loads>) -> IO(Unit):
  do IO<Unit>:
    +current : Modal <- Ref.read(Modal,modal)
    Ref.modify(Loads,Unit,loads,old => (enteredScope(current,old),Unit{}))
def resetEnteredScope(modal: Ref.Ref<Modal>,loader: HostLoader,selected: Action) -> IO(Unit):
  match loader selected:
    case HostLoader{loads,_,_,_} SwitchScope{}: resetScopeProgress(modal,loads)
    case _ _: IO.pure(Unit,Unit{})
def syncHostLoading(current: Modal,loader: HostLoader) -> IO(Unit):
  match current loader:
    case Closed{} _: stopHostLoading(loader)
    case Open{State{_,_,All{},_,_,_,_}} HostLoader{_,worker,_,_}:
      do IO<Unit>:
        value : Maybe<&2,Loading> <- Ref.read(Maybe<&2,Loading>,worker)
        requestLoadedAll(value)
    case _ _: IO.pure(Unit,Unit{})
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,theme: Ref.Ref<Theme.Theme>,words: Ref.Ref<Words.Source>,chosen: Callback.Callback<String,Unit>,ids: Uuid.Generator,session: Ref.Ref<AgentSession.AgentSession>,loader: HostLoader}
type HostOwner is Type:
  HostOwner{host: Host,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>}
def drawModalCurrent(current: Modal,editor: Component.Component,+bindings: Bindings.KeybindingsManager,theme: Ref.Ref<Theme.Theme>,loads: Loads,+width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}:
      do IO<List<&2,String>>:
        now : F64 <- Date.now()
        home : Result<&2,&2,FS.Error,String> <- FS.homedir()
        currentTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        renderState(state,width,bindings,currentTheme,loads,now,Result.default(&2,&2,FS.Error,String,home,""),True{})
    case Renaming{_,_,input}:
      do IO<List<&2,String>>:
        +selected : Theme.Theme <- Ref.read(Theme.Theme,theme)
        rendered : SearchInput.Input & List<&2,String> <- SearchInput.render(input,width)
        return List.concat(&2,String,[["",Theme.fg(selected,"accent",rule(width)),""," " ++ Theme.bold("Rename Session"),""],renderedQuery(rendered),[""," " ++ Theme.fg(selected,"muted","enter to save · escape/ctrl+c to cancel"),"",Theme.fg(selected,"accent",rule(width))]])
def drawModal(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,editor,bindings,theme,_,_,_,_,HostLoader{loads,_,_,_}}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        loading : Loads <- Ref.read(Loads,loads)
        drawModalCurrent(current,editor,bindings,theme,loading,width)
# Query editing may yield while rows arrive. Apply the input to the newest
# cached rows rather than restoring the snapshot read before the edit.
def inputState(latest: State,+next: State) -> State:
  match latest next:
    case State{current,all,_,_,_,_,Controls{_,_,_,_,_,+active}} State{_,_,+scope,+query,+index,+choice,Controls{+sort,+loadedNamed,+path,+deleting,+status,_}}:
      +updated = {State{current,all,scope,query,index,choice,Controls{sort,loadedNamed,path,deleting,status,active}}: State}
      +previous = List.get(&2,Session.SessionInfo,visible(next),index)
      revisedRows(updated,scope,query,retainedPrevious(previous,updated,index),choice,Controls{sort,loadedNamed,path,deleting,status,active})
def inputModal(current: Modal,next: State) -> Modal:
  match current:
    case Closed{}: Closed{}
    case Open{latest}: Open{inputState(latest,next)}
    case Renaming{latest,_,_}: Open{inputState(latest,next)}
def afterTransition(modal: Ref.Ref<Modal>,chosen: Callback.Callback<String,Unit>,next: State) -> IO(Unit):
  match next:
    case State{_,_,_,_,_,Chosen{path},_}:
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(String,Unit,chosen,path)
    case State{_,_,_,_,_,Cancelled{},_}: Ref.write(Modal,modal,Closed{})
    case other:
      +saved = {other: State}
      Ref.modify(Modal,Unit,modal,current => (inputModal(current,saved),Unit{}))
def modalTransitionPair(modal: Ref.Ref<Modal>,chosen: Callback.Callback<String,Unit>,pair: State & Bool) -> IO(Unit):
  match pair:
    case (next,_): afterTransition(modal,chosen,next)
def modalTransition(+modal: Ref.Ref<Modal>,+bindings: Bindings.KeybindingsManager,words: Ref.Ref<Words.Source>,+chosen: Callback.Callback<String,Unit>,+state: State,+data: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),editable(state,action(bindings,data)),
    _ => do IO<Unit>:
      next : SearchInput.Input <- editQuery(queryOf(state),words,bindings,data)
      afterTransition(modal,chosen,withQuery(state,next)),
    _ => modalTransitionPair(modal,chosen,transition(state,data,bindings)))(Unit{})
def modalDeleteAction(modal: Ref.Ref<Modal>,bindings: Bindings.KeybindingsManager,words: Ref.Ref<Words.Source>,chosen: Callback.Callback<String,Unit>,state: State,+path: String,data: String,selected: Action) -> IO(Unit):
  match selected:
    case Confirm{}:
      do IO<Unit>:
        result : Result<&2,&2,String,String> <- removeSession(path)
        Ref.write(Modal,modal,Open{removed(state,path,result)})
    case _: modalTransition(modal,bindings,words,chosen,state,data)
def sessionName(info: Session.SessionInfo) -> String:
  match info: case Session.SessionInfo{_,_,_,name,_,_,_,_,_,_}: Maybe.default(&2,String,name,"")
def sessionCwd(info: Session.SessionInfo) -> String:
  match info: case Session.SessionInfo{_,_,cwd,_,_,_,_,_,_,_}: cwd
def namedInfo(info: Session.SessionInfo,name: String) -> Session.SessionInfo:
  match info:
    case Session.SessionInfo{path,id,cwd,_,parent,created,modified,count,first,messages}:
      Session.SessionInfo{path,id,cwd,Some{name},parent,created,modified,count,first,messages}
def namedEntries(items: List<&2,Session.SessionInfo>,+path: String,+name: String) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest:
      Bool.pick(Unit -> List<&2,Session.SessionInfo>,Strings.equal(infoPath(info),path),
        _ => namedInfo(info,name) <> namedEntries(rest,path,name),
        _ => info <> namedEntries(rest,path,name))(Unit{})
def namedState(state: State,+path: String,+name: String) -> State:
  match state:
    case State{current,all,scope,query,index,choice,controls}:
      State{namedEntries(current,path,name),namedEntries(all,path,name),scope,query,index,choice,controls}
def selectedIndex(state: State) -> Nat:
  match state: case State{_,_,_,_,index,_,_}: index
def renameOpened(opened: Persistence.Outcome(AgentSession.Session()),name: String) -> IO(Bool):
  match opened:
    case Fail{_}: IO.pure(Bool,False{})
    case Done{session}:
      do IO<Bool>:
        result : Persistence.Outcome(AgentSession.Appended()) <- AgentSession.recordName(session,name)
        return Result.is_done(&2,&2,Persistence.Error,AgentSession.Appended(),result)
def renameStored(ids: Uuid.Generator,+info: Session.SessionInfo,name: String) -> IO(Bool):
  do IO<Bool>:
    opened : Persistence.Outcome(AgentSession.Session()) <- AgentSession.openSession(ids,infoPath(info),None{},sessionCwd(info))
    renameOpened(opened,name)
def beginRenameFound(modal: Ref.Ref<Modal>,+state: State,selected: Maybe<&2,Session.SessionInfo>) -> IO(Unit):
  match selected:
    case None{}: IO.pure(Unit,Unit{})
    case Some{+info}: Ref.write(Modal,modal,Renaming{state,info,SearchInput.setValue(newQuery(),sessionName(info))})
def beginRename(modal: Ref.Ref<Modal>,+state: State) -> IO(Unit):
  beginRenameFound(modal,state,List.get(&2,Session.SessionInfo,visible(state),selectedIndex(state)))
def renamedModalAction(ids: Uuid.Generator,modal: Ref.Ref<Modal>,+state: State,+target: Session.SessionInfo,input: SearchInput.Input,words: Ref.Ref<Words.Source>,bindings: Bindings.KeybindingsManager,data: String,selected: Action) -> IO(Unit):
  match selected:
    case Cancel{}: Ref.write(Modal,modal,Open{state})
    case Confirm{}:
      +name = String.trim(queryText(input))
      Bool.pick(Unit -> IO(Unit),String.is_empty(name),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
        saved : Bool <- renameStored(ids,target,name)
        Ref.write(Modal,modal,Open{Bool.pick(State,saved,namedState(state,infoPath(target),name),state)}))(Unit{})
    case _:
      do IO<Unit>:
        next : SearchInput.Input <- editQuery(input,words,bindings,data)
        Ref.write(Modal,modal,Renaming{state,target,next})
def renamedModal(ids: Uuid.Generator,modal: Ref.Ref<Modal>,state: State,target: Session.SessionInfo,input: SearchInput.Input,words: Ref.Ref<Words.Source>,+bindings: Bindings.KeybindingsManager,+data: String) -> IO(Unit):
  renamedModalAction(ids,modal,state,target,input,words,bindings,data,action(bindings,data))
def receivedModalOpenAction(modal: Ref.Ref<Modal>,+bindings: Bindings.KeybindingsManager,words: Ref.Ref<Words.Source>,chosen: Callback.Callback<String,Unit>,+state: State,+data: String,selected: Action) -> IO(Unit):
  match state selected:
    case State{_,_,_,_,_,Pending{},Controls{_,_,_,Some{+path},_,_}} _:
      modalDeleteAction(modal,bindings,words,chosen,state,path,data,selected)
    case state Rename{}: beginRename(modal,state)
    case _ _: modalTransition(modal,bindings,words,chosen,state,data)
def receivedModalOpen(modal: Ref.Ref<Modal>,+bindings: Bindings.KeybindingsManager,words: Ref.Ref<Words.Source>,chosen: Callback.Callback<String,Unit>,+state: State,+data: String) -> IO(Unit):
  receivedModalOpenAction(modal,bindings,words,chosen,state,data,action(bindings,data))
def receivedModalCurrent(ids: Uuid.Generator,current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,bindings: Bindings.KeybindingsManager,words: Ref.Ref<Words.Source>,chosen: Callback.Callback<String,Unit>,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}: receivedModalOpen(modal,bindings,words,chosen,state,data)
    case Renaming{state,target,input}: renamedModal(ids,modal,state,target,input,words,bindings,data)
def touchesSelection(selected: Action) -> Bool:
  match selected:
    case MoveUp{}: True{} case MoveDown{}: True{} case PageUp{}: True{} case PageDown{}: True{} case Edit{_}: True{} case _: False{}
def touchModal(current: Modal,loader: HostLoader,bindings: Bindings.KeybindingsManager,data: String) -> IO(Unit):
  match current loader:
    case Open{_} HostLoader{_,_,_,touched}:
      +changed = touchesSelection(action(bindings,data))
      Ref.modify(Bool,Unit,touched,old => (old || changed,Unit{}))
    case _ _: IO.pure(Unit,Unit{})
def receivedModalCopied(host: Host,+data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,+bindings,_,words,handler,ids,_,+loader}:
      do IO<Unit>:
        +current : Modal <- Ref.read(Modal,modal)
        touchModal(current,loader,bindings,data)
        receivedModalCurrent(ids,current,modal,editor,bindings,words,handler,data)
        resetEnteredScope(modal,loader,action(bindings,data))
        next : Modal <- Ref.read(Modal,modal)
        syncHostLoading(next,loader)
def receivedModal(host: Host,data: String) -> IO(Unit): receivedModalCopied(host,data)
def mouseCurrent(current: Modal,mouse: Maybe<&2,Callback.Callback<Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>>,event: Ui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current mouse:
    case Closed{} Some{callback}: Callback.call(Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _ _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def modalMouse(host: Host,event: Ui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{+modal,Component.Component{_,_,_,mouse,_,_,_},_,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,mouse,event)
def modalInvalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_,_}: Component.invalidate(editor)
def modalFocus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_,_}: Component.setFocused(editor,value)
def createHost(ids: Uuid.Generator,+editor: Component.Component,bindings: Bindings.KeybindingsManager,theme: Ref.Ref<Theme.Theme>,words: Words.Source,chosen: Callback.Callback<String,Unit>,session: Ref.Ref<AgentSession.AgentSession>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(HostOwner):
  do IO<HostOwner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    wordRef : Ref.Ref<Words.Source> <- Ref.new(Words.Source,words)
    loads : Ref.Ref<Loads> <- Ref.new(Loads,Loads{None{},None{}})
    worker : Ref.Ref<Maybe<&2,Loading>> <- Ref.new(Maybe<&2,Loading>,None{})
    touched : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +host : Host <- IO.pure(Host,Host{modal,editor,bindings,theme,wordRef,chosen,ids,session,HostLoader{loads,worker,redraw,touched}})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~drawModal,host)
    +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receivedModal,host)
    +mouse : Callback.Callback<Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Ui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~modalMouse,host)
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~modalInvalidate,host)
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~modalFocus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),render,Some{input},Some{mouse},invalidate,Some{focus},False{}})
    return HostOwner{host,component,render,input,mouse,invalidate,focus}
def borrowHost(owner: HostOwner) -> HostOwner & Host & Component.Component:
  match owner: case HostOwner{+host,+component,render,input,mouse,invalidate,focus}: (HostOwner{host,component,render,input,mouse,invalidate,focus},host,component)
def resetTouched(loader: HostLoader) -> IO(Unit):
  match loader: case HostLoader{_,_,_,touched}: Ref.write(Bool,touched,False{})
def openHost(host: Host,+current: List<&2,Session.SessionInfo>,+all: List<&2,Session.SessionInfo>) -> IO(Unit):
  match host:
    case Host{modal,_,_,_,_,_,_,session,+loader}:
      do IO<Unit>:
        stopHostLoading(loader)
        resetTouched(loader)
        live : AgentSession.AgentSession <- Ref.read(AgentSession.AgentSession,session)
        stored : AgentSession.Session() <- AgentSession.sessionOf(live)
        active : List<&2,String> <- protectedPaths(List.append(&2,Session.SessionInfo,current,all),Persistence.getSessionFile(Unit,Tools.ToolDetails,V.Value,stored))
        Ref.write(Modal,modal,Open{State{current,all,Current{},newQuery(),0n,Pending{},Controls{Threaded{},False{},False{},None{},None{},active}}})
def openLoadingHost(+host: Host,+context: LoadContext) -> IO(Unit):
  match host:
    case Host{+modal,_,_,_,_,_,_,session,HostLoader{+loads,+worker,+redraw,+touched}}:
      do IO<Unit>:
        openHost(host,Nil{},Nil{})
        live : AgentSession.AgentSession <- Ref.read(AgentSession.AgentSession,session)
        stored : AgentSession.Session() <- AgentSession.sessionOf(live)
        +path : Maybe<&2,String> = Persistence.getSessionFile(Unit,Tools.ToolDetails,V.Value,stored)
        Ref.write(Loads,loads,Loads{Some{Starting{}},Some{Starting{}}})
        +current : ModalProgress = ModalProgress{modal,loads,redraw,Current{},path,touched}
        +all : ModalProgress = ModalProgress{modal,loads,redraw,All{},path,touched}
        +currentCallback : Callback.Callback<Persistence.ListProgress,Unit> <- Callback.create(~ModalProgress,~Persistence.ListProgress,~Unit,~modalProgress,current)
        +allCallback : Callback.Callback<Persistence.ListProgress,Unit> <- Callback.create(~ModalProgress,~Persistence.ListProgress,~Unit,~modalProgress,all)
        +cancel : Abort.AbortController<Unit> <- Abort.new(Unit)
        +requested : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        currentWorker : Chan(Unit) <- IO.fork(Unit,modalList(context,Abort.signal(Unit,cancel),current,currentCallback,Current{}))
        allWorker : Chan(Unit) <- IO.fork(Unit,modalAll(context,Abort.signal(Unit,cancel),requested,all,allCallback))
        Ref.write(Maybe<&2,Loading>,worker,Some{Loading{cancel,requested,currentWorker,allWorker,currentCallback,allCallback}})
        requestProgress(redraw)
def disposeLoader(loader: HostLoader) -> IO(Unit):
  match loader:
    case HostLoader{loads,worker,_,touched}:
      do IO<Unit>:
        oldTouched : Bool <- Ref.dispose(Bool,touched)
        oldLoads : Loads <- Ref.dispose(Loads,loads)
        oldWorker : Maybe<&2,Loading> <- Ref.dispose(Maybe<&2,Loading>,worker)
        return Unit{}
def disposeHost(owner: HostOwner) -> IO(Unit):
  match owner:
    case HostOwner{Host{modal,_,_,_,words,_,_,_,+loader},_,render,input,mouse,invalidate,focus}:
      do IO<Unit>:
        stopHostLoading(loader)
        disposeLoader(loader)
        discarded : Modal <- Ref.dispose(Modal,modal)
        oldWords : Words.Source <- Ref.dispose(Words.Source,words)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Ui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)

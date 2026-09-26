import Base
import ../packages/coding-agent/src/cli/session-picker.bend as Picker
import ../packages/coding-agent/src/core/session-manager.bend as Session
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/word-segmenter.bend as Words
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/json.bend as Parse
import ../packages/runtime/src/f64.bend as F
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/keybindings.bend as Bindings

def field(value: V.Value,key: String) -> Maybe<&2,V.Value>:
  match value: case V.ObjectValue{record}: R.get(V.Value,record,key) case _: None{}
def text(value: Maybe<&2,V.Value>,fallback: String) -> String:
  match value: case Some{V.Text{string}}: string case _: fallback
def maybeText(value: Maybe<&2,V.Value>) -> Maybe<&2,String>:
  match value: case Some{V.Text{string}}: Some{string} case _: None{}
def number(value: Maybe<&2,V.Value>,fallback: F64) -> F64:
  match value: case Some{V.Number{numeric}}: numeric case _: fallback
def array(value: Maybe<&2,V.Value>) -> List<&2,V.Value>:
  match value: case Some{V.ArrayValue{values}}: values case _: Nil{}
def strings(values: List<&2,V.Value>) -> List<&2,String>:
  match values: case Nil{}: Nil{} case V.Text{string} <> rest: string <> strings(rest) case _ <> rest: strings(rest)
def info(+value: V.Value) -> Session.SessionInfo:
  Session.SessionInfo{text(field(value,"path"),""),text(field(value,"id"),""),text(field(value,"cwd"),""),maybeText(field(value,"name")),maybeText(field(value,"parentSessionPath")),F.fromU32(0),number(field(value,"modified"),F.fromU32(0)),1n,text(field(value,"firstMessage"),"hello"),text(field(value,"allMessagesText"),"hello")}
def infos(values: List<&2,V.Value>) -> List<&2,Session.SessionInfo>:
  match values: case Nil{}: Nil{} case value <> rest: info(value) <> infos(rest)
def jsonStrings(values: List<&2,String>) -> List<&2,V.Value>:
  match values: case Nil{}: Nil{} case value <> rest: V.Text{value} <> jsonStrings(rest)
def paths(values: List<&2,Session.SessionInfo>) -> List<&2,V.Value>:
  match values: case Nil{}: Nil{} case value <> rest: V.Text{Picker.infoPath(value)} <> paths(rest)
def choice(value: Picker.Choice) -> String:
  match value: case Picker.Pending{}: "continue" case Picker.Cancelled{}: "cancel" case Picker.Chosen{path}: "chosen:" ++ path
def optional(value: Maybe<&2,String>) -> V.Value:
  match value: case None{}: V.Null{} case Some{string}: V.Text{string}
def statusText(value: Maybe<&2,Picker.StatusMessage>) -> V.Value:
  match value: case None{}: V.Null{} case Some{Picker.Info{string}}: V.Text{string} case Some{Picker.Error{string}}: V.Text{string}
def snapshot(+state: Picker.State,lines: List<&2,String>) -> V.Value:
  match state:
    case Picker.State{_,_,_,_,index,result,Picker.Controls{_,_,_,deleting,status,_}}:
      +visible = Picker.visible(state)
      V.ObjectValue{R.Record{[R.Property{"paths",V.ArrayValue{paths(visible)}},R.Property{"selected",optional(Maybe.map(&2,Session.SessionInfo,String,Picker.infoPath,List.get(&2,Session.SessionInfo,visible,index)))},R.Property{"query",V.Text{Picker.queryText(Picker.queryOf(state))}},R.Property{"action",V.Text{choice(result)}},R.Property{"deleting",optional(deleting)},R.Property{"status",statusText(status)},R.Property{"lines",V.ArrayValue{jsonStrings(lines)}}]}}
def emit(+state: Picker.State,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(Unit):
  do IO<Unit>:
    lines : List<&2,String> <- Picker.renderState(state,width,bindings,theme,Picker.Loads{None{},None{}},F.fromU32(3600000),"/home/agent",True{})
    IO.print(Maybe.default(&2,String,Json.stringify(SchemaJson.toJson(snapshot(state,lines))),"null"))
def key(name: String) -> String:
  match name:
    case "up": "\u{1b}[A"
    case "down": "\u{1b}[B"
    case "page-up": "\u{1b}[5~"
    case "page-down": "\u{1b}[6~"
    case "enter": "\r"
    case "escape": "\u{1b}"
    case "scope": "\t"
    case "sort": "\u{13}"
    case "named": "\u{e}"
    case "path": "\u{10}"
    case "delete": "\u{4}"
    case "delete-alias": "\u{1b}[127;5u"
    case "backspace": "\u{7f}"
    case "clear": "\u{15}"
    case _: name
def steps(actions: List<&2,String>,+state: Ref.Ref<Picker.State>,+words: Ref.Ref<Words.Source>,+theme: Theme.Theme,+width: Nat,+bindings: Bindings.KeybindingsManager,+all: List<&2,Session.SessionInfo>,+requested: Bool) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case +action <> rest:
      do IO<Unit>:
        stopped : Bool <- Picker.editedTransition(state,words,bindings,key(action))
        loaded : Unit <- Bool.pick(Unit -> IO(Unit),String.eq(action,"scope") && Bool.not(requested),
          _ => Ref.modify(Picker.State,Unit,state,value => (Picker.changedSessions(value,Picker.All{},all),Unit{})),
          _ => IO.pure(Unit,Unit{}))(Unit{})
        current : Picker.State <- Ref.read(Picker.State,state)
        emit(current,theme,width,bindings)
        steps(rest,state,words,theme,width,bindings,all,requested || String.eq(action,"scope"))
def runCase(+value: V.Value,+theme: Theme.Theme,root: String) -> IO(Unit):
  do IO<Unit>:
    +current : List<&2,Session.SessionInfo> = infos(array(field(value,"current")))
    +all : List<&2,Session.SessionInfo> = infos(array(field(value,"all")))
    active : List<&2,String> <- Picker.protectedPaths(List.append(&2,Session.SessionInfo,current,all),maybeText(field(value,"active")))
    +state : Ref.Ref<Picker.State> <- Ref.new(Picker.State,Picker.State{current,Nil{},Picker.Current{},Picker.newQuery(),0n,Picker.Pending{},Picker.Controls{Picker.Threaded{},False{},False{},None{},None{},active}})
    +words : Ref.Ref<Words.Source> <- Ref.new(Words.Source,Words.Pending{root ++ "/packages/runtime/data"})
    +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
    +width : Nat = U32.to_nat(F64.to_u32(number(field(value,"width"),F.fromU32(100))))
    first : Picker.State <- Ref.read(Picker.State,state)
    emit(first,theme,width,bindings)
    steps(strings(array(field(value,"actions"))),state,words,theme,width,bindings,all,False{})
    final : Picker.State <- Ref.dispose(Picker.State,state)
    used : Words.Source <- Ref.dispose(Words.Source,words)
    return Unit{}
def cases(values: List<&2,V.Value>,+theme: Theme.Theme,+root: String) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        runCase(value,theme,root)
        cases(rest,theme,root)
def loaded(theme: Result<&2,&2,Theme.LoadError,Theme.Theme>,parsed: Result<&2,&2,Parse.ParseError,V.Value>,root: String) -> IO(Unit):
  match theme parsed:
    case Done{selected} Done{V.ArrayValue{values}}: cases(values,selected,root)
    case _ _: IO.die(Unit,1,"invalid resume fixture input or theme")
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> json <> Nil{}:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,Parse.parse(json),root)
    case _: IO.die(Unit,1,"expected root cases")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

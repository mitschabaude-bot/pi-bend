import Base
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deferred.bend as Deferred
import ./resume-selector.bend as Fixture
import ../packages/coding-agent/src/cli/session-picker.bend as Picker
import ../packages/coding-agent/src/core/session-persistence.bend as Persistence
import ../packages/coding-agent/src/core/session-manager.bend as Session
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/schema-value.bend as V
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/ai/src/utils/json.bend as Json
import ../packages/runtime/src/json.bend as Parse
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/word-segmenter.bend as Words
import ../packages/runtime/src/f64.bend as F
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys

def selected(_: Unit,_: String) -> IO(Unit): IO.pure(Unit,Unit{})
def scope(value: V.Value) -> Picker.Scope:
  match value: case V.Text{"all"}: Picker.All{} case _: Picker.Current{}
def count(value: V.Value) -> Nat: U32.to_nat(F64.to_u32(Fixture.number(Some{value},F.fromU32(0))))
def emitModal(current: Picker.Modal,loads: Picker.Loads,+theme: Theme.Theme,width: Nat,+bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match current:
    case Picker.Open{+state}:
      do IO<Unit>:
        lines : List<&2,String> <- Picker.renderState(state,width,bindings,theme,loads,F.fromU32(3600000),"/home/agent",True{})
        IO.print(Maybe.default(&2,String,Json.stringify(SchemaJson.toJson(Fixture.snapshot(state,lines))),"null"))
    case _: IO.die(Unit,1,"unexpected closed resume fixture")
def emit(+modal: Ref.Ref<Picker.Modal>,+loads: Ref.Ref<Picker.Loads>,theme: Theme.Theme,width: Nat,bindings: Bindings.KeybindingsManager) -> IO(Unit):
  do IO<Unit>:
    state : Picker.Modal <- Ref.read(Picker.Modal,modal)
    progress : Picker.Loads <- Ref.read(Picker.Loads,loads)
    emitModal(state,progress,theme,width,bindings)
def field(value: V.Value,key: String) -> V.Value: Maybe.default(&2,V.Value,Fixture.field(value,key),V.Null{})
def input(current: Picker.Modal,modal: Ref.Ref<Picker.Modal>,bindings: Bindings.KeybindingsManager,words: Ref.Ref<Words.Source>,chosen: Callback.Callback<String,Unit>,data: String) -> IO(Unit):
  match current: case Picker.Open{state}: Picker.modalTransition(modal,bindings,words,chosen,state,data) case _: IO.die(Unit,1,"expected open picker")
def operation(+value: V.Value,+modal: Ref.Ref<Picker.Modal>,+loads: Ref.Ref<Picker.Loads>,+touched: Ref.Ref<Bool>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,words: Ref.Ref<Words.Source>,+bindings: Bindings.KeybindingsManager,chosen: Callback.Callback<String,Unit>,kind: V.Value) -> IO(Unit):
  match kind:
    case V.Text{"progress"}: Picker.modalProgress(Picker.ModalProgress{modal,loads,redraw,scope(field(value,"scope")),None{},touched},Persistence.ListProgress{count(field(value,"loaded")),count(field(value,"total")),Some{Fixture.infos(Fixture.array(Fixture.field(value,"items")))}})
    case V.Text{"complete"}: Picker.modalCompleted(Picker.ModalProgress{modal,loads,redraw,scope(field(value,"scope")),None{},touched},Done{Fixture.infos(Fixture.array(Fixture.field(value,"items")))})
    case V.Text{"key"}:
      do IO<Unit>:
        +data : String = Fixture.key(Maybe.default(&2,String,Fixture.maybeText(Fixture.field(value,"key")),""))
        +changed : Bool = Picker.touchesSelection(Picker.action(bindings,data))
        Ref.modify(Bool,Unit,touched,old => (old || changed,Unit{}))
        current : Picker.Modal <- Ref.read(Picker.Modal,modal)
        input(current,modal,bindings,words,chosen,data)
        Bool.pick(Unit -> IO(Unit),String.eq(data,"\t"),_ => Picker.resetScopeProgress(modal,loads),_ => IO.pure(Unit,Unit{}))(Unit{})
    case _: IO.die(Unit,1,"unknown loading fixture action")
def steps(actions: List<&2,V.Value>,+modal: Ref.Ref<Picker.Modal>,+loads: Ref.Ref<Picker.Loads>,+touched: Ref.Ref<Bool>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+words: Ref.Ref<Words.Source>,+bindings: Bindings.KeybindingsManager,+chosen: Callback.Callback<String,Unit>,+theme: Theme.Theme,+width: Nat) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case +value <> rest:
      do IO<Unit>:
        operation(value,modal,loads,touched,redraw,words,bindings,chosen,field(value,"kind"))
        emit(modal,loads,theme,width,bindings)
        steps(rest,modal,loads,touched,redraw,words,bindings,chosen,theme,width)
def runCase(+value: V.Value,+theme: Theme.Theme,root: String) -> IO(Unit):
  do IO<Unit>:
    +modal : Ref.Ref<Picker.Modal> <- Ref.new(Picker.Modal,Picker.Open{Picker.State{Nil{},Nil{},Picker.Current{},Picker.newQuery(),0n,Picker.Pending{},Picker.Controls{Picker.Threaded{},False{},False{},None{},None{},Nil{}}}})
    +loads : Ref.Ref<Picker.Loads> <- Ref.new(Picker.Loads,Picker.Loads{Some{Picker.Starting{}},Some{Picker.Starting{}}})
    +touched : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
    +words : Ref.Ref<Words.Source> <- Ref.new(Words.Source,Words.Pending{root ++ "/packages/runtime/data"})
    +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
    +chosen : Callback.Callback<String,Unit> <- Callback.create(~Unit,~String,~Unit,~selected,Unit{})
    +width : Nat = count(field(value,"width"))
    emit(modal,loads,theme,width,bindings)
    steps(Fixture.array(Fixture.field(value,"actions")),modal,loads,touched,redraw,words,bindings,chosen,theme,width)
    oldModal : Picker.Modal <- Ref.dispose(Picker.Modal,modal)
    oldLoads : Picker.Loads <- Ref.dispose(Picker.Loads,loads)
    oldTouched : Bool <- Ref.dispose(Bool,touched)
    oldRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    oldWords : Words.Source <- Ref.dispose(Words.Source,words)
    Callback.dispose(String,Unit,chosen)
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
    case _ _: IO.die(Unit,1,"invalid loading fixture input or theme")
def unexpectedProgress(_: Unit,_: Persistence.ListProgress) -> IO(Unit): IO.die(Unit,1,"cancelled All loader published progress")
def stoppedLazyWorker(+root: String) -> IO(Unit):
  do IO<Unit>:
    +modal : Ref.Ref<Picker.Modal> <- Ref.new(Picker.Modal,Picker.Closed{})
    +loads : Ref.Ref<Picker.Loads> <- Ref.new(Picker.Loads,Picker.Loads{None{},None{}})
    +touched : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
    +callback : Callback.Callback<Persistence.ListProgress,Unit> <- Callback.create(~Unit,~Persistence.ListProgress,~Unit,~unexpectedProgress,Unit{})
    +otherCallback : Callback.Callback<Persistence.ListProgress,Unit> <- Callback.create(~Unit,~Persistence.ListProgress,~Unit,~unexpectedProgress,Unit{})
    +cancel : Abort.AbortController<Unit> <- Abort.new(Unit)
    +requested : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    current : Chan(Unit) <- IO.fork(Unit,IO.pure(Unit,Unit{}))
    all : Chan(Unit) <- IO.fork(Unit,Picker.modalAll(Picker.LoadContext{root,Some{root},root,root,root},Abort.signal(Unit,cancel),requested,Picker.ModalProgress{modal,loads,redraw,Picker.All{},None{},touched},callback))
    Picker.stopLoading(Some{Picker.Loading{cancel,requested,current,all,otherCallback,callback}})
    oldModal : Picker.Modal <- Ref.dispose(Picker.Modal,modal)
    oldLoads : Picker.Loads <- Ref.dispose(Picker.Loads,loads)
    oldTouched : Bool <- Ref.dispose(Bool,touched)
    oldRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    return Unit{}
def run(args: List<String>) -> IO(Unit):
  match args:
    case +root <> json <> Nil{}:
      do IO<Unit>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(root ++ "/packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
        loaded(theme,Parse.parse(json),root)
        stoppedLazyWorker(root)
    case _: IO.die(Unit,1,"expected root cases")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

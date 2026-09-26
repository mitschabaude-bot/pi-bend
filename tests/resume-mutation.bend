import Base
import ../packages/coding-agent/src/cli/session-picker.bend as Picker
import ../packages/coding-agent/src/core/session-manager.bend as Session
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/word-segmenter.bend as Words
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys

def require(condition: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),condition,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
def ready(current: Picker.Modal,loads: Picker.Loads,scope: Picker.Scope) -> Bool:
  match current loads scope:
    case Picker.Open{_} Picker.Loads{None{},_} Picker.Current{}: True{}
    case Picker.Open{_} Picker.Loads{_,None{}} Picker.All{}: True{}
    case _ _ _: False{}
def waitLoaded(+modal: Ref.Ref<Picker.Modal>,+loads: Ref.Ref<Picker.Loads>,+scope: Picker.Scope,fuel: Nat) -> IO(Unit):
  match fuel:
    case Zero{}: IO.die(Unit,1,"resume load did not settle")
    case Succ{remaining}:
      do IO<Unit>:
        current : Picker.Modal <- Ref.read(Picker.Modal,modal)
        count : Picker.Loads <- Ref.read(Picker.Loads,loads)
        Bool.pick(Unit -> IO(Unit),ready(current,count,scope),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
          IO.sleep(1)
          waitLoaded(modal,loads,scope,remaining))(Unit{})
def rows(items: List<&2,Session.SessionInfo>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case +info <> rest: V.ArrayValue{[V.Text{Picker.infoPath(info)},V.Text{Picker.sessionName(info)}]} <> rows(rest)
def requestedState(state: Deferred.State<Unit>) -> Bool:
  match state: case Deferred.Pending{_,_}: False{} case Deferred.Resolved{_}: True{}
def requested(worker: Picker.ScopeWorker) -> IO(Bool):
  match worker:
    case Picker.ScopeWorker{Deferred.Deferred{state},_,_}:
      do IO<Bool>:
        value : Deferred.State<Unit> <- Ref.read(Deferred.State<Unit>,state)
        return requestedState(value)
def requests(value: Maybe<&2,Picker.Loading>) -> IO(V.Value):
  match value:
    case None{}: IO.pure(V.Value,V.Null{})
    case Some{Picker.Loading{_,current,all,_}}:
      do IO<V.Value>:
        currentRequested : Bool <- requested(current)
        allRequested : Bool <- requested(all)
        return V.ArrayValue{[V.Boolean{currentRequested},V.Boolean{allRequested}]}
def snapshot(stage: String,current: Picker.Modal,demand: V.Value) -> IO(Unit):
  match current:
    case Picker.Open{Picker.State{locals,all,scope,_,_,_,_}}:
      IO.print(Maybe.default(&2,String,Json.stringify(SchemaJson.toJson(V.ObjectValue{R.Record{[R.Property{"stage",V.Text{stage}},R.Property{"scope",V.Text{Bool.pick(String,Picker.isAll(scope),"all","current")}},R.Property{"current",V.ArrayValue{rows(locals)}},R.Property{"all",V.ArrayValue{rows(all)}},R.Property{"requested",demand}]}})),"null"))
    case _: IO.die(Unit,1,"expected completed mutation to return to list")
def emit(stage: String,+modal: Ref.Ref<Picker.Modal>,loader: Picker.HostLoader) -> IO(Unit):
  match loader:
    case Picker.HostLoader{_,worker,_,_}:
      do IO<Unit>:
        current : Picker.Modal <- Ref.read(Picker.Modal,modal)
        loaded : Maybe<&2,Picker.Loading> <- Ref.read(Maybe<&2,Picker.Loading>,worker)
        demand : V.Value <- requests(loaded)
        snapshot(stage,current,demand)
def openState(current: Picker.Modal) -> Picker.State:
  match current: case Picker.Open{state}: state case _: Picker.State{Nil{},Nil{},Picker.Current{},Picker.newQuery(),0n,Picker.Pending{},Picker.Controls{Picker.Threaded{},False{},False{},None{},None{},Nil{}}}
def target(current: Picker.Modal) -> IO(Session.SessionInfo):
  match current:
    case Picker.Renaming{_,info,_}: IO.pure(Session.SessionInfo,info)
    case _: IO.die(Session.SessionInfo,1,"rename did not open")
def switchedModal(current: Picker.Modal) -> Picker.Modal:
  match current: case Picker.Open{state}: Picker.Open{Picker.switchedScope(state)} case _: current
def selectScope(+modal: Ref.Ref<Picker.Modal>,+loader: Picker.HostLoader) -> IO(Unit):
  do IO<Unit>:
    Ref.modify(Picker.Modal,Unit,modal,current => (switchedModal(current),Unit{}))
    current : Picker.Modal <- Ref.read(Picker.Modal,modal)
    Picker.syncHostLoading(current,loader)
def ignoredChoice(_: Unit,_: String) -> IO(Unit): IO.die(Unit,1,"mutation selected a session")
def finishIds(ids: Uuid.Generator) -> IO(Unit):
  match ids:
    case Uuid.Generator{state}:
      do IO<Unit>:
        old : Uuid.State <- Ref.dispose(Uuid.State,state)
        return Unit{}
def run(+root: String,+assets: String) -> IO(Unit):
  do IO<Unit>:
    +modal : Ref.Ref<Picker.Modal> <- Ref.new(Picker.Modal,Picker.Open{Picker.State{Nil{},Nil{},Picker.Current{},Picker.newQuery(),0n,Picker.Pending{},Picker.Controls{Picker.Threaded{},False{},False{},None{},None{},Nil{}}}})
    +loads : Ref.Ref<Picker.Loads> <- Ref.new(Picker.Loads,Picker.Loads{None{},None{}})
    +worker : Ref.Ref<Maybe<&2,Picker.Loading>> <- Ref.new(Maybe<&2,Picker.Loading>,None{})
    +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
    +touched : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +loader : Picker.HostLoader = Picker.HostLoader{loads,worker,redraw,touched}
    Picker.startLoading(modal,loader,Picker.LoadSource{Picker.LoadContext{root ++ "/project",Some{root ++ "/sessions"},root ++ "/home/.pi/agent",root ++ "/home/.pi/agent/sessions",assets},None{}},Picker.Current{},Picker.Browse{})
    waitLoaded(modal,loads,Picker.Current{},10000n)
    emit("current",modal,loader)
    selectScope(modal,loader)
    waitLoaded(modal,loads,Picker.All{},10000n)
    emit("all",modal,loader)
    selectScope(modal,loader)
    state : Picker.Modal <- Ref.read(Picker.Modal,modal)
    unused : Picker.Mutation <- Picker.beginLoadedRename(modal,openState(state),loader)
    renamed : Picker.Modal <- Ref.read(Picker.Modal,modal)
    +info : Session.SessionInfo <- target(renamed)
    +ids : Uuid.Generator <- Uuid.generator()
    +saved : Bool <- Picker.renameStored(ids,info,"Renamed target")
    require(saved,"native rename failed")
    mutation : Picker.Mutation <- Picker.renameSaved(modal,loader,info,"Renamed target",saved)
    Picker.refreshMutation(modal,loader,mutation)
    waitLoaded(modal,loads,Picker.Current{},10000n)
    emit("renamed-current",modal,loader)
    selectScope(modal,loader)
    waitLoaded(modal,loads,Picker.All{},10000n)
    emit("renamed-all",modal,loader)
    deleting : Picker.Modal <- Ref.read(Picker.Modal,modal)
    +bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),R.new(List<&2,Keys.KeyId>))
    +words : Ref.Ref<Words.Source> <- Ref.new(Words.Source,Words.Pending{assets ++ "/packages/runtime/data"})
    # Confirmation never edits the query or invokes a selection callback.
    +chosen : Callback.Callback<String,Unit> <- Callback.create(~Unit,~String,~Unit,~ignoredChoice,Unit{})
    deleted : Picker.Mutation <- Picker.modalDeleteAction(modal,bindings,words,chosen,openState(deleting),Picker.infoPath(info),"\r",Picker.Confirm{},loader)
    Picker.refreshMutation(modal,loader,deleted)
    waitLoaded(modal,loads,Picker.All{},10000n)
    emit("deleted-all",modal,loader)
    selectScope(modal,loader)
    waitLoaded(modal,loads,Picker.Current{},10000n)
    emit("deleted-current",modal,loader)
    Picker.stopHostLoading(loader)
    Picker.disposeLoader(loader)
    oldModal : Picker.Modal <- Ref.dispose(Picker.Modal,modal)
    oldRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    oldWords : Words.Source <- Ref.dispose(Words.Source,words)
    Callback.dispose(String,Unit,chosen)
    finishIds(ids)
def args(values: List<String>) -> IO(Unit):
  match values: case root <> assets <> Nil{}: run(root,assets) case _: IO.die(Unit,1,"expected root assets")
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

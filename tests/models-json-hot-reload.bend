import Base
import ./models-json.bend as Fixture
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/providers/radius.bend as Radius
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/coding-agent/src/core/auth-storage.bend as Storage
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/components/model-selector.bend as Picker
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/utils/ansi.bend as Ansi
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys

def present(model: Maybe<&2,Models.Model()>) -> Bool: Maybe.is_some(&2,Models.Model(),model)

def state(+runtime: Models.ModelRuntime) -> IO(String):
  do IO<String>:
    old : Maybe<&2,Models.Model()> <- Models.getModel(runtime,"old-provider","old-model")
    new : Maybe<&2,Models.Model()> <- Models.getModel(runtime,"new-provider","new-model")
    return Bool.pick(String,present(old),"old","-") ++ "/" ++ Bool.pick(String,present(new),"new","-")

def written(result: Result<&2,&2,FS.Error,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{_}: IO.die(Unit,1,"could not replace models.json")

def rendered(pair: Picker.State & List<&2,String>) -> String:
  match pair:
    case (_,lines): Ansi.stripAnsi(String.join(lines,"\n"))

def selectorText(state: Picker.State) -> IO(String):
  do IO<String>:
    theme : Theme.Theme = Theme.create("test",Color.TrueColor{},Record.new(Color.Color),Record.new(Color.Color))
    bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>))
    output : Picker.State & List<&2,String> <- Picker.render(state,theme,bindings,120n)
    return rendered(output)

def run(+path: String,replacement: String) -> IO(Unit):
  do IO<Unit>:
    owner : Storage.AuthStorageOwner <- Storage.inMemory(Record.new(Auth.Credential))
    store : Auth.CredentialStore <- Fixture.storeOf(Storage.borrow(owner))
    codex : Auth.OAuthAuth <- Fixture.oauth("Codex")
    anthropic : Auth.OAuthAuth <- Fixture.oauth("Anthropic")
    fetch : Fetch.Fetch(Unit) <- Callback.create(~Unit,~(Fetch.Input<Unit>),~(Fetch.Result_(Unit)),~Fixture.offline,Unit{})
    +runtime : Models.ModelRuntime <- Models.createWithModelsPath(store,codex,Some{anthropic},Radius.RadiusTransport{fetch,Fixture.urlContext()},Some{path})
    +before : String <- state(runtime)
    initial : List<&2,Models.Model()> <- Models.getAvailableSnapshot(runtime)
    picker : Picker.State = Picker.createScoped(initial,Nil{},None{},"",None{})
    write : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,replacement)
    written(write)
    refreshed : Models.ModelsRefreshResult <- Models.refreshShared(runtime,None{})
    +after : String <- state(runtime)
    available : List<&2,Models.Model()> <- Models.getAvailableSnapshot(runtime)
    +display : String <- selectorText(Picker.refreshedState(picker,available,"Model catalogs refreshed."))
    Bool.pick(Unit -> IO(Unit),String.eq(before,"old/-") && String.eq(after,"-/new"),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"models.json refresh did not replace the provider"))(Unit{})
    Bool.pick(Unit -> IO(Unit),String.contains(display,"new-model [new-provider]") && Bool.not(String.contains(display,"old-model [old-provider]")),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"model selector still shows stale models"))(Unit{})
    IO.print(before ++ " -> " ++ after)
    Models.dispose(runtime)

def runArgs(args: List<String>) -> IO(Unit):
  match args:
    case path <> replacement <> Nil{}: run(path,replacement)
    case _: IO.die(Unit,2,"usage: models-json-hot-reload <path> <replacement-json>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    runArgs(args)

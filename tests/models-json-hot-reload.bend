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

def run(+path: String,replacement: String) -> IO(Unit):
  do IO<Unit>:
    owner : Storage.AuthStorageOwner <- Storage.inMemory(Record.new(Auth.Credential))
    store : Auth.CredentialStore <- Fixture.storeOf(Storage.borrow(owner))
    codex : Auth.OAuthAuth <- Fixture.oauth("Codex")
    anthropic : Auth.OAuthAuth <- Fixture.oauth("Anthropic")
    fetch : Fetch.Fetch(Unit) <- Callback.create(~Unit,~(Fetch.Input<Unit>),~(Fetch.Result_(Unit)),~Fixture.offline,Unit{})
    +runtime : Models.ModelRuntime <- Models.createWithModelsPath(store,codex,Some{anthropic},Radius.RadiusTransport{fetch,Fixture.urlContext()},Some{path})
    +before : String <- state(runtime)
    write : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,replacement)
    written(write)
    refreshed : Models.ModelsRefreshResult <- Models.refresh(runtime,Models.ModelsRefreshOptions{Some{False{}},None{},None{},None{}})
    +after : String <- state(runtime)
    Bool.pick(Unit -> IO(Unit),String.eq(before,"old/-") && String.eq(after,"-/new"),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"models.json refresh did not replace the provider"))(Unit{})
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

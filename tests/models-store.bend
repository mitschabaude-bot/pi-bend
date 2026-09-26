import Base
import ../packages/coding-agent/src/core/models-store.bend as FileStore
import ../packages/ai/src/models-store.bend as Store
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/serial-resource.bend as Serial

# upstream packages/coding-agent/test/models-store.test.ts (FileModelsStore).
# tests/models_store_check.py prepares the files (and the held lock), runs one
# mode per upstream case and checks what the file system shows afterwards.
# Separate stores of one path share a read state as upstream's instances do;
# a store with its own read state stands for a fresh process.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def model(provider: String, +id: String) -> T.Model<T.JsonValue>:
  T.Model{id, id, T.OpenAICompletionsApi{}, provider, "https://example.test/v1", False{}, None{}, [T.InputText{}], None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def entry(+provider: String, id: String, checkedAt: U32) -> Store.ModelsStoreEntry:
  Store.ModelsStoreEntry{[model(provider, id)], None{}, Some{F.fromU32(checkedAt)}, None{}}

def ids(models: List<&2, T.Model<T.JsonValue>>) -> String:
  match models:
    case Nil{}: ""
    case model <> Nil{}: T.modelId(model)
    case model <> rest: T.modelId(model) ++ "," ++ ids(rest)

def modelIds(result: Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)) -> String:
  match result:
    case Done{Some{Store.ModelsStoreEntry{models, _, _, _}}}: ids(models)
    case Done{None{}}: "<undefined>"
    case Fail{message}: "<error " ++ message ++ ">"

def checkedAt(result: Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)) -> F64:
  match result:
    case Done{Some{Store.ModelsStoreEntry{_, _, Some{value}, _}}}: value
    case _: F.fromU32(0)

def storeOn(path: String, pair: FileStore.FileModelsReadState & Serial.Handle<FileStore.ReadState>) -> IO(Store.ModelsStore):
  match pair:
    case (_, handle): FileStore.fileModelsStore(path, handle)

def fresh(path: String) -> IO(Store.ModelsStore):
  do IO<Store.ModelsStore>:
    state : FileStore.FileModelsReadState <- FileStore.newReadState()
    storeOn(path, FileStore.borrowReadState(state))

def persists(+path: String) -> IO(Unit):
  do IO<Unit>:
    +store : Store.ModelsStore <- fresh(path)
    one : Store.StoreResult(Unit) <- Store.write(store, "one", entry("one", "m1", 100), None{})
    two : Store.StoreResult(Unit) <- Store.write(store, "two", entry("two", "m2", 200), None{})
    +reloaded : Store.ModelsStore <- fresh(path)
    +first : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(reloaded, "one", None{})
    second : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(reloaded, "two", None{})
    deleted : Store.StoreResult(Unit) <- Store.delete(reloaded, "one", None{})
    gone : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(reloaded, "one", None{})
    kept : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(reloaded, "two", None{})
    check(String.eq(modelIds(first), "m1") && F64.is_eq(checkedAt(first), F.fromU32(100)) && String.eq(modelIds(second), "m2") && String.eq(modelIds(gone), "<undefined>") && String.eq(modelIds(kept), "m2"), "FileModelsStore persists provider catalogs without replacing unrelated providers")

def preservesMode(+path: String) -> IO(Unit):
  do IO<Unit>:
    store : Store.ModelsStore <- fresh(path)
    written : Store.StoreResult(Unit) <- Store.write(store, "one", entry("one", "m1", 100), None{})
    check(Result.is_done(&2, &2, String, Unit, written), "FileModelsStore preserves the mode of an existing models file")

def coalescedWith(+path: String, +otherPath: String, pair: FileStore.FileModelsReadState & Serial.Handle<FileStore.ReadState>) -> IO(Unit):
  match pair:
    case (_, +handle):
      do IO<Unit>:
        +first : Store.ModelsStore <- FileStore.fileModelsStore(path, handle)
        +second : Store.ModelsStore <- FileStore.fileModelsStore(path, handle)
        one : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(first, "one", None{})
        two : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(second, "two", None{})
        missing : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(first, "missing", None{})
        again : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(second, "one", None{})
        +other : Store.ModelsStore <- fresh(otherPath)
        otherOne : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(other, "one", None{})
        otherAgain : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(other, "one", None{})
        +third : Store.ModelsStore <- FileStore.fileModelsStore(path, handle)
        rewritten : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, "{\"one\":{\"models\":[{\"id\":\"newest-model\",\"name\":\"newest-model\",\"api\":\"openai-completions\",\"provider\":\"one\",\"baseUrl\":\"https://example.test/v1\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":1000,\"maxTokens\":100}]}}")
        firstReload : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(first, "one", None{})
        thirdReload : Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>) <- Store.read(third, "one", None{})
        check(String.eq(modelIds(one), "old") && String.eq(modelIds(two), "m2") && String.eq(modelIds(missing), "<undefined>") && String.eq(modelIds(again), "old") && String.eq(modelIds(otherOne), "<undefined>") && String.eq(modelIds(otherAgain), "<undefined>") && String.eq(modelIds(firstReload), "newest-model") && String.eq(modelIds(thirdReload), "newest-model"), "FileModelsStore coalesces file reloads across concurrent readers and interleaved storage instances")

# Two stores of the shared path (one read state), a third store of it, and a
# store of another path; the file changes underneath between reads.
def coalesces(+path: String, +otherPath: String) -> IO(Unit):
  do IO<Unit>:
    state : FileStore.FileModelsReadState <- FileStore.newReadState()
    coalescedWith(path, otherPath, FileStore.borrowReadState(state))

def abortSoon(controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(10)
    aborted : Bool <- Abort.abort(Unit, controller, None{})
    return Unit{}

def isAbort(result: Store.StoreResult(Unit)) -> Bool:
  match result:
    case Fail{message}: String.contains(message, "aborted")
    case Done{_}: False{}

# The lock is held by tests/models_store_check.py; the write is cancelled
# 10 ms after it starts waiting.
def cancelsWrite(+path: String) -> IO(Unit):
  do IO<Unit>:
    store : Store.ModelsStore <- fresh(path)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    canceller : Chan(Unit) <- IO.fork(Unit, abortSoon(controller))
    pending : Store.StoreResult(Unit) <- Store.write(store, "two", entry("two", "cancelled", 1), Some{Abort.signal(Unit, controller)})
    done : Unit <- IO.join(Unit, canceller)
    check(isAbort(pending), "FileModelsStore cancels a catalog write waiting for a held file lock without writing later")

def started(args: List<String>) -> IO(Unit):
  match args:
    case "persist" <> path <> Nil{}: persists(path)
    case "mode" <> path <> Nil{}: preservesMode(path)
    case "coalesce" <> path <> other <> Nil{}: coalesces(path, other)
    case "cancel" <> path <> Nil{}: cancelsWrite(path)
    case _: IO.die(Unit, 2, "usage: models-store <persist|mode|coalesce|cancel> <path> [other path]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)

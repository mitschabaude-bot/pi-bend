import Base
import ./auth-storage.bend as AuthStorage
import ./model-config.bend as ModelConfig
import ./provider-composer.bend as Composer
import ../utils/paths.bend as Paths
import ../../../ai/src/types.bend as T
import ../../../ai/src/models-store.bend as Store
import ../../../ai/src/utils/json.bend as Render
import ../../../ai/src/utils/model-api.bend as Api
import ../../../ai/src/utils/model-json.bend as ModelJson
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/file-lock.bend as Lock
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/utf8.bend as Utf8

# upstream core/models-store.ts FileModelsStore: provider catalogs persisted
# in models-store.json under auth.json's locking protocol. The file keeps
# other providers' entries as written (raw JSON); entries decode to typed
# models on read. Reads reuse the last load while the file revision is
# unchanged; concurrent readers of one read state wait for a single reload
# (upstream shares a module-level read state per path; here the caller shares
# the FileModelsReadState explicitly).

def Signal() -> Data: Store.Signal()

def StoredData() -> Data: R.Record<V.Value>

type ReadState is Data:
  ReadState{data: StoredData(), revision: Maybe<&2, String>}

type FileModelsReadState is Type:
  FileModelsReadState{owner: Serial.Owner<ReadState>}

type FileModelsStore is Data:
  FileModelsStore{path: String, state: Serial.Handle<ReadState>}

def newReadState() -> IO(FileModelsReadState):
  do IO<FileModelsReadState>:
    owner : Serial.Owner<ReadState> <- Serial.create(ReadState, ReadState{R.new(V.Value), None{}})
    return FileModelsReadState{owner}

def borrowed(pair: Serial.Owner<ReadState> & Serial.Handle<ReadState>) -> FileModelsReadState & Serial.Handle<ReadState>:
  match pair:
    case (owner, handle): (FileModelsReadState{owner}, handle)

def borrowReadState(state: FileModelsReadState) -> FileModelsReadState & Serial.Handle<ReadState>:
  match state:
    case FileModelsReadState{owner}: borrowed(Serial.borrow(ReadState, owner))

def disposeReadState(state: FileModelsReadState) -> IO(Unit):
  match state:
    case FileModelsReadState{owner}:
      do IO<Unit>:
        last : ReadState <- Serial.retire(ReadState, owner)
        return Unit{}

# Entry codec
# -----------

def optionalNumber(+name: String, value: Maybe<&2, F64>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{number}: [R.Property{name, V.Number{number}}]
    case None{}: Nil{}

def modelValues(models: List<&2, T.Model<T.JsonValue>>) -> List<&2, V.Value>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: ModelJson.model(model) <> modelValues(rest)

def etagField(etag: Maybe<&2, String>) -> List<&2, R.Property<V.Value>>:
  match etag:
    case Some{text}: [R.Property{"etag", V.Text{text}}]
    case None{}: Nil{}

def encodeEntry(entry: Store.ModelsStoreEntry) -> V.Value:
  match entry:
    case Store.ModelsStoreEntry{models, lastModified, checkedAt, etag}:
      V.ObjectValue{R.Record{R.Property{"models", V.ArrayValue{modelValues(models)}} <> List.append(&2, R.Property<V.Value>, optionalNumber("lastModified", lastModified), List.append(&2, R.Property<V.Value>, optionalNumber("checkedAt", checkedAt), etagField(etag)))}}

def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def numberOf(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{number}}: Some{number}
    case _: None{}

def textEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, V.Text{value}} <> rest: R.Property{key, value} <> textEntries(rest)
    case _ <> rest: textEntries(rest)

def headersOf(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<String>>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{R.Record{textEntries(R.entries(V.Value, properties))}}
    case _: None{}

def withHeaders(model: T.Model<T.JsonValue>, headers: Maybe<&2, R.Record<String>>) -> T.Model<T.JsonValue>:
  match model:
    case T.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, _, compat}: T.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def modelField(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def decodedModel(+providerId: String, +value: V.Value) -> T.Model<T.JsonValue>:
  +definition = ModelConfig.modelOf(value)
  withHeaders(Composer.builtModel(Maybe.default(&2, String, textOf(modelField(value, "provider")), providerId), definition, None{}, Api.fromString(Maybe.default(&2, String, textOf(modelField(value, "api")), "")), Maybe.default(&2, String, textOf(modelField(value, "baseUrl")), "")), headersOf(modelField(value, "headers")))

def decodedModels(+providerId: String, values: List<&2, V.Value>) -> List<&2, T.Model<T.JsonValue>>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: decodedModel(providerId, value) <> decodedModels(providerId, rest)

def modelsIn(+providerId: String, value: Maybe<&2, V.Value>) -> List<&2, T.Model<T.JsonValue>>:
  match value:
    case Some{V.ArrayValue{values}}: decodedModels(providerId, values)
    case _: Nil{}

def decodeEntry(+providerId: String, value: V.Value) -> Maybe<&2, Store.ModelsStoreEntry>:
  match value:
    case V.ObjectValue{+fields}: Some{Store.ModelsStoreEntry{modelsIn(providerId, R.get(V.Value, fields, "models")), numberOf(R.get(V.Value, fields, "lastModified")), numberOf(R.get(V.Value, fields, "checkedAt")), textOf(R.get(V.Value, fields, "etag"))}}
    case _: None{}

def stripBom(text: String) -> String:
  match text:
    case SCon{'\u{feff}', rest}: rest
    case other: other

def parsedObject(result: Result<&2, &2, Json.ParseError, V.Value>) -> Result<&2, &2, String, StoredData()>:
  match result:
    case Done{V.ObjectValue{fields}}: Done{fields}
    case Done{_}: Done{R.new(V.Value)}
    case Fail{_}: Fail{"Unexpected token in models-store.json"}

# upstream parse: an empty file is {}.
def parseStored(content: String) -> Result<&2, &2, String, StoredData()>:
  match content:
    case SNil{}: Done{R.new(V.Value)}
    case text: parsedObject(Json.parse(stripBom(text)))

# JSON.stringify(current, null, 2)
def serialized(data: StoredData()) -> String: Maybe.default(&2, String, Render.stringifyPretty(SchemaJson.toJson(V.ObjectValue{data})), "{}")

# Locked file access
# ------------------

# What one locked transaction does with the stored data.
type Change is Data:
  Reload{}
  Put{providerId: String, entry: Store.ModelsStoreEntry}
  Remove{providerId: String}

def changed(change: Change, data: StoredData()) -> StoredData() & Maybe<&2, String>:
  match change:
    case Reload{}: (data, None{})
    case Put{providerId, entry}:
      +next = R.set(V.Value, data, providerId, encodeEntry(entry))
      (next, Some{serialized(next)})
    case Remove{providerId}:
      +next = R.remove(V.Value, data, providerId)
      (next, Some{serialized(next)})

def abortedMessage() -> String: "The operation was aborted"

def aborted(signal: Signal()) -> IO(Bool):
  match signal:
    case Some{value}: Abort.aborted(Unit, value)
    case None{}: IO.pure(Bool, False{})

def lockText(error: Lock.Error) -> String: AuthStorage.lockMessage(error)

def written(+data: StoredData(), result: Result<&2, &2, FS.Error, Unit>) -> Result<&2, &2, String, StoredData()>:
  match result:
    case Done{_}: Done{data}
    case Fail{error}: Fail{FS.errorMessage(error)}

def commitChecked(+path: String, +data: StoredData(), next: String, cancelled: Bool, checked: Result<&2, &2, Lock.Error, Unit>) -> IO(Result<&2, &2, String, StoredData()>):
  match cancelled checked:
    case True{} _: IO.pure(Result<&2, &2, String, StoredData()>, Fail{abortedMessage()})
    case False{} Fail{error}: IO.pure(Result<&2, &2, String, StoredData()>, Fail{lockText(error)})
    case False{} Done{_}:
      do IO<Result<&2, &2, String, StoredData()>>:
        result : Result<&2, &2, FS.Error, Unit> <- FS.writeFileMode(path, next, 384)
        return written(data, result)

def committed(+path: String, signal: Signal(), handle: Lock.Handle, pair: StoredData() & Maybe<&2, String>) -> IO(Result<&2, &2, String, StoredData()>):
  match pair:
    case (+data, None{}): IO.pure(Result<&2, &2, String, StoredData()>, Done{data})
    case (+data, Some{next}):
      do IO<Result<&2, &2, String, StoredData()>>:
        cancelled : Bool <- aborted(signal)
        checked : Result<&2, &2, Lock.Error, Unit> <- Lock.check(handle)
        commitChecked(path, data, next, cancelled, checked)

def contentOf(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: Utf8.decodeBuffer(bytes)
    case Fail{_}: ""

def applied(+path: String, signal: Signal(), handle: Lock.Handle, change: Change, parsed: Result<&2, &2, String, StoredData()>) -> IO(Result<&2, &2, String, StoredData()>):
  match parsed:
    case Fail{message}: IO.pure(Result<&2, &2, String, StoredData()>, Fail{message})
    case Done{data}: committed(path, signal, handle, changed(change, data))

def insideLock(+path: String, +signal: Signal(), handle: Lock.Handle, change: Change, cancelled: Bool) -> IO(Result<&2, &2, String, StoredData()>):
  match cancelled:
    case True{}: IO.pure(Result<&2, &2, String, StoredData()>, Fail{abortedMessage()})
    case False{}:
      do IO<Result<&2, &2, String, StoredData()>>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        applied(path, signal, handle, change, parseStored(contentOf(bytes)))

def revisionAfter(+path: String, result: Result<&2, &2, String, StoredData()>) -> IO(Result<&2, &2, String, StoredData()> & Maybe<&2, String>):
  do IO<Result<&2, &2, String, StoredData()> & Maybe<&2, String>>:
    revision : Maybe<&2, String> <- Paths.getFileRevision(path)
    return (result, revision)

def released(result: Result<&2, &2, String, StoredData()>, release: Result<&2, &2, Lock.Error, Unit>) -> Result<&2, &2, String, StoredData()>:
  match result release:
    case Done{data} Fail{error}: Fail{lockText(error)}
    case other _: other

def withOwner(+path: String, +signal: Signal(), change: Change, pair: Lock.Owner & Lock.Handle) -> IO(Result<&2, &2, String, StoredData()>):
  match pair:
    case (owner, handle):
      do IO<Result<&2, &2, String, StoredData()>>:
        cancelled : Bool <- aborted(signal)
        result : Result<&2, &2, String, StoredData()> <- insideLock(path, signal, handle, change, cancelled)
        release : Result<&2, &2, Lock.Error, Unit> <- Lock.release(owner)
        return released(result, release)

def acquired(+path: String, +signal: Signal(), change: Change, owner: Result<&2, &1, String, Lock.Owner>) -> IO(Result<&2, &2, String, StoredData()>):
  match owner:
    case Fail{message}: IO.pure(Result<&2, &2, String, StoredData()>, Fail{message})
    case Done{value}: withOwner(path, signal, change, Lock.borrow(value))

def ensureFile(+path: String, present: Bool) -> IO(Unit):
  match present:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        created : Result<&2, &2, FS.Error, Unit> <- FS.writeFileMode(path, "{}", 384)
        return Unit{}

# upstream withLockAsync: parent directory and an empty-object file first,
# then the lock (30 s deadline, cancellable), the change, and the write.
def withLock(+path: String, +signal: Signal(), change: Change, cancelled: Bool) -> IO(Result<&2, &2, String, StoredData()>):
  match cancelled:
    case True{}: IO.pure(Result<&2, &2, String, StoredData()>, Fail{abortedMessage()})
    case False{}:
      do IO<Result<&2, &2, String, StoredData()>>:
        parent : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(Path.join(path, ".."))
        present : Bool <- FS.accessible(path, 0)
        ensureFile(path, present)
        now : F64 <- Date.now()
        owner : Result<&2, &1, String, Lock.Owner> <- AuthStorage.acquireAuthLock(path, signal, F.add(now, F.fromU32(30000)))
        acquired(path, signal, change, owner)

def locked(+path: String, +signal: Signal(), change: Change) -> IO(Result<&2, &2, String, StoredData()>):
  do IO<Result<&2, &2, String, StoredData()>>:
    cancelled : Bool <- aborted(signal)
    withLock(path, signal, change, cancelled)

# Operations
# ----------

def keptOr(state: ReadState, result: Result<&2, &2, String, StoredData()>, revision: Maybe<&2, String>) -> ReadState & Result<&2, &2, String, StoredData()>:
  match result:
    case Done{+data}: (ReadState{data, revision}, Done{data})
    case Fail{message}: (state, Fail{message})

def reloaded(+path: String, +signal: Signal(), state: ReadState) -> IO(ReadState & Result<&2, &2, String, StoredData()>):
  do IO<ReadState & Result<&2, &2, String, StoredData()>>:
    result : Result<&2, &2, String, StoredData()> <- locked(path, signal, Reload{})
    revision : Maybe<&2, String> <- Paths.getFileRevision(path)
    return keptOr(state, result, revision)

def sameRevision(current: Maybe<&2, String>, cached: Maybe<&2, String>) -> Bool:
  match current cached:
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

# upstream readLatest: an unchanged revision serves the cached data.
def latest(+path: String, +signal: Signal(), +current: Maybe<&2, String>, state: ReadState) -> IO(ReadState & Result<&2, &2, String, StoredData()>):
  match state:
    case ReadState{+data, +revision}: Bool.pick(Unit -> IO(ReadState & Result<&2, &2, String, StoredData()>), sameRevision(current, revision), _ => IO.pure(ReadState & Result<&2, &2, String, StoredData()>, (ReadState{data, revision}, Done{data})), _ => reloaded(path, signal, ReadState{data, revision}))(Unit{})

def entryOf(+providerId: String, data: Result<&2, &2, String, StoredData()>, cancelled: Bool) -> Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>):
  match data cancelled:
    case Fail{message} _: Fail{message}
    case _ True{}: Fail{abortedMessage()}
    case Done{found} False{}: Done{Maybe.bind(&2, V.Value, Store.ModelsStoreEntry, R.get(V.Value, found, providerId), value => decodeEntry(providerId, value))}

def readEntry(store: FileModelsStore, request: Store.StoreRequest) -> IO(Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)):
  match store request:
    case FileModelsStore{+path, state} Store.StoreRequest{+providerId, +signal}:
      do IO<Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)>:
        cancelled : Bool <- aborted(signal)
        Bool.pick(Unit -> IO(Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)), cancelled, _ => IO.pure(Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>), Fail{abortedMessage()}), _ => do IO<Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)>:
          +current : Maybe<&2, String> <- Paths.getFileRevision(path)
          data : Result<&2, &2, String, StoredData()> <- Serial.run(ReadState, Result<&2, &2, String, StoredData()>, state, cached => latest(path, signal, current, cached))
          after : Bool <- aborted(signal)
          return entryOf(providerId, data, after))(Unit{})

def replacedState(result: Result<&2, &2, String, StoredData()>, state: ReadState) -> IO(ReadState & Store.StoreResult(Unit)):
  match result:
    case Done{data}: IO.pure(ReadState & Store.StoreResult(Unit), (ReadState{data, None{}}, Done{Unit{}}))
    case Fail{message}: IO.pure(ReadState & Store.StoreResult(Unit), (state, Fail{message}))

def changedStore(store: FileModelsStore, +signal: Signal(), change: Change) -> IO(Store.StoreResult(Unit)):
  match store:
    case FileModelsStore{+path, state}:
      do IO<Store.StoreResult(Unit)>:
        result : Result<&2, &2, String, StoredData()> <- locked(path, signal, change)
        Serial.run(ReadState, Store.StoreResult(Unit), state, current => replacedState(result, current))

def writeEntry(store: FileModelsStore, request: Store.StoreWrite) -> IO(Store.StoreResult(Unit)):
  match request:
    case Store.StoreWrite{providerId, entry, signal}: changedStore(store, signal, Put{providerId, entry})

def deleteEntry(store: FileModelsStore, request: Store.StoreRequest) -> IO(Store.StoreResult(Unit)):
  match request:
    case Store.StoreRequest{providerId, signal}: changedStore(store, signal, Remove{providerId})

def storeCallbacks(+store: FileModelsStore) -> IO(Store.ModelsStore):
  do IO<Store.ModelsStore>:
    reader : C.Callback<Store.StoreRequest, Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>)> <- C.create(~FileModelsStore, ~Store.StoreRequest, ~Store.StoreResult(Maybe<&2, Store.ModelsStoreEntry>), ~readEntry, store)
    writer : C.Callback<Store.StoreWrite, Store.StoreResult(Unit)> <- C.create(~FileModelsStore, ~Store.StoreWrite, ~Store.StoreResult(Unit), ~writeEntry, store)
    deleter : C.Callback<Store.StoreRequest, Store.StoreResult(Unit)> <- C.create(~FileModelsStore, ~Store.StoreRequest, ~Store.StoreResult(Unit), ~deleteEntry, store)
    return Store.ModelsStore{reader, writer, deleter}

# upstream new FileModelsStore(path): the read state is shared by the stores
# of one path.
def fileModelsStore(path: String, state: Serial.Handle<ReadState>) -> IO(Store.ModelsStore): storeCallbacks(FileModelsStore{path, state})


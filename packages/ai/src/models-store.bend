import Base
import ./types.bend as T
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref

# upstream models-store.ts: provider-scoped persisted model catalogs. The
# store is an injectable interface; InMemoryModelsStore is the in-process
# implementation (upstream FileModelsStore, models-store.json, is not ported).

type ModelsStoreEntry is Data:
  ModelsStoreEntry{models: List<&2, T.Model<T.JsonValue>>, lastModified: Maybe<&2, F64>, checkedAt: Maybe<&2, F64>, etag: Maybe<&2, String>}

def Signal() -> Data: Maybe<&2, Abort.AbortSignal<Unit>>

type StoreRequest is Data:
  StoreRequest{providerId: String, signal: Signal()}

type StoreWrite is Data:
  StoreWrite{providerId: String, entry: ModelsStoreEntry, signal: Signal()}

# Failures are the message upstream's rejected promise carries.
def StoreResult(-A: Data) -> Data: Result<&2, &2, String, A>

type ModelsStore is Data:
  ModelsStore{read: C.Callback<StoreRequest, StoreResult(Maybe<&2, ModelsStoreEntry>)>, write: C.Callback<StoreWrite, StoreResult(Unit)>, delete: C.Callback<StoreRequest, StoreResult(Unit)>}

def read(store: ModelsStore, providerId: String, signal: Signal()) -> IO(StoreResult(Maybe<&2, ModelsStoreEntry>)):
  match store:
    case ModelsStore{callback, _, _}: C.call(StoreRequest, StoreResult(Maybe<&2, ModelsStoreEntry>), callback, StoreRequest{providerId, signal})

def write(store: ModelsStore, providerId: String, entry: ModelsStoreEntry, signal: Signal()) -> IO(StoreResult(Unit)):
  match store:
    case ModelsStore{_, callback, _}: C.call(StoreWrite, StoreResult(Unit), callback, StoreWrite{providerId, entry, signal})

def delete(store: ModelsStore, providerId: String, signal: Signal()) -> IO(StoreResult(Unit)):
  match store:
    case ModelsStore{_, _, callback}: C.call(StoreRequest, StoreResult(Unit), callback, StoreRequest{providerId, signal})

def dispose(store: ModelsStore) -> IO(Unit):
  match store:
    case ModelsStore{reader, writer, deleter}:
      do IO<Unit>:
        C.dispose(StoreRequest, StoreResult(Maybe<&2, ModelsStoreEntry>), reader)
        C.dispose(StoreWrite, StoreResult(Unit), writer)
        C.dispose(StoreRequest, StoreResult(Unit), deleter)

# InMemoryModelsStore
# -------------------

def Entries() -> Data: Ref.Ref<R.Record<ModelsStoreEntry>>

# upstream options.signal?.throwIfAborted()
def unlessAborted(signal: Signal()) -> IO(StoreResult(Unit)):
  match signal:
    case None{}: IO.pure(StoreResult(Unit), Done{Unit{}})
    case Some{signal}:
      do IO<StoreResult(Unit)>:
        aborted : Bool <- Abort.aborted(Unit, signal)
        return Bool.pick(StoreResult(Unit), aborted, Fail{"This operation was aborted"}, Done{Unit{}})

def entryIf(allowed: StoreResult(Unit), found: Maybe<&2, ModelsStoreEntry>) -> StoreResult(Maybe<&2, ModelsStoreEntry>):
  match allowed:
    case Fail{error}: Fail{error}
    case Done{_}: Done{found}

def readEntry(entries: Entries(), request: StoreRequest) -> IO(StoreResult(Maybe<&2, ModelsStoreEntry>)):
  match request:
    case StoreRequest{providerId, signal}:
      do IO<StoreResult(Maybe<&2, ModelsStoreEntry>)>:
        allowed : StoreResult(Unit) <- unlessAborted(signal)
        current : R.Record<ModelsStoreEntry> <- Ref.read(R.Record<ModelsStoreEntry>, entries)
        return entryIf(allowed, R.get(ModelsStoreEntry, current, providerId))

def writeAllowed(entries: Entries(), +providerId: String, entry: ModelsStoreEntry, allowed: StoreResult(Unit)) -> IO(StoreResult(Unit)):
  match allowed:
    case Fail{error}: IO.pure(StoreResult(Unit), Fail{error})
    case Done{_}:
      do IO<StoreResult(Unit)>:
        Ref.modify(R.Record<ModelsStoreEntry>, Unit, entries, current => (R.set(ModelsStoreEntry, current, providerId, entry), Unit{}))
        return Done{Unit{}}

def writeEntry(entries: Entries(), request: StoreWrite) -> IO(StoreResult(Unit)):
  match request:
    case StoreWrite{providerId, entry, signal}:
      do IO<StoreResult(Unit)>:
        allowed : StoreResult(Unit) <- unlessAborted(signal)
        writeAllowed(entries, providerId, entry, allowed)

def deleteAllowed(entries: Entries(), +providerId: String, allowed: StoreResult(Unit)) -> IO(StoreResult(Unit)):
  match allowed:
    case Fail{error}: IO.pure(StoreResult(Unit), Fail{error})
    case Done{_}:
      do IO<StoreResult(Unit)>:
        Ref.modify(R.Record<ModelsStoreEntry>, Unit, entries, current => (R.remove(ModelsStoreEntry, current, providerId), Unit{}))
        return Done{Unit{}}

def deleteEntry(entries: Entries(), request: StoreRequest) -> IO(StoreResult(Unit)):
  match request:
    case StoreRequest{providerId, signal}:
      do IO<StoreResult(Unit)>:
        allowed : StoreResult(Unit) <- unlessAborted(signal)
        deleteAllowed(entries, providerId, allowed)

# The entries live as long as the store's callbacks.
def inMemoryModelsStore() -> IO(ModelsStore):
  do IO<ModelsStore>:
    +entries : Entries() <- Ref.new(R.Record<ModelsStoreEntry>, R.new(ModelsStoreEntry))
    reader : C.Callback<StoreRequest, StoreResult(Maybe<&2, ModelsStoreEntry>)> <- C.create(~Entries(), ~StoreRequest, ~StoreResult(Maybe<&2, ModelsStoreEntry>), ~readEntry, entries)
    writer : C.Callback<StoreWrite, StoreResult(Unit)> <- C.create(~Entries(), ~StoreWrite, ~StoreResult(Unit), ~writeEntry, entries)
    deleter : C.Callback<StoreRequest, StoreResult(Unit)> <- C.create(~Entries(), ~StoreRequest, ~StoreResult(Unit), ~deleteEntry, entries)
    return ModelsStore{reader, writer, deleter}

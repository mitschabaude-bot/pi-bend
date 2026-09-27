import Base
import ./types.bend as Auth
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref

# upstream auth/credential-store.ts: InMemoryCredentialStore, the default
# credential store of a Models collection (apps inject persistent stores).
# One credential per provider id. Reads and lists see the current entries
# without waiting; modify and delete run one at a time. Upstream chains them
# per provider id; here one lock orders them across providers, which only
# makes operations on different providers wait for each other.

def Entries() -> Data: Ref.Ref<R.Record<Auth.Credential>>

type InMemory is Data:
  InMemory{entries: Entries(), lock: Ref.Ref<Unit>}

def abortedMessage() -> String: "This operation was aborted"

# upstream options.signal?.throwIfAborted()
def aborted(signal: Auth.Signal()) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{signal}: Abort.aborted(Unit, signal)

def readCredential(store: InMemory, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match store request:
    case InMemory{entries, _} Auth.Request{providerId, signal}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        stopped : Bool <- aborted(signal)
        current : R.Record<Auth.Credential> <- Ref.read(R.Record<Auth.Credential>, entries)
        return Bool.pick(Auth.StoreResult(Maybe<&2, Auth.Credential>), stopped, Fail{abortedMessage()}, Done{R.get(Auth.Credential, current, providerId)})

def infos(entries: List<&2, R.Property<Auth.Credential>>) -> List<&2, Auth.CredentialInfo>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{providerId, credential} <> rest: Auth.info(providerId, credential) <> infos(rest)

def listCredentials(store: InMemory, signal: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)):
  match store:
    case InMemory{entries, _}:
      do IO<Auth.StoreResult(List<&2, Auth.CredentialInfo>)>:
        stopped : Bool <- aborted(signal)
        current : R.Record<Auth.Credential> <- Ref.read(R.Record<Auth.Credential>, entries)
        return Bool.pick(Auth.StoreResult(List<&2, Auth.CredentialInfo>), stopped, Fail{abortedMessage()}, Done{infos(R.entries(Auth.Credential, current))})

def Modified() -> Data: Auth.StoreResult(Maybe<&2, Auth.Credential>)

# The function's replacement is stored unless the operation was aborted
# meanwhile; None leaves the entry, and the result is the entry afterwards.
def stored(entries: Entries(), +providerId: String, current: Maybe<&2, Auth.Credential>, stopped: Bool, next: Modified()) -> IO(Modified()):
  match stopped next:
    case _ Fail{error}: IO.pure(Modified(), Fail{error})
    case True{} Done{_}: IO.pure(Modified(), Fail{abortedMessage()})
    case False{} Done{None{}}: IO.pure(Modified(), Done{current})
    case False{} Done{Some{+credential}}:
      do IO<Modified()>:
        Ref.modify(R.Record<Auth.Credential>, Unit, entries, all => (R.set(Auth.Credential, all, providerId, credential), Unit{}))
        return Done{Some{credential}}

def modifyUnlessAborted(+entries: Entries(), +providerId: String, update: Auth.Modification(), +signal: Auth.Signal(), stopped: Bool) -> IO(Modified()):
  match stopped:
    case True{}: IO.pure(Modified(), Fail{abortedMessage()})
    case False{}:
      do IO<Modified()>:
        all : R.Record<Auth.Credential> <- Ref.read(R.Record<Auth.Credential>, entries)
        +current : Maybe<&2, Auth.Credential> <- IO.pure(Maybe<&2, Auth.Credential>, R.get(Auth.Credential, all, providerId))
        next : Modified() <- C.call(Maybe<&2, Auth.Credential>, Modified(), update, current)
        after : Bool <- aborted(signal)
        stored(entries, providerId, current, after, next)

def locked(entries: Entries(), providerId: String, update: Auth.Modification(), +signal: Auth.Signal(), unused: Unit) -> IO(Unit & Modified()):
  do IO<Unit & Modified()>:
    stopped : Bool <- aborted(signal)
    result : Modified() <- modifyUnlessAborted(entries, providerId, update, signal, stopped)
    return (Unit{}, result)

def modifyCredential(store: InMemory, request: Auth.Modify) -> IO(Modified()):
  match store request:
    case InMemory{entries, lock} Auth.Modify{providerId, update, signal}:
      Ref.update(Unit, Modified(), lock, unused => locked(entries, providerId, update, signal, unused))

def deleteLocked(+entries: Entries(), +providerId: String, signal: Auth.Signal(), unused: Unit) -> IO(Unit & Auth.StoreResult(Unit)):
  do IO<Unit & Auth.StoreResult(Unit)>:
    stopped : Bool <- aborted(signal)
    Bool.pick(Unit -> IO(Unit & Auth.StoreResult(Unit)), stopped, _ => IO.pure(Unit & Auth.StoreResult(Unit), (Unit{}, Fail{abortedMessage()})), _ => do IO<Unit & Auth.StoreResult(Unit)>:
      Ref.modify(R.Record<Auth.Credential>, Unit, entries, all => (R.remove(Auth.Credential, all, providerId), Unit{}))
      return (Unit{}, Done{Unit{}}))(Unit{})

def deleteCredential(store: InMemory, request: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  match store request:
    case InMemory{entries, lock} Auth.Request{providerId, signal}:
      Ref.update(Unit, Auth.StoreResult(Unit), lock, unused => deleteLocked(entries, providerId, signal, unused))

# upstream new InMemoryCredentialStore(). The entries live as long as the
# store's callbacks (Auth.disposeStore).
def inMemoryCredentialStore() -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    entries : Entries() <- Ref.new(R.Record<Auth.Credential>, R.new(Auth.Credential))
    lock : Ref.Ref<Unit> <- Ref.new(Unit, Unit{})
    +store : InMemory <- IO.pure(InMemory, InMemory{entries, lock})
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~InMemory, ~Auth.Request, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~readCredential, store)
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~InMemory, ~Auth.Signal(), ~Auth.StoreResult(List<&2, Auth.CredentialInfo>), ~listCredentials, store)
    modifier : C.Callback<Auth.Modify, Modified()> <- C.create(~InMemory, ~Auth.Modify, ~Modified(), ~modifyCredential, store)
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~InMemory, ~Auth.Request, ~Auth.StoreResult(Unit), ~deleteCredential, store)
    return Auth.CredentialStore{reader, lister, modifier, deleter}

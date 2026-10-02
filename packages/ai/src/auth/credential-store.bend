import Base
import ../../../runtime/src/deferred.bend as D
import ../../../runtime/src/cancellable-task.bend as Tasks
import ./types.bend as Auth
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref

# upstream auth/credential-store.ts: InMemoryCredentialStore, the default
# credential store of a Models collection (apps inject persistent stores).
# One credential per provider id. Reads and lists see the current entries
# without waiting; mutations reserve a place in their provider's queue before
# starting a worker. Cancellation releases queued callers while retaining their captured invocation until the
# queue advances; an aborted invocation is never run or committed.

def Entries() -> Data: Ref.Ref<R.Record<Auth.Credential>>

type Tail is Data:
  Tail{generation: Nat, done: D.Deferred<Unit>}

type QueueState is Data:
  QueueState{next: Nat, tails: R.Record<Tail>}

type Turn is Data:
  Turn{generation: Nat, previous: Maybe<&2, Tail>, done: D.Deferred<Unit>}

type InMemory is Data:
  InMemory{entries: Entries(), queue: Ref.Ref<QueueState>}

def reserved(+id: String, +done: D.Deferred<Unit>, state: QueueState) -> QueueState & Turn:
  match state:
    case QueueState{+next, +tails}:
      (QueueState{Nat.add(next, 1n), R.set(Tail, tails, id, Tail{next, done})}, Turn{next, R.get(Tail, tails, id), done})

def reserve(store: InMemory, id: String) -> IO(Turn):
  match store:
    case InMemory{_, queue}:
      do IO<Turn>:
        done : D.Deferred<Unit> <- D.new(Unit)
        Ref.modify(QueueState, Turn, queue, state => reserved(id, done, state))

def waitPrevious(previous: Maybe<&2, Tail>) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit, Unit{})
    case Some{Tail{_, done}}: D.result(Unit, done)

def retireTail(+id: String, generation: Nat, +tails: R.Record<Tail>, current: Maybe<&2, Tail>) -> R.Record<Tail>:
  match current:
    case Some{Tail{active, _}}: Bool.pick(R.Record<Tail>, Nat.is_eq(generation, active), R.remove(Tail, tails, id), tails)
    case None{}: tails

def retired(+id: String, generation: Nat, state: QueueState) -> QueueState & Unit:
  match state:
    case QueueState{next, +tails}:
      (QueueState{next, retireTail(id, generation, tails, R.get(Tail, tails, id))}, Unit{})


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

def modifyUnlessAborted(+entries: Entries(), +providerId: String, update: Maybe<&2, Auth.Credential> -> IO(Modified()), +signal: Auth.Signal(), stopped: Bool) -> IO(Modified()):
  match stopped:
    case True{}: IO.pure(Modified(), Fail{abortedMessage()})
    case False{}:
      do IO<Modified()>:
        all : R.Record<Auth.Credential> <- Ref.read(R.Record<Auth.Credential>, entries)
        +current : Maybe<&2, Auth.Credential> <- IO.pure(Maybe<&2, Auth.Credential>, R.get(Auth.Credential, all, providerId))
        next : Modified() <- update(current)
        after : Bool <- aborted(signal)
        stored(entries, providerId, current, after, next)

# Release the queue only after the active work settles. The last tail is
# removed; retained predecessor values stay alive through ordinary sharing.
def finishTurn(store: InMemory, id: String, turn: Turn) -> IO(Unit):
  match store turn:
    case InMemory{_, queue} Turn{generation, _, done}:
      do IO<Unit>:
        resolved : Bool <- D.resolve(Unit, done, Unit{})
        Ref.modify(QueueState, Unit, queue, state => retired(id, generation, state))

def modifyQueued(+store: InMemory, +id: String, +turn: Turn, update: Maybe<&2, Auth.Credential> -> IO(Modified()), +signal: Auth.Signal()) -> IO(Modified()):
  match store turn:
    case InMemory{entries, queue} Turn{generation, previous, done}:
      do IO<Modified()>:
        waitPrevious(previous)
        stopped : Bool <- aborted(signal)
        result : Modified() <- modifyUnlessAborted(entries, id, update, signal, stopped)
        finishTurn(store, id, turn)
        return result

def modifyCaptured(store: InMemory, id: String, turn: Turn, invoke: Maybe<&2, Auth.Credential> -> IO(Modified()), signal: Auth.Signal()) -> IO(Modified()):
  match signal:
    case None{}: modifyQueued(store, id, turn, invoke, None{})
    case Some{caller}: Tasks.run(Modified(), caller, child => modifyQueued(store, id, turn, invoke, Some{child}), IO.pure(Maybe<&2, Modified()>, Some{Fail{abortedMessage()}}), IO.pure(Unit, Unit{}))

def modifyCredential(store: InMemory, request: Auth.Modify) -> IO(Modified()):
  match request:
    case Auth.Modify{+providerId, update, signal}:
      do IO<Modified()>:
        +shared : InMemory = store
        invoke : (Maybe<&2, Auth.Credential> -> IO(Modified())) <- C.borrow(Maybe<&2, Auth.Credential>, Modified(), update)
        turn : Turn <- reserve(shared, providerId)
        modifyCaptured(shared, providerId, turn, invoke, signal)

def deleteUnlessAborted(entries: Entries(), +id: String, stopped: Bool) -> IO(Auth.StoreResult(Unit)):
  match stopped:
    case True{}: IO.pure(Auth.StoreResult(Unit), Fail{abortedMessage()})
    case False{}:
      do IO<Auth.StoreResult(Unit)>:
        Ref.modify(R.Record<Auth.Credential>, Unit, entries, all => (R.remove(Auth.Credential, all, id), Unit{}))
        return Done{Unit{}}

def deleteQueued(+store: InMemory, +id: String, +turn: Turn, signal: Auth.Signal()) -> IO(Auth.StoreResult(Unit)):
  match store turn:
    case InMemory{entries, queue} Turn{generation, previous, done}:
      do IO<Auth.StoreResult(Unit)>:
        waitPrevious(previous)
        stopped : Bool <- aborted(signal)
        result : Auth.StoreResult(Unit) <- deleteUnlessAborted(entries, id, stopped)
        finishTurn(store, id, turn)
        return result

def deleteCaptured(store: InMemory, id: String, turn: Turn, signal: Auth.Signal()) -> IO(Auth.StoreResult(Unit)):
  match signal:
    case None{}: deleteQueued(store, id, turn, None{})
    case Some{caller}: Tasks.run(Auth.StoreResult(Unit), caller, child => deleteQueued(store, id, turn, Some{child}), IO.pure(Maybe<&2, Auth.StoreResult(Unit)>, Some{Fail{abortedMessage()}}), IO.pure(Unit, Unit{}))

def deleteCredential(store: InMemory, request: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  match request:
    case Auth.Request{+id, signal}:
      do IO<Auth.StoreResult(Unit)>:
        +shared : InMemory = store
        turn : Turn <- reserve(shared, id)
        deleteCaptured(shared, id, turn, signal)

# upstream new InMemoryCredentialStore(). The entries live as long as the
# store's callbacks (Auth.disposeStore).
def inMemoryCredentialStore() -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    entries : Entries() <- Ref.new(R.Record<Auth.Credential>, R.new(Auth.Credential))
    queue : Ref.Ref<QueueState> <- Ref.new(QueueState, QueueState{0n, R.new(Tail)})
    +store : InMemory <- IO.pure(InMemory, InMemory{entries, queue})
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~InMemory, ~Auth.Request, ~Auth.StoreResult(Maybe<&2, Auth.Credential>), ~readCredential, store)
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~InMemory, ~Auth.Signal(), ~Auth.StoreResult(List<&2, Auth.CredentialInfo>), ~listCredentials, store)
    modifier : C.Callback<Auth.Modify, Modified()> <- C.create(~InMemory, ~Auth.Modify, ~Modified(), ~modifyCredential, store)
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~InMemory, ~Auth.Request, ~Auth.StoreResult(Unit), ~deleteCredential, store)
    return Auth.CredentialStore{reader, lister, modifier, deleter}

import Base
import ../../../ai/src/auth/types.bend as Auth
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/abort.bend as Abort

# Credential store overlay for non-persistent runtime API keys (`--api-key`).
# Overrides mask stored credentials for reads and listing; writes go through
# the persistent store.

def Outcome(-A: Data) -> Data: Result<&2, &2, String, A>
def Overrides() -> Data: R.Record<String>

type RuntimeCredentials is Data:
  RuntimeCredentials{store: Auth.CredentialStore, overrides: Ref.Ref<Overrides()>}

def create(store: Auth.CredentialStore) -> IO(RuntimeCredentials):
  do IO<RuntimeCredentials>:
    overrides : Ref.Ref<Overrides()> <- Ref.new(Overrides(), R.new(String))
    return RuntimeCredentials{store, overrides}

# Disposes the overlay only; the wrapped store belongs to its owner.
def dispose(credentials: RuntimeCredentials) -> IO(Unit):
  match credentials:
    case RuntimeCredentials{_, overrides}:
      do IO<Unit>:
        entries : Overrides() <- Ref.dispose(Overrides(), overrides)
        return Unit{}

def setRuntimeApiKey(credentials: RuntimeCredentials, providerId: String, apiKey: String) -> IO(Unit):
  match credentials:
    case RuntimeCredentials{_, overrides}: Ref.modify(Overrides(), Unit, overrides, current => (R.set(String, current, providerId, apiKey), Unit{}))

def removeRuntimeApiKey(credentials: RuntimeCredentials, providerId: String) -> IO(Unit):
  match credentials:
    case RuntimeCredentials{_, overrides}: Ref.modify(Overrides(), Unit, overrides, current => (R.remove(String, current, providerId), Unit{}))

def override(credentials: RuntimeCredentials, providerId: String) -> IO(Maybe<&2, String>):
  match credentials:
    case RuntimeCredentials{_, overrides}:
      do IO<Maybe<&2, String>>:
        entries : Overrides() <- Ref.read(Overrides(), overrides)
        return R.get(String, entries, providerId)

def hasRuntimeApiKey(credentials: RuntimeCredentials, providerId: String) -> IO(Bool):
  do IO<Bool>:
    value : Maybe<&2, String> <- override(credentials, providerId)
    return Maybe.is_some(&2, String, value)

def aborted(signal: Auth.Signal()) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{signal}: Abort.aborted(Unit, signal)

def abortedError() -> String: "The operation was aborted"

def readOverridden(store: Auth.CredentialStore, providerId: String, signal: Auth.Signal(), cancelled: Bool, override: Maybe<&2, String>) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match cancelled override:
    case True{} _: IO.pure(Outcome(Maybe<&2, Auth.Credential>), Fail{abortedError()})
    case False{} Some{key}: IO.pure(Outcome(Maybe<&2, Auth.Credential>), Done{Some{Auth.ApiKeyCredential{Some{key}, None{}}}})
    case False{} None{}: Auth.read(store, providerId, signal)

def read(credentials: RuntimeCredentials, +providerId: String, +signal: Auth.Signal()) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match credentials:
    case RuntimeCredentials{store, overrides}:
      do IO<Outcome(Maybe<&2, Auth.Credential>)>:
        cancelled : Bool <- aborted(signal)
        entries : Overrides() <- Ref.read(Overrides(), overrides)
        readOverridden(store, providerId, signal, cancelled, R.get(String, entries, providerId))

def infoKey(info: Auth.CredentialInfo) -> String:
  match info:
    case Auth.CredentialInfo{providerId, _}: providerId

def indexed(infos: List<&2, Auth.CredentialInfo>, entries: R.Record<Auth.CredentialInfo>) -> R.Record<Auth.CredentialInfo>:
  match infos:
    case Nil{}: entries
    case +info <> rest: indexed(rest, R.set(Auth.CredentialInfo, entries, infoKey(info), info))

def overridden(overrides: List<&2, R.Property<String>>, entries: R.Record<Auth.CredentialInfo>) -> R.Record<Auth.CredentialInfo>:
  match overrides:
    case Nil{}: entries
    case R.Property{+providerId, _} <> rest: overridden(rest, R.set(Auth.CredentialInfo, entries, providerId, Auth.CredentialInfo{providerId, Auth.ApiKeyType{}}))

def values(entries: List<&2, R.Property<Auth.CredentialInfo>>) -> List<&2, Auth.CredentialInfo>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{_, info} <> rest: info <> values(rest)

# Overrides replace or extend stored metadata without exposing key values.
def entries(record: R.Record<Auth.CredentialInfo>) -> List<&2, Auth.CredentialInfo>:
  match record:
    case R.Record{combined}: values(combined)

def merged(stored: Outcome(List<&2, Auth.CredentialInfo>), overrides: Overrides()) -> Outcome(List<&2, Auth.CredentialInfo>):
  match stored overrides:
    case Fail{error} _: Fail{error}
    case Done{infos} R.Record{overriding}: Done{entries(overridden(overriding, indexed(infos, R.new(Auth.CredentialInfo))))}

def listMerged(stored: Outcome(List<&2, Auth.CredentialInfo>), cancelled: Bool, overrides: Overrides()) -> Outcome(List<&2, Auth.CredentialInfo>):
  match cancelled:
    case True{}: Fail{abortedError()}
    case False{}: merged(stored, overrides)

def listWith(credentials: RuntimeCredentials, +signal: Auth.Signal()) -> IO(Outcome(List<&2, Auth.CredentialInfo>)):
  match credentials:
    case RuntimeCredentials{store, overrides}:
      do IO<Outcome(List<&2, Auth.CredentialInfo>)>:
        stored : Outcome(List<&2, Auth.CredentialInfo>) <- Auth.list(store, signal)
        cancelled : Bool <- aborted(signal)
        entries : Overrides() <- Ref.read(Overrides(), overrides)
        return listMerged(stored, cancelled, entries)

# Callback bodies take plain parameters; the affine copy happens inside.
def list(credentials: RuntimeCredentials, signal: Auth.Signal()) -> IO(Outcome(List<&2, Auth.CredentialInfo>)):
  listWith(credentials, signal)

def modify(credentials: RuntimeCredentials, providerId: String, update: Auth.Modification(), signal: Auth.Signal()) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match credentials:
    case RuntimeCredentials{store, _}: Auth.modify(store, providerId, update, signal)

def deleted(overrides: Ref.Ref<Overrides()>, providerId: String, result: Outcome(Unit)) -> IO(Outcome(Unit)):
  match result:
    case Fail{error}: IO.pure(Outcome(Unit), Fail{error})
    case Done{Unit{}}:
      do IO<Outcome(Unit)>:
        Ref.modify(Overrides(), Unit, overrides, current => (R.remove(String, current, providerId), Unit{}))
        return Done{Unit{}}

def deleteUnlessAborted(store: Auth.CredentialStore, providerId: String, signal: Auth.Signal(), cancelled: Bool) -> IO(Outcome(Unit)):
  match cancelled:
    case True{}: IO.pure(Outcome(Unit), Fail{abortedError()})
    case False{}: Auth.delete(store, providerId, signal)

# The override is kept when the persistent deletion fails or is cancelled.
def delete(credentials: RuntimeCredentials, +providerId: String, +signal: Auth.Signal()) -> IO(Outcome(Unit)):
  match credentials:
    case RuntimeCredentials{store, overrides}:
      do IO<Outcome(Unit)>:
        cancelled : Bool <- aborted(signal)
        result : Outcome(Unit) <- deleteUnlessAborted(store, providerId, signal, cancelled)
        deleted(overrides, providerId, result)

# CredentialStore view
# --------------------

def readRequest(credentials: RuntimeCredentials, request: Auth.Request) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Request{providerId, signal}: read(credentials, providerId, signal)

def modifyRequest(credentials: RuntimeCredentials, request: Auth.Modify) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Modify{providerId, update, signal}: modify(credentials, providerId, update, signal)

def deleteRequest(credentials: RuntimeCredentials, request: Auth.Request) -> IO(Outcome(Unit)):
  match request:
    case Auth.Request{providerId, signal}: delete(credentials, providerId, signal)

def store(+credentials: RuntimeCredentials) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Outcome(Maybe<&2, Auth.Credential>)> <- C.create(~RuntimeCredentials, ~Auth.Request, ~(Outcome(Maybe<&2, Auth.Credential>)), ~readRequest, credentials)
    lister : C.Callback<Auth.Signal(), Outcome(List<&2, Auth.CredentialInfo>)> <- C.create(~RuntimeCredentials, ~(Auth.Signal()), ~(Outcome(List<&2, Auth.CredentialInfo>)), ~list, credentials)
    modifier : C.Callback<Auth.Modify, Outcome(Maybe<&2, Auth.Credential>)> <- C.create(~RuntimeCredentials, ~Auth.Modify, ~(Outcome(Maybe<&2, Auth.Credential>)), ~modifyRequest, credentials)
    deleter : C.Callback<Auth.Request, Outcome(Unit)> <- C.create(~RuntimeCredentials, ~Auth.Request, ~(Outcome(Unit)), ~deleteRequest, credentials)
    return Auth.CredentialStore{reader, lister, modifier, deleter}

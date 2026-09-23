import Base
import ../config.bend as Config
import ../core/agent-runtime.bend as Runtime
import ../core/auth-storage.bend as Storage
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/oauth/openai-codex.bend as Codex
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/filesystem.bend as FS

# The caller owns cancellation; this function owns the transport and credential
# store. The notice exposes only the URL and user-visible code to the UI.
type DevicePrompt is Data: DevicePrompt{url: String, code: String}
def Notice() -> Data: C.Callback<DevicePrompt, Unit>
def Outcome() -> Type: Result<&2, &2, String, Unit>

def replace(credential: Auth.Credential, old: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{credential}})

def saved(result: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Outcome():
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{message}: Fail{"Could not save OpenAI Codex credentials: " ++ message}

def save(store: Auth.CredentialStore, credential: Auth.Credential, signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    +update : Auth.Modification() <- C.create(~Auth.Credential, ~Maybe<&2, Auth.Credential>, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~replace, credential)
    result : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(store, "openai-codex", update, Some{signal})
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)
    return saved(result)

def exchanged(store: Auth.CredentialStore, result: Result<&2, &2, String, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match result:
    case Fail{message}: IO.pure(Outcome(), Fail{message})
    case Done{credential}: save(store, credential, signal)

def authorized(flow: Codex.Flow, endpoints: Codex.DeviceEndpoints, store: Auth.CredentialStore, result: Result<&2, &2, String, Codex.AuthorizationCode>, +signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match result:
    case Fail{message}: IO.pure(Outcome(), Fail{message})
    case Done{code}:
      do IO<Outcome()>:
        credential : Result<&2, &2, String, Auth.Credential> <- Codex.exchangeDevice(flow, endpoints, code, signal)
        exchanged(store, credential, signal)

def started(+flow: Codex.Flow, +endpoints: Codex.DeviceEndpoints, store: Auth.CredentialStore, notice: Notice(), result: Result<&2, &2, String, Codex.DeviceCode>, +signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match result:
    case Fail{message}: IO.pure(Outcome(), Fail{message})
    case Done{+device}:
      do IO<Outcome()>:
        C.call(DevicePrompt, Unit, notice, DevicePrompt{Codex.deviceVerificationUri(device), Codex.deviceUserCode(device)})
        code : Result<&2, &2, String, Codex.AuthorizationCode> <- Codex.pollDevice(flow, endpoints, device, signal)
        authorized(flow, endpoints, store, code, signal)

def loginStore(owner: Storage.AuthStorageOwner, view: Storage.AuthStorage, transport: Runtime.Transport, +endpoints: Codex.DeviceEndpoints, +signal: Abort.AbortSignal<Unit>, notice: Notice()) -> IO(Outcome()):
  match transport:
    case Runtime.Transport{+authorizer, runtime, +network}:
      do IO<Outcome()>:
        +store : Auth.CredentialStore <- Storage.store(view)
        +flow : Codex.Flow = Codex.Flow{network, Runtime.urlContext()}
        device : Result<&2, &2, String, Codex.DeviceCode> <- Codex.startDevice(flow, endpoints, signal)
        outcome : Outcome() <- started(flow, endpoints, store, notice, device, signal)
        Auth.disposeStore(store)
        Storage.dispose(owner)
        Runtime.disposeTransport(Runtime.Transport{authorizer, runtime, network})
        return outcome

def loginBorrowed(transport: Runtime.Transport, pair: Storage.AuthStorageOwner & Storage.AuthStorage, endpoints: Codex.DeviceEndpoints, signal: Abort.AbortSignal<Unit>, notice: Notice()) -> IO(Outcome()):
  match pair:
    case (owner, view): loginStore(owner, view, transport, endpoints, signal, notice)

def loginWith(transport: Runtime.Transport, path: String, endpoints: Codex.DeviceEndpoints, signal: Abort.AbortSignal<Unit>, notice: Notice()) -> IO(Outcome()):
  do IO<Outcome()>:
    owner : Storage.AuthStorageOwner <- Storage.create(path)
    loginBorrowed(transport, Storage.borrow(owner), endpoints, signal, notice)

def ready(transport: Runtime.Outcome(Runtime.Transport), path: Result<&2, &2, FS.Error, String>, endpoints: Codex.DeviceEndpoints, signal: Abort.AbortSignal<Unit>, notice: Notice()) -> IO(Outcome()):
  match transport path:
    case Fail{message} _: IO.pure(Outcome(), Fail{message})
    case Done{transport} Fail{_}:
      do IO<Outcome()>:
        Runtime.disposeTransport(transport)
        return Fail{"Could not locate the auth file"}
    case Done{transport} Done{path}: loginWith(transport, path, endpoints, signal, notice)

def bundle(value: Result<&1, &1, U32 & String, String>) -> String:
  match value:
    case Done{path}: path
    case Fail{_}: "/etc/ssl/certs/ca-certificates.crt"

def authenticate(endpoints: Codex.DeviceEndpoints, signal: Abort.AbortSignal<Unit>, notice: Notice()) -> IO(Outcome()):
  do IO<Outcome()>:
    path : Result<&2, &2, FS.Error, String> <- Config.getAuthPath()
    certs : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
    transport : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransport(bundle(certs))
    ready(transport, path, endpoints, signal, notice)

def printPrompt(_: Unit, prompt: DevicePrompt) -> IO(Unit):
  match prompt:
    case DevicePrompt{url, code}: IO.print("Open " ++ url ++ " and enter code: " ++ code)

def finish(result: Outcome()) -> IO(Unit):
  match result:
    case Done{_}: IO.print("Logged in to OpenAI Codex. Credentials saved in auth.json.")
    case Fail{message}: IO.die(Unit, 1, message)

def runWithEndpoints(endpoints: Codex.DeviceEndpoints) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +notice : Notice() <- C.create(~Unit, ~DevicePrompt, ~Unit, ~printPrompt, Unit{})
    result : Outcome() <- authenticate(endpoints, Abort.signal(Unit, controller), notice)
    C.dispose(DevicePrompt, Unit, notice)
    Abort.dispose(Unit, controller)
    finish(result)

def run() -> IO(Unit): runWithEndpoints(Codex.deviceEndpoints())

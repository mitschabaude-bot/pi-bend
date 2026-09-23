import Base
import ../config.bend as Config
import ../core/agent-runtime.bend as Runtime
import ../core/auth-storage.bend as Storage
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/oauth/openai-codex.bend as Codex
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/filesystem.bend as FS

# Headless Codex login. This entry point uses the same native transport and
# serialized credential store as model requests, so the next process sees the
# newly selected account and can refresh the token normally.

def replace(credential: Auth.Credential, old: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{credential}})

def saved(result: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Unit):
  match result:
    case Done{_}: IO.print("Logged in to OpenAI Codex. Credentials saved in auth.json.")
    case Fail{message}: IO.die(Unit, 1, "Could not save OpenAI Codex credentials: " ++ message)

def save(store: Auth.CredentialStore, credential: Auth.Credential, signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  do IO<Unit>:
    +update : Auth.Modification() <- C.create(~Auth.Credential, ~Maybe<&2, Auth.Credential>, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~replace, credential)
    result : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(store, "openai-codex", update, Some{signal})
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)
    saved(result)

def exchanged(store: Auth.CredentialStore, result: Result<&2, &2, String, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{credential}: save(store, credential, signal)

def authorized(flow: Codex.Flow, endpoints: Codex.DeviceEndpoints, store: Auth.CredentialStore, result: Result<&2, &2, String, Codex.AuthorizationCode>, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{code}:
      do IO<Unit>:
        exchangedCredential : Result<&2, &2, String, Auth.Credential> <- Codex.exchangeDevice(flow, endpoints, code, signal)
        exchanged(store, exchangedCredential, signal)

def started(+flow: Codex.Flow, +endpoints: Codex.DeviceEndpoints, store: Auth.CredentialStore, result: Result<&2, &2, String, Codex.DeviceCode>, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{+device}:
      do IO<Unit>:
        IO.print("Open " ++ Codex.deviceVerificationUri(device) ++ " and enter code: " ++ Codex.deviceUserCode(device))
        code : Result<&2, &2, String, Codex.AuthorizationCode> <- Codex.pollDevice(flow, endpoints, device, signal)
        authorized(flow, endpoints, store, code, signal)

def loginStore(owner: Storage.AuthStorageOwner, view: Storage.AuthStorage, transport: Runtime.Transport, +endpoints: Codex.DeviceEndpoints) -> IO(Unit):
  match transport:
    case Runtime.Transport{+authorizer, runtime, +network}:
      do IO<Unit>:
        +store : Auth.CredentialStore <- Storage.store(view)
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        +signal : Abort.AbortSignal<Unit> = Abort.signal(Unit, controller)
        +flow : Codex.Flow = Codex.Flow{network, Runtime.urlContext()}
        result : Result<&2, &2, String, Codex.DeviceCode> <- Codex.startDevice(flow, endpoints, signal)
        started(flow, endpoints, store, result, signal)
        Abort.dispose(Unit, controller)
        Auth.disposeStore(store)
        Storage.dispose(owner)
        Runtime.disposeTransport(Runtime.Transport{authorizer, runtime, network})

def loginBorrowed(transport: Runtime.Transport, pair: Storage.AuthStorageOwner & Storage.AuthStorage, endpoints: Codex.DeviceEndpoints) -> IO(Unit):
  match pair:
    case (owner, view): loginStore(owner, view, transport, endpoints)

def loginWith(transport: Runtime.Transport, path: String, endpoints: Codex.DeviceEndpoints) -> IO(Unit):
  do IO<Unit>:
    owner : Storage.AuthStorageOwner <- Storage.create(path)
    loginBorrowed(transport, Storage.borrow(owner), endpoints)

def ready(transport: Runtime.Outcome(Runtime.Transport), path: Result<&2, &2, FS.Error, String>, endpoints: Codex.DeviceEndpoints) -> IO(Unit):
  match transport path:
    case Fail{message} _: IO.die(Unit, 1, message)
    case Done{transport} Fail{_}:
      do IO<Unit>:
        Runtime.disposeTransport(transport)
        IO.die(Unit, 1, "Could not locate the auth file")
    case Done{transport} Done{path}: loginWith(transport, path, endpoints)

def bundle(value: Result<&1, &1, U32 & String, String>) -> String:
  match value:
    case Done{path}: path
    case Fail{_}: "/etc/ssl/certs/ca-certificates.crt"

def runWithEndpoints(endpoints: Codex.DeviceEndpoints) -> IO(Unit):
  do IO<Unit>:
    path : Result<&2, &2, FS.Error, String> <- Config.getAuthPath()
    certs : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
    transport : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransport(bundle(certs))
    ready(transport, path, endpoints)

def run() -> IO(Unit): runWithEndpoints(Codex.deviceEndpoints())

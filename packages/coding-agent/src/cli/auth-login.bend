import Base
import ../config.bend as Config
import ../core/agent-runtime.bend as Runtime
import ../core/auth-storage.bend as Storage
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/oauth/openai-codex.bend as Codex
import ../../../ai/src/auth/oauth/anthropic.bend as Anthropic
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/filesystem.bend as FS

# The caller owns cancellation; this function owns the transport and credential
# store. The notice exposes only the URL and user-visible code to the UI.
type DevicePrompt is Data: DevicePrompt{url: String, code: String}
def Notice() -> Data: C.Callback<DevicePrompt, Unit>
def Outcome() -> Type: Result<&2, &2, String, Unit>
type ManualPrompt is Data: ManualPrompt{url: String,answer: Deferred.Deferred<String>}
type BrowserInteraction is Data:
  BrowserInteraction{signal: Abort.AbortSignal<Unit>,show: C.Callback<ManualPrompt,Unit>,hide: C.Callback<Unit,Unit>}

def replace(credential: Auth.Credential, old: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{credential}})

def saved(provider: String,result: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Outcome():
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{message}: Fail{"Could not save " ++ provider ++ " credentials: " ++ message}

def save(store: Auth.CredentialStore, +provider: String, credential: Auth.Credential, signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    +update : Auth.Modification() <- C.create(~Auth.Credential, ~Maybe<&2, Auth.Credential>, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~replace, credential)
    result : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(store, provider, update, Some{signal})
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)
    return saved(provider,result)

def saveApiKeyCredential(store: Auth.CredentialStore,provider: String,credential: Auth.LoginOutcome(),signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match credential:
    case Fail{reason}: IO.pure(Outcome(),Fail{reason})
    case Done{value}: save(store,provider,value,signal)
def saveApiKey(provider: String,credential: Auth.LoginOutcome(),signal: Abort.AbortSignal<Unit>,pair: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(Outcome()):
  match pair:
    case (owner,view):
      do IO<Outcome()>:
        +store : Auth.CredentialStore <- Storage.store(view)
        result : Outcome() <- saveApiKeyCredential(store,provider,credential,signal)
        Auth.disposeStore(store)
        Storage.dispose(owner)
        return result
def apiKeyPath(provider: String,credential: Auth.LoginOutcome(),signal: Abort.AbortSignal<Unit>,path: Result<&2,&2,FS.Error,String>) -> IO(Outcome()):
  match path:
    case Fail{_}: IO.pure(Outcome(),Fail{"Could not locate the auth file"})
    case Done{value}:
      do IO<Outcome()>:
        owner : Storage.AuthStorageOwner <- Storage.create(value)
        saveApiKey(provider,credential,signal,Storage.borrow(owner))
def authenticateApiKey(provider: String,login: C.Callback<Auth.ProviderAuthInteraction,Auth.LoginOutcome()>,+interaction: Auth.ProviderAuthInteraction) -> IO(Outcome()):
  match interaction:
    case Auth.ProviderAuthInteraction{signal,_,_}:
      do IO<Outcome()>:
        credential : Auth.LoginOutcome() <- C.call(Auth.ProviderAuthInteraction,Auth.LoginOutcome(),login,interaction)
        path : Result<&2,&2,FS.Error,String> <- Config.getAuthPath()
        apiKeyPath(provider,credential,signal,path)

def exchanged(store: Auth.CredentialStore, result: Result<&2, &2, String, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match result:
    case Fail{message}: IO.pure(Outcome(), Fail{message})
    case Done{credential}: save(store, "openai-codex", credential, signal)

def savedAnthropic(store: Auth.CredentialStore,result: Result<&2,&2,String,Auth.Credential>,signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match result:
    case Fail{message}: IO.pure(Outcome(),Fail{message})
    case Done{value}: save(store,"anthropic",value,signal)
def anthropicExchange(flow: Anthropic.Flow,store: Auth.CredentialStore,code: Result<&2,&2,String,String>,verifier: String,+signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match code:
    case Fail{message}: IO.pure(Outcome(),Fail{message})
    case Done{value}:
      do IO<Outcome()>:
        credential : Result<&2,&2,String,Auth.Credential> <- Anthropic.exchangeCode(flow,value,verifier,signal)
        savedAnthropic(store,credential,signal)
def callbackCode(flow: Anthropic.Flow,store: Auth.CredentialStore,listener: Listener,url: String,+verifier: String,interaction: BrowserInteraction) -> IO(Outcome()):
  match interaction:
    case BrowserInteraction{+signal,show,hide}:
      do IO<Outcome()>:
        +answer : Deferred.Deferred<String> <- Deferred.new(String)
        worker : Chan(Unit) <- IO.fork(Unit,Anthropic.callbackRun(Anthropic.Listening{listener},answer,verifier,signal))
        C.call(ManualPrompt,Unit,show,ManualPrompt{url,answer})
        input : String <- Deferred.result(String,answer)
        IO.join(Unit,worker)
        C.call(Unit,Unit,hide,Unit{})
        Deferred.dispose(String,answer)
        code : Result<&2,&2,String,String> <- IO.pure(Result<&2,&2,String,String>,Anthropic.authorizationInput(input,verifier))
        anthropicExchange(flow,store,code,verifier,signal)
def manualCode(flow: Anthropic.Flow,store: Auth.CredentialStore,url: String,+verifier: String,interaction: BrowserInteraction) -> IO(Outcome()):
  match interaction:
    case BrowserInteraction{+signal,show,hide}:
      do IO<Outcome()>:
        +answer : Deferred.Deferred<String> <- Deferred.new(String)
        C.call(ManualPrompt,Unit,show,ManualPrompt{url,answer})
        input : String <- Deferred.result(String,answer)
        C.call(Unit,Unit,hide,Unit{})
        Deferred.dispose(String,answer)
        code : Result<&2,&2,String,String> <- IO.pure(Result<&2,&2,String,String>,Anthropic.authorizationInput(input,verifier))
        anthropicExchange(flow,store,code,verifier,signal)
def callbackReady(flow: Anthropic.Flow,store: Auth.CredentialStore,listener: Result<&1,&1,U32 & String,Listener>,url: String,verifier: String,interaction: BrowserInteraction) -> IO(Outcome()):
  match listener:
    case Fail{_}: manualCode(flow,store,url,verifier,interaction)
    case Done{bound}: callbackCode(flow,store,bound,url,verifier,interaction)
def anthropicCode(flow: Anthropic.Flow,store: Auth.CredentialStore,authorization: Anthropic.Authorization,interaction: BrowserInteraction) -> IO(Outcome()):
  match authorization:
    case Anthropic.Authorization{url,verifier}:
      do IO<Outcome()>:
        listener : Result<&1,&1,U32 & String,Listener> <- Anthropic.listenCallback()
        callbackReady(flow,store,listener,url,verifier,interaction)
def anthropicStarted(flow: Anthropic.Flow,store: Auth.CredentialStore,started: Result<&2,&2,String,Anthropic.Authorization>,interaction: BrowserInteraction) -> IO(Outcome()):
  match started:
    case Fail{message}: IO.pure(Outcome(),Fail{message})
    case Done{authorization}: anthropicCode(flow,store,authorization,interaction)
def anthropicStore(owner: Storage.AuthStorageOwner,view: Storage.AuthStorage,transport: Runtime.Transport,tokenUrl: String,interaction: BrowserInteraction) -> IO(Outcome()):
  match transport:
    case Runtime.Transport{+authorizer,runtime,+network}:
      do IO<Outcome()>:
        +store : Auth.CredentialStore <- Storage.store(view)
        started : Result<&2,&2,String,Anthropic.Authorization> <- Anthropic.beginAuthorization()
        outcome : Outcome() <- anthropicStarted(Anthropic.Flow{network,Runtime.urlContext(),tokenUrl},store,started,interaction)
        Auth.disposeStore(store)
        Storage.dispose(owner)
        Runtime.disposeTransport(Runtime.Transport{authorizer,runtime,network})
        return outcome
def anthropicBorrowed(pair: Storage.AuthStorageOwner & Storage.AuthStorage,transport: Runtime.Transport,tokenUrl: String,interaction: BrowserInteraction) -> IO(Outcome()):
  match pair:
    case (owner,view): anthropicStore(owner,view,transport,tokenUrl,interaction)
def anthropicReady(transport: Runtime.Outcome(Runtime.Transport),path: Result<&2,&2,FS.Error,String>,tokenUrl: String,interaction: BrowserInteraction) -> IO(Outcome()):
  match transport path:
    case Fail{message} _: IO.pure(Outcome(),Fail{message})
    case Done{transport} Fail{_}:
      do IO<Outcome()>:
        Runtime.disposeTransport(transport)
        return Fail{"Could not locate the auth file"}
    case Done{transport} Done{path}:
      do IO<Outcome()>:
        owner : Storage.AuthStorageOwner <- Storage.create(path)
        anthropicBorrowed(Storage.borrow(owner),transport,tokenUrl,interaction)

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

def authenticateAnthropicWithTokenURL(tokenUrl: String,interaction: BrowserInteraction) -> IO(Outcome()):
  do IO<Outcome()>:
    path : Result<&2,&2,FS.Error,String> <- Config.getAuthPath()
    certs : Result<&1,&1,U32 & String,String> <- IO.get_env("SSL_CERT_FILE")
    transport : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransport(bundle(certs))
    anthropicReady(transport,path,tokenUrl,interaction)
def authenticateAnthropic(interaction: BrowserInteraction) -> IO(Outcome()):
  authenticateAnthropicWithTokenURL(Anthropic.TOKEN_URL(),interaction)

def authenticate(endpoints: Codex.DeviceEndpoints, signal: Abort.AbortSignal<Unit>, notice: Notice()) -> IO(Outcome()):
  do IO<Outcome()>:
    path : Result<&2, &2, FS.Error, String> <- Config.getAuthPath()
    certs : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
    transport : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransport(bundle(certs))
    ready(transport, path, endpoints, signal, notice)

def StoredCredentials() -> Data: Result<&2,&2,String,List<&2,Auth.CredentialInfo>>
def listedCredentials(pair: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(StoredCredentials()):
  match pair:
    case (owner,view):
      do IO<StoredCredentials()>:
        +store : Auth.CredentialStore <- Storage.store(view)
        result : StoredCredentials() <- Auth.list(store,None{})
        Auth.disposeStore(store)
        Storage.dispose(owner)
        return result
def credentialsPath(path: Result<&2,&2,FS.Error,String>) -> IO(StoredCredentials()):
  match path:
    case Fail{_}: IO.pure(StoredCredentials(),Fail{"Could not locate the auth file"})
    case Done{value}:
      do IO<StoredCredentials()>:
        owner : Storage.AuthStorageOwner <- Storage.create(value)
        listedCredentials(Storage.borrow(owner))
def storedCredentials() -> IO(StoredCredentials()):
  do IO<StoredCredentials()>:
    path : Result<&2,&2,FS.Error,String> <- Config.getAuthPath()
    credentialsPath(path)

def deletedCredential(provider: String,pair: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(Outcome()):
  match pair:
    case (owner,view):
      do IO<Outcome()>:
        +store : Auth.CredentialStore <- Storage.store(view)
        result : Outcome() <- Auth.delete(store,provider,None{})
        Auth.disposeStore(store)
        Storage.dispose(owner)
        return result
def deletePath(provider: String,path: Result<&2,&2,FS.Error,String>) -> IO(Outcome()):
  match path:
    case Fail{_}: IO.pure(Outcome(),Fail{"Could not locate the auth file"})
    case Done{value}:
      do IO<Outcome()>:
        owner : Storage.AuthStorageOwner <- Storage.create(value)
        deletedCredential(provider,Storage.borrow(owner))
def logout(provider: String) -> IO(Outcome()):
  do IO<Outcome()>:
    path : Result<&2,&2,FS.Error,String> <- Config.getAuthPath()
    deletePath(provider,path)

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

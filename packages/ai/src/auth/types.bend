import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/abort.bend as Abort

# Request auth for a single model request. Values that are not an apiKey,
# headers or baseUrl are provider configuration, not auth.
type ModelAuth is Data:
  ModelAuth{apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, baseUrl: Maybe<&2, String>}

# One type-tagged credential per provider: the shape of auth.json. OAuth
# credentials keep the flow-specific extra members (such as accountId) as
# JSON values because the store round-trips them without interpreting them.
type Credential is Data:
  ApiKeyCredential{key: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>}
  OAuthCredential{refresh: String, access: String, expires: F64, extra: R.Record<V.Value>}

type CredentialType is Data:
  ApiKeyType{}
  OAuthType{}

def credentialType(credential: Credential) -> CredentialType:
  match credential:
    case ApiKeyCredential{_, _}: ApiKeyType{}
    case OAuthCredential{_, _, _, _}: OAuthType{}

def typeName(value: CredentialType) -> String:
  match value:
    case ApiKeyType{}: "api_key"
    case OAuthType{}: "oauth"

# Non-secret credential metadata for account/status enumeration.
type CredentialInfo is Data:
  CredentialInfo{providerId: String, kind: CredentialType}

def info(providerId: String, credential: Credential) -> CredentialInfo:
  CredentialInfo{providerId, credentialType(credential)}

# Optional cancellation for public auth and credential operations.
def Signal() -> Data: Maybe<&2, Abort.AbortSignal<Unit>>

# Store operations fail only on storage failure; the message is what the
# caller surfaces (Models wraps it in a ModelsError with code "auth").
def StoreResult(-A: Data) -> Data: Result<&2, &2, String, A>

type Request is Data:
  Request{providerId: String, signal: Signal()}

# `modify` is the only write path: a serialized read-modify-write whose
# function sees the current credential and returns the replacement, or None to
# leave the entry unchanged. Failures from the function propagate.
def Modification() -> Data: C.Callback<Maybe<&2, Credential>, StoreResult(Maybe<&2, Credential>)>

type Modify is Data:
  Modify{providerId: String, update: Modification(), signal: Signal()}

# App-owned credential storage keyed by provider id. Implementations serve
# read/list from a possibly stale view and serialize modify/delete.
type CredentialStore is Data:
  CredentialStore{read: C.Callback<Request, StoreResult(Maybe<&2, Credential>)>, list: C.Callback<Signal(), StoreResult(List<&2, CredentialInfo>)>, modify: C.Callback<Modify, StoreResult(Maybe<&2, Credential>)>, delete: C.Callback<Request, StoreResult(Unit)>}

def read(store: CredentialStore, providerId: String, signal: Signal()) -> IO(StoreResult(Maybe<&2, Credential>)):
  match store:
    case CredentialStore{callback, _, _, _}: C.call(Request, StoreResult(Maybe<&2, Credential>), callback, Request{providerId, signal})

def list(store: CredentialStore, signal: Signal()) -> IO(StoreResult(List<&2, CredentialInfo>)):
  match store:
    case CredentialStore{_, callback, _, _}: C.call(Signal(), StoreResult(List<&2, CredentialInfo>), callback, signal)

def modify(store: CredentialStore, providerId: String, update: Modification(), signal: Signal()) -> IO(StoreResult(Maybe<&2, Credential>)):
  match store:
    case CredentialStore{_, _, callback, _}: C.call(Modify, StoreResult(Maybe<&2, Credential>), callback, Modify{providerId, update, signal})

def delete(store: CredentialStore, providerId: String, signal: Signal()) -> IO(StoreResult(Unit)):
  match store:
    case CredentialStore{_, _, _, callback}: C.call(Request, StoreResult(Unit), callback, Request{providerId, signal})

def disposeStore(store: CredentialStore) -> IO(Unit):
  match store:
    case CredentialStore{reader, lister, modifier, deleter}:
      do IO<Unit>:
        C.dispose(Request, StoreResult(Maybe<&2, Credential>), reader)
        C.dispose(Signal(), StoreResult(List<&2, CredentialInfo>), lister)
        C.dispose(Modify, StoreResult(Maybe<&2, Credential>), modifier)
        C.dispose(Request, StoreResult(Unit), deleter)

# Environment access for auth resolution; injectable for tests. Blank
# environment values count as unset. `fileExists` accepts a leading `~`.
type AuthContext is Data:
  AuthContext{env: C.Callback<String, Maybe<&2, String>>, fileExists: C.Callback<String, Bool>}

def envValue(context: AuthContext, name: String) -> IO(Maybe<&2, String>):
  match context:
    case AuthContext{callback, _}: C.call(String, Maybe<&2, String>, callback, name)

def fileExists(context: AuthContext, path: String) -> IO(Bool):
  match context:
    case AuthContext{_, exists}: C.call(String, Bool, exists, path)

def disposeContext(context: AuthContext) -> IO(Unit):
  match context:
    case AuthContext{environment, exists}:
      do IO<Unit>:
        C.dispose(String, Maybe<&2, String>, environment)
        C.dispose(String, Bool, exists)

# Result of resolving auth for a model. `source` labels status UI:
# "ANTHROPIC_API_KEY", "OAuth", "stored credential".
type AuthResult is Data:
  AuthResult{auth: ModelAuth, env: Maybe<&2, T.ProviderEnv()>, source: Maybe<&2, String>}

type ResolveInput is Data:
  ResolveInput{context: AuthContext, credential: Maybe<&2, Credential>, signal: Abort.AbortSignal<Unit>}

def AuthOutcome() -> Data: Result<&2, &2, String, Maybe<&2, AuthResult>>

# Api-key auth: stored key/provider env plus ambient sources. Resolution is
# provider-scoped; endpoint preparation happens after auth is resolved.
# Interactive login is a separate flow and is not part of request auth.
type ApiKeyAuth is Data:
  ApiKeyAuth{name: String, resolve: C.Callback<ResolveInput, AuthOutcome()>}

type RefreshInput is Data:
  RefreshInput{credential: Credential, signal: Abort.AbortSignal<Unit>}

# OAuth auth: refresh rotates a stored credential; toAuth derives request auth.
type OAuthAuth is Data:
  OAuthAuth{name: String, isSubscription: Bool, loginLabel: Maybe<&2, String>, refresh: C.Callback<RefreshInput, Result<&2, &2, String, Credential>>, toAuth: C.Callback<Credential, Result<&2, &2, String, ModelAuth>>}

type ProviderAuth is Data:
  ProviderAuth{apiKey: Maybe<&2, ApiKeyAuth>, oauth: Maybe<&2, OAuthAuth>}

def disposeApiKeyAuth(auth: ApiKeyAuth) -> IO(Unit):
  match auth:
    case ApiKeyAuth{_, resolve}: C.dispose(ResolveInput, AuthOutcome(), resolve)

def disposeOAuthAuth(auth: OAuthAuth) -> IO(Unit):
  match auth:
    case OAuthAuth{_, _, _, refresh, toAuth}:
      do IO<Unit>:
        C.dispose(RefreshInput, Result<&2, &2, String, Credential>, refresh)
        C.dispose(Credential, Result<&2, &2, String, ModelAuth>, toAuth)

def disposeMaybe(-A: Data, value: Maybe<&2, A>, dispose: A -> IO(Unit)) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: dispose(value)

def disposeProviderAuth(auth: ProviderAuth) -> IO(Unit):
  match auth:
    case ProviderAuth{apiKey, oauth}:
      do IO<Unit>:
        disposeMaybe(ApiKeyAuth, apiKey, disposeApiKeyAuth)
        disposeMaybe(OAuthAuth, oauth, disposeOAuthAuth)

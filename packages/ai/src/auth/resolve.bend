import Base
import ./types.bend as Auth
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date

# Auth resolution shared by the Models collections. A stored credential owns
# the provider: ambient/env is consulted only when nothing is stored. No silent
# env fallback after a failed refresh or for a credential type without a
# matching handler.

type ModelsErrorCode is Data:
  ModelSource{}
  ModelValidation{}
  ProviderError{}
  StreamError{}
  AuthError{}
  OAuthError{}

type ModelsError is Data:
  ModelsError{code: ModelsErrorCode, message: String}

# Callers surface the message only, so the underlying reason stays in it.
def withCauseDetail(+message: String, +cause: String) -> String:
  Bool.pick(String, String.is_empty(cause) || String.contains(message, cause), message, message ++ ": " ++ cause)

def failure(code: ModelsErrorCode, message: String, cause: String) -> ModelsError:
  ModelsError{code, withCauseDetail(message, String.trim(cause))}

def errorMessage(error: ModelsError) -> String:
  match error:
    case ModelsError{_, message}: message

# The `{id, auth}` part of a Provider that resolution needs.
type ProviderRef is Data:
  ProviderRef{id: String, auth: Auth.ProviderAuth}

type AuthResolutionOverrides is Data:
  AuthResolutionOverrides{apiKey: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>, minOAuthValidityMs: Maybe<&2, F64>, signal: Auth.Signal()}

def noOverrides() -> AuthResolutionOverrides: AuthResolutionOverrides{None{}, None{}, None{}, None{}}

def Resolution() -> Data: Result<&2, &2, ModelsError, Maybe<&2, Auth.AuthResult>>

def abortedError() -> ModelsError: ModelsError{AuthError{}, "The operation was aborted"}

# Environment overlay
# -------------------

type Overlay is Data:
  Overlay{base: Auth.AuthContext, env: T.ProviderEnv()}

def overlaid(base: Auth.AuthContext, name: String, scoped: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match scoped:
    case Some{SCon{first, rest}}: IO.pure(Maybe<&2, String>, Some{SCon{first, rest}})
    case _: Auth.envValue(base, name)

def overlayLookup(overlay: Overlay, +name: String) -> IO(Maybe<&2, String>):
  match overlay:
    case Overlay{base, env}: overlaid(base, name, R.get(String, env, name))

# Callback bodies take plain parameters; the affine copy happens inside.
def overlayValue(overlay: Overlay, name: String) -> IO(Maybe<&2, String>):
  overlayLookup(overlay, name)

def overlayExists(overlay: Overlay, path: String) -> IO(Bool):
  match overlay:
    case Overlay{base, _}: Auth.fileExists(base, path)

# Request-scoped env values win over the ambient context for the request.
def overlayEnvAuthContext(+base: Auth.AuthContext, +env: T.ProviderEnv()) -> IO(Auth.AuthContext):
  do IO<Auth.AuthContext>:
    environment : C.Callback<String, Maybe<&2, String>> <- C.create(~Overlay, ~String, ~Maybe<&2, String>, ~overlayValue, Overlay{base, env})
    exists : C.Callback<String, Bool> <- C.create(~Overlay, ~String, ~Bool, ~overlayExists, Overlay{base, env})
    return Auth.AuthContext{environment, exists}

# API keys
# --------

def apiKeyOutcome(providerId: String, outcome: Auth.AuthOutcome()) -> Resolution():
  match outcome:
    case Fail{cause}: Fail{failure(AuthError{}, "API key auth failed for provider " ++ providerId, cause)}
    case Done{result}: Done{result}

def resolveApiKey(authContext: Auth.AuthContext, apiKey: Auth.ApiKeyAuth, providerId: String, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Resolution()):
  match apiKey:
    case Auth.ApiKeyAuth{_, resolve}:
      do IO<Resolution()>:
        outcome : Auth.AuthOutcome() <- C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, Auth.ResolveInput{authContext, credential, signal})
        return apiKeyOutcome(providerId, outcome)

# OAuth
# -----

def DEFAULT_OAUTH_MINIMUM_VALIDITY_MS() -> F64: F.fromU32(300000)

def minimumValidity(requested: Maybe<&2, F64>) -> F64:
  F.maximum(DEFAULT_OAUTH_MINIMUM_VALIDITY_MS(), Maybe.default(&2, F64, requested, F.fromU32(0)))

# now + minimum >= expires
def expiresSoon(now: F64, minimum: F64, credential: Auth.Credential) -> Bool:
  match credential:
    case Auth.OAuthCredential{_, _, expires, _}: F.isAtLeast(F.compare(F.add(now, minimum), expires))
    case _: False{}

type Refresh is Data:
  Refresh{providerId: String, oauth: Auth.OAuthAuth, minimum: F64, signal: Abort.AbortSignal<Unit>, failed: Ref.Ref<Maybe<&2, ModelsError>>}

def refreshed(providerId: String, failed: Ref.Ref<Maybe<&2, ModelsError>>, result: Result<&2, &2, String, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match result:
    case Done{credential}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Some{credential}})
    case Fail{cause}:
      +error = failure(OAuthError{}, "OAuth refresh failed for " ++ providerId, cause)
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        Ref.write(Maybe<&2, ModelsError>, failed, Some{error})
        return Fail{errorMessage(error)}

def refreshUnlessFresh(providerId: String, refresh: C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>>, signal: Abort.AbortSignal<Unit>, failed: Ref.Ref<Maybe<&2, ModelsError>>, credential: Auth.Credential, stale: Bool) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match stale:
    case False{}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{None{}})
    case True{}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        result : Result<&2, &2, String, Auth.Credential> <- C.call(Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>, refresh, Auth.RefreshInput{credential, signal})
        refreshed(providerId, failed, result)

# Under the store lock: the authoritative expiry check, then one refresh.
# A logged-out or already-refreshed entry is left unchanged.
def refreshCurrent(refresh: Refresh, current: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match refresh current:
    case _ None{}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{None{}})
    case _ Some{Auth.ApiKeyCredential{_, _}}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{None{}})
    case Refresh{providerId, Auth.OAuthAuth{_, _, _, refresh, _}, minimum, signal, failed} Some{+credential}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        now : F64 <- Date.now()
        refreshUnlessFresh(providerId, refresh, signal, failed, credential, expiresSoon(now, minimum, credential))

def toAuthOutcome(providerId: String, result: Result<&2, &2, String, Auth.ModelAuth>) -> Resolution():
  match result:
    case Fail{cause}: Fail{failure(OAuthError{}, "OAuth auth derivation failed for " ++ providerId, cause)}
    case Done{auth}: Done{Some{Auth.AuthResult{auth, None{}, Some{"OAuth"}}}}

def deriveAuth(providerId: String, oauth: Auth.OAuthAuth, credential: Auth.Credential) -> IO(Resolution()):
  match oauth:
    case Auth.OAuthAuth{_, _, _, _, toAuth}:
      do IO<Resolution()>:
        result : Result<&2, &2, String, Auth.ModelAuth> <- C.call(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, toAuth, credential)
        return toAuthOutcome(providerId, result)

# The five-minute window triggers a refresh without imposing a provider
# contract; explicit minimum validity is required after the refresh.
def checkedValidity(providerId: String, requested: Maybe<&2, F64>, minimum: F64, now: F64, +credential: Auth.Credential) -> Result<&2, &2, ModelsError, Auth.Credential>:
  match requested:
    case None{}: Done{credential}
    case Some{_}: Bool.pick(Result<&2, &2, ModelsError, Auth.Credential>, expiresSoon(now, minimum, credential), Fail{ModelsError{OAuthError{}, "OAuth refresh returned a token that expires too soon for " ++ providerId}}, Done{credential})

def derivedChecked(providerId: String, oauth: Auth.OAuthAuth, checked: Result<&2, &2, ModelsError, Auth.Credential>) -> IO(Resolution()):
  match checked:
    case Fail{error}: IO.pure(Resolution(), Fail{error})
    case Done{credential}: deriveAuth(providerId, oauth, credential)

def postRefresh(+providerId: String, oauth: Auth.OAuthAuth, requested: Maybe<&2, F64>, minimum: F64, recorded: Maybe<&2, ModelsError>, post: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Resolution()):
  match recorded post:
    case Some{error} _: IO.pure(Resolution(), Fail{error})
    case None{} Fail{cause}: IO.pure(Resolution(), Fail{failure(AuthError{}, "Credential store modify failed for " ++ providerId, cause)})
    case None{} Done{Some{Auth.OAuthCredential{refresh, access, expires, extra}}}:
      do IO<Resolution()>:
        now : F64 <- Date.now()
        derivedChecked(providerId, oauth, checkedValidity(providerId, requested, minimum, now, Auth.OAuthCredential{refresh, access, expires, extra}))
    case None{} Done{_}: IO.pure(Resolution(), Done{None{}})

def refreshStored(credentials: Auth.CredentialStore, +providerId: String, +oauth: Auth.OAuthAuth, +signal: Abort.AbortSignal<Unit>, requested: Maybe<&2, F64>, +minimum: F64) -> IO(Resolution()):
  do IO<Resolution()>:
    +failed : Ref.Ref<Maybe<&2, ModelsError>> <- Ref.new(Maybe<&2, ModelsError>, None{})
    +update : Auth.Modification() <- C.create(~Refresh, ~Maybe<&2, Auth.Credential>, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~refreshCurrent, Refresh{providerId, oauth, minimum, signal, failed})
    post : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.modify(credentials, providerId, update, Some{signal})
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), update)
    recorded : Maybe<&2, ModelsError> <- Ref.dispose(Maybe<&2, ModelsError>, failed)
    postRefresh(providerId, oauth, requested, minimum, recorded, post)

def refreshIfStale(credentials: Auth.CredentialStore, providerId: String, oauth: Auth.OAuthAuth, stored: Auth.Credential, signal: Abort.AbortSignal<Unit>, requested: Maybe<&2, F64>, minimum: F64, stale: Bool) -> IO(Resolution()):
  match stale:
    case True{}: refreshStored(credentials, providerId, oauth, signal, requested, minimum)
    case False{}: deriveAuth(providerId, oauth, stored)

# OAuth resolution with double-checked locking: tokens with less than five
# minutes remaining lock, re-check expiry under the lock, refresh once
# globally, and persist the rotated credential before release.
def resolveStoredOAuth(credentials: Auth.CredentialStore, +providerId: String, +oauth: Auth.OAuthAuth, +stored: Auth.Credential, signal: Abort.AbortSignal<Unit>, +requested: Maybe<&2, F64>) -> IO(Resolution()):
  +minimum = minimumValidity(requested)
  do IO<Resolution()>:
    now : F64 <- Date.now()
    refreshIfStale(credentials, providerId, oauth, stored, signal, requested, minimum, expiresSoon(now, minimum, stored))

# Provider resolution
# -------------------

def mergedEntries(extra: List<&2, R.Property<String>>, base: List<&2, R.Property<String>>) -> List<&2, R.Property<String>>:
  match extra:
    case Nil{}: base
    case R.Property{key, value} <> rest: mergedEntries(rest, R.setProperties(String, base, key, value))

def mergedEnv(stored: Maybe<&2, T.ProviderEnv()>, overrides: Maybe<&2, T.ProviderEnv()>) -> Maybe<&2, T.ProviderEnv()>:
  match stored overrides:
    case stored None{}: stored
    case None{} Some{env}: Some{env}
    case Some{R.Record{base}} Some{R.Record{extra}}: Some{R.Record{mergedEntries(extra, base)}}

def readOutcome(providerId: String, result: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> Result<&2, &2, ModelsError, Maybe<&2, Auth.Credential>>:
  match result:
    case Fail{cause}: Fail{failure(AuthError{}, "Credential store read failed for " ++ providerId, cause)}
    case Done{credential}: Done{credential}

# Bend flattens multi-scrutinee matches in parameter order, so the scrutinized
# parameters come last.
def resolveStored(credentials: Auth.CredentialStore, providerId: String, context: Auth.AuthContext, signal: Abort.AbortSignal<Unit>, storedResult: Result<&2, &2, ModelsError, Maybe<&2, Auth.Credential>>, providerAuth: Auth.ProviderAuth, resolution: AuthResolutionOverrides) -> IO(Resolution()):
  match storedResult providerAuth resolution:
    case Fail{error} _ _: IO.pure(Resolution(), Fail{error})
    case Done{Some{Auth.OAuthCredential{refresh, access, expires, extra}}} Auth.ProviderAuth{_, Some{oauth}} AuthResolutionOverrides{_, _, minimum, _}: resolveStoredOAuth(credentials, providerId, oauth, Auth.OAuthCredential{refresh, access, expires, extra}, signal, minimum)
    case Done{Some{Auth.ApiKeyCredential{key, env}}} Auth.ProviderAuth{Some{apiKey}, _} AuthResolutionOverrides{_, extra, _, _}: resolveApiKey(context, apiKey, providerId, Some{Auth.ApiKeyCredential{key, mergedEnv(env, extra)}}, signal)
    case Done{Some{_}} _ _: IO.pure(Resolution(), Done{None{}})
    case Done{None{}} Auth.ProviderAuth{Some{apiKey}, _} _: resolveApiKey(context, apiKey, providerId, None{}, signal)
    case Done{None{}} _ _: IO.pure(Resolution(), Done{None{}})

def resolveWithContext(provider: ProviderRef, +credentials: Auth.CredentialStore, context: Auth.AuthContext, overrides: AuthResolutionOverrides, +signal: Abort.AbortSignal<Unit>) -> IO(Resolution()):
  match provider overrides:
    case ProviderRef{+providerId, Auth.ProviderAuth{Some{apiKey}, oauth}} AuthResolutionOverrides{Some{key}, env, minimum, requestSignal}: resolveApiKey(context, apiKey, providerId, Some{Auth.ApiKeyCredential{Some{key}, env}}, signal)
    case ProviderRef{+providerId, auth} overrides:
      do IO<Resolution()>:
        stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentials, providerId, Some{signal})
        resolveStored(credentials, providerId, context, signal, readOutcome(providerId, stored), auth, overrides)

def resolveOverlaid(provider: ProviderRef, credentials: Auth.CredentialStore, base: Auth.AuthContext, +overrides: AuthResolutionOverrides, signal: Abort.AbortSignal<Unit>) -> IO(Resolution()):
  match overrides:
    case AuthResolutionOverrides{_, Some{env}, _, _}:
      do IO<Resolution()>:
        +overlay : Auth.AuthContext <- overlayEnvAuthContext(base, env)
        result : Resolution() <- resolveWithContext(provider, credentials, overlay, overrides, signal)
        Auth.disposeContext(overlay)
        return result
    case _: resolveWithContext(provider, credentials, base, overrides, signal)

def resolveUnlessAborted(provider: ProviderRef, credentials: Auth.CredentialStore, context: Auth.AuthContext, overrides: AuthResolutionOverrides, signal: Abort.AbortSignal<Unit>, cancelled: Bool) -> IO(Resolution()):
  match cancelled:
    case True{}: IO.pure(Resolution(), Fail{abortedError()})
    case False{}: resolveOverlaid(provider, credentials, context, overrides, signal)

def resolveSignalled(provider: ProviderRef, credentials: Auth.CredentialStore, context: Auth.AuthContext, overrides: AuthResolutionOverrides, +signal: Abort.AbortSignal<Unit>) -> IO(Resolution()):
  do IO<Resolution()>:
    cancelled : Bool <- Abort.aborted(Unit, signal)
    resolveUnlessAborted(provider, credentials, context, overrides, signal, cancelled)

def signalOf(overrides: AuthResolutionOverrides) -> Auth.Signal():
  match overrides:
    case AuthResolutionOverrides{_, _, _, signal}: signal

# Without a caller signal the operation runs under a private, never-aborted one.
def resolveWithSignal(provider: ProviderRef, credentials: Auth.CredentialStore, context: Auth.AuthContext, overrides: AuthResolutionOverrides, signal: Auth.Signal()) -> IO(Resolution()):
  match signal:
    case Some{signal}: resolveSignalled(provider, credentials, context, overrides, signal)
    case None{}:
      do IO<Resolution()>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : Resolution() <- resolveSignalled(provider, credentials, context, overrides, Abort.signal(Unit, controller))
        Abort.dispose(Unit, controller)
        return result

def resolveProviderAuth(provider: ProviderRef, credentials: Auth.CredentialStore, context: Auth.AuthContext, +overrides: AuthResolutionOverrides) -> IO(Resolution()):
  resolveWithSignal(provider, credentials, context, overrides, signalOf(overrides))

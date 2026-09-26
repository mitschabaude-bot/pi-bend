import Base
import ./args.bend as Args
import ./auth-command.bend as Command
import ../core/model-runtime.bend as Models
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/providers/radius.bend as Radius
import ../../../runtime/src/collation.bend as Collation
import ../../../runtime/src/posix-path.bend as Path

# upstream cli/auth-check.ts: `pi auth check`. The package directory locates
# the collation data used to order an ambiguous model's matches.

type AuthCheckStatus is Data:
  Ready{}
  NotReady{}
  Invalid{}

type AuthCheckReason is Data:
  ProviderNotFound{}
  CredentialsNotConfigured{}
  CredentialNotAvailable{}
  InvalidState{}

type AuthCheckResult is Data:
  AuthCheckResult{status: AuthCheckStatus, provider: String, reason: Maybe<&2, AuthCheckReason>, authType: Maybe<&2, Auth.CredentialType>}

def statusName(status: AuthCheckStatus) -> String:
  match status:
    case Ready{}: "ready"
    case NotReady{}: "not_ready"
    case Invalid{}: "invalid"

def reasonName(reason: AuthCheckReason) -> String:
  match reason:
    case ProviderNotFound{}: "provider_not_found"
    case CredentialsNotConfigured{}: "credentials_not_configured"
    case CredentialNotAvailable{}: "credential_not_available"
    case InvalidState{}: "invalid_state"

def typeName(kind: Auth.CredentialType) -> String:
  match kind:
    case Auth.ApiKeyType{}: "api_key"
    case Auth.OAuthType{}: "oauth"

def notReady(provider: String, reason: AuthCheckReason) -> AuthCheckResult: AuthCheckResult{NotReady{}, provider, Some{reason}, None{}}
def invalid(provider: String) -> AuthCheckResult: AuthCheckResult{Invalid{}, provider, Some{InvalidState{}}, None{}}

# Model resolution
# ----------------

def collated(matches: List<&2, String>, loaded: Result<&2, &2, Collation.LoadError, Collation.Collator>) -> List<&2, String>:
  match loaded:
    case Done{collator}: Collation.sort(collator, matches)
    case Fail{_}: matches

# upstream resolveCliModel's result; an ambiguous id lists its matches in
# localeCompare order.
def finished(+packageDir: String, resolution: Models.Resolution) -> IO(Models.ResolveCliModelResult):
  match resolution:
    case Models.Resolved{result}: IO.pure(Models.ResolveCliModelResult, result)
    case Models.AmbiguousAcross{cliModel, matches, hint}:
      do IO<Models.ResolveCliModelResult>:
        loaded : Result<&2, &2, Collation.LoadError, Collation.Collator> <- Collation.load(Path.join(packageDir, "packages/runtime/data"))
        return Models.ambiguityMessage(cliModel, collated(matches, loaded), hint)

def resolveCliModel(+runtime: Models.ModelRuntime, +packageDir: String, cliProvider: Maybe<&2, String>, cliModel: String) -> IO(Models.ResolveCliModelResult):
  do IO<Models.ResolveCliModelResult>:
    resolution : Models.Resolution <- Models.resolveCliModel(runtime, cliProvider, Some{cliModel}, None{})
    finished(packageDir, resolution)

def modelProvider(+cliModel: String, result: Models.ResolveCliModelResult) -> Result<&2, &2, String, String>:
  match result:
    case Models.ResolveCliModelResult{_, _, _, Some{error}}: Fail{error}
    case Models.ResolveCliModelResult{Some{model}, _, _, None{}}: Done{Models.modelProvider(model)}
    case Models.ResolveCliModelResult{None{}, _, _, None{}}: Fail{"Unable to resolve model \"" ++ cliModel ++ "\""}

def providerFor(+runtime: Models.ModelRuntime, +packageDir: String, requested: Command.RequestedAuth) -> IO(Result<&2, &2, String, String>):
  match requested:
    case Command.RequestedAuth{provider, Some{+cliModel}}:
      do IO<Result<&2, &2, String, String>>:
        result : Models.ResolveCliModelResult <- resolveCliModel(runtime, packageDir, provider, cliModel)
        return modelProvider(cliModel, result)
    case Command.RequestedAuth{Some{provider}, None{}}: IO.pure(Result<&2, &2, String, String>, Done{provider})
    case Command.RequestedAuth{None{}, None{}}: IO.pure(Result<&2, &2, String, String>, Fail{"Unable to resolve an auth provider"})

# checkProviderAuth
# -----------------

def refreshed(+provider: String, kind: Auth.CredentialType, resolution: Resolve.Resolution()) -> AuthCheckResult:
  match resolution:
    case Done{Some{_}}: AuthCheckResult{Ready{}, provider, None{}, Some{kind}}
    case Done{None{}}: notReady(provider, CredentialsNotConfigured{})
    case Fail{_}: invalid(provider)

def checked(+runtime: Models.ModelRuntime, +provider: String, refresh: Bool, check: Result<&2, &2, String, Maybe<&2, Models.AuthCheck>>) -> IO(AuthCheckResult):
  match check refresh:
    case Fail{_} _: IO.pure(AuthCheckResult, invalid(provider))
    case Done{None{}} _: IO.pure(AuthCheckResult, notReady(provider, CredentialsNotConfigured{}))
    case Done{Some{Models.AuthCheck{_, kind}}} False{}: IO.pure(AuthCheckResult, AuthCheckResult{Ready{}, provider, None{}, Some{kind}})
    case Done{Some{Models.AuthCheck{_, kind}}} True{}:
      do IO<AuthCheckResult>:
        resolution : Resolve.Resolution() <- Models.getAuth(runtime, provider, Resolve.noOverrides())
        return refreshed(provider, kind, resolution)

def known(+runtime: Models.ModelRuntime, +provider: String, refresh: Bool, found: Maybe<&2, AiModels.Provider>) -> IO(AuthCheckResult):
  match found:
    case None{}: IO.pure(AuthCheckResult, notReady(provider, ProviderNotFound{}))
    case Some{_}:
      do IO<AuthCheckResult>:
        check : Result<&2, &2, String, Maybe<&2, Models.AuthCheck>> <- Models.checkAuth(runtime, provider)
        checked(runtime, provider, refresh, check)

def withProvider(+runtime: Models.ModelRuntime, refresh: Bool, provider: Result<&2, &2, String, String>) -> IO(Result<&2, &2, String, AuthCheckResult>):
  match provider:
    case Fail{message}: IO.pure(Result<&2, &2, String, AuthCheckResult>, Fail{message})
    case Done{+id}:
      Bool.pick(Unit -> IO(Result<&2, &2, String, AuthCheckResult>), Maybe.is_some(&2, String, Models.getError(runtime)),
        _ => IO.pure(Result<&2, &2, String, AuthCheckResult>, Done{invalid(id)}),
        _ => do IO<Result<&2, &2, String, AuthCheckResult>>:
          found : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, id)
          result : AuthCheckResult <- known(runtime, id, refresh, found)
          return Done{result})(Unit{})

def requestedCheck(+runtime: Models.ModelRuntime, +packageDir: String, refresh: Bool, requested: Result<&2, &2, String, Command.RequestedAuth>) -> IO(Result<&2, &2, String, AuthCheckResult>):
  match requested:
    case Fail{message}: IO.pure(Result<&2, &2, String, AuthCheckResult>, Fail{message})
    case Done{value}:
      do IO<Result<&2, &2, String, AuthCheckResult>>:
        provider : Result<&2, &2, String, String> <- providerFor(runtime, packageDir, value)
        withProvider(runtime, refresh, provider)

# upstream checkProviderAuth: Fail is an AuthCommandError (invalid arguments
# or an unresolvable model). Refreshing resolves the provider's auth once,
# which refreshes an expired OAuth token.
def checkProviderAuth(args: Args.Args, +runtime: Models.ModelRuntime, +packageDir: String, refresh: Bool) -> IO(Result<&2, &2, String, AuthCheckResult>):
  requestedCheck(runtime, packageDir, refresh, Command.validateAuthCommandArgs(args, Command.Check{}))

# getProviderCredential
# ---------------------

def fromAuth(resolution: Resolve.Resolution()) -> Result<&2, &2, String, Maybe<&2, String>>:
  match resolution:
    case Fail{error}: Fail{Resolve.errorMessage(error)}
    case Done{auth}: Done{Command.getAuthCredential(auth)}

def resolvedCredential(+runtime: Models.ModelRuntime, +providerId: String) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  do IO<Result<&2, &2, String, Maybe<&2, String>>>:
    resolution : Resolve.Resolution() <- Models.getAuth(runtime, providerId, Resolve.noOverrides())
    return fromAuth(resolution)

def storedCredential(+runtime: Models.ModelRuntime, +providerId: String, refresh: Bool, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match stored refresh:
    case Fail{message} _: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{message})
    case Done{Some{Auth.OAuthCredential{_, access, _, _}}} False{}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Done{Some{access}})
    case _ _: resolvedCredential(runtime, providerId)

# upstream getProviderCredential: without refresh a stored OAuth access token
# as is; otherwise the resolved credential (refreshing OAuth).
def getProviderCredential(+providerId: String, +runtime: Models.ModelRuntime, credentials: Auth.CredentialStore, refresh: Bool) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  do IO<Result<&2, &2, String, Maybe<&2, String>>>:
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentials, providerId, None{})
    storedCredential(runtime, providerId, refresh, stored)

# upstream createAuthCheckModelRuntime: the production providers over the
# given credentials, with in-memory catalogs and no model network access.
def createAuthCheckModelRuntime(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropic: Auth.OAuthAuth, radius: Radius.RadiusTransport) -> IO(Models.ModelRuntime):
  Models.createWithAnthropic(credentials, codex, Some{anthropic}, radius)

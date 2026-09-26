import Base
import ../models.bend as Models
import ../types.bend as T
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./anthropic.models.bend as Catalog
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R

# The OAuth handler ("Anthropic (Claude Pro/Max)") is created by the caller.
def ANTHROPIC_AUTH_TOKEN_ENV() -> String: "ANTHROPIC_AUTH_TOKEN"
def ANTHROPIC_OAUTH_TOKEN_ENV() -> String: "ANTHROPIC_OAUTH_TOKEN"
def ANTHROPIC_API_KEY_ENV() -> String: "ANTHROPIC_API_KEY"

def aborted() -> Auth.AuthOutcome(): Fail{"The operation was aborted"}

def bearer(token: String) -> Auth.AuthOutcome():
  Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, Some{R.Record{R.Property{"Authorization", T.PresentValue{"Bearer " ++ token}} <> Nil{}}}, None{}}, None{}, Some{ANTHROPIC_AUTH_TOKEN_ENV()}}}}

def afterToken(+context: Auth.AuthContext, token: Maybe<&2, String>, cancelled: Bool) -> IO(Auth.AuthOutcome()):
  match cancelled token:
    case True{} _: IO.pure(Auth.AuthOutcome(), aborted())
    case False{} Some{SCon{c, cs}}: IO.pure(Auth.AuthOutcome(), bearer(SCon{c, cs}))
    case False{} _:
      do IO<Auth.AuthOutcome()>:
        found : Maybe<&2, Helpers.Found> <- Helpers.firstEnv(context, ANTHROPIC_OAUTH_TOKEN_ENV() <> ANTHROPIC_API_KEY_ENV() <> Nil{}, None{})
        return Helpers.ambient(found)

# upstream anthropicApiKeyAuth.resolve: a stored key, else ANTHROPIC_AUTH_TOKEN
# as a Bearer Authorization header, else ANTHROPIC_OAUTH_TOKEN or
# ANTHROPIC_API_KEY as the API key.
def fromEnvironment(+context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>) -> IO(Auth.AuthOutcome()):
  do IO<Auth.AuthOutcome()>:
    token : Maybe<&2, String> <- Auth.envValue(context, ANTHROPIC_AUTH_TOKEN_ENV())
    cancelled : Bool <- Abort.aborted(Unit, signal)
    afterToken(context, token, cancelled)

def resolveStored(context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Auth.AuthOutcome()):
  match credential:
    case Some{Auth.ApiKeyCredential{Some{SCon{first, rest}}, env}}: IO.pure(Auth.AuthOutcome(), Helpers.keyResult(SCon{first, rest}, env, "stored credential"))
    case _: fromEnvironment(context, signal)

def resolveChecked(context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>, cancelled: Bool) -> IO(Auth.AuthOutcome()):
  match cancelled:
    case True{}: IO.pure(Auth.AuthOutcome(), aborted())
    case False{}: resolveStored(context, credential, signal)

def resolveAnthropic(unused: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match input:
    case Auth.ResolveInput{context, credential, +signal}:
      do IO<Auth.AuthOutcome()>:
        cancelled : Bool <- Abort.aborted(Unit, signal)
        resolveChecked(context, credential, signal, cancelled)

def withResolve(generic: Auth.ApiKeyAuth, resolve: C.Callback<Auth.ResolveInput, Auth.AuthOutcome()>) -> IO(Auth.ApiKeyAuth):
  match generic:
    case Auth.ApiKeyAuth{name, login, previous}:
      do IO<Auth.ApiKeyAuth>:
        C.dispose(Auth.ResolveInput, Auth.AuthOutcome(), previous)
        return Auth.ApiKeyAuth{name, login, resolve}

# Login prompts for the key like the standard env api-key auth.
def anthropicApiKeyAuth() -> IO(Auth.ApiKeyAuth):
  do IO<Auth.ApiKeyAuth>:
    generic : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Anthropic API key", ANTHROPIC_OAUTH_TOKEN_ENV() <> ANTHROPIC_API_KEY_ENV() <> Nil{})
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~(Auth.AuthOutcome()), ~resolveAnthropic, Unit{})
    withResolve(generic, resolve)

def anthropicProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- anthropicApiKeyAuth()
    return Models.Provider{"anthropic", "Anthropic", "https://api.anthropic.com", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.ANTHROPIC_MODELS(), Models.ApiStreams{}, None{}}

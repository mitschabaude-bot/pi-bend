import Base
import ../models.bend as Models
import ../types.bend as T
import ../auth/types.bend as Auth
import ./amazon-bedrock.models.bend as Catalog
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R

# upstream providers/amazon-bedrock.ts. Bedrock accepts a bearer token or the
# AWS SDK's default credential chain; resolve reports which source is
# configured without copying ambient AWS credentials. The login flow's
# method selection and notice need select/notify prompts, which the port's
# LoginInteraction does not offer yet, so no login is registered.

def AuthOutcome() -> Data: Auth.AuthOutcome()

def ambientAuth(env: Maybe<&2, T.ProviderEnv()>, source: String) -> AuthOutcome():
  Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, None{}, None{}}, env, Some{source}}}}

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def storedProfile(env: Maybe<&2, T.ProviderEnv()>) -> Maybe<&2, String>:
  match env:
    case Some{record}: R.get(String, record, "AWS_PROFILE")
    case None{}: None{}

def abortedError() -> String: "The operation was aborted"

# Each ambient lookup checks the signal before and after, as upstream's env().
def lookup(context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>, name: String) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  do IO<Result<&2, &2, String, Maybe<&2, String>>>:
    before : Bool <- Abort.aborted(Unit, signal)
    value : Maybe<&2, String> <- Auth.envValue(context, name)
    after : Bool <- Abort.aborted(Unit, signal)
    return Bool.pick(Result<&2, &2, String, Maybe<&2, String>>, before || after, Fail{abortedError()}, Done{value})

type Step is Data:
  Resolved{outcome: AuthOutcome()}
  Next{}

def found(value: Result<&2, &2, String, Maybe<&2, String>>, outcome: AuthOutcome()) -> Step:
  match value:
    case Fail{reason}: Resolved{Fail{reason}}
    case Done{Some{SCon{_, _}}}: Resolved{outcome}
    case Done{_}: Next{}

def both(first: Result<&2, &2, String, Maybe<&2, String>>, second: Result<&2, &2, String, Maybe<&2, String>>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match first second:
    case Fail{reason} _: Fail{reason}
    case Done{Some{SCon{c, cs}}} Fail{reason}: Fail{reason}
    case Done{Some{SCon{c, cs}}} Done{Some{SCon{_, _}}}: Done{Some{SCon{c, cs}}}
    case _ _: Done{None{}}

def continued(step: Step, next: IO(AuthOutcome())) -> IO(AuthOutcome()):
  match step:
    case Resolved{outcome}: IO.pure(AuthOutcome(), outcome)
    case Next{}: next

def tail(+context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>) -> IO(AuthOutcome()):
  do IO<AuthOutcome()>:
    relative : Result<&2, &2, String, Maybe<&2, String>> <- lookup(context, signal, "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    full : Result<&2, &2, String, Maybe<&2, String>> <- lookup(context, signal, "AWS_CONTAINER_CREDENTIALS_FULL_URI")
    identity : Result<&2, &2, String, Maybe<&2, String>> <- lookup(context, signal, "AWS_WEB_IDENTITY_TOKEN_FILE")
    continued(found(relative, ambientAuth(None{}, "ECS task role")), continued(found(full, ambientAuth(None{}, "ECS task role")), continued(found(identity, ambientAuth(None{}, "web identity token")), IO.pure(AuthOutcome(), Done{None{}}))))

def keys(+context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>) -> IO(AuthOutcome()):
  do IO<AuthOutcome()>:
    access : Result<&2, &2, String, Maybe<&2, String>> <- lookup(context, signal, "AWS_ACCESS_KEY_ID")
    secret : Result<&2, &2, String, Maybe<&2, String>> <- lookup(context, signal, "AWS_SECRET_ACCESS_KEY")
    continued(found(both(access, secret), ambientAuth(None{}, "AWS access keys")), tail(context, signal))

def profileStep(stored: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>, ambient: Result<&2, &2, String, Maybe<&2, String>>) -> Step:
  match stored:
    case Some{SCon{_, _}}: Resolved{ambientAuth(env, "stored credential")}
    case _: found(ambient, ambientAuth(env, "AWS_PROFILE"))

def ambientProfile(stored: Maybe<&2, String>, +context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match stored:
    case Some{_}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Done{None{}})
    case None{}: lookup(context, signal, "AWS_PROFILE")

def profiles(+context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>, +env: Maybe<&2, T.ProviderEnv()>) -> IO(AuthOutcome()):
  do IO<AuthOutcome()>:
    ambient : Result<&2, &2, String, Maybe<&2, String>> <- ambientProfile(storedProfile(env), context, signal)
    continued(profileStep(storedProfile(env), env, ambient), keys(context, signal))

def credentialEnv(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, T.ProviderEnv()>:
  match credential:
    case Some{Auth.ApiKeyCredential{_, env}}: env
    case _: None{}

def storedKey(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.ApiKeyCredential{key, _}}: nonempty(key)
    case _: None{}

def storedAuth(key: String, env: Maybe<&2, T.ProviderEnv()>) -> AuthOutcome():
  Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, None{}, None{}}, env, Some{"stored credential"}}}}

def chain(stored: Maybe<&2, String>, +context: Auth.AuthContext, +credential: Maybe<&2, Auth.Credential>, +signal: Abort.AbortSignal<Unit>) -> IO(AuthOutcome()):
  match stored:
    case Some{key}: IO.pure(AuthOutcome(), storedAuth(key, credentialEnv(credential)))
    case None{}:
      do IO<AuthOutcome()>:
        bearer : Result<&2, &2, String, Maybe<&2, String>> <- lookup(context, signal, "AWS_BEARER_TOKEN_BEDROCK")
        continued(found(bearer, ambientAuth(None{}, "AWS_BEARER_TOKEN_BEDROCK")), profiles(context, signal, credentialEnv(credential)))

# upstream bedrockAuth.resolve.
def resolveBedrock(unused: Unit, input: Auth.ResolveInput) -> IO(AuthOutcome()):
  match input:
    case Auth.ResolveInput{+context, +credential, +signal}: chain(storedKey(credential), context, credential, signal)

def amazonBedrockProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    resolve : C.Callback<Auth.ResolveInput, AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~AuthOutcome(), ~resolveBedrock, Unit{})
    return Models.Provider{"amazon-bedrock", "Amazon Bedrock", "", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"AWS credentials or bearer token", None{}, resolve}}, None{}}, Catalog.AMAZON_BEDROCK_MODELS(), Models.ApiStreams{}, None{}}

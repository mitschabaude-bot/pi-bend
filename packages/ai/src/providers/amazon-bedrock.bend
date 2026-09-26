import Base
import ../models.bend as Models
import ../types.bend as T
import ../auth/types.bend as Auth
import ./amazon-bedrock.models.bend as Catalog
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R

# upstream providers/amazon-bedrock.ts. Bedrock accepts a bearer token or the
# AWS SDK's default credential chain: login stores a token or a profile
# choice, and resolve reports which source is configured without copying
# ambient AWS credentials.

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

# upstream bedrockAuth.login: a bearer token, an AWS profile name, or the
# existing AWS credential chain.
def bedrockMethods() -> List<&2, Auth.AuthSelectOption>:
  [Auth.AuthSelectOption{"bearer-token", "Bearer token", None{}}, Auth.AuthSelectOption{"aws-profile", "AWS profile", None{}}, Auth.AuthSelectOption{"credential-chain", "Existing AWS credential chain", None{}}]

def credentialInfo() -> Auth.AuthEvent:
  Auth.InfoEvent{"Amazon Bedrock supports AWS profiles, IAM credentials, and role-based credentials.", [Auth.AuthInfoLink{"https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html", Some{"AWS credential provider chain"}}]}

def ask(interaction: Auth.ProviderAuthInteraction, question: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match interaction:
    case Auth.ProviderAuthInteraction{_, prompt, _}: C.call(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt, question)

def notified(interaction: Auth.ProviderAuthInteraction, event: Auth.AuthEvent) -> IO(Unit):
  match interaction:
    case Auth.ProviderAuthInteraction{_, _, notify}: C.call(Auth.AuthEvent, Unit, notify, event)

def interactionAborted(interaction: Auth.ProviderAuthInteraction) -> IO(Bool):
  match interaction:
    case Auth.ProviderAuthInteraction{signal, _, _}: Abort.aborted(Unit, signal)

def bearerCredential(answer: Result<&2, &2, String, String>) -> Auth.LoginOutcome():
  match answer:
    case Fail{reason}: Fail{reason}
    case Done{key}: Done{Auth.ApiKeyCredential{Some{key}, None{}}}

def profileCredential(answer: Result<&2, &2, String, String>) -> Auth.LoginOutcome():
  match answer:
    case Fail{reason}: Fail{reason}
    case Done{name}: Done{Auth.ApiKeyCredential{None{}, Some{R.Record{[R.Property{"AWS_PROFILE", name}]}}}}

def chainCredential(answer: Result<&2, &2, String, String>) -> Auth.LoginOutcome():
  match answer:
    case Fail{reason}: Fail{reason}
    case Done{_}: Done{Auth.ApiKeyCredential{None{}, None{}}}

def afterNotice(+interaction: Auth.ProviderAuthInteraction, +method: String) -> IO(Auth.LoginOutcome()):
  match method:
    case "aws-profile":
      do IO<Auth.LoginOutcome()>:
        name : Result<&2, &2, String, String> <- ask(interaction, Auth.TextPrompt{"Enter AWS profile name", None{}, None{}})
        return profileCredential(name)
    case "credential-chain":
      do IO<Auth.LoginOutcome()>:
        answer : Result<&2, &2, String, String> <- ask(interaction, Auth.TextPrompt{"Configure AWS credentials, then press Enter to continue", None{}, None{}})
        return chainCredential(answer)
    case _: IO.pure(Auth.LoginOutcome(), Fail{"Unknown Amazon Bedrock auth method: " ++ method})

def methodChosen(+interaction: Auth.ProviderAuthInteraction, +method: String) -> IO(Auth.LoginOutcome()):
  match method:
    case "bearer-token":
      do IO<Auth.LoginOutcome()>:
        key : Result<&2, &2, String, String> <- ask(interaction, Auth.SecretPrompt{"Enter Amazon Bedrock bearer token", None{}, None{}})
        return bearerCredential(key)
    case _:
      do IO<Auth.LoginOutcome()>:
        notified(interaction, credentialInfo())
        afterNotice(interaction, method)

def selectedMethod(+interaction: Auth.ProviderAuthInteraction, answer: Result<&2, &2, String, String>, aborted: Bool) -> IO(Auth.LoginOutcome()):
  match answer aborted:
    case Fail{reason} _: IO.pure(Auth.LoginOutcome(), Fail{reason})
    case _ True{}: IO.pure(Auth.LoginOutcome(), Fail{abortedError()})
    case Done{method} False{}: methodChosen(interaction, method)

def selectMethod(+interaction: Auth.ProviderAuthInteraction, aborted: Bool) -> IO(Auth.LoginOutcome()):
  match aborted:
    case True{}: IO.pure(Auth.LoginOutcome(), Fail{abortedError()})
    case False{}:
      do IO<Auth.LoginOutcome()>:
        answer : Result<&2, &2, String, String> <- ask(interaction, Auth.SelectPrompt{"Select Amazon Bedrock authentication method:", bedrockMethods(), None{}})
        after : Bool <- interactionAborted(interaction)
        selectedMethod(interaction, answer, after)

def loginRun(+interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    before : Bool <- interactionAborted(interaction)
    selectMethod(interaction, before)

def loginBedrock(unused: Unit, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginRun(interaction)

def amazonBedrockProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    resolve : C.Callback<Auth.ResolveInput, AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~AuthOutcome(), ~resolveBedrock, Unit{})
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~(Auth.LoginOutcome()), ~loginBedrock, Unit{})
    return Models.Provider{"amazon-bedrock", "Amazon Bedrock", "", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"AWS credentials or bearer token", Some{login}, resolve}}, None{}}, Catalog.AMAZON_BEDROCK_MODELS(), Models.ApiStreams{}, None{}}

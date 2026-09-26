import Base
import ../models.bend as Models
import ../types.bend as T
import ../auth/types.bend as Auth
import ./google-vertex.models.bend as Catalog
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R

# upstream providers/google-vertex.ts. Vertex accepts an explicit API key or
# Application Default Credentials (`gcloud auth application-default login`)
# with project and location env vars, which the api reads itself.

def AuthOutcome() -> Data: Auth.AuthOutcome()

def Lookup() -> Data: Result<&2, &2, String, Maybe<&2, String>>

def VERTEX_ADC_PATH() -> String: "~/.config/gcloud/application_default_credentials.json"

def abortedError() -> String: "The operation was aborted"

# Each ambient lookup checks the signal before and after, as upstream's env().
def lookup(context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>, name: String) -> IO(Lookup()):
  do IO<Lookup()>:
    before : Bool <- Abort.aborted(Unit, signal)
    value : Maybe<&2, String> <- Auth.envValue(context, name)
    after : Bool <- Abort.aborted(Unit, signal)
    return Bool.pick(Lookup(), before || after, Fail{abortedError()}, Done{value})

def truthy(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{SCon{_, _}}: True{}
    case _: False{}

def storedKey(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.ApiKeyCredential{key, _}}: key
    case _: None{}

def storedEnv(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, T.ProviderEnv()>:
  match credential:
    case Some{Auth.ApiKeyCredential{_, env}}: env
    case _: None{}

def envVar(env: Maybe<&2, T.ProviderEnv()>, name: String) -> Maybe<&2, String>:
  match env:
    case Some{record}: R.get(String, record, name)
    case None{}: None{}

def storedVar(credential: Maybe<&2, Auth.Credential>, name: String) -> Maybe<&2, String>: envVar(storedEnv(credential), name)

# `stored ?? await env(name)`: the environment is read only without a stored
# value.
def orLookup(stored: Maybe<&2, String>, context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>, name: String) -> IO(Lookup()):
  match stored:
    case Some{value}: IO.pure(Lookup(), Done{Some{value}})
    case None{}: lookup(context, signal, name)

def orNext(first: Lookup(), context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>, name: String) -> IO(Lookup()):
  match first:
    case Fail{reason}: IO.pure(Lookup(), Fail{reason})
    case Done{Some{value}}: IO.pure(Lookup(), Done{Some{value}})
    case Done{None{}}: lookup(context, signal, name)

def isCredential(credential: Maybe<&2, Auth.Credential>) -> Bool:
  match credential:
    case Some{_}: True{}
    case None{}: False{}

def keyAuth(key: String, stored: Bool) -> AuthOutcome():
  Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, None{}, None{}}, None{}, Some{Bool.pick(String, stored, "stored credential", "GOOGLE_CLOUD_API_KEY")}}}}

type Adc is Data:
  Adc{exists: Bool, project: Lookup(), location: Lookup()}

def exists(context: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>, path: Maybe<&2, String>) -> IO(Result<&2, &2, String, Bool>):
  do IO<Result<&2, &2, String, Bool>>:
    before : Bool <- Abort.aborted(Unit, signal)
    found : Bool <- Auth.fileExists(context, Maybe.default(&2, String, path, VERTEX_ADC_PATH()))
    after : Bool <- Abort.aborted(Unit, signal)
    return Bool.pick(Result<&2, &2, String, Bool>, before || after, Fail{abortedError()}, Done{found})

def adcOutcome(+credential: Maybe<&2, Auth.Credential>, adc: Adc) -> AuthOutcome():
  match adc:
    case Adc{_, Fail{reason}, _}: Fail{reason}
    case Adc{_, _, Fail{reason}}: Fail{reason}
    case Adc{found, Done{project}, Done{location}}:
      Bool.pick(AuthOutcome(), found && truthy(project) && truthy(location), Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, None{}, None{}}, storedEnv(credential), Some{Bool.pick(String, isCredential(credential), "stored credential", "gcloud application default credentials")}}}}, Done{None{}})

def adcChecked(+context: Auth.AuthContext, +credential: Maybe<&2, Auth.Credential>, +signal: Abort.AbortSignal<Unit>, file: Result<&2, &2, String, Bool>) -> IO(AuthOutcome()):
  match file:
    case Fail{reason}: IO.pure(AuthOutcome(), Fail{reason})
    case Done{found}:
      do IO<AuthOutcome()>:
        first : Lookup() <- orLookup(storedVar(credential, "GOOGLE_CLOUD_PROJECT"), context, signal, "GOOGLE_CLOUD_PROJECT")
        project : Lookup() <- orNext(first, context, signal, "GCLOUD_PROJECT")
        location : Lookup() <- orLookup(storedVar(credential, "GOOGLE_CLOUD_LOCATION"), context, signal, "GOOGLE_CLOUD_LOCATION")
        return adcOutcome(credential, Adc{found, project, location})

def adcPathChecked(+context: Auth.AuthContext, +credential: Maybe<&2, Auth.Credential>, +signal: Abort.AbortSignal<Unit>, path: Lookup()) -> IO(AuthOutcome()):
  match path:
    case Fail{reason}: IO.pure(AuthOutcome(), Fail{reason})
    case Done{file}:
      do IO<AuthOutcome()>:
        found : Result<&2, &2, String, Bool> <- exists(context, signal, file)
        adcChecked(context, credential, signal, found)

def keyChecked(+context: Auth.AuthContext, +credential: Maybe<&2, Auth.Credential>, +signal: Abort.AbortSignal<Unit>, key: Lookup()) -> IO(AuthOutcome()):
  match key:
    case Fail{reason}: IO.pure(AuthOutcome(), Fail{reason})
    case Done{Some{SCon{c, cs}}}: IO.pure(AuthOutcome(), keyAuth(SCon{c, cs}, truthy(storedKey(credential))))
    case Done{_}:
      do IO<AuthOutcome()>:
        path : Lookup() <- orLookup(storedVar(credential, "GOOGLE_APPLICATION_CREDENTIALS"), context, signal, "GOOGLE_APPLICATION_CREDENTIALS")
        adcPathChecked(context, credential, signal, path)

# upstream vertexAuth.resolve: an API key (stored, else GOOGLE_CLOUD_API_KEY),
# else ADC when the credentials file exists and a project and location are
# configured.
def resolveVertex(unused: Unit, input: Auth.ResolveInput) -> IO(AuthOutcome()):
  match input:
    case Auth.ResolveInput{+context, +credential, +signal}:
      do IO<AuthOutcome()>:
        key : Lookup() <- orLookup(storedKey(credential), context, signal, "GOOGLE_CLOUD_API_KEY")
        keyChecked(context, credential, signal, key)

# Login
# -----

def vertexMethods() -> List<&2, Auth.AuthSelectOption>:
  [Auth.AuthSelectOption{"api-key", "Google Cloud API key", None{}}, Auth.AuthSelectOption{"adc", "Application Default Credentials", None{}}, Auth.AuthSelectOption{"service-account", "Service account credentials file", None{}}]

def notice(+method: String) -> Auth.AuthEvent:
  Auth.InfoEvent{Bool.pick(String, String.eq(method, "adc"), "Run `gcloud auth application-default login`, then provide the project and location.", "Provide a service account credentials file, project, and location."), [Auth.AuthInfoLink{"https://cloud.google.com/docs/authentication/provide-credentials-adc", Some{"Application Default Credentials"}}]}

def ask(interaction: Auth.ProviderAuthInteraction, question: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match interaction:
    case Auth.ProviderAuthInteraction{_, prompt, _}: C.call(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt, question)

def notified(interaction: Auth.ProviderAuthInteraction, event: Auth.AuthEvent) -> IO(Unit):
  match interaction:
    case Auth.ProviderAuthInteraction{_, _, notify}: C.call(Auth.AuthEvent, Unit, notify, event)

def interactionAborted(interaction: Auth.ProviderAuthInteraction) -> IO(Bool):
  match interaction:
    case Auth.ProviderAuthInteraction{signal, _, _}: Abort.aborted(Unit, signal)

def keyCredential(answer: Result<&2, &2, String, String>) -> Auth.LoginOutcome():
  match answer:
    case Fail{reason}: Fail{reason}
    case Done{key}: Done{Auth.ApiKeyCredential{Some{key}, None{}}}

def envCredential(project: String, location: String, file: Maybe<&2, String>) -> Auth.Credential:
  match file:
    case Some{SCon{c, cs}}: Auth.ApiKeyCredential{None{}, Some{R.Record{[R.Property{"GOOGLE_CLOUD_PROJECT", project}, R.Property{"GOOGLE_CLOUD_LOCATION", location}, R.Property{"GOOGLE_APPLICATION_CREDENTIALS", SCon{c, cs}}]}}}
    case _: Auth.ApiKeyCredential{None{}, Some{R.Record{[R.Property{"GOOGLE_CLOUD_PROJECT", project}, R.Property{"GOOGLE_CLOUD_LOCATION", location}]}}}

def withFile(project: String, location: String, answer: Result<&2, &2, String, String>) -> Auth.LoginOutcome():
  match answer:
    case Fail{reason}: Fail{reason}
    case Done{file}: Done{envCredential(project, location, Some{file})}

def serviceAccountFile(interaction: Auth.ProviderAuthInteraction, project: String, location: String) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    file : Result<&2, &2, String, String> <- ask(interaction, Auth.TextPrompt{"Enter service account credentials file path", None{}, None{}})
    return withFile(project, location, file)

def locationAnswered(+interaction: Auth.ProviderAuthInteraction, +method: String, +project: String, answer: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match answer:
    case Fail{reason}: IO.pure(Auth.LoginOutcome(), Fail{reason})
    case Done{+location}:
      Bool.pick(Unit -> IO(Auth.LoginOutcome()), String.eq(method, "service-account"), _ => serviceAccountFile(interaction, project, location), _ => IO.pure(Auth.LoginOutcome(), Done{envCredential(project, location, None{})}))(Unit{})

def projectAnswered(+interaction: Auth.ProviderAuthInteraction, +method: String, answer: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match answer:
    case Fail{reason}: IO.pure(Auth.LoginOutcome(), Fail{reason})
    case Done{project}:
      do IO<Auth.LoginOutcome()>:
        location : Result<&2, &2, String, String> <- ask(interaction, Auth.TextPrompt{"Enter Google Cloud location", None{}, None{}})
        locationAnswered(interaction, method, project, location)

def adcLogin(+interaction: Auth.ProviderAuthInteraction, +method: String) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    notified(interaction, notice(method))
    project : Result<&2, &2, String, String> <- ask(interaction, Auth.TextPrompt{"Enter Google Cloud project ID", None{}, None{}})
    projectAnswered(interaction, method, project)

def methodChosen(+interaction: Auth.ProviderAuthInteraction, +method: String) -> IO(Auth.LoginOutcome()):
  match method:
    case "api-key":
      do IO<Auth.LoginOutcome()>:
        key : Result<&2, &2, String, String> <- ask(interaction, Auth.SecretPrompt{"Enter Google Cloud API key", None{}, None{}})
        return keyCredential(key)
    case "adc": adcLogin(interaction, method)
    case "service-account": adcLogin(interaction, method)
    case _: IO.pure(Auth.LoginOutcome(), Fail{"Unknown Google Vertex AI auth method: " ++ method})

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
        answer : Result<&2, &2, String, String> <- ask(interaction, Auth.SelectPrompt{"Select Google Vertex AI authentication method:", vertexMethods(), None{}})
        after : Bool <- interactionAborted(interaction)
        selectedMethod(interaction, answer, after)

def loginRun(+interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    before : Bool <- interactionAborted(interaction)
    selectMethod(interaction, before)

# upstream vertexAuth.login: an API key, or the project, location and (for a
# service account) the credentials file path stored as env.
def loginVertex(unused: Unit, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginRun(interaction)

def googleVertexProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    resolve : C.Callback<Auth.ResolveInput, AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~AuthOutcome(), ~resolveVertex, Unit{})
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~(Auth.LoginOutcome()), ~loginVertex, Unit{})
    return Models.Provider{"google-vertex", "Google Vertex AI", "", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Google Cloud credentials", Some{login}, resolve}}, None{}}, Catalog.GOOGLE_VERTEX_MODELS(), Models.ApiStreams{}, None{}}

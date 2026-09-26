import Base
import ../src/types.bend as T
import ../src/auth/types.bend as Auth
import ../src/providers/google-vertex.bend as Vertex
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/record.bend as R
import ../src/models.bend as Models
import ../../runtime/src/ref.bend as Ref

# The Vertex cases of upstream providers.test.ts ("builtin providers"):
# "runs provider-owned Vertex API key and ADC login flows" (scripted
# answers, recorded prompts and events, then its resolve assertion) and
# "resolves vertex via ADC file plus project and location", which upstream
# runs through createModels().getAuth with a fake auth context; without a
# stored credential getAuth returns resolve's result, so these cases call
# ApiKeyAuth.resolve with the same context. The fake context's files exist
# when listed in its FILES variable (upstream's `files` argument).
# Results render as `key|headers|env|source` (`-` for absent).

def Env() -> Data: R.Record<String>

def lookup(env: Env(), name: String) -> IO(Maybe<&2, String>):
  IO.pure(Maybe<&2, String>, R.get(String, env, name))

def exists(env: Env(), path: String) -> IO(Bool): IO.pure(Bool, String.contains(Maybe.default(&2, String, R.get(String, env, "FILES"), ""), "|" ++ path ++ "|"))

def fakeAuthContext(env: Env()) -> IO(Auth.AuthContext):
  do IO<Auth.AuthContext>:
    +values : Env() <- IO.pure(Env(), env)
    environment : C.Callback<String, Maybe<&2, String>> <- C.create(~Env(), ~String, ~Maybe<&2, String>, ~lookup, values)
    exists : C.Callback<String, Bool> <- C.create(~Env(), ~String, ~Bool, ~exists, values)
    return Auth.AuthContext{environment, exists}

def vars(entries: List<&2, R.Property<String>>) -> Env(): R.Record{entries}

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "-"
    case Some{text}: text

def headerValue(value: T.Nullable<String>) -> String:
  match value:
    case T.NullValue{}: "null"
    case T.PresentValue{text}: text

def headerList(entries: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ ":" ++ headerValue(value)) <> headerList(rest)

def envList(entries: List<&2, R.Property<String>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ "=" ++ value) <> envList(rest)

def headersText(headers: Maybe<&2, T.ProviderHeaders()>) -> String:
  match headers:
    case None{}: "-"
    case Some{R.Record{entries}}: String.join(headerList(entries), ",")

def envText(env: Maybe<&2, T.ProviderEnv()>) -> String:
  match env:
    case None{}: "-"
    case Some{R.Record{entries}}: String.join(envList(entries), ",")

def rendered(outcome: Auth.AuthOutcome()) -> String:
  match outcome:
    case Fail{message}: "error:" ++ message
    case Done{None{}}: "undefined"
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, headers, _}, env, source}}}:
      optional(key) ++ "|" ++ headersText(headers) ++ "|" ++ envText(env) ++ "|" ++ optional(source)

def resolveWith(auth: Auth.ApiKeyAuth, context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Auth.AuthOutcome()):
  match auth:
    case Auth.ApiKeyAuth{_, _, resolve}: C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, Auth.ResolveInput{context, credential, signal})

def resolvedText(auth: IO(Auth.ApiKeyAuth), env: Env(), credential: Maybe<&2, Auth.Credential>, cancel: Bool) -> IO(String):
  do IO<String>:
    selected : Auth.ApiKeyAuth <- auth
    context : Auth.AuthContext <- fakeAuthContext(env)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Bool.pick(IO(Bool), cancel, Abort.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
    outcome : Auth.AuthOutcome() <- resolveWith(selected, context, credential, Abort.signal(Unit, controller))
    Abort.dispose(Unit, controller)
    return rendered(outcome)

def expect(+name: String, actual: IO(String), +expected: String) -> IO(Unit):
  do IO<Unit>:
    +value : String <- actual
    Bool.pick(IO(Unit), String.eq(value, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ value ++ " != " ++ expected))

def apiKeyAuth(provider: Models.Provider) -> IO(Auth.ApiKeyAuth):
  match provider:
    case Models.Provider{_, _, _, Auth.ProviderAuth{Some{auth}, _}, _, _, _}: IO.pure(Auth.ApiKeyAuth, auth)
    case _: IO.die(Auth.ApiKeyAuth, 1, "amazon-bedrock has no api key auth")

def vertex() -> IO(Auth.ApiKeyAuth):
  do IO<Auth.ApiKeyAuth>:
    provider : Models.Provider <- Vertex.googleVertexProvider()
    apiKeyAuth(provider)

def var(name: String, value: String) -> R.Property<String>: R.Property{name, value}

def stored(value: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>) -> Maybe<&2, Auth.Credential>:
  Some{Auth.ApiKeyCredential{value, env}}

def adcFile() -> R.Property<String>: var("FILES", "|~/.config/gcloud/application_default_credentials.json|")

def projectEnv() -> Maybe<&2, T.ProviderEnv()>: Some{R.Record{[var("GOOGLE_CLOUD_PROJECT", "project-id"), var("GOOGLE_CLOUD_LOCATION", "us-central1")]}}

# Login
# -----

type Script is Data:
  Script{answers: Ref.Ref<List<&2, String>>, log: Ref.Ref<List<&2, String>>}

def optionIds(options: List<&2, Auth.AuthSelectOption>) -> List<&2, String>:
  match options:
    case Nil{}: Nil{}
    case Auth.AuthSelectOption{id, label, _} <> rest: (id ++ "=" ++ label) <> optionIds(rest)

def promptText(prompt: Auth.AuthPrompt) -> String:
  match prompt:
    case Auth.TextPrompt{message, _, _}: "text:" ++ message
    case Auth.SecretPrompt{message, _, _}: "secret:" ++ message
    case Auth.SelectPrompt{message, options, _}: "select:" ++ message ++ "[" ++ String.join(optionIds(options), ",") ++ "]"
    case Auth.ManualCodePrompt{message, _, _}: "code:" ++ message

def appended(+line: String, list: List<&2, String>) -> List<&2, String> & Unit: (List.append(&2, String, list, [line]), Unit{})

def popped(list: List<&2, String>) -> List<&2, String> & Result<&2, &2, String, String>:
  match list:
    case Nil{}: (Nil{}, Fail{"no scripted answer"})
    case next <> rest: (rest, Done{next})

def answer(script: Script, prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match script:
    case Script{answers, log}:
      do IO<Result<&2, &2, String, String>>:
        Ref.modify(List<&2, String>, Unit, log, list => appended(promptText(prompt), list))
        Ref.modify(List<&2, String>, Result<&2, &2, String, String>, answers, popped)

def optionalText(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: text
    case None{}: "-"

def linkLabels(links: List<&2, Auth.AuthInfoLink>) -> List<&2, String>:
  match links:
    case Nil{}: Nil{}
    case Auth.AuthInfoLink{_, label} <> rest: optionalText(label) <> linkLabels(rest)

def eventText(event: Auth.AuthEvent) -> String:
  match event:
    case Auth.InfoEvent{_, links}: "info[" ++ String.join(linkLabels(links), ",") ++ "]"
    case _: "other"

def record(script: Script, event: Auth.AuthEvent) -> IO(Unit):
  match script:
    case Script{_, log}: Ref.modify(List<&2, String>, Unit, log, list => appended(eventText(event), list))

def loginResult(result: Auth.LoginOutcome()) -> String:
  match result:
    case Fail{reason}: "error:" ++ reason
    case Done{Auth.ApiKeyCredential{key, env}}: optional(key) ++ "|" ++ envText(env)
    case Done{_}: "wrong credential type"

def callLogin(auth: Auth.ApiKeyAuth, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match auth:
    case Auth.ApiKeyAuth{_, Some{callback}, _}: C.call(Auth.ProviderAuthInteraction, Auth.LoginOutcome(), callback, interaction)
    case _: IO.pure(Auth.LoginOutcome(), Fail{"login unavailable"})

def loginText(answers: List<&2, String>, cancel: Bool) -> IO(String):
  do IO<String>:
    selected : Auth.ApiKeyAuth <- vertex()
    +queue : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, answers)
    +log : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, Nil{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Bool.pick(IO(Bool), cancel, Abort.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
    prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Script, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~answer, Script{queue, log})
    notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Script, ~Auth.AuthEvent, ~Unit, ~record, Script{queue, log})
    result : Auth.LoginOutcome() <- callLogin(selected, Auth.ProviderAuthInteraction{Abort.signal(Unit, controller), prompt, notify})
    lines : List<&2, String> <- Ref.read(List<&2, String>, log)
    Abort.dispose(Unit, controller)
    return loginResult(result) ++ " / " ++ String.join(lines, " ; ")

def selectLine() -> String: "select:Select Google Vertex AI authentication method:[api-key=Google Cloud API key,adc=Application Default Credentials,service-account=Service account credentials file]"

def main() -> IO(Unit):
  do IO<Unit>:
    expect("runs provider-owned Vertex API key and ADC login flows (API key)", loginText(["api-key", "vertex-key"], False{}), "vertex-key|- / " ++ selectLine() ++ " ; secret:Enter Google Cloud API key")
    expect("runs provider-owned Vertex API key and ADC login flows (ADC)", loginText(["adc", "project-id", "us-central1"], False{}), "-|GOOGLE_CLOUD_PROJECT=project-id,GOOGLE_CLOUD_LOCATION=us-central1 / " ++ selectLine() ++ " ; info[Application Default Credentials] ; text:Enter Google Cloud project ID ; text:Enter Google Cloud location")
    expect("runs provider-owned Vertex API key and ADC login flows (stored ADC resolve)", resolvedText(vertex(), vars([adcFile()]), stored(None{}, projectEnv()), False{}), "-|-|GOOGLE_CLOUD_PROJECT=project-id,GOOGLE_CLOUD_LOCATION=us-central1|stored credential")
    expect("the service-account login also stores the credentials file", loginText(["service-account", "p", "l", "/keys/sa.json"], False{}), "-|GOOGLE_CLOUD_PROJECT=p,GOOGLE_CLOUD_LOCATION=l,GOOGLE_APPLICATION_CREDENTIALS=/keys/sa.json / " ++ selectLine() ++ " ; info[Application Default Credentials] ; text:Enter Google Cloud project ID ; text:Enter Google Cloud location ; text:Enter service account credentials file path")
    expect("an unknown Vertex login method is rejected", loginText(["other"], False{}), "error:Unknown Google Vertex AI auth method: other / " ++ selectLine())
    expect("resolves vertex via ADC file plus project and location", resolvedText(vertex(), vars([var("GOOGLE_CLOUD_PROJECT", "proj"), var("GOOGLE_CLOUD_LOCATION", "us-central1"), adcFile()]), None{}, False{}), "-|-|-|gcloud application default credentials")
    expect("resolves vertex via ADC file plus project and location (no location)", resolvedText(vertex(), vars([var("GOOGLE_CLOUD_PROJECT", "proj"), adcFile()]), None{}, False{}), "undefined")
    expect("resolves vertex via ADC file plus project and location (explicit key)", resolvedText(vertex(), vars([var("GOOGLE_CLOUD_API_KEY", "vertex-key")]), None{}, False{}), "vertex-key|-|-|GOOGLE_CLOUD_API_KEY")
    expect("GCLOUD_PROJECT is the fallback project", resolvedText(vertex(), vars([var("GCLOUD_PROJECT", "proj"), var("GOOGLE_CLOUD_LOCATION", "l"), adcFile()]), None{}, False{}), "-|-|-|gcloud application default credentials")
    expect("GOOGLE_APPLICATION_CREDENTIALS names the checked file", resolvedText(vertex(), vars([var("GOOGLE_APPLICATION_CREDENTIALS", "/keys/sa.json"), var("GOOGLE_CLOUD_PROJECT", "p"), var("GOOGLE_CLOUD_LOCATION", "l"), var("FILES", "|/keys/sa.json|")]), None{}, False{}), "-|-|-|gcloud application default credentials")
    expect("ADC needs the credentials file", resolvedText(vertex(), vars([var("GOOGLE_CLOUD_PROJECT", "p"), var("GOOGLE_CLOUD_LOCATION", "l")]), None{}, False{}), "undefined")
    expect("a stored key wins", resolvedText(vertex(), vars([var("GOOGLE_CLOUD_API_KEY", "env-key")]), stored(Some{"stored-key"}, None{}), False{}), "stored-key|-|-|stored credential")
    expect("an aborted signal stops an environment lookup", resolvedText(vertex(), vars([var("GOOGLE_CLOUD_API_KEY", "k")]), None{}, True{}), "error:The operation was aborted")

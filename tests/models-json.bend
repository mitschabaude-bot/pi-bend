import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/resolve.bend as Resolve
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/ai/src/utils/model-json.bend as ModelJson
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/callback.bend as C
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/ai/src/models.bend as AiModels
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/model-config.bend as Config

# Differential fixture for models.json support (model-config.ts,
# provider-composer.ts, model-runtime.ts). Usage:
#   models-json <models.json path> [<provider>/<model> ...]
# Builds the production model runtime (built-in providers plus models.json,
# in-memory credentials) and prints one JSON line: the load/composition error,
# every provider id, and for each models.json provider its name, baseUrl,
# models, availability and request auth; each extra argument prints that
# model's request auth including its configured headers.

def line(value: V.Value) -> String:
  Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(value)), "null")

def text(value: String) -> V.Value: V.Text{value}

def optionalText(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.Text{value}

def object(entries: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{entries}}

def texts(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> texts(rest)

def modelValues(models: List<&2, Models.Model()>) -> List<&2, V.Value>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: ModelJson.model(model) <> modelValues(rest)

def headerEntries(entries: List<&2, R.Property<Ai.Nullable<String>>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, Ai.PresentValue{value}} <> rest: R.Property{key, V.Text{value}} <> headerEntries(rest)
    case R.Property{key, Ai.NullValue{}} <> rest: R.Property{key, V.Null{}} <> headerEntries(rest)

def headersValue(headers: Maybe<&2, Ai.ProviderHeaders()>) -> V.Value:
  match headers:
    case None{}: V.Null{}
    case Some{values}: object(headerEntries(R.entries(Ai.Nullable<String>, values)))

def authValue(resolution: Resolve.Resolution()) -> V.Value:
  match resolution:
    case Fail{error}: object([R.Property{"error", text(Resolve.errorMessage(error))}])
    case Done{None{}}: V.Null{}
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, headers, _}, _, source}}}: object([R.Property{"apiKey", optionalText(apiKey)}, R.Property{"headers", headersValue(headers)}, R.Property{"source", optionalText(source)}])

def providerValue(+runtime: Models.ModelRuntime, provider: AiModels.Provider) -> IO(V.Value):
  match provider:
    case AiModels.Provider{+id, name, baseUrl, _, models}:
      do IO<V.Value>:
        available : Bool <- Models.hasConfiguredAuth(runtime, id)
        auth : Resolve.Resolution() <- Models.getAuth(runtime, id, Resolve.noOverrides())
        return object([R.Property{"id", text(id)}, R.Property{"name", text(name)}, R.Property{"baseUrl", text(baseUrl)}, R.Property{"models", V.ArrayValue{modelValues(models)}}, R.Property{"available", V.Boolean{available}}, R.Property{"auth", authValue(auth)}])

def presentValue(+runtime: Models.ModelRuntime, found: Maybe<&2, AiModels.Provider>) -> IO(Maybe<&2, V.Value>):
  match found:
    case None{}: IO.pure(Maybe<&2, V.Value>, None{})
    case Some{provider}:
      do IO<Maybe<&2, V.Value>>:
        value : V.Value <- providerValue(runtime, provider)
        return Some{value}

def prepend(value: Maybe<&2, V.Value>, rest: List<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case None{}: rest
    case Some{value}: value <> rest

def configuredValues(+runtime: Models.ModelRuntime, ids: List<&2, String>) -> IO(List<&2, V.Value>):
  match ids:
    case Nil{}: IO.pure(List<&2, V.Value>, Nil{})
    case +id <> rest:
      do IO<List<&2, V.Value>>:
        value : Maybe<&2, V.Value> <- presentValue(runtime, Models.getProvider(runtime, id))
        others : List<&2, V.Value> <- configuredValues(runtime, rest)
        return prepend(value, others)

def providerIds(providers: List<&2, AiModels.Provider>) -> List<&2, String>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: Models.providerId(provider) <> providerIds(rest)

def modelAuthValue(+runtime: Models.ModelRuntime, +reference: String, found: Maybe<&2, Models.Model()>) -> IO(R.Property<V.Value>):
  match found:
    case None{}: IO.pure(R.Property<V.Value>, R.Property{reference, V.Null{}})
    case Some{model}:
      do IO<R.Property<V.Value>>:
        auth : Resolve.Resolution() <- Models.getModelAuth(runtime, model, Resolve.noOverrides())
        return R.Property{reference, authValue(auth)}

def modelAuths(+runtime: Models.ModelRuntime, references: List<String>) -> IO(List<&2, R.Property<V.Value>>):
  match references:
    case Nil{}: IO.pure(List<&2, R.Property<V.Value>>, Nil{})
    case +reference <> rest:
      do IO<List<&2, R.Property<V.Value>>>:
        entry : R.Property<V.Value> <- modelAuthValue(runtime, reference, Models.findExactModelReferenceMatch(reference, Models.getModels(runtime)))
        others : List<&2, R.Property<V.Value>> <- modelAuths(runtime, rest)
        return entry <> others

def report(+runtime: Models.ModelRuntime, references: List<String>) -> IO(String):
  do IO<String>:
    configured : List<&2, V.Value> <- configuredValues(runtime, Config.getProviderIds(Models.getModelConfig(runtime)))
    auths : List<&2, R.Property<V.Value>> <- modelAuths(runtime, references)
    return line(object([R.Property{"error", optionalText(Models.getError(runtime))}, R.Property{"providers", V.ArrayValue{texts(providerIds(Models.getProviders(runtime)))}}, R.Property{"configured", V.ArrayValue{configured}}, R.Property{"modelAuth", object(auths)}]))

def unusedRefresh(unused: Unit, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"unused"})

def unusedToAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"unused"})

# The OAuth handlers are never invoked: availability reads stored credentials only.
def oauth(name: String) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    refresh : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Unit, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~unusedRefresh, Unit{})
    toAuth : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~unusedToAuth, Unit{})
    return Auth.OAuthAuth{name, True{}, None{}, refresh, toAuth}

def storeOf(pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Auth.CredentialStore):
  match pair:
    case (_, storage): AuthStorage.store(storage)

def run(values: List<String>) -> IO(Unit):
  match values:
    case path <> references:
      do IO<Unit>:
        owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(R.new(Auth.Credential))
        store : Auth.CredentialStore <- storeOf(AuthStorage.borrow(owner))
        codex : Auth.OAuthAuth <- oauth("ChatGPT Plus/Pro (Codex Subscription)")
        anthropic : Auth.OAuthAuth <- oauth("Anthropic (Claude Pro/Max)")
        +runtime : Models.ModelRuntime <- Models.createWithModelsPath(store, codex, Some{anthropic}, Some{path})
        output : String <- report(runtime, references)
        IO.print(output)
        Models.dispose(runtime)
    case _: IO.die(Unit, 2, "usage: models-json <models.json> [<provider>/<model> ...]")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)

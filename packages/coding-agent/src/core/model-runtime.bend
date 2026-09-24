import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/context.bend as Context
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/providers/all.bend as Builtin
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/glob.bend as Glob
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/filesystem.bend as FS
import ../config.bend as AppConfig
import ./model-config.bend as Config
import ./provider-composer.bend as Composer

# The provider catalog with auth resolution: pi-ai's Models collection and the
# coding agent's ModelRuntime. Built-in providers are composed with their
# models.json entries and models.json custom providers are added; dynamic
# catalog refresh, models-store.json, radius OAuth providers and the
# extension provider registry are not ported.

def Model() -> Data: Ai.Model<Ai.JsonValue>

# `retained` owns the built-in auth parts that composed providers wrap.
type ModelRuntime is Data:
  ModelRuntime{providers: List<&2, AiModels.Provider>, credentials: Auth.CredentialStore, context: Auth.AuthContext, config: Config.ModelConfig, compositionErrors: List<&2, String>, retained: List<&2, Composer.Retained>}

# Composition (recomposeProvider/rebuildProviders)
# -----------------------------------------------

def providerId(provider: AiModels.Provider) -> String:
  match provider:
    case AiModels.Provider{id, _, _, _, _}: id

def providerModels(provider: AiModels.Provider) -> List<&2, Model()>:
  match provider:
    case AiModels.Provider{_, _, _, _, models}: models

def findProvider(providers: List<&2, AiModels.Provider>, +id: String) -> Maybe<&2, AiModels.Provider>:
  match providers:
    case Nil{}: None{}
    case +provider <> rest: Bool.pick(Maybe<&2, AiModels.Provider>, String.eq(providerId(provider), id), Some{provider}, findProvider(rest, id))

def base(provider: Maybe<&2, AiModels.Provider>) -> Maybe<&2, Composer.Base>:
  match provider:
    case None{}: None{}
    case Some{AiModels.Provider{_, name, url, auth, models}}: Some{Composer.Base{name, url, auth, models}}

type Composition is Data:
  Composition{providers: List<&2, AiModels.Provider>, errors: List<&2, String>, retained: List<&2, Composer.Retained>}

def added(provider: Maybe<&2, AiModels.Provider>, composition: Composition) -> Composition:
  match provider composition:
    case None{} composition: composition
    case Some{provider} Composition{providers, errors, retained}: Composition{provider <> providers, errors, retained}

# A failed composition keeps the built-in provider untouched (or omits a
# custom one) and records the error.
def recomposed(+id: String, +builtin: Maybe<&2, AiModels.Provider>, result: Result<&2, &2, String, Composer.Composed>, composition: Composition) -> Composition:
  match result composition:
    case Fail{error} Composition{providers, errors, retained}: added(builtin, Composition{providers, ("Provider \"" ++ id ++ "\": " ++ error) <> errors, retained})
    case Done{Composer.Composed{name, url, auth, models, owned}} Composition{providers, errors, retained}: Composition{AiModels.Provider{id, name, url, auth, models} <> providers, errors, List.append(&2, Composer.Retained, owned, retained)}

def recomposeProvider(+id: String, +builtin: Maybe<&2, AiModels.Provider>, entry: Maybe<&2, Config.ModelsJsonProvider>, composition: Composition) -> IO(Composition):
  match entry:
    # No overlay: the built-in provider is used untouched.
    case None{}: IO.pure(Composition, added(builtin, composition))
    case Some{entry}:
      do IO<Composition>:
        result : Result<&2, &2, String, Composer.Composed> <- Composer.composeModelProvider(id, base(builtin), entry)
        return recomposed(id, builtin, result, composition)

def containsId(ids: List<&2, String>, +id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case +first <> rest: String.eq(first, id) || containsId(rest, id)

def builtinIds(providers: List<&2, AiModels.Provider>) -> List<&2, String>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: providerId(provider) <> builtinIds(rest)

def newIds(ids: List<&2, String>, +known: List<&2, String>) -> List<&2, String>:
  match ids:
    case Nil{}: Nil{}
    case +id <> rest:
      +tail = newIds(rest, known)
      Bool.pick(List<&2, String>, containsId(known, id), tail, id <> tail)

# Built-in ids first, then models.json ids, each once.
def composedIds(+builtins: List<&2, AiModels.Provider>, +config: Config.ModelConfig) -> List<&2, String>:
  List.append(&2, String, builtinIds(builtins), newIds(Config.getProviderIds(config), builtinIds(builtins)))

def rebuildProviders(ids: List<&2, String>, +builtins: List<&2, AiModels.Provider>, +config: Config.ModelConfig, composition: Composition) -> IO(Composition):
  match ids:
    case Nil{}: IO.pure(Composition, composition)
    case +id <> rest:
      do IO<Composition>:
        next : Composition <- recomposeProvider(id, findProvider(builtins, id), Config.getProvider(config, id), composition)
        rebuildProviders(rest, builtins, config, next)

def assembled(composition: Composition, credentials: Auth.CredentialStore, context: Auth.AuthContext, config: Config.ModelConfig) -> ModelRuntime:
  match composition:
    case Composition{providers, errors, retained}: ModelRuntime{List.reverse(&2, AiModels.Provider, providers), credentials, context, config, List.reverse(&2, String, errors), retained}

# The credential store is borrowed; the built-in providers are owned from here on.
def createWithProviders(credentials: Auth.CredentialStore, +builtins: List<&2, AiModels.Provider>, modelsPath: Maybe<&2, String>) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    +config : Config.ModelConfig <- Config.load(modelsPath)
    composition : Composition <- rebuildProviders(composedIds(builtins, config), builtins, config, Composition{Nil{}, Nil{}, Nil{}})
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    return assembled(composition, credentials, context, config)

# Providers without models.json, as test fixtures build them.
def fromProviders(providers: List<&2, AiModels.Provider>, credentials: Auth.CredentialStore, context: Auth.AuthContext) -> ModelRuntime:
  ModelRuntime{providers, credentials, context, Config.empty(), Nil{}, Nil{}}

def locatedPath(path: Result<&2, &2, FS.Error, String>) -> Maybe<&2, String>:
  match path:
    case Done{path}: Some{path}
    case Fail{_}: None{}

# `<agentDir>/models.json`, the default models path.
def defaultModelsPath() -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    path : Result<&2, &2, FS.Error, String> <- AppConfig.getModelsPath()
    return locatedPath(path)

# The credential store is borrowed; the OAuth handlers are owned from here on.
def createWithModelsPath(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, modelsPath: Maybe<&2, String>) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    builtins : List<&2, AiModels.Provider> <- Builtin.builtinProviders(codex, anthropicOAuth)
    createWithProviders(credentials, builtins, modelsPath)

# Upstream's default models path: <agentDir>/models.json.
def createWithAnthropic(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    modelsPath : Maybe<&2, String> <- defaultModelsPath()
    createWithModelsPath(credentials, codex, anthropicOAuth, modelsPath)

def create(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth) -> IO(ModelRuntime):
  createWithAnthropic(credentials, codex, None{})

def disposeProviders(providers: List<&2, AiModels.Provider>) -> IO(Unit):
  match providers:
    case Nil{}: IO.pure(Unit, Unit{})
    case AiModels.Provider{_, _, _, auth, _} <> rest:
      do IO<Unit>:
        Auth.disposeProviderAuth(auth)
        disposeProviders(rest)

def dispose(runtime: ModelRuntime) -> IO(Unit):
  match runtime:
    case ModelRuntime{providers, _, context, _, _, retained}:
      do IO<Unit>:
        disposeProviders(providers)
        Composer.disposeRetained(retained)
        Auth.disposeContext(context)

# models.json load and provider composition errors, as upstream getError().
def joinedErrors(configError: Maybe<&2, String>, errors: List<&2, String>) -> Maybe<&2, String>:
  match configError errors:
    case None{} Nil{}: None{}
    case None{} errors: Some{String.join(errors, "\n\n")}
    case Some{error} errors: Some{String.join(error <> errors, "\n\n")}

def getError(runtime: ModelRuntime) -> Maybe<&2, String>:
  match runtime:
    case ModelRuntime{_, _, _, config, errors, _}: joinedErrors(Config.getError(config), errors)

def getModelConfig(runtime: ModelRuntime) -> Config.ModelConfig:
  match runtime:
    case ModelRuntime{_, _, _, config, _, _}: config

# Catalog
# -------

def getProviders(runtime: ModelRuntime) -> List<&2, AiModels.Provider>:
  match runtime:
    case ModelRuntime{providers, _, _, _, _, _}: providers

def getProvider(runtime: ModelRuntime, id: String) -> Maybe<&2, AiModels.Provider>:
  findProvider(getProviders(runtime), id)

def allModels(providers: List<&2, AiModels.Provider>) -> List<&2, Model()>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: List.append(&2, Model(), providerModels(provider), allModels(rest))

def getModels(runtime: ModelRuntime) -> List<&2, Model()>:
  allModels(getProviders(runtime))

def modelId(model: Model()) -> String:
  match model:
    case Ai.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def modelName(model: Model()) -> String:
  match model:
    case Ai.Model{_, name, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: name

def modelProvider(model: Model()) -> String:
  match model:
    case Ai.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: provider

def reference(+model: Model()) -> String: modelProvider(model) ++ "/" ++ modelId(model)

def findModel(models: List<&2, Model()>, +provider: String, +id: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, Model()>, String.eq(modelProvider(model), provider) && String.eq(modelId(model), id), Some{model}, findModel(rest, provider, id))

def getModel(runtime: ModelRuntime, provider: String, id: String) -> Maybe<&2, Model()>:
  findModel(getModels(runtime), provider, id)

# Auth
# ----

def providerRef(provider: AiModels.Provider) -> Resolve.ProviderRef:
  match provider:
    case AiModels.Provider{id, _, _, auth, _}: Resolve.ProviderRef{id, auth}

def unknownProvider(id: String) -> Resolve.ModelsError:
  Resolve.ModelsError{Resolve.ProviderError{}, "Unknown provider: " ++ id}

def resolveFor(credentials: Auth.CredentialStore, context: Auth.AuthContext, id: String, +provider: Maybe<&2, AiModels.Provider>, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match provider:
    case None{}: IO.pure(Resolve.Resolution(), Fail{unknownProvider(id)})
    case Some{provider}: Resolve.resolveProviderAuth(providerRef(provider), credentials, context, overrides)

def getAuth(runtime: ModelRuntime, +id: String, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match runtime:
    case ModelRuntime{providers, credentials, context, _, _, _}: resolveFor(credentials, context, id, findProvider(providers, id), overrides)

def sameHeaderName(+left: String, +right: String) -> Bool: String.eq(String.to_lower(left), String.to_lower(right))

def withoutHeader(entries: List<&2, R.Property<Ai.Nullable<String>>>, +name: String) -> List<&2, R.Property<Ai.Nullable<String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = withoutHeader(rest, name)
      Bool.pick(List<&2, R.Property<Ai.Nullable<String>>>, sameHeaderName(key, name), tail, R.Property{key, value} <> tail)

def overrideHeaders(overrides: List<&2, R.Property<Ai.Nullable<String>>>, entries: List<&2, R.Property<Ai.Nullable<String>>>) -> List<&2, R.Property<Ai.Nullable<String>>>:
  match overrides:
    case Nil{}: entries
    case R.Property{+name, value} <> rest: overrideHeaders(rest, List.append(&2, R.Property<Ai.Nullable<String>>, withoutHeader(entries, name), R.Property{name, value} <> Nil{}))

# upstream mergeHeaders: an override replaces any header whose name differs
# only in case.
def mergeHeaders(base: Maybe<&2, Ai.ProviderHeaders()>, override: Maybe<&2, Ai.ProviderHeaders()>) -> Maybe<&2, Ai.ProviderHeaders()>:
  match base override:
    case base None{}: base
    case None{} Some{R.Record{values}}: Some{R.Record{overrideHeaders(values, Nil{})}}
    case Some{R.Record{entries}} Some{R.Record{values}}: Some{R.Record{overrideHeaders(values, entries)}}

def presentHeaders(values: List<&2, R.Property<String>>) -> List<&2, R.Property<Ai.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, Ai.PresentValue{value}} <> presentHeaders(rest)

def configuredHeaders(configured: Maybe<&2, R.Record<String>>) -> Maybe<&2, Ai.ProviderHeaders()>:
  match configured:
    case None{}: None{}
    case Some{values}: Some{R.Record{presentHeaders(R.entries(String, values))}}

def modelHeaders(resolution: Resolve.Resolution(), headers: Result<&2, &2, String, Maybe<&2, R.Record<String>>>) -> Resolve.Resolution():
  match resolution headers:
    case Fail{error} _: Fail{error}
    case Done{None{}} _: Done{None{}}
    case _ Fail{error}: Fail{Resolve.ModelsError{Resolve.AuthError{}, error}}
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, existing, url}, env, source}}} Done{configured}: Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, mergeHeaders(existing, configuredHeaders(configured)), url}, env, source}}}

def resolutionEnv(resolution: Resolve.Resolution(), overrides: Maybe<&2, Ai.ProviderEnv()>) -> Maybe<&2, Ai.ProviderEnv()>:
  match resolution overrides:
    case Done{Some{Auth.AuthResult{_, Some{env}, _}}} Some{extra}: Some{Composer.spread(String, env, R.entries(String, extra))}
    case Done{Some{Auth.AuthResult{_, Some{env}, _}}} None{}: Some{env}
    case _ extra: extra

def withModelHeaders(+model: Model(), config: Maybe<&2, Config.ModelsJsonProvider>, +resolution: Resolve.Resolution(), overrides: Maybe<&2, Ai.ProviderEnv()>) -> IO(Resolve.Resolution()):
  match resolution:
    case Done{Some{_}}:
      do IO<Resolve.Resolution()>:
        headers : Result<&2, &2, String, Maybe<&2, R.Record<String>>> <- Composer.resolveConfiguredModelHeaders(model, config, resolutionEnv(resolution, overrides))
        return modelHeaders(resolution, headers)
    case other: IO.pure(Resolve.Resolution(), other)

def overrideEnv(overrides: Resolve.AuthResolutionOverrides) -> Maybe<&2, Ai.ProviderEnv()>:
  match overrides:
    case Resolve.AuthResolutionOverrides{_, env, _, _}: env

# Request auth for a model (upstream getAuth(model)): the provider's auth
# plus the model's own configured headers.
def getModelAuth(+runtime: ModelRuntime, +model: Model(), +overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    resolution : Resolve.Resolution() <- getAuth(runtime, Ai.modelProvider(model), overrides)
    withModelHeaders(model, Config.getProvider(getModelConfig(runtime), Ai.modelProvider(model)), resolution, overrideEnv(overrides))

def configured(resolution: Resolve.Resolution()) -> Bool:
  match resolution:
    case Done{Some{_}}: True{}
    case _: False{}

def resolvesAuth(runtime: ModelRuntime, id: String) -> IO(Bool):
  do IO<Bool>:
    resolution : Resolve.Resolution() <- getAuth(runtime, id, Resolve.noOverrides())
    return configured(resolution)

def supportsOAuth(provider: Maybe<&2, AiModels.Provider>) -> Bool:
  match provider:
    case Some{AiModels.Provider{_, _, _, Auth.ProviderAuth{_, Some{_}}, _}}: True{}
    case _: False{}

def configuredKey(entry: Maybe<&2, Config.ModelsJsonProvider>) -> Maybe<&2, String>:
  match entry:
    case Some{Config.ModelsJsonProvider{_, _, apiKey, _, _, _, _, _, _, _}}: apiKey
    case None{}: None{}

# A models.json apiKey is checked without resolving it, so a command-backed
# key is never run for availability (upstream composed ApiKeyAuth.check).
def checkedConfigured(+runtime: ModelRuntime, +id: String, key: Maybe<&2, String>) -> IO(Bool):
  match runtime key:
    case ModelRuntime{_, _, context, _, _, _} Some{key}: Composer.checkConfiguredApiKey(key, context)
    case _ None{}: resolvesAuth(runtime, id)

def checkedStored(+runtime: ModelRuntime, +id: String, stored: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> IO(Bool):
  match runtime stored:
    case ModelRuntime{providers, _, _, _, _, _} Done{Some{Auth.OAuthCredential{_, _, _, _}}}: IO.pure(Bool, supportsOAuth(findProvider(providers, id)))
    case ModelRuntime{_, _, _, config, _, _} Done{None{}}: checkedConfigured(runtime, id, configuredKey(Config.getProvider(config, id)))
    case _ _: resolvesAuth(runtime, id)

# upstream Models.checkProviderAuth: a stored OAuth credential counts when the
# provider supports OAuth, without refreshing it; otherwise the provider's
# API key must resolve.
def hasConfiguredAuth(+runtime: ModelRuntime, +id: String) -> IO(Bool):
  match runtime:
    case ModelRuntime{_, +credentials, _, _, _, _}:
      do IO<Bool>:
        stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(credentials, id, None{})
        checkedStored(runtime, id, stored)

def availableProviders(+runtime: ModelRuntime, providers: List<&2, AiModels.Provider>) -> IO(List<&2, AiModels.Provider>):
  match providers:
    case Nil{}: IO.pure(List<&2, AiModels.Provider>, Nil{})
    case +provider <> rest:
      do IO<List<&2, AiModels.Provider>>:
        ready : Bool <- hasConfiguredAuth(runtime, providerId(provider))
        +others : List<&2, AiModels.Provider> <- availableProviders(runtime, rest)
        return Bool.pick(List<&2, AiModels.Provider>, ready, provider <> others, others)

# Models whose provider resolves auth now.
def getAvailable(+runtime: ModelRuntime) -> IO(List<&2, Model()>):
  do IO<List<&2, Model()>>:
    providers : List<&2, AiModels.Provider> <- availableProviders(runtime, getProviders(runtime))
    return allModels(providers)

# Model resolution (model-resolver.ts)
# ------------------------------------

type DefaultModel is Data:
  DefaultModel{provider: String, id: String}

# upstream defaultModelPerProvider, in its key order, which
# findInitialModel follows. Entries for providers without a built-in port
# still apply to models.json providers of that id.
def defaultModelPerProvider() -> List<&2, DefaultModel>:
  [DefaultModel{"amazon-bedrock", "us.anthropic.claude-opus-4-6-v1"}, DefaultModel{"ant-ling", "Ring-2.6-1T"}, DefaultModel{"anthropic", "claude-opus-4-8"}, DefaultModel{"openai", "gpt-5.5"}, DefaultModel{"azure-openai-responses", "gpt-5.4"}, DefaultModel{"openai-codex", "gpt-5.5"}, DefaultModel{"radius", "balanced"}, DefaultModel{"nvidia", "nvidia/nemotron-3-super-120b-a12b"}, DefaultModel{"deepseek", "deepseek-v4-pro"}, DefaultModel{"google", "gemini-3.1-pro-preview"}, DefaultModel{"google-vertex", "gemini-3.1-pro-preview"}, DefaultModel{"github-copilot", "gpt-5.4"}, DefaultModel{"openrouter", "moonshotai/kimi-k2.6"}, DefaultModel{"vercel-ai-gateway", "zai/glm-5.1"}, DefaultModel{"xai", "grok-4.7"}, DefaultModel{"groq", "openai/gpt-oss-120b"}, DefaultModel{"cerebras", "gpt-oss-120b"}, DefaultModel{"zai", "glm-5.3"}, DefaultModel{"zai-coding-cn", "glm-5.3"}, DefaultModel{"mistral", "devstral-medium-latest"}, DefaultModel{"minimax", "MiniMax-M2.7"}, DefaultModel{"minimax-cn", "MiniMax-M2.7"}, DefaultModel{"moonshotai", "kimi-k2.6"}, DefaultModel{"moonshotai-cn", "kimi-k2.6"}, DefaultModel{"huggingface", "moonshotai/Kimi-K2.6"}, DefaultModel{"fireworks", "accounts/fireworks/models/kimi-k2p6"}, DefaultModel{"together", "moonshotai/Kimi-K2.6"}, DefaultModel{"baseten", "zai-org/GLM-5.2"}, DefaultModel{"opencode", "kimi-k2.6"}, DefaultModel{"opencode-go", "kimi-k2.6"}, DefaultModel{"kimi-coding", "kimi-for-coding"}, DefaultModel{"meta", "muse-spark-1.3"}, DefaultModel{"cloudflare-workers-ai", "@cf/moonshotai/kimi-k2.6"}, DefaultModel{"cloudflare-ai-gateway", "workers-ai/@cf/moonshotai/kimi-k2.6"}, DefaultModel{"qwen-token-plan", "qwen3.7-max"}, DefaultModel{"qwen-token-plan-cn", "qwen3.7-max"}, DefaultModel{"qwen-token-plan-individual", "qwen3.8-max"}, DefaultModel{"xiaomi", "mimo-v2.5-pro"}, DefaultModel{"xiaomi-token-plan-cn", "mimo-v2.5-pro"}, DefaultModel{"xiaomi-token-plan-ams", "mimo-v2.5-pro"}, DefaultModel{"xiaomi-token-plan-sgp", "mimo-v2.5-pro"}]

# A split text; tuples are affine types, so pairs of strings are data.
type Split is Data:
  Split{first: String, second: String}

def reversedDate(chars: List<&2, Char>) -> Bool:
  match chars:
    case a <> b <> c <> d <> e <> f <> g <> h <> '-' <> _: Char.is_digit(a) && Char.is_digit(b) && Char.is_digit(c) && Char.is_digit(d) && Char.is_digit(e) && Char.is_digit(f) && Char.is_digit(g) && Char.is_digit(h)
    case _: False{}

def endsWithDate(text: String) -> Bool:
  reversedDate(List.reverse(&2, Char, String.to_list(text)))

# -latest ids are aliases; -YYYYMMDD ids are dated versions.
def isAlias(+id: String) -> Bool:
  String.ends_with(id, "-latest") || Bool.not(endsWithDate(id))

def canonicalMatches(models: List<&2, Model()>, +normalized: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = canonicalMatches(rest, normalized)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(reference(model)), normalized), model <> tail, tail)

def idMatches(models: List<&2, Model()>, +normalized: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = idMatches(rest, normalized)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelId(model)), normalized), model <> tail, tail)

# Zero matches fall through; more than one is ambiguous and rejects.
type Matched is Data:
  NoMatch{}
  OneMatch{model: Model()}
  Ambiguous{}

def matched(models: List<&2, Model()>) -> Matched:
  match models:
    case Nil{}: NoMatch{}
    case model <> Nil{}: OneMatch{model}
    case _: Ambiguous{}

def providerIdMatches(models: List<&2, Model()>, +provider: String, +id: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = providerIdMatches(rest, provider, id)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelProvider(model)), provider) && String.eq(String.to_lower(modelId(model)), id), model <> tail, tail)

def trimmedParts(parts: List<&2, String>) -> Maybe<&2, Split>:
  match parts:
    case Nil{}: None{}
    case _ <> Nil{}: None{}
    case head <> rest: Some{Split{String.trim(head), String.trim(String.join(rest, "/"))}}

def slashParts(text: String) -> Maybe<&2, Split>:
  trimmedParts(Strings.split(text, '/'))

def bareMatched(result: Matched) -> Maybe<&2, Model()>:
  match result:
    case OneMatch{model}: Some{model}
    case _: None{}

def bareMatch(models: List<&2, Model()>, normalized: String) -> Maybe<&2, Model()>:
  bareMatched(matched(idMatches(models, normalized)))

def providerMatched(result: Matched, models: List<&2, Model()>, normalized: String) -> Maybe<&2, Model()>:
  match result:
    case OneMatch{model}: Some{model}
    case Ambiguous{}: None{}
    case NoMatch{}: bareMatch(models, normalized)

def providerMatch(split: Maybe<&2, Split>, +models: List<&2, Model()>, +normalized: String) -> Maybe<&2, Model()>:
  match split:
    case Some{Split{SCon{p, ps}, SCon{i, ids}}}: providerMatched(matched(providerIdMatches(models, String.to_lower(SCon{p, ps}), String.to_lower(SCon{i, ids}))), models, normalized)
    case _: bareMatch(models, normalized)

def canonicalMatched(result: Matched, +reference: String, +models: List<&2, Model()>, +normalized: String) -> Maybe<&2, Model()>:
  match result:
    case OneMatch{model}: Some{model}
    case Ambiguous{}: None{}
    case NoMatch{}: providerMatch(slashParts(reference), models, normalized)

def exactReference(+reference: String, +models: List<&2, Model()>, +normalized: String) -> Maybe<&2, Model()>:
  match normalized:
    case SNil{}: None{}
    case _: canonicalMatched(matched(canonicalMatches(models, normalized)), reference, models, normalized)

# A bare id or canonical provider/id reference; ambiguous matches reject.
def findExactModelReferenceMatch(+reference: String, models: List<&2, Model()>) -> Maybe<&2, Model()>:
  exactReference(String.trim(reference), models, String.to_lower(String.trim(reference)))

def partialMatches(models: List<&2, Model()>, +pattern: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = partialMatches(rest, pattern)
      Bool.pick(List<&2, Model()>, String.contains(String.to_lower(modelId(model)), pattern) || String.contains(String.to_lower(modelName(model)), pattern), model <> tail, tail)

def aliases(models: List<&2, Model()>, +wanted: Bool) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = aliases(rest, wanted)
      Bool.pick(List<&2, Model()>, Bool.pick(Bool, wanted, isAlias(modelId(model)), Bool.not(isAlias(modelId(model)))), model <> tail, tail)

def notGreater(compared: (String & String) & Cmp) -> Bool:
  match compared:
    case Tuple{_, GT{}}: False{}
    case Tuple{_, _}: True{}

# left sorts at or after right in descending id order
def descending(left: Model(), right: Model()) -> Bool:
  notGreater(String.cmp(modelId(right), modelId(left)))

def highestFrom(models: List<&2, Model()>, +best: Model()) -> Model():
  match models:
    case Nil{}: best
    case +candidate <> rest: highestFrom(rest, Bool.pick(Model(), descending(best, candidate), best, candidate))

def highest(models: List<&2, Model()>) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case first <> rest: Some{highestFrom(rest, first)}

def preferredAlias(found: List<&2, Model()>, dated: List<&2, Model()>) -> Maybe<&2, Model()>:
  match found:
    case Nil{}: highest(dated)
    case aliased: highest(aliased)

# Prefer an alias; otherwise the latest dated version.
def preferred(+matches: List<&2, Model()>) -> Maybe<&2, Model()>:
  preferredAlias(aliases(matches, True{}), aliases(matches, False{}))

def tryMatchModel(+pattern: String, +models: List<&2, Model()>) -> Maybe<&2, Model()>:
  Maybe.or(&2, Model(), findExactModelReferenceMatch(pattern, models), preferred(partialMatches(models, String.to_lower(pattern))))

type ParsedModelResult is Data:
  ParsedModelResult{model: Maybe<&2, Model()>, thinkingLevel: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>}

def noMatch() -> ParsedModelResult: ParsedModelResult{None{}, None{}, None{}}

def splitReversed(parts: List<&2, String>) -> Maybe<&2, Split>:
  match parts:
    case Nil{}: None{}
    case _ <> Nil{}: None{}
    case suffix <> reversed: Some{Split{String.join(List.reverse(&2, String, reversed), ":"), suffix}}

def lastColonSplit(pattern: String) -> Maybe<&2, Split>:
  splitReversed(List.reverse(&2, String, Strings.split(pattern, ':')))

def thinkingLevel(value: String) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match value:
    case "off": Some{Ai.Off{}}
    case "minimal": Some{Ai.Thinking{Ai.Minimal{}}}
    case "low": Some{Ai.Thinking{Ai.Low{}}}
    case "medium": Some{Ai.Thinking{Ai.Medium{}}}
    case "high": Some{Ai.Thinking{Ai.High{}}}
    case "xhigh": Some{Ai.Thinking{Ai.XHigh{}}}
    case "max": Some{Ai.Thinking{Ai.Max{}}}
    case _: None{}

def withLevel(result: ParsedModelResult, level: Ai.ModelThinkingLevel) -> ParsedModelResult:
  match result:
    case ParsedModelResult{Some{model}, _, None{}}: ParsedModelResult{Some{model}, Some{level}, None{}}
    case other: other

def withWarning(result: ParsedModelResult, +suffix: String, +pattern: String) -> ParsedModelResult:
  match result:
    case ParsedModelResult{Some{model}, _, _}: ParsedModelResult{Some{model}, None{}, Some{"Invalid thinking level \"" ++ suffix ++ "\" in pattern \"" ++ pattern ++ "\". Using default instead."}}
    case other: other

# "pattern:level" parsing. Bend has no mutual recursion, so the loop carries
# the exact match and the last-colon split of each candidate as data and
# recurses on fuel; ids with colons still match when the full text does.
type PatternStep is Data:
  PatternStep{pattern: String, exact: Maybe<&2, Model()>, split: Maybe<&2, Split>}

def stepOf(+pattern: String, models: List<&2, Model()>) -> PatternStep:
  PatternStep{pattern, tryMatchModel(pattern, models), lastColonSplit(pattern)}

def combined(+level: Maybe<&2, Ai.ModelThinkingLevel>, +inner: ParsedModelResult, suffix: String, pattern: String, allowFallback: Bool) -> ParsedModelResult:
  match level allowFallback:
    case Some{level} _: withLevel(inner, level)
    case None{} True{}: withWarning(inner, suffix, pattern)
    case None{} False{}: noMatch()

def parseLoop(fuel: Nat, step: PatternStep, +models: List<&2, Model()>, +allowFallback: Bool) -> ParsedModelResult:
  match fuel step:
    case _ PatternStep{_, Some{model}, _}: ParsedModelResult{Some{model}, None{}, None{}}
    case _ PatternStep{_, None{}, None{}}: noMatch()
    case 0n PatternStep{_, None{}, Some{_}}: noMatch()
    case 1n+n PatternStep{pattern, None{}, Some{Split{prefix, +suffix}}}: combined(thinkingLevel(suffix), parseLoop(n, stepOf(prefix, models), models, allowFallback), suffix, pattern, allowFallback)

def parsePattern(+pattern: String, +models: List<&2, Model()>, allowFallback: Bool) -> ParsedModelResult:
  parseLoop(1n + String.length(pattern), stepOf(pattern, models), models, allowFallback)

# Resolve the authenticated --models scope in CLI order. An invalid pattern
# fails startup rather than silently widening the cycling set.
type ScopedModel is Data: ScopedModel{model: Model(), thinking: Maybe<&2,Ai.ModelThinkingLevel>}

def scopedContains(items: List<&2,ScopedModel>,+model: Model()) -> Bool:
  match items:
    case Nil{}: False{}
    case ScopedModel{+previous,_} <> rest:
      (String.eq(modelProvider(previous),modelProvider(model)) && String.eq(modelId(previous),modelId(model))) || scopedContains(rest,model)
def addScoped(+items: List<&2,ScopedModel>,+model: Model(),thinking: Maybe<&2,Ai.ModelThinkingLevel>) -> List<&2,ScopedModel>:
  Bool.pick(List<&2,ScopedModel>,scopedContains(items,model),items,List.append(&2,ScopedModel,items,ScopedModel{model,thinking} <> Nil{}))
def globMatches(models: List<&2,Model()>,+pattern: Glob.Pattern) -> List<&2,Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = globMatches(rest,pattern)
      +id = String.to_lower(modelId(model))
      +full = String.to_lower(reference(model))
      Bool.pick(List<&2,Model()>,Glob.matches(pattern,id) || Glob.matches(pattern,full),model <> tail,tail)
def addGlobMatches(models: List<&2,Model()>,+thinking: Maybe<&2,Ai.ModelThinkingLevel>,items: List<&2,ScopedModel>) -> List<&2,ScopedModel>:
  match models:
    case Nil{}: items
    case model <> rest: addGlobMatches(rest,thinking,addScoped(items,model,thinking))
def scopedGlobResult(pattern: String,thinking: Maybe<&2,Ai.ModelThinkingLevel>,models: List<&2,Model()>,items: List<&2,ScopedModel>,compiled: Result<&2,&2,Glob.Error,Glob.Pattern>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match compiled:
    case Fail{_}: Fail{"Invalid model glob pattern: " ++ pattern}
    case Done{glob}:
      +matches = globMatches(models,glob)
      Bool.pick(Result<&2,&2,String,List<&2,ScopedModel>>,List.is_empty(&2,Model(),matches),Fail{"No models match pattern: " ++ pattern},Done{addGlobMatches(matches,thinking,items)})
def scopedGlob(pattern: String,globText: String,thinking: Maybe<&2,Ai.ModelThinkingLevel>,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  scopedGlobResult(pattern,thinking,models,items,Glob.compile(String.to_lower(globText)))
def scopedGlobLevel(+pattern: String,prefix: String,level: Maybe<&2,Ai.ModelThinkingLevel>,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match level:
    case Some{chosen}: scopedGlob(pattern,prefix,Some{chosen},models,items)
    case None{}: scopedGlob(pattern,pattern,None{},models,items)
def scopedGlobSuffix(+pattern: String,split: Maybe<&2,Split>,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match split:
    case Some{Split{prefix,suffix}}: scopedGlobLevel(pattern,prefix,thinkingLevel(suffix),models,items)
    case None{}: scopedGlob(pattern,pattern,None{},models,items)
def scopedParsed(pattern: String,items: List<&2,ScopedModel>,parsed: ParsedModelResult) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match parsed:
    case ParsedModelResult{Some{model},thinking,None{}}: Done{addScoped(items,model,thinking)}
    case ParsedModelResult{_,_,Some{_}}: Fail{"Invalid thinking level in model pattern: " ++ pattern}
    case _: Fail{"No models match pattern: " ++ pattern}
def scopedPlain(+pattern: String,models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  scopedParsed(pattern,items,parsePattern(pattern,models,True{}))
def scopedOne(+pattern: String,+models: List<&2,Model()>,+items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  Bool.pick(Unit -> Result<&2,&2,String,List<&2,ScopedModel>>,String.contains(pattern,"*") || String.contains(pattern,"?") || String.contains(pattern,"["),_ => scopedGlobSuffix(pattern,lastColonSplit(pattern),models,items),_ => scopedPlain(pattern,models,items))(Unit{})
def resolveScope(patterns: List<&2,String>,+models: List<&2,Model()>,items: List<&2,ScopedModel>) -> Result<&2,&2,String,List<&2,ScopedModel>>:
  match patterns:
    case Nil{}: Done{items}
    case pattern <> rest:
      Result.bind(&2,&2,String,List<&2,ScopedModel>,List<&2,ScopedModel>,scopedOne(pattern,models,items),next => resolveScope(rest,models,next))

type ResolveCliModelResult is Data:
  ResolveCliModelResult{model: Maybe<&2, Model()>, thinkingLevel: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, error: Maybe<&2, String>}

def cliError(message: String) -> ResolveCliModelResult: ResolveCliModelResult{None{}, None{}, None{}, Some{message}}

def canonicalProvider(models: List<&2, Model()>, +wanted: String) -> Maybe<&2, String>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, String>, String.eq(String.to_lower(modelProvider(model)), wanted), Some{modelProvider(model)}, canonicalProvider(rest, wanted))

def providerModelsOf(models: List<&2, Model()>, +provider: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = providerModelsOf(rest, provider)
      Bool.pick(List<&2, Model()>, String.eq(modelProvider(model), provider), model <> tail, tail)

def splitSlash(parts: List<&2, String>) -> Maybe<&2, Split>:
  match parts:
    case Nil{}: None{}
    case _ <> Nil{}: None{}
    case head <> rest: Some{Split{head, String.join(rest, "/")}}

def slashSplit(text: String) -> Maybe<&2, Split>:
  splitSlash(Strings.split(text, '/'))

def stripPrefix(+pattern: String, +prefix: String) -> String:
  Bool.pick(String, String.starts_with(String.to_lower(pattern), String.to_lower(prefix)), String.drop(pattern, String.length(prefix)), pattern)

def resolved(parsed: ParsedModelResult) -> ResolveCliModelResult:
  match parsed:
    case ParsedModelResult{model, level, warning}: ResolveCliModelResult{model, level, warning, None{}}

def resolveWithin(provider: String, pattern: String, models: List<&2, Model()>) -> ResolveCliModelResult:
  resolved(parsePattern(pattern, providerModelsOf(models, provider), False{}))

# upstream buildFallbackModel: an unknown id on a known provider borrows the
# provider's default model (else its first) under the requested id.
def renamed(model: Model(), +id: String) -> Model():
  match model:
    case Ai.Model{_, _, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}:
      Ai.Model{id, id, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def defaultIdOf(defaults: List<&2, DefaultModel>, +provider: String) -> Maybe<&2, String>:
  match defaults:
    case Nil{}: None{}
    case DefaultModel{name, id} <> rest: Bool.pick(Maybe<&2, String>, String.eq(name, provider), Some{id}, defaultIdOf(rest, provider))

def baseModelOf(+provider: String, +candidates: List<&2, Model()>) -> Maybe<&2, Model()>:
  Maybe.or(&2, Model(), Maybe.bind(&2, String, Model(), defaultIdOf(defaultModelPerProvider(), provider), id => findModel(candidates, provider, id)), List.head(&2, Model(), candidates))

def buildFallbackModel(+provider: String, +modelId: String, models: List<&2, Model()>) -> Maybe<&2, Model()>:
  Maybe.map(&2, Model(), Model(), model => renamed(model, modelId), baseModelOf(provider, providerModelsOf(models, provider)))

def withReasoning(model: Model(), requested: Maybe<&2, Ai.ModelThinkingLevel>) -> Model():
  match model requested:
    case Ai.Model{id, name, api, provider, baseUrl, _, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat} Some{Ai.Thinking{_}}:
      Ai.Model{id, name, api, provider, baseUrl, True{}, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}
    case _ _: model

def notFound(+display: String, warning: Maybe<&2, String>) -> ResolveCliModelResult:
  ResolveCliModelResult{None{}, None{}, warning, Some{"Model \"" ++ display ++ "\" not found. Use --list-models to see available models."}}

def fallbackWarning(warning: Maybe<&2, String>, +message: String) -> String:
  match warning:
    case None{}: message
    case Some{earlier}: earlier ++ " " ++ message

# The id and a thinking level from a trailing ":<level>", unless --thinking
# was given.
def suffixLevel(split: Maybe<&2, Split>) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match split:
    case Some{Split{_, suffix}}: thinkingLevel(suffix)
    case None{}: None{}

def suffixPrefix(split: Maybe<&2, Split>, +pattern: String) -> String:
  match split:
    case Some{Split{prefix, _}}: prefix
    case None{}: pattern

def fallbackBuilt(+provider: String, +pattern: String, +id: String, +level: Maybe<&2, Ai.ModelThinkingLevel>, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, built: Maybe<&2, Model()>) -> ResolveCliModelResult:
  match built:
    case None{}: notFound(provider ++ "/" ++ pattern, warning)
    case Some{model}: ResolveCliModelResult{Some{withReasoning(model, Maybe.or(&2, Ai.ModelThinkingLevel, cliThinking, level))}, level, Some{fallbackWarning(warning, "Model \"" ++ id ++ "\" not found for provider \"" ++ provider ++ "\". Using custom model id.")}, None{}}

def fallbackSplit(+provider: String, +pattern: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, +split: Maybe<&2, Split>, models: List<&2, Model()>) -> ResolveCliModelResult:
  +level = suffixLevel(split)
  +id = Bool.pick(String, Maybe.is_some(&2, Ai.ModelThinkingLevel, level), suffixPrefix(split, pattern), pattern)
  fallbackBuilt(provider, pattern, id, level, cliThinking, warning, buildFallbackModel(provider, id, models))

def fallbackResult(+provider: String, +pattern: String, +cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, warning: Maybe<&2, String>, models: List<&2, Model()>) -> ResolveCliModelResult:
  fallbackSplit(provider, pattern, cliThinking, warning, Bool.pick(Maybe<&2, Split>, Maybe.is_some(&2, Ai.ModelThinkingLevel, cliThinking), None{}, lastColonSplit(pattern)), models)

# upstream resolveCliModel's tail: a known provider without a match falls back
# to a custom model id; otherwise the model is not found.
def orFallback(+provider: String, +pattern: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, models: List<&2, Model()>, result: ResolveCliModelResult) -> ResolveCliModelResult:
  match result:
    case ResolveCliModelResult{None{}, _, warning, None{}}: fallbackResult(provider, pattern, cliThinking, warning, models)
    case other: other

def orNotFound(+display: String, result: ResolveCliModelResult) -> ResolveCliModelResult:
  match result:
    case ResolveCliModelResult{None{}, _, warning, None{}}: notFound(display, warning)
    case other: other

def resolveAcross(pattern: String, models: List<&2, Model()>) -> ResolveCliModelResult:
  resolved(parsePattern(pattern, models, False{}))

# The pure resolution; an ambiguous bare id carries its matches so the caller
# can order them as upstream's localeCompare does.
type Resolution is Data:
  Resolved{result: ResolveCliModelResult}
  AmbiguousAcross{cliModel: String, matches: List<&2, String>, hint: String}

def found(model: Model()) -> ResolveCliModelResult: ResolveCliModelResult{Some{model}, None{}, None{}, None{}}
def authedIn(authed: List<&2, String>, +provider: String) -> Bool:
  match authed:
    case Nil{}: False{}
    case name <> rest: String.eq(name, provider) || authedIn(rest, provider)
def authenticatedAmong(models: List<&2, Model()>, +authed: List<&2, String>) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = authenticatedAmong(rest, authed)
      Bool.pick(List<&2, Model()>, authedIn(authed, modelProvider(model)), model <> tail, tail)
def referenceOf(+model: Model()) -> String: modelProvider(model) ++ "/" ++ modelId(model)
def references(models: List<&2, Model()>) -> List<&2, String>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: referenceOf(model) <> references(rest)
def ambiguousBare(+cliModel: String, +matches: List<&2, Model()>, authenticated: List<&2, Model()>) -> Resolution:
  match authenticated:
    case one <> Nil{}: Resolved{found(one)}
    case Nil{}: AmbiguousAcross{cliModel, references(matches), "No matching provider is authenticated."}
    case _: AmbiguousAcross{cliModel, references(matches), "More than one matching provider is authenticated."}
def exactAmong(+cliModel: String, +one: Model(), +more: List<&2, Model()>, +authed: List<&2, String>) -> Resolution:
  match more:
    case Nil{}: Resolved{found(one)}
    case _: ambiguousBare(cliModel, one <> more, authenticatedAmong(one <> more, authed))
# upstream: without a provider, an exact id (or provider/id) match wins; several
# prefer the sole authenticated provider, otherwise the id is ambiguous.
def bareExact(+cliModel: String, exact: List<&2, Model()>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match exact:
    case Nil{}: Resolved{orNotFound(cliModel, resolveAcross(cliModel, models))}
    case +one <> more: exactAmong(cliModel, one, more, authed)
def exactMatches(models: List<&2, Model()>, +lower: String) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = exactMatches(rest, lower)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelId(model)), lower) || String.eq(String.to_lower(referenceOf(model)), lower), model <> tail, tail)
def bareResolution(+cliModel: String, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  bareExact(cliModel, exactMatches(models, String.to_lower(cliModel)), authed, models)

# upstream: an inferred provider/model on an unauthenticated provider yields to
# the one authenticated model whose raw id is the whole input.
def sameModel(+left: Model(), +right: Model()) -> Bool: String.eq(modelProvider(left), modelProvider(right)) && String.eq(modelId(left), modelId(right))
def rawIdMatches(models: List<&2, Model()>, +lower: String, +chosen: Model()) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = rawIdMatches(rest, lower, chosen)
      Bool.pick(List<&2, Model()>, String.eq(String.to_lower(modelId(model)), lower) && Bool.not(sameModel(model, chosen)), model <> tail, tail)
def soleAuthenticated(candidates: List<&2, Model()>, result: ResolveCliModelResult) -> ResolveCliModelResult:
  match candidates:
    case one <> Nil{}: found(one)
    case _: result
def preferAuthenticatedRaw(+cliModel: String, result: ResolveCliModelResult, +authed: List<&2, String>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match result:
    case ResolveCliModelResult{Some{+model}, +level, +warning, None{}}:
      Bool.pick(Unit -> ResolveCliModelResult, authedIn(authed, modelProvider(model)),
        _ => ResolveCliModelResult{Some{model}, level, warning, None{}},
        _ => soleAuthenticated(authenticatedAmong(rawIdMatches(models, String.to_lower(cliModel), model), authed), ResolveCliModelResult{Some{model}, level, warning, None{}}))(Unit{})
    case other: other

# upstream: when the inferred provider has no match, the whole input is tried as
# a raw id (first exact id or provider/id match), then as a pattern.
def firstExact(+cliModel: String, exact: List<&2, Model()>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match exact:
    case one <> _: found(one)
    case Nil{}: resolveAcross(cliModel, models)
def fallbackAcross(+cliModel: String, scoped: ResolveCliModelResult, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match scoped:
    case ResolveCliModelResult{None{}, _, _, None{}}: firstExact(cliModel, exactMatches(models, String.to_lower(cliModel)), models)
    case other: other

def resolveCandidate(+cliModel: String, +provider: Maybe<&2, String>, +rest: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match provider:
    case None{}: bareResolution(cliModel, authed, models)
    case Some{+provider}: Resolved{orFallback(provider, rest, cliThinking, models, fallbackAcross(cliModel, preferAuthenticatedRaw(cliModel, resolveWithin(provider, rest, models), authed, models), models))}

# "provider/model" prefers the provider interpretation when the prefix names a
# known provider; a failed provider-scoped match falls back to the full text.
def resolveInferred(+cliModel: String, split: Maybe<&2, Split>, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match split:
    case None{}: bareResolution(cliModel, authed, models)
    case Some{Split{+head, +rest}}: resolveCandidate(cliModel, canonicalProvider(models, String.to_lower(head)), rest, cliThinking, authed, models)

def resolveKnown(+provider: Maybe<&2, String>, cliProvider: String, cliModel: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match provider:
    case None{}: cliError("Unknown provider \"" ++ cliProvider ++ "\". Use --list-models to see available providers/models.")
    case Some{+provider}:
      +pattern = stripPrefix(cliModel, provider ++ "/")
      orFallback(provider, pattern, cliThinking, models, resolveWithin(provider, pattern, models))

def resolveExplicit(+cliProvider: String, cliModel: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  resolveKnown(canonicalProvider(models, String.to_lower(cliProvider)), cliProvider, cliModel, cliThinking, models)

def resolveCliModelWith(cliProvider: Maybe<&2, String>, +cliModel: String, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>, +authed: List<&2, String>, +models: List<&2, Model()>) -> Resolution:
  match cliProvider models:
    case _ Nil{}: Resolved{cliError("No models available. Check your installation or add models to models.json.")}
    case Some{provider} _: Resolved{resolveExplicit(provider, cliModel, cliThinking, models)}
    case None{} _: resolveInferred(cliModel, slashSplit(cliModel), cliThinking, authed, models)

# Providers with configured auth among the models' providers.
def providersOf(models: List<&2, Model()>, +seen: List<&2, String>) -> List<&2, String>:
  match models:
    case Nil{}: List.reverse(&2, String, seen)
    case model <> rest:
      +provider = modelProvider(model)
      providersOf(rest, Bool.pick(List<&2, String>, authedIn(seen, provider), seen, provider <> seen))
def authenticatedProviders(+runtime: ModelRuntime, providers: List<&2, String>) -> IO(List<&2, String>):
  match providers:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case +provider <> rest:
      do IO<List<&2, String>>:
        configured : Bool <- hasConfiguredAuth(runtime, provider)
        +more : List<&2, String> <- authenticatedProviders(runtime, rest)
        return Bool.pick(List<&2, String>, configured, provider <> more, more)

# Uses all models, not just authenticated ones, so --api-key works for
# first-time setup; configured auth only breaks ties between providers.
def resolveCliModel(+runtime: ModelRuntime, cliProvider: Maybe<&2, String>, cliModel: Maybe<&2, String>, cliThinking: Maybe<&2, Ai.ModelThinkingLevel>) -> IO(Resolution):
  match cliModel:
    case None{}: IO.pure(Resolution, Resolved{ResolveCliModelResult{None{}, None{}, None{}, None{}}})
    case Some{pattern}:
      +models = getModels(runtime)
      do IO<Resolution>:
        authed : List<&2, String> <- authenticatedProviders(runtime, providersOf(models, Nil{}))
        return resolveCliModelWith(cliProvider, pattern, cliThinking, authed, models)

# The ambiguity message lists the matches in upstream's localeCompare order.
def ambiguityMessage(cliModel: String, sorted: List<&2, String>, hint: String) -> ResolveCliModelResult:
  cliError("Model \"" ++ cliModel ++ "\" is ambiguous across providers: " ++ String.join(sorted, ", ") ++ ". " ++ hint ++ " Use --provider or provider/model.")

def defaultAmong(defaults: List<&2, DefaultModel>, +models: List<&2, Model()>) -> Maybe<&2, Model()>:
  match defaults:
    case Nil{}: List.head(&2, Model(), models)
    case DefaultModel{provider, id} <> rest: Maybe.or(&2, Model(), findModel(models, provider, id), defaultAmong(rest, models))

def authorizedModel(+runtime: ModelRuntime, found: Maybe<&2, Model()>) -> IO(Maybe<&2, Model()>):
  match found:
    case None{}: IO.pure(Maybe<&2, Model()>, None{})
    case Some{+model}:
      do IO<Maybe<&2, Model()>>:
        configured : Bool <- hasConfiguredAuth(runtime, modelProvider(model))
        return Bool.pick(Maybe<&2, Model()>, configured, Some{model}, None{})

def savedDefault(+runtime: ModelRuntime, defaultProvider: Maybe<&2, String>, defaultModelId: Maybe<&2, String>) -> IO(Maybe<&2, Model()>):
  match defaultProvider defaultModelId:
    case Some{provider} Some{id}: authorizedModel(runtime, getModel(runtime, provider, id))
    case _ _: IO.pure(Maybe<&2, Model()>, None{})

def firstAvailable(+runtime: ModelRuntime, saved: Maybe<&2, Model()>) -> IO(Maybe<&2, Model()>):
  match saved:
    case Some{model}: IO.pure(Maybe<&2, Model()>, Some{model})
    case None{}:
      do IO<Maybe<&2, Model()>>:
        available : List<&2, Model()> <- getAvailable(runtime)
        return defaultAmong(defaultModelPerProvider(), available)

# Without a CLI model: the settings' saved default when its provider is
# authenticated, else the first known default whose provider is
# authenticated, otherwise the first available model (upstream steps 3–4;
# scoped models are not ported).
def findInitialModel(+runtime: ModelRuntime, defaultProvider: Maybe<&2, String>, defaultModelId: Maybe<&2, String>) -> IO(Maybe<&2, Model()>):
  do IO<Maybe<&2, Model()>>:
    saved : Maybe<&2, Model()> <- savedDefault(runtime, defaultProvider, defaultModelId)
    firstAvailable(runtime, saved)

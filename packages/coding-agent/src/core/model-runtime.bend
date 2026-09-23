import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/helpers.bend as Helpers
import ../../../ai/src/auth/context.bend as Context
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/providers/openai.models.bend as OpenAI
import ../../../ai/src/providers/openai-codex.models.bend as Codex
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../runtime/src/string.bend as Strings

# The provider catalog with auth resolution: pi-ai's Models collection and the
# coding agent's ModelRuntime, without models.json custom providers, dynamic
# catalog refresh or the extension provider registry.

type Provider is Data:
  Provider{id: String, name: String, baseUrl: String, auth: Auth.ProviderAuth, models: List<&2, Ai.Model<Ai.JsonValue>>}

def Model() -> Data: Ai.Model<Ai.JsonValue>

type ModelRuntime is Data:
  ModelRuntime{providers: List<&2, Provider>, credentials: Auth.CredentialStore, context: Auth.AuthContext}

def openaiProvider() -> IO(Provider):
  do IO<Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("OpenAI API key", ["OPENAI_API_KEY"])
    return Provider{"openai", "OpenAI", "https://api.openai.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, OpenAI.OPENAI_MODELS()}

def openaiCodexProvider(oauth: Auth.OAuthAuth) -> Provider:
  Provider{"openai-codex", "OpenAI Codex", "https://chatgpt.com/backend-api", Auth.ProviderAuth{None{}, Some{oauth}}, Codex.OPENAI_CODEX_MODELS()}

# The credential store is borrowed; the OAuth handler is owned from here on.
def create(credentials: Auth.CredentialStore, codex: Auth.OAuthAuth) -> IO(ModelRuntime):
  do IO<ModelRuntime>:
    openai : Provider <- openaiProvider()
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    return ModelRuntime{[openai, openaiCodexProvider(codex)], credentials, context}

def disposeProviders(providers: List<&2, Provider>) -> IO(Unit):
  match providers:
    case Nil{}: IO.pure(Unit, Unit{})
    case Provider{_, _, _, auth, _} <> rest:
      do IO<Unit>:
        Auth.disposeProviderAuth(auth)
        disposeProviders(rest)

def dispose(runtime: ModelRuntime) -> IO(Unit):
  match runtime:
    case ModelRuntime{providers, _, context}:
      do IO<Unit>:
        disposeProviders(providers)
        Auth.disposeContext(context)

# Catalog
# -------

def providerId(provider: Provider) -> String:
  match provider:
    case Provider{id, _, _, _, _}: id

def providerModels(provider: Provider) -> List<&2, Model()>:
  match provider:
    case Provider{_, _, _, _, models}: models

def getProviders(runtime: ModelRuntime) -> List<&2, Provider>:
  match runtime:
    case ModelRuntime{providers, _, _}: providers

def findProvider(providers: List<&2, Provider>, +id: String) -> Maybe<&2, Provider>:
  match providers:
    case Nil{}: None{}
    case +provider <> rest: Bool.pick(Maybe<&2, Provider>, String.eq(providerId(provider), id), Some{provider}, findProvider(rest, id))

def getProvider(runtime: ModelRuntime, id: String) -> Maybe<&2, Provider>:
  findProvider(getProviders(runtime), id)

def allModels(providers: List<&2, Provider>) -> List<&2, Model()>:
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

def providerRef(provider: Provider) -> Resolve.ProviderRef:
  match provider:
    case Provider{id, _, _, auth, _}: Resolve.ProviderRef{id, auth}

def unknownProvider(id: String) -> Resolve.ModelsError:
  Resolve.ModelsError{Resolve.ProviderError{}, "Unknown provider: " ++ id}

def resolveFor(credentials: Auth.CredentialStore, context: Auth.AuthContext, id: String, +provider: Maybe<&2, Provider>, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match provider:
    case None{}: IO.pure(Resolve.Resolution(), Fail{unknownProvider(id)})
    case Some{provider}: Resolve.resolveProviderAuth(providerRef(provider), credentials, context, overrides)

def getAuth(runtime: ModelRuntime, +id: String, overrides: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match runtime:
    case ModelRuntime{providers, credentials, context}: resolveFor(credentials, context, id, findProvider(providers, id), overrides)

def configured(resolution: Resolve.Resolution()) -> Bool:
  match resolution:
    case Done{Some{_}}: True{}
    case _: False{}

def hasConfiguredAuth(runtime: ModelRuntime, id: String) -> IO(Bool):
  do IO<Bool>:
    resolution : Resolve.Resolution() <- getAuth(runtime, id, Resolve.noOverrides())
    return configured(resolution)

def availableProviders(+runtime: ModelRuntime, providers: List<&2, Provider>) -> IO(List<&2, Provider>):
  match providers:
    case Nil{}: IO.pure(List<&2, Provider>, Nil{})
    case +provider <> rest:
      do IO<List<&2, Provider>>:
        ready : Bool <- hasConfiguredAuth(runtime, providerId(provider))
        +others : List<&2, Provider> <- availableProviders(runtime, rest)
        return Bool.pick(List<&2, Provider>, ready, provider <> others, others)

# Models whose provider resolves auth now.
def getAvailable(+runtime: ModelRuntime) -> IO(List<&2, Model()>):
  do IO<List<&2, Model()>>:
    providers : List<&2, Provider> <- availableProviders(runtime, getProviders(runtime))
    return allModels(providers)

# Model resolution (model-resolver.ts)
# ------------------------------------

type DefaultModel is Data:
  DefaultModel{provider: String, id: String}

def defaultModelPerProvider() -> List<&2, DefaultModel>:
  [DefaultModel{"openai", "gpt-5.5"}, DefaultModel{"openai-codex", "gpt-5.5"}]

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

def resolveAcross(pattern: String, models: List<&2, Model()>) -> ResolveCliModelResult:
  resolved(parsePattern(pattern, models, False{}))

def fallbackAcross(cliModel: String, scoped: ResolveCliModelResult, models: List<&2, Model()>) -> ResolveCliModelResult:
  match scoped:
    case ResolveCliModelResult{None{}, _, _, None{}}: resolveAcross(cliModel, models)
    case other: other

def resolveCandidate(+cliModel: String, +provider: Maybe<&2, String>, rest: String, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match provider:
    case None{}: resolveAcross(cliModel, models)
    case Some{+provider}: fallbackAcross(cliModel, resolveWithin(provider, rest, models), models)

# "provider/model" prefers the provider interpretation when the prefix names a
# known provider; a failed provider-scoped match falls back to the full text.
def resolveInferred(+cliModel: String, split: Maybe<&2, Split>, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match split:
    case None{}: resolveAcross(cliModel, models)
    case Some{Split{+head, +rest}}: resolveCandidate(cliModel, canonicalProvider(models, String.to_lower(head)), rest, models)

def resolveKnown(+provider: Maybe<&2, String>, cliProvider: String, cliModel: String, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match provider:
    case None{}: cliError("Unknown provider \"" ++ cliProvider ++ "\". Use --list-models to see available providers/models.")
    case Some{+provider}: resolveWithin(provider, stripPrefix(cliModel, provider ++ "/"), models)

def resolveExplicit(+cliProvider: String, cliModel: String, +models: List<&2, Model()>) -> ResolveCliModelResult:
  resolveKnown(canonicalProvider(models, String.to_lower(cliProvider)), cliProvider, cliModel, models)

def resolveCliModelWith(cliProvider: Maybe<&2, String>, +cliModel: String, +models: List<&2, Model()>) -> ResolveCliModelResult:
  match cliProvider models:
    case _ Nil{}: cliError("No models available. Check your installation or add models to models.json.")
    case Some{provider} _: resolveExplicit(provider, cliModel, models)
    case None{} _: resolveInferred(cliModel, slashSplit(cliModel), models)

# Uses all models, not just authenticated ones, so --api-key works for first-time setup.
def resolveCliModel(runtime: ModelRuntime, cliProvider: Maybe<&2, String>, cliModel: Maybe<&2, String>) -> ResolveCliModelResult:
  match cliModel:
    case None{}: ResolveCliModelResult{None{}, None{}, None{}, None{}}
    case Some{pattern}: resolveCliModelWith(cliProvider, pattern, getModels(runtime))

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

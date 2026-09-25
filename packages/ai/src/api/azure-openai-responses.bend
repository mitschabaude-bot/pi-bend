import Base
import ../types.bend as T
import ../utils/provider-env.bend as Env
import ../utils/headers.bend as ProviderHeaders
import ../utils/thinking-levels.bend as Thinking
import ../utils/transcript.bend as Transcript
import ../utils/schema-json.bend as Convert
import ./constrained-sampling.bend as Sampling
import ./openai-client.bend as Client
import ./openai-prompt-cache.bend as CacheKey
import ./openai-responses-shared.bend as Shared
import ./openai-responses-stream.bend as Stream
import ./openai-responses.bend as Responses
import ./simple-options.bend as Simple
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/url.bend as URL

# The Azure OpenAI Responses provider (pi `azure-openai-responses.ts`). It
# resolves the deployment, base URL and API version, builds the Azure request
# body from the shared Responses conversions and runs it through the shared
# Responses request lifecycle with `api-key` authentication.

def DEFAULT_AZURE_API_VERSION() -> String: "v1"

def AZURE_TOOL_CALL_PROVIDERS() -> List<&2, String>:
  "openai" <> "openai-codex" <> "opencode" <> "azure-openai-responses" <> Nil{}

# Options
# -------

# Extends StreamOptions, which is kept whole as `base`.
type AzureOpenAIResponsesOptions<-Reason: Data, -Telemetry: Data, -E: Data> is Data:
  AzureOpenAIResponsesOptions{base: Responses.StreamOptions(Reason, Telemetry, E), reasoningEffort: Maybe<&2, T.ThinkingLevel>, toolChoice: Maybe<&2, T.JsonValue>, reasoningSummary: Maybe<&2, T.Nullable<Responses.ReasoningSummary>>, azureApiVersion: Maybe<&2, String>, azureResourceName: Maybe<&2, String>, azureBaseUrl: Maybe<&2, String>, azureDeploymentName: Maybe<&2, String>}

# JavaScript truthiness of an optional string.
def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SNil{}}: None{}
    case other: other

def trimmed(value: Maybe<&2, String>) -> Maybe<&2, String>:
  nonempty(Maybe.map(&2, String, String, Space.trim, value))

# Deployment names
# ----------------

# `trimmed.split("=", 2)`: the text before the first "=" and up to the next.
def deploymentEntry(parts: List<&2, String>, names: R.Record<String>) -> R.Record<String>:
  match parts:
    case SNil{} <> _: names
    case _ <> SNil{} <> _: names
    case modelId <> deploymentName <> _: R.set(String, names, Space.trim(modelId), Space.trim(deploymentName))
    case _: names

def trimmedEntry(entry: String, names: R.Record<String>) -> R.Record<String>:
  match entry:
    case SNil{}: names
    case text: deploymentEntry(String.split(text, '='), names)

def deploymentEntries(entries: List<&2, String>, names: R.Record<String>) -> R.Record<String>:
  match entries:
    case Nil{}: names
    case entry <> rest: deploymentEntries(rest, trimmedEntry(Space.trim(entry), names))

# "model=deployment,..." with later entries replacing earlier ones.
def parseDeploymentNameMap(value: Maybe<&2, String>) -> R.Record<String>:
  match value:
    case None{}: R.new(String)
    case Some{text}: deploymentEntries(String.split(text, ','), R.new(String))

def deploymentFrom(requested: Maybe<&2, String>, +modelId: String, env: Maybe<&2, T.ProviderEnv()>) -> IO(String):
  match requested:
    case Some{name}: IO.pure(String, name)
    case None{}:
      do IO<String>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", env)
        return Maybe.default(&2, String, nonempty(R.get(String, parseDeploymentNameMap(value), modelId)), modelId)

# options.azureDeploymentName, then AZURE_OPENAI_DEPLOYMENT_NAME_MAP, then the
# model id.
def resolveDeploymentName(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(String):
  match model options:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} AzureOpenAIResponsesOptions{T.StreamOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, deploymentName}:
      deploymentFrom(nonempty(deploymentName), id, env)

# Base URL and API version
# ------------------------

type AzureConfig is Data:
  AzureConfig{baseUrl: String, apiVersion: String}

def withoutTrailingSlashes(text: String) -> String:
  String.reverse(Client.stripLeadingSlashes(String.reverse(text)))

def azureHostname(+name: String) -> Bool:
  String.ends_with(name, ".openai.azure.com") || String.ends_with(name, ".cognitiveservices.azure.com") || String.ends_with(name, ".ai.azure.com")

def azureHost(host: Maybe<&2, URL.Host>) -> Bool:
  match host:
    case None{}: False{}
    case Some{value}: azureHostname(URL.serializeHost(value))

# Root, `/openai` and `/openai/v1/responses` paths, compared without trailing
# slashes.
def rootPath(path: String) -> Bool:
  match path:
    case "": True{}
    case "/": True{}
    case "/openai": True{}
    case "/openai/v1/responses": True{}
    case _: False{}

def rebased(rewrite: Bool, url: URL.URL) -> URL.URL:
  match rewrite url:
    case False{} value: value
    case True{} URL.URL{scheme, username, password, host, port, _, _, fragment}: URL.URL{scheme, username, password, host, port, URL.Hierarchical{"openai" <> "v1" <> Nil{}}, None{}, fragment}

# Azure hosts get /openai/v1 as their base path and lose their query, so the
# client can append /responses and ?api-version.
def normalizedURL(url: URL.URL) -> String:
  match url:
    case URL.URL{scheme, username, password, +host, port, +path, query, fragment}:
      rewrite = azureHost(host) && rootPath(withoutTrailingSlashes(URL.serializePath(path)))
      withoutTrailingSlashes(URL.serialize(rebased(rewrite, URL.URL{scheme, username, password, host, port, path, query, fragment}), False{}))

def parsedBaseUrl(baseUrl: String, result: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, Responses.PreparationError, String>:
  match result:
    case Fail{_}: Fail{Responses.InvalidAzureBaseUrl{baseUrl}}
    case Done{url}: Done{normalizedURL(url)}

def normalizeAzureBaseUrl(urls: URL.Context, +baseUrl: String) -> Result<&2, &2, Responses.PreparationError, String>:
  parsedBaseUrl(baseUrl, URL.parse(urls, withoutTrailingSlashes(Space.trim(baseUrl))))

def buildDefaultBaseUrl(resourceName: String) -> String:
  "https://" ++ resourceName ++ ".openai.azure.com/openai/v1"

def selectedBaseUrl(baseUrl: Maybe<&2, String>, resourceName: Maybe<&2, String>, modelBaseUrl: String) -> Maybe<&2, String>:
  match baseUrl resourceName:
    case Some{url} _: Some{url}
    case None{} Some{name}: Some{buildDefaultBaseUrl(name)}
    case None{} None{}: nonempty(Some{modelBaseUrl})

def versioned(apiVersion: String, result: Result<&2, &2, Responses.PreparationError, String>) -> Result<&2, &2, Responses.PreparationError, AzureConfig>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{baseUrl}: Done{AzureConfig{baseUrl, apiVersion}}

def configured(urls: URL.Context, apiVersion: String, baseUrl: Maybe<&2, String>) -> Result<&2, &2, Responses.PreparationError, AzureConfig>:
  match baseUrl:
    case None{}: Fail{Responses.MissingAzureBaseUrl{}}
    case Some{url}: versioned(apiVersion, normalizeAzureBaseUrl(urls, url))

# Options first, then the environment: azureBaseUrl / AZURE_OPENAI_BASE_URL,
# azureResourceName / AZURE_OPENAI_RESOURCE_NAME, then model.baseUrl.
def resolveAzureConfig(-Reason: Data, -Telemetry: Data, -E: Data, urls: URL.Context, modelBaseUrl: String, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(Result<&2, &2, Responses.PreparationError, AzureConfig>):
  match options:
    case AzureOpenAIResponsesOptions{T.StreamOptions{_, _, _, _, +env, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, apiVersion, resourceName, baseUrl, _}:
      do IO<Result<&2, &2, Responses.PreparationError, AzureConfig>>:
        envVersion : Maybe<&2, String> <- Env.getProviderEnvValue("AZURE_OPENAI_API_VERSION", env)
        envBaseUrl : Maybe<&2, String> <- Env.getProviderEnvValue("AZURE_OPENAI_BASE_URL", env)
        envResourceName : Maybe<&2, String> <- Env.getProviderEnvValue("AZURE_OPENAI_RESOURCE_NAME", env)
        return configured(urls, Maybe.default(&2, String, Maybe.or(&2, String, nonempty(apiVersion), envVersion), DEFAULT_AZURE_API_VERSION()), selectedBaseUrl(Maybe.or(&2, String, trimmed(baseUrl), trimmed(envBaseUrl)), Maybe.or(&2, String, nonempty(resourceName), envResourceName), modelBaseUrl))

# Request parameters
# ------------------

# Azure honors a model's compatibility only for the Azure API. Its defaults
# coincide with Codex's: strict mode on, every other capability off.
def compatFor(api: T.ModelApi, provider: String, baseUrl: String, compat: Maybe<&2, T.ModelCompatibility(api)>) -> Responses.ResolvedCompat:
  match api:
    case T.AzureOpenAIResponsesApi{}: Responses.getCodexCompat(provider, baseUrl, compat)
    case _: Responses.getCodexCompat(provider, baseUrl, None{})

def getCompat(model: T.Model<T.JsonValue>) -> Responses.ResolvedCompat:
  match model:
    case T.Model{_, _, api, provider, baseUrl, _, _, _, _, _, _, _, _, _, _, compat}: compatFor(api, provider, baseUrl, compat)

def baseParams(deploymentName: String, input: List<&2, T.JsonValue>, sessionId: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  fields = {R.Record{R.Property{"model", T.JsonString{deploymentName}} <> R.Property{"input", T.JsonArray{input}} <> R.Property{"stream", T.JsonBoolean{True{}}} <> Nil{}} : R.Record<T.JsonValue>}
  R.set(T.JsonValue, Responses.optionalString(fields, "prompt_cache_key", CacheKey.clampOpenAIPromptCacheKey(sessionId)), "store", T.JsonBoolean{False{}})

def reasoningFields(requested: Bool, fields: R.Record<T.JsonValue>, mapping: Maybe<&2, T.ThinkingLevelMap>, effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match requested:
    case False{}: Responses.offEffort(fields, Thinking.mapped(mapping, T.Off{}))
    case True{}: Responses.requestedReasoning(fields, mapping, effort, summary)

def addReasoning(fields: R.Record<T.JsonValue>, model: T.Model<T.JsonValue>, +effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, T.Nullable<Responses.ReasoningSummary>>) -> R.Record<T.JsonValue>:
  match model:
    case T.Model{_, _, _, _, _, False{}, _, _, _, _, _, _, _, _, _, _}: fields
    case T.Model{_, _, _, _, _, True{}, mapping, _, _, _, _, _, _, _, _, _}:
      +selected = Responses.summaryText(summary)
      reasoningFields(Responses.reasoningRequested(effort, selected), fields, mapping, effort, selected)

# The wire object in upstream field order; sampling parameters override last.
def assembledParams(-Reason: Data, -Telemetry: Data, -E: Data, +model: T.Model<T.JsonValue>, deploymentName: String, input: List<&2, T.JsonValue>, tools: List<&2, T.JsonValue>, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> T.JsonValue:
  match options:
    case AzureOpenAIResponsesOptions{T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, sampling, maxTokens, _, _, sessionId, _, _}, effort, choice, summary, _, _, _, _}:
      budgeted = Responses.optionalNumber(baseParams(deploymentName, input, sessionId), "max_output_tokens", Responses.outputTokens(True{}, maxTokens))
      tempered = Responses.optionalNumber(budgeted, "temperature", temperature)
      toolFields = Responses.optionalValue(Responses.addTools(tempered, tools), "tool_choice", choice)
      T.JsonObject{Responses.samplingFields(addReasoning(toolFields, model, effort, summary), sampling)}

def convertedTools(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, deploymentName: String, items: List<&2, Shared.ResponseInputItem>, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>, tools: Result<&2, &2, Sampling.Error, List<&2, Shared.OpenAITool>>) -> Result<&2, &2, Responses.BuildError, T.JsonValue>:
  match tools:
    case Fail{error}: Fail{Responses.ToolConversion{error}}
    case Done{converted}: Done{assembledParams(Reason, Telemetry, E, model, deploymentName, Responses.inputJson(items), Responses.toolsJson(converted), options)}

def convertedParams(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, deploymentName: String, input: Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>, tools: Transcript.TranscriptTools<V.Value>, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>, compat: Responses.ResolvedCompat) -> Result<&2, &2, Responses.BuildError, T.JsonValue>:
  match input tools:
    case Fail{error} _: Fail{Responses.MessageConversion{error}}
    case Done{items} Transcript.TranscriptTools{values, _}: convertedTools(Reason, Telemetry, E, model, deploymentName, items, options, Shared.convertResponsesTools(values, Some{Responses.toolOptions(compat, Responses.ResponsesEndpoint{})}))

# Messages and tools convert as for OpenAI Responses, with Azure's tool-call
# providers and strict-mode default.
def buildParams(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, +model: T.Model<T.JsonValue>, +context: Responses.Context(G, D), options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>, +compat: Responses.ResolvedCompat, grammar: R.Record<String>, deploymentName: String) -> IO(Result<&2, &2, Responses.BuildError, T.JsonValue>):
  do IO<Result<&2, &2, Responses.BuildError, T.JsonValue>>:
    input : Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>> <- Shared.convertResponsesMessagesWith(~V.Value, ~V.Value, ~G, ~D, ~T.JsonValue, ~Shared.parameterValue, ~Shared.parameterValue, ~Shared.conversionClock, model, context, AZURE_TOOL_CALL_PROVIDERS(), Some{Responses.messageOptions(compat, grammar, Responses.ResponsesEndpoint{})})
    return convertedParams(Reason, Telemetry, E, model, deploymentName, input, Responses.requestTools(G, D, context, compat), options, compat)

# Preparation
# -----------

# pi's User-Agent, the model's headers, then the caller's.
def clientHeaders(agent: String, modelHeaders: Maybe<&2, R.Record<String>>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  defaults = {R.Record{R.Property{"User-Agent", T.PresentValue{agent}} <> Nil{}} : T.ProviderHeaders()}
  ProviderHeaders.overlay(ProviderHeaders.overlayStrings(defaults, modelHeaders), optionsHeaders)

def requestHeaders(-Reason: Data, -Telemetry: Data, -E: Data, agent: String, model: T.Model<T.JsonValue>, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> T.ProviderHeaders():
  match model options:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, modelHeaders, _} AzureOpenAIResponsesOptions{T.StreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _}:
      clientHeaders(agent, modelHeaders, headers)

def optionApiKey(-Reason: Data, -Telemetry: Data, -E: Data, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> Maybe<&2, String>:
  match options:
    case AzureOpenAIResponsesOptions{T.StreamOptions{_, _, apiKey, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _}: apiKey

def baseUrlOf(model: T.Model<T.JsonValue>) -> String:
  match model:
    case T.Model{_, _, _, _, baseUrl, _, _, _, _, _, _, _, _, _, _, _}: baseUrl

def completed(apiKey: String, headers: T.ProviderHeaders(), config: AzureConfig, grammar: R.Record<String>, payload: Result<&2, &2, Responses.BuildError, T.JsonValue>) -> Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>:
  match config payload:
    case _ Fail{cause}: Fail{Responses.PayloadFailure{cause}}
    case AzureConfig{baseUrl, apiVersion} Done{value}: Done{Responses.ProviderRequest{apiKey, baseUrl, headers, value, Responses.AzureTarget{apiVersion}, Stream.OpenAIResponsesStreamOptions{None{}, grammar}}}

def withGrammar(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, context: Responses.Context(G, D), options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>, compat: Responses.ResolvedCompat, deploymentName: String, apiKey: String, headers: T.ProviderHeaders(), config: AzureConfig, grammar: Result<&2, &2, Responses.PreparationError, R.Record<String>>) -> IO(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>):
  match grammar:
    case Fail{cause}: IO.pure(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>, Fail{cause})
    case Done{+properties}:
      do IO<Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>>:
        payload : Result<&2, &2, Responses.BuildError, T.JsonValue> <- buildParams(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, compat, properties, deploymentName)
        return completed(apiKey, headers, config, properties, payload)

def withConfig(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, +context: Responses.Context(G, D), options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>, +compat: Responses.ResolvedCompat, deploymentName: String, apiKey: String, headers: T.ProviderHeaders(), config: Result<&2, &2, Responses.PreparationError, AzureConfig>) -> IO(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>):
  match config:
    case Fail{cause}: IO.pure(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>, Fail{cause})
    case Done{value}: withGrammar(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, compat, deploymentName, apiKey, headers, value, Responses.grammarProperties(G, D, context, compat))

def withApiKey(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, urls: URL.Context, agent: String, +model: T.Model<T.JsonValue>, context: Responses.Context(G, D), +options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>, compat: Responses.ResolvedCompat, deploymentName: String, apiKey: Maybe<&2, String>) -> IO(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>):
  match apiKey:
    case None{}: IO.pure(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>, Fail{Responses.MissingApiKey{T.modelProvider(model)}})
    case Some{key}:
      do IO<Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>>:
        config : Result<&2, &2, Responses.PreparationError, AzureConfig> <- resolveAzureConfig(Reason, Telemetry, E, urls, baseUrlOf(model), options)
        withConfig(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, compat, deploymentName, key, requestHeaders(Reason, Telemetry, E, agent, model, options), config)

# Deployment, API key, base URL, grammar discovery and the wire payload, in
# the order the upstream `stream` performs them.
def prepare(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, urls: URL.Context, agent: String, +model: T.Model<T.JsonValue>, context: Responses.Context(G, D), +options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>):
  +compat = getCompat(model)
  do IO<Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>>:
    deploymentName : String <- resolveDeploymentName(Reason, Telemetry, E, model, options)
    withApiKey(~Reason, ~Telemetry, ~E, ~G, ~D, urls, agent, model, Transcript.resolveTranscript(V.Value, V.Value, G, D, context, Some{Responses.midConversation(compat)}), options, compat, deploymentName, nonempty(optionApiKey(Reason, Telemetry, E, options)))

# Public entry points
# -------------------

def baseOptions(-Reason: Data, -Telemetry: Data, -E: Data, options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> Responses.StreamOptions(Reason, Telemetry, E):
  match options:
    case AzureOpenAIResponsesOptions{base, _, _, _, _, _, _, _}: base

def urlContext(config: Responses.Config) -> URL.Context:
  match config:
    case Responses.Config{urls, _, _, _, _, _, _}: urls

# Generate function for the Azure OpenAI Responses API.
def stream(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, +config: Responses.Config, +model: T.Model<T.JsonValue>, context: Responses.Context(G, D), +options: AzureOpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(Responses.Run<Reason, G, E>):
  Responses.start(~Reason, ~Telemetry, ~G, ~E, ~render, config, model, baseOptions(Reason, Telemetry, E, options), prepare(~Reason, ~Telemetry, ~E, ~G, ~D, urlContext(config), Responses.userAgent(config), model, context, options))

def simpleOptions(-Reason: Data, -Telemetry: Data, -E: Data, base: Responses.StreamOptions(Reason, Telemetry, E), settings: Responses.ResponsesSettings) -> AzureOpenAIResponsesOptions<Reason, Telemetry, E>:
  match settings:
    case Responses.ResponsesSettings{effort, summary, _, choice}: AzureOpenAIResponsesOptions{base, effort, choice, summary, None{}, None{}, None{}, None{}}

# streamSimple: base options with the model's defaults and context budget,
# tool choice, and the reasoning level clamped to the model's support. A
# missing API key fails the stream instead of throwing before it starts.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Responses.Config, +model: T.Model<T.JsonValue>, +context: Responses.Context(G, D), +options: Maybe<&2, Responses.SimpleStreamOptions(Reason, Telemetry, E)>) -> IO(Responses.Run<Reason, G, E>):
  stream(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, model, context, simpleOptions(Reason, Telemetry, E, Simple.buildBaseOptionsWith(~V.Value, ~V.Value, ~G, ~D, ~T.JsonValue, ~(Responses.Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, ~Convert.toJson, ~Convert.toJson, model, context, options, Responses.simpleApiKey(Reason, Telemetry, E, options)), Responses.simpleSettings(Reason, Telemetry, E, model, options)))

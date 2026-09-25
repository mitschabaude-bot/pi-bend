import Base
import ../types.bend as T
import ../models.bend as Models
import ../utils/error-body.bend as Body
import ../utils/event-stream.bend as Events
import ../utils/model-api.bend as Api
import ../utils/provider-env.bend as Env
import ../utils/headers.bend as ProviderHeaders
import ../utils/provider-retry.bend as Retry
import ../utils/thinking-levels.bend as Thinking
import ../utils/transcript.bend as Transcript
import ../utils/jwt.bend as Jwt
import ../utils/text.bend as Text
import ./constrained-sampling.bend as Sampling
import ./github-copilot-headers.bend as Copilot
import ./openai-client.bend as Client
import ./openai-prompt-cache.bend as CacheKey
import ./openai-responses-shared.bend as Shared
import ./openai-responses-stream.bend as Stream
import ./openai-sse.bend as Sse
import ./simple-options.bend as Simple
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/http-response.bend as Scope
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/json.bend as StringJSON
import ../utils/schema-json.bend as Convert
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-exchange.bend as HTTP
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response.bend as Metadata
import ../../../runtime/src/http-response.bend as Progress
import ../../../runtime/src/json.bend as JsonParse
import ../../../runtime/src/random.bend as Seed
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/u64.bend as Word
import ../../../runtime/src/http-message.bend as Header

# The OpenAI Responses provider (pi `openai-responses.ts`). `stream` prepares
# the request, runs it through the native client with pi's retry policy, folds
# the SSE response into the canonical assistant event stream and settles the
# final message. Message/tool conversion and response processing are shared
# with the other Responses providers through the two shared modules; Azure
# (azure-openai-responses.bend) prepares its own requests and runs them
# through this module's request lifecycle (`startRequest`).

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Reason>
def StreamOptions(-Reason: Data, -Telemetry: Data, -E: Data) -> Data: T.StreamOptions<T.JsonValue, Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>
def SimpleStreamOptions(-Reason: Data, -Telemetry: Data, -E: Data) -> Data: T.SimpleStreamOptions<T.JsonValue, Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>
def Context(-G: Data, -D: Data) -> Data: T.TranscriptContext<V.Value, V.Value, G, D>
def ReaderError(-Reason: Data) -> Data: Stream.ReaderError<Sse.TransportError(Reason)>

# Options
# -------

type ReasoningSummary is Data:
  SummaryAuto{}
  SummaryDetailed{}
  SummaryConcise{}

type ServiceTier is Data:
  TierAuto{}
  TierDefault{}
  TierFlex{}
  TierScale{}
  TierPriority{}

def summaryName(value: ReasoningSummary) -> String:
  match value:
    case SummaryAuto{}: "auto"
    case SummaryDetailed{}: "detailed"
    case SummaryConcise{}: "concise"

def tierName(value: ServiceTier) -> String:
  match value:
    case TierAuto{}: "auto"
    case TierDefault{}: "default"
    case TierFlex{}: "flex"
    case TierScale{}: "scale"
    case TierPriority{}: "priority"

# Extends StreamOptions with the Responses-specific fields. Tool choice is the
# SDK's JSON-shaped union, kept as the wire value.
type OpenAIResponsesOptions<-Reason: Data, -Telemetry: Data, -E: Data> is Data:
  OpenAIResponsesOptions{signal: Maybe<&2, Signal(Reason)>, telemetryContext: Maybe<&2, Telemetry>, apiKey: Maybe<&2, String>, fetch: Maybe<&2, Fetch.Fetch(Reason)>, env: Maybe<&2, T.ProviderEnv()>, onPayload: Maybe<&2, T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, headers: Maybe<&2, T.ProviderHeaders()>, timeoutMs: Maybe<&2, F64>, maxRetries: Maybe<&2, F64>, maxRetryDelayMs: Maybe<&2, F64>, temperature: Maybe<&2, F64>, samplingParams: Maybe<&2, R.Record<T.JsonValue>>, maxTokens: Maybe<&2, F64>, transport: Maybe<&2, T.Transport>, cacheRetention: Maybe<&2, T.CacheRetention>, sessionId: Maybe<&2, String>, websocketConnectTimeoutMs: Maybe<&2, F64>, metadata: Maybe<&2, R.Record<T.JsonValue>>, reasoningEffort: Maybe<&2, T.ThinkingLevel>, reasoningSummary: Maybe<&2, T.Nullable<ReasoningSummary>>, serviceTier: Maybe<&2, T.Nullable<ServiceTier>>, toolChoice: Maybe<&2, T.JsonValue>}

type ResponsesSettings is Data:
  ResponsesSettings{reasoningEffort: Maybe<&2, T.ThinkingLevel>, reasoningSummary: Maybe<&2, T.Nullable<ReasoningSummary>>, serviceTier: Maybe<&2, T.Nullable<ServiceTier>>, toolChoice: Maybe<&2, T.JsonValue>}

def fromStreamOptions(-Reason: Data, -Telemetry: Data, -E: Data, base: StreamOptions(Reason, Telemetry, E), settings: ResponsesSettings) -> OpenAIResponsesOptions<Reason, Telemetry, E>:
  match base settings:
    case T.StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata} ResponsesSettings{reasoningEffort, reasoningSummary, serviceTier, toolChoice}:
      OpenAIResponsesOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, reasoningEffort, reasoningSummary, serviceTier, toolChoice}

def toStreamOptions(-Reason: Data, -Telemetry: Data, -E: Data, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> StreamOptions(Reason, Telemetry, E):
  match options:
    case OpenAIResponsesOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, _, _, _, _}:
      T.StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata}

def settings(-Reason: Data, -Telemetry: Data, -E: Data, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> ResponsesSettings:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, reasoningEffort, reasoningSummary, serviceTier, toolChoice}: ResponsesSettings{reasoningEffort, reasoningSummary, serviceTier, toolChoice}

# Compatibility and caching policy
# --------------------------------

# Required<OpenAIResponsesCompat>: every upstream field retains its name.
# The model's API selects the endpoint: the SDK's Responses resource or the
# ChatGPT Codex backend, which shares the wire protocol but not URL, headers
# or the request body's framing.
type Endpoint is Data:
  ResponsesEndpoint{}
  CodexEndpoint{}

type ResolvedCompat is Data:
  ResolvedCompat{supportsDeveloperRole: Bool, supportsMidConvoSystemMessages: Bool, sessionAffinityFormat: T.SessionAffinityFormat, supportsLongCacheRetention: Bool, supportsStrictMode: Bool, supportsOpenAIGrammarTools: Bool, supportsAdditionalTools: Bool, supportsToolSearch: Bool, supportsExplicitPromptCacheMode: Bool, supportsMaxOutputTokens: Bool}

def boolDefault(value: Maybe<&2, Bool>, fallback: Bool) -> Bool:
  match value:
    case None{}: fallback
    case Some{flag}: flag

def detectSessionAffinityFormat(provider: String, baseUrl: String) -> T.SessionAffinityFormat:
  Bool.pick(T.SessionAffinityFormat, String.eq(provider, "openrouter") || String.contains(baseUrl, "openrouter.ai"), T.OpenRouterSession{}, T.OpenAISession{})

def affinityDefault(value: Maybe<&2, T.SessionAffinityFormat>, provider: String, baseUrl: String) -> T.SessionAffinityFormat:
  match value:
    case None{}: detectSessionAffinityFormat(provider, baseUrl)
    case Some{format}: format

def getCompat(provider: String, baseUrl: String, compat: Maybe<&2, T.OpenAIResponsesCompat>) -> ResolvedCompat:
  match compat:
    case None{}: ResolvedCompat{True{}, False{}, detectSessionAffinityFormat(provider, baseUrl), True{}, False{}, False{}, False{}, False{}, False{}, True{}}
    case Some{T.OpenAIResponsesCompat{developer, midConvo, affinity, longCache, strict, grammar, additional, search, explicitCache, maxOutput}}:
      ResolvedCompat{boolDefault(developer, True{}), boolDefault(midConvo, False{}), affinityDefault(affinity, provider, baseUrl), boolDefault(longCache, True{}), boolDefault(strict, False{}), boolDefault(grammar, False{}), boolDefault(additional, False{}), boolDefault(search, False{}), boolDefault(explicitCache, False{}), boolDefault(maxOutput, True{})}

# Defaults to "short"; PI_CACHE_RETENTION=long is honored for compatibility.
def environmentRetention(envValue: Maybe<&2, String>) -> T.CacheRetention:
  match envValue:
    case None{}: T.CacheShort{}
    case Some{text}: Bool.pick(T.CacheRetention, String.eq(text, "long"), T.CacheLong{}, T.CacheShort{})

def resolveCacheRetention(retention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>) -> IO(T.CacheRetention):
  match retention:
    case Some{value}: IO.pure(T.CacheRetention, value)
    case None{}:
      do IO<T.CacheRetention>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue("PI_CACHE_RETENTION", env)
        return environmentRetention(value)

type PromptCacheOptions is Data:
  ExplicitMode{}
  ThirtyMinuteTtl{}

def getPromptCacheRetention(compat: ResolvedCompat, retention: T.CacheRetention) -> Maybe<&2, String>:
  match compat retention:
    case ResolvedCompat{_, _, _, True{}, _, _, _, _, False{}, _} T.CacheLong{}: Some{"24h"}
    case _ _: None{}

def getPromptCacheOptions(compat: ResolvedCompat, retention: T.CacheRetention) -> Maybe<&2, PromptCacheOptions>:
  match compat retention:
    case ResolvedCompat{_, _, _, _, _, _, _, _, True{}, _} T.CacheNone{}: Some{ExplicitMode{}}
    case ResolvedCompat{_, _, _, True{}, _, _, _, _, True{}, _} T.CacheLong{}: Some{ThirtyMinuteTtl{}}
    case _ _: None{}

def resolveCacheRetentionValue(retention: Maybe<&2, T.CacheRetention>, envValue: Maybe<&2, String>) -> T.CacheRetention:
  match retention:
    case None{}: environmentRetention(envValue)
    case Some{value}: value

def cacheSessionId(retention: T.CacheRetention, sessionId: Maybe<&2, String>) -> Maybe<&2, String>:
  match retention:
    case T.CacheNone{}: None{}
    case _: sessionId

def promptCacheKey(retention: T.CacheRetention, sessionId: Maybe<&2, String>) -> Maybe<&2, String>:
  CacheKey.clampOpenAIPromptCacheKey(cacheSessionId(retention, sessionId))

# Credentials
# -----------

def headerCredential(provider: String, +headers: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, String, String>:
  Bool.pick(Result<&2, &2, String, String>, ProviderHeaders.hasHeader(headers, "authorization") || ProviderHeaders.hasHeader(headers, "cf-aig-authorization"), Done{"unused"}, Fail{provider})

# A caller-supplied Authorization header replaces the key with "unused". The
# failure carries the provider name for the "No API key" diagnostic.
def getClientApiKey(provider: String, apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, String, String>:
  match apiKey:
    case None{}: headerCredential(provider, headers)
    case Some{SNil{}}: headerCredential(provider, headers)
    case Some{text}: Done{text}

# Client headers
# --------------

def affinityHeaders(format: T.SessionAffinityFormat, sessionId: Maybe<&2, String>) -> R.Record<String>:
  match format sessionId:
    case _ None{}: R.new(String)
    case _ Some{SNil{}}: R.new(String)
    case T.OpenRouterSession{} Some{text}: R.Record{R.Property{"x-session-id", text} <> Nil{}}
    case T.OpenAINoSession{} Some{text}: R.Record{R.Property{"x-client-request-id", text} <> Nil{}}
    case T.OpenAISession{} Some{+text}: R.Record{R.Property{"session_id", text} <> R.Property{"x-client-request-id", text} <> Nil{}}

# createClient: user agent, model headers, Copilot dynamic headers, session
# affinity, then the caller's headers last so they can override defaults.
def defaultHeaders(agent: String, modelHeaders: Maybe<&2, R.Record<String>>, copilotHeaders: Maybe<&2, R.Record<String>>, affinity: T.SessionAffinityFormat, sessionId: Maybe<&2, String>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  defaults = {R.Record{R.Property{"User-Agent", T.PresentValue{agent}} <> Nil{}} : T.ProviderHeaders()}
  model = ProviderHeaders.overlayStrings(defaults, modelHeaders)
  copilot = ProviderHeaders.overlayStrings(model, copilotHeaders)
  session = ProviderHeaders.overlayStrings(copilot, Some{affinityHeaders(affinity, sessionId)})
  ProviderHeaders.overlay(session, optionsHeaders)

def clientHeaders(-P: Data, -A: Data, -G: Data, -D: Data, agent: String, provider: String, modelHeaders: Maybe<&2, R.Record<String>>, context: T.TranscriptContext<P, A, G, D>, affinity: T.SessionAffinityFormat, sessionId: Maybe<&2, String>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  match context:
    case T.TranscriptContext{messages}: defaultHeaders(agent, modelHeaders, Copilot.forProvider(P, A, G, D, provider, messages), affinity, sessionId, optionsHeaders)

# Request parameters
# ------------------

def OPENAI_TOOL_CALL_PROVIDERS() -> List<&2, String>:
  "openai" <> "openai-codex" <> "opencode" <> Nil{}

# OpenAI Responses rejects max_output_tokens below 16 (pi#6265).
def OPENAI_RESPONSES_MIN_OUTPUT_TOKENS() -> F64: F.fromU32(16)

type BuildError is Data:
  MessageConversion{error: Shared.MessageError}
  ToolConversion{error: Sampling.Error}

def optionalString(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{text}: R.set(T.JsonValue, fields, key, T.JsonString{text})

def optionalNullableString(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, T.Nullable<String>>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{T.NullValue{}}: R.set(T.JsonValue, fields, key, T.JsonNull{})
    case Some{T.PresentValue{text}}: R.set(T.JsonValue, fields, key, T.JsonString{text})

def optionalNumber(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, F64>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{scalar}: R.set(T.JsonValue, fields, key, T.JsonNumber{scalar})

def optionalValue(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, T.JsonValue>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{json}: R.set(T.JsonValue, fields, key, json)

def activeNumber(value: F.Decoded) -> Bool:
  match value:
    case F.NotANumber{}: False{}
    case F.Infinity{_}: True{}
    case F.Finite{_, _, magnitude}: Bool.not(Word.equal(magnitude, Word.zero()))

# `options.maxTokens &&`: zero and NaN are falsy and send no budget.
def outputTokens(enabled: Bool, value: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match enabled value:
    case True{} Some{+scalar}: Bool.pick(Maybe<&2, F64>, activeNumber(F.decode(scalar)), Some{F.maximum(scalar, OPENAI_RESPONSES_MIN_OUTPUT_TOKENS())}, None{})
    case _ _: None{}

def mappedEffort(value: Maybe<&2, T.Nullable<String>>, fallback: String) -> String:
  match value:
    case Some{T.PresentValue{text}}: text
    case _: fallback

def requestedEffort(value: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>) -> String:
  match value:
    case None{}: "medium"
    case Some{+level}: mappedEffort(Thinking.mapped(mapping, T.Thinking{level}), Thinking.name(T.Thinking{level}))

def summaryText(value: Maybe<&2, T.Nullable<ReasoningSummary>>) -> Maybe<&2, String>:
  match value:
    case Some{T.PresentValue{selected}}: Some{summaryName(selected)}
    case _: None{}

def summaryOrAuto(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "auto"
    case Some{text}: text

def reasoningRequested(effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, String>) -> Bool:
  match effort summary:
    case None{} None{}: False{}
    case _ _: True{}

def encryptedContent(fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  R.set(T.JsonValue, fields, "include", T.JsonArray{T.JsonString{"reasoning.encrypted_content"} <> Nil{}})

# Without a requested effort or summary, reasoning is turned off explicitly
# unless the model maps "off" to null.
def offEffort(fields: R.Record<T.JsonValue>, mapping: Maybe<&2, T.Nullable<String>>) -> R.Record<T.JsonValue>:
  match mapping:
    case Some{T.NullValue{}}: fields
    case value: R.set(T.JsonValue, fields, "reasoning", T.JsonObject{R.Record{R.Property{"effort", T.JsonString{mappedEffort(value, "none")}} <> Nil{}}})

def offReasoning(fields: R.Record<T.JsonValue>, provider: String, mapping: Maybe<&2, T.Nullable<String>>) -> R.Record<T.JsonValue>:
  match provider:
    case "github-copilot": fields
    case _: offEffort(fields, mapping)

def requestedReasoning(fields: R.Record<T.JsonValue>, mapping: Maybe<&2, T.ThinkingLevelMap>, effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  encryptedContent(R.set(T.JsonValue, fields, "reasoning", T.JsonObject{R.Record{R.Property{"effort", T.JsonString{requestedEffort(effort, mapping)}} <> R.Property{"summary", T.JsonString{summaryOrAuto(summary)}} <> Nil{}}}))

def configuredReasoning(requested: Bool, fields: R.Record<T.JsonValue>, provider: String, mapping: Maybe<&2, T.ThinkingLevelMap>, effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match requested:
    case False{}: offReasoning(fields, provider, Thinking.mapped(mapping, T.Off{}))
    case True{}: requestedReasoning(fields, mapping, effort, summary)

def xaiInclude(provider: String, fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  match provider:
    case "xai": encryptedContent(fields)
    case _: fields

def addReasoning(fields: R.Record<T.JsonValue>, model: T.Model<T.JsonValue>, +effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, T.Nullable<ReasoningSummary>>) -> R.Record<T.JsonValue>:
  match model:
    case T.Model{_, _, _, _, _, False{}, _, _, _, _, _, _, _, _, _, _}: fields
    case T.Model{_, _, _, +provider, _, True{}, mapping, _, _, _, _, _, _, _, _, _}:
      +selected = summaryText(summary)
      xaiInclude(provider, configuredReasoning(reasoningRequested(effort, selected), fields, provider, mapping, effort, selected))

def cacheOptions(fields: R.Record<T.JsonValue>, value: Maybe<&2, PromptCacheOptions>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{ExplicitMode{}}: R.set(T.JsonValue, fields, "prompt_cache_options", T.JsonObject{R.Record{R.Property{"mode", T.JsonString{"explicit"}} <> Nil{}}})
    case Some{ThirtyMinuteTtl{}}: R.set(T.JsonValue, fields, "prompt_cache_options", T.JsonObject{R.Record{R.Property{"ttl", T.JsonString{"30m"}} <> Nil{}}})

def baseFields(id: String, input: List<&2, T.JsonValue>, +compat: ResolvedCompat, +retention: T.CacheRetention, sessionId: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  fields = {R.Record{R.Property{"model", T.JsonString{id}} <> R.Property{"input", T.JsonArray{input}} <> R.Property{"stream", T.JsonBoolean{True{}}} <> R.Property{"store", T.JsonBoolean{False{}}} <> Nil{}} : R.Record<T.JsonValue>}
  cacheOptions(optionalString(optionalString(fields, "prompt_cache_key", promptCacheKey(retention, sessionId)), "prompt_cache_retention", getPromptCacheRetention(compat, retention)), getPromptCacheOptions(compat, retention))

def addTools(fields: R.Record<T.JsonValue>, tools: List<&2, T.JsonValue>) -> R.Record<T.JsonValue>:
  match tools:
    case Nil{}: fields
    case values: R.set(T.JsonValue, fields, "tools", T.JsonArray{values})

# Custom sampling fields override named fields last, including null.
def overrideFields(entries: List<&2, R.Property<T.JsonValue>>, fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  match entries:
    case Nil{}: fields
    case R.Property{key, value} <> rest: overrideFields(rest, R.set(T.JsonValue, fields, key, value))

def samplingFields(fields: R.Record<T.JsonValue>, sampling: Maybe<&2, R.Record<T.JsonValue>>) -> R.Record<T.JsonValue>:
  match sampling:
    case None{}: fields
    case Some{values}: overrideFields(R.entries(T.JsonValue, values), fields)

def maxOutputSupport(value: ResolvedCompat) -> Bool:
  match value:
    case ResolvedCompat{_, _, _, _, _, _, _, _, _, enabled}: enabled

def toolsJson(items: List<&2, Shared.OpenAITool>) -> List<&2, T.JsonValue>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: Shared.toolToJson(head) <> toolsJson(rest)

def inputJson(items: List<&2, Shared.ResponseInputItem>) -> List<&2, T.JsonValue>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: Shared.inputItemToJson(head) <> inputJson(rest)

def tierValue(value: Maybe<&2, T.Nullable<ServiceTier>>) -> Maybe<&2, T.Nullable<String>>:
  match value:
    case None{}: None{}
    case Some{T.NullValue{}}: Some{T.NullValue{}}
    case Some{T.PresentValue{selected}}: Some{T.PresentValue{tierName(selected)}}

# The final wire object from already-encoded input items and tools.
def assembledParams(-Reason: Data, -Telemetry: Data, -E: Data, +model: T.Model<T.JsonValue>, input: List<&2, T.JsonValue>, tools: List<&2, T.JsonValue>, options: OpenAIResponsesOptions<Reason, Telemetry, E>, +compat: ResolvedCompat, retention: T.CacheRetention) -> T.JsonValue:
  match model options:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, sampling, maxTokens, _, _, session, _, _, effort, summary, tier, choice}:
      fields = baseFields(id, input, compat, retention, session)
      budgeted = optionalNumber(fields, "max_output_tokens", outputTokens(maxOutputSupport(compat), maxTokens))
      configured = optionalNullableString(optionalNumber(budgeted, "temperature", temperature), "service_tier", tierValue(tier))
      toolFields = optionalValue(addTools(configured, tools), "tool_choice", choice)
      T.JsonObject{samplingFields(addReasoning(toolFields, model, effort, summary), sampling)}

# Codex wire object: instructions instead of an input system message, low
# verbosity text, encrypted reasoning always included, parallel tool calls,
# an explicit tool choice, and no output-token budget or cache retention.
def codexParams(-Reason: Data, -Telemetry: Data, -E: Data, +model: T.Model<T.JsonValue>, input: List<&2, T.JsonValue>, tools: List<&2, T.JsonValue>, options: OpenAIResponsesOptions<Reason, Telemetry, E>, retention: T.CacheRetention, instructions: String) -> T.JsonValue:
  match model options:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, sampling, _, _, _, session, _, _, effort, summary, tier, choice}:
      fields = {R.Record{R.Property{"model", T.JsonString{id}} <> R.Property{"store", T.JsonBoolean{False{}}} <> R.Property{"stream", T.JsonBoolean{True{}}} <> R.Property{"instructions", T.JsonString{instructions}} <> R.Property{"input", T.JsonArray{input}} <> R.Property{"text", T.JsonObject{R.Record{R.Property{"verbosity", T.JsonString{"low"}} <> Nil{}}}} <> R.Property{"include", T.JsonArray{T.JsonString{"reasoning.encrypted_content"} <> Nil{}}} <> Nil{}} : R.Record<T.JsonValue>}
      keyed = optionalString(fields, "prompt_cache_key", promptCacheKey(retention, session))
      chosen = R.set(T.JsonValue, R.set(T.JsonValue, keyed, "tool_choice", Maybe.default(&2, T.JsonValue, choice, T.JsonString{"auto"})), "parallel_tool_calls", T.JsonBoolean{True{}})
      configured = optionalNullableString(optionalNumber(chosen, "temperature", temperature), "service_tier", tierValue(tier))
      T.JsonObject{samplingFields(addReasoning(addTools(configured, tools), model, effort, summary), sampling)}

def endpointParams(-Reason: Data, -Telemetry: Data, -E: Data, endpoint: Endpoint, instructions: Maybe<&2, String>, model: T.Model<T.JsonValue>, input: List<&2, T.JsonValue>, tools: List<&2, T.JsonValue>, options: OpenAIResponsesOptions<Reason, Telemetry, E>, compat: ResolvedCompat, retention: T.CacheRetention) -> T.JsonValue:
  match endpoint instructions:
    case ResponsesEndpoint{} _: assembledParams(Reason, Telemetry, E, model, input, tools, options, compat, retention)
    case CodexEndpoint{} text: codexParams(Reason, Telemetry, E, model, input, tools, options, retention, Maybe.default(&2, String, text, "You are a helpful assistant."))

def nonemptyInstructions(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case value: Some{value}

def systemText(message: Maybe<&2, T.SystemMessage<V.Value>>) -> Maybe<&2, String>:
  match message:
    case None{}: None{}
    case Some{value}: nonemptyInstructions(Text.renderComplete(V.Value, value))

# The leading system message becomes Codex `instructions`; empty text falls
# back to the upstream default.
def instructions(-G: Data, -D: Data, endpoint: Endpoint, context: Context(G, D)) -> Maybe<&2, String>:
  match endpoint context:
    case ResponsesEndpoint{} _: None{}
    case CodexEndpoint{} T.TranscriptContext{messages}: systemText(Transcript.getInitialSystemMessage(V.Value, V.Value, G, D, messages))

def defaultToolStrict(endpoint: Endpoint) -> Maybe<&2,T.Nullable<Bool>>:
  match endpoint:
    case ResponsesEndpoint{}: None{}
    case CodexEndpoint{}: Some{T.NullValue{}}

def toolOptions(compat: ResolvedCompat, endpoint: Endpoint) -> Shared.ConvertResponsesToolsOptions:
  match compat:
    case ResolvedCompat{_, _, _, _, strict, grammar, _, _, _, _}: Shared.ConvertResponsesToolsOptions{defaultToolStrict(endpoint), Some{strict}, Some{grammar}, None{}}

# The Codex backend carries the system prompt as `instructions`, not as input.
def includeSystemPrompt(endpoint: Endpoint) -> Maybe<&2, Bool>:
  match endpoint:
    case ResponsesEndpoint{}: None{}
    case CodexEndpoint{}: Some{False{}}

def messageOptions(+compat: ResolvedCompat, grammar: R.Record<String>, +endpoint: Endpoint) -> Shared.ConvertResponsesMessagesOptions:
  match compat:
    case ResolvedCompat{_, midConvo, _, _, strict, grammarSupport, additional, search, _, _}:
      Shared.ConvertResponsesMessagesOptions{includeSystemPrompt(endpoint), Some{grammar}, Some{midConvo}, Some{additional}, Some{search}, Some{Shared.ConvertResponsesToolsOptions{defaultToolStrict(endpoint), Some{strict}, Some{grammarSupport}, None{}}}}

def requestTools(-G: Data, -D: Data, context: Context(G, D), compat: ResolvedCompat) -> Transcript.TranscriptTools<V.Value>:
  match context compat:
    case T.TranscriptContext{messages} ResolvedCompat{_, _, _, _, _, _, additional, search, _, _}: Transcript.resolveTranscriptTools(V.Value, V.Value, G, D, messages, additional || search)

def convertedTools(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, items: List<&2, Shared.ResponseInputItem>, options: OpenAIResponsesOptions<Reason, Telemetry, E>, compat: ResolvedCompat, retention: T.CacheRetention, endpoint: Endpoint, instructions: Maybe<&2, String>, tools: Result<&2, &2, Sampling.Error, List<&2, Shared.OpenAITool>>) -> Result<&2, &2, BuildError, T.JsonValue>:
  match tools:
    case Fail{error}: Fail{ToolConversion{error}}
    case Done{converted}: Done{endpointParams(Reason, Telemetry, E, endpoint, instructions, model, inputJson(items), toolsJson(converted), options, compat, retention)}

def convertedParams(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, input: Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>, tools: Transcript.TranscriptTools<V.Value>, options: OpenAIResponsesOptions<Reason, Telemetry, E>, +compat: ResolvedCompat, retention: T.CacheRetention, +endpoint: Endpoint, instructions: Maybe<&2, String>) -> Result<&2, &2, BuildError, T.JsonValue>:
  match input tools:
    case Fail{error} _: Fail{MessageConversion{error}}
    case Done{items} Transcript.TranscriptTools{values, _}: convertedTools(Reason, Telemetry, E, model, items, options, compat, retention, endpoint, instructions, Shared.convertResponsesTools(values, Some{toolOptions(compat, endpoint)}))

def buildParams(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, +model: T.Model<T.JsonValue>, +context: Context(G, D), options: OpenAIResponsesOptions<Reason, Telemetry, E>, +compat: ResolvedCompat, grammar: R.Record<String>, retention: T.CacheRetention, +endpoint: Endpoint) -> IO(Result<&2, &2, BuildError, T.JsonValue>):
  do IO<Result<&2, &2, BuildError, T.JsonValue>>:
    input : Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>> <- Shared.convertResponsesMessagesWith(~V.Value, ~V.Value, ~G, ~D, ~T.JsonValue, ~Shared.parameterValue, ~Shared.parameterValue, ~Shared.conversionClock, model, context, OPENAI_TOOL_CALL_PROVIDERS(), Some{messageOptions(compat, grammar, endpoint)})
    return convertedParams(Reason, Telemetry, E, model, input, requestTools(G, D, context, compat), options, compat, retention, endpoint, instructions(G, D, endpoint, context))

# Preparation
# -----------

type PreparationError is Data:
  UnsupportedApi{api: T.ModelApi}
  MissingApiKey{provider: String}
  MissingAccountId{}
  GrammarFailure{cause: Sampling.Error}
  PayloadFailure{cause: BuildError}
  InvalidAzureBaseUrl{baseUrl: String}
  MissingAzureBaseUrl{}

# Everything `stream` computes before touching the network. No socket,
# callback or task is acquired by preparation.
type Prepared is Data:
  Prepared{apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), payload: T.JsonValue, compat: ResolvedCompat, grammarToolInputProperties: R.Record<String>, cacheRetention: T.CacheRetention, endpoint: Endpoint, accountId: Maybe<&2, String>, sessionId: Maybe<&2, String>}

# What the shared request lifecycle needs from a provider's preparation. The
# wire target selects URL, authentication and fixed headers.
type Target is Data:
  SDKTarget{}
  CodexTarget{accountId: String, sessionId: Maybe<&2, String>}
  AzureTarget{apiVersion: String}

type ProviderRequest is Data:
  ProviderRequest{apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), payload: T.JsonValue, target: Target, streamOptions: Stream.OpenAIResponsesStreamOptions}

def wireTarget(endpoint: Endpoint, accountId: Maybe<&2, String>, sessionId: Maybe<&2, String>) -> Target:
  match endpoint:
    case ResponsesEndpoint{}: SDKTarget{}
    case CodexEndpoint{}: CodexTarget{Maybe.default(&2, String, accountId, ""), sessionId}

def requestedTier(tier: Maybe<&2, T.Nullable<ServiceTier>>) -> Maybe<&2, String>:
  match tier:
    case Some{T.PresentValue{selected}}: Some{tierName(selected)}
    case _: None{}

def providerRequest(prepared: Prepared, tier: Maybe<&2, T.Nullable<ServiceTier>>) -> ProviderRequest:
  match prepared:
    case Prepared{apiKey, baseUrl, headers, payload, _, grammar, _, endpoint, accountId, sessionId}:
      ProviderRequest{apiKey, baseUrl, headers, payload, wireTarget(endpoint, accountId, sessionId), Stream.OpenAIResponsesStreamOptions{requestedTier(tier), grammar}}

type ModelSettings is Data:
  ModelSettings{provider: String, baseUrl: String, headers: Maybe<&2, R.Record<String>>, compat: ResolvedCompat, endpoint: Endpoint}

# Codex assumes strict-mode support unless the model explicitly disables it.
def getCodexCompat(provider: String, baseUrl: String, compat: Maybe<&2,T.OpenAIResponsesCompat>) -> ResolvedCompat:
  match compat:
    case None{}: getCompat(provider,baseUrl,Some{T.OpenAIResponsesCompat{None{},None{},None{},None{},Some{True{}},None{},None{},None{},None{},None{}}})
    case Some{T.OpenAIResponsesCompat{developer,midConvo,affinity,longCache,strict,grammar,additional,search,explicitCache,maxOutput}}:
      getCompat(provider,baseUrl,Some{T.OpenAIResponsesCompat{developer,midConvo,affinity,longCache,Some{boolDefault(strict,True{})},grammar,additional,search,explicitCache,maxOutput}})

def compatible(api: T.ModelApi, +provider: String, +baseUrl: String, headers: Maybe<&2, R.Record<String>>, compat: Maybe<&2, T.ModelCompatibility(api)>) -> Result<&2, &2, PreparationError, ModelSettings>:
  match api:
    case T.OpenAIResponsesApi{}: Done{ModelSettings{provider, baseUrl, headers, getCompat(provider, baseUrl, compat), ResponsesEndpoint{}}}
    case T.OpenAICodexResponsesApi{}: Done{ModelSettings{provider, baseUrl, headers, getCodexCompat(provider, baseUrl, compat), CodexEndpoint{}}}
    case other: Fail{UnsupportedApi{other}}

def modelSettings(model: T.Model<T.JsonValue>) -> Result<&2, &2, PreparationError, ModelSettings>:
  match model:
    case T.Model{_, _, api, provider, baseUrl, _, _, _, _, _, _, _, _, _, headers, compat}: compatible(api, provider, baseUrl, headers, compat)

def grammarResult(result: Result<&2, &2, Sampling.Error, R.Record<String>>) -> Result<&2, &2, PreparationError, R.Record<String>>:
  match result:
    case Fail{error}: Fail{GrammarFailure{error}}
    case Done{properties}: Done{properties}

def grammarProperties(-G: Data, -D: Data, context: Context(G, D), compat: ResolvedCompat) -> Result<&2, &2, PreparationError, R.Record<String>>:
  match context compat:
    case T.TranscriptContext{messages} ResolvedCompat{_, _, _, _, _, enabled, _, _, _, _}:
      grammarResult(Sampling.createGrammarToolInputProperties(Some{Transcript.getDeclaredTools(V.Value, V.Value, G, D, messages)}, enabled))

def credentialResult(result: Result<&2, &2, String, String>) -> Result<&2, &2, PreparationError, String>:
  match result:
    case Fail{provider}: Fail{MissingApiKey{provider}}
    case Done{apiKey}: Done{apiKey}

def credential(-Reason: Data, -Telemetry: Data, -E: Data, provider: String, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> Result<&2, &2, PreparationError, String>:
  match options:
    case OpenAIResponsesOptions{_, _, apiKey, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: credentialResult(getClientApiKey(provider, apiKey, headers))

def finishPreparation(apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), compat: ResolvedCompat, grammar: R.Record<String>, retention: T.CacheRetention, endpoint: Endpoint, accountId: Maybe<&2, String>, sessionId: Maybe<&2, String>, payload: Result<&2, &2, BuildError, T.JsonValue>) -> Result<&2, &2, PreparationError, Prepared>:
  match payload:
    case Fail{cause}: Fail{PayloadFailure{cause}}
    case Done{value}: Done{Prepared{apiKey, baseUrl, headers, value, compat, grammar, retention, endpoint, accountId, sessionId}}

def accountFound(found: Maybe<&2, String>) -> Result<&2, &2, PreparationError, Maybe<&2, String>>:
  match found:
    case None{}: Fail{MissingAccountId{}}
    case Some{id}: Done{Some{id}}

# The Codex backend reads the ChatGPT account id from the bearer token.
def codexAccount(endpoint: Endpoint, apiKey: String) -> Result<&2, &2, PreparationError, Maybe<&2, String>>:
  match endpoint:
    case ResponsesEndpoint{}: Done{None{}}
    case CodexEndpoint{}: accountFound(Jwt.chatgptAccountId(apiKey))

def finishedPreparation(apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), compat: ResolvedCompat, grammar: R.Record<String>, retention: T.CacheRetention, endpoint: Endpoint, sessionId: Maybe<&2, String>, account: Result<&2, &2, PreparationError, Maybe<&2, String>>, payload: Result<&2, &2, BuildError, T.JsonValue>) -> Result<&2, &2, PreparationError, Prepared>:
  match account:
    case Fail{cause}: Fail{cause}
    case Done{accountId}: finishPreparation(apiKey, baseUrl, headers, compat, grammar, retention, endpoint, accountId, sessionId, payload)

def optionEnv(-Reason: Data, -Telemetry: Data, -E: Data, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> Maybe<&2, T.ProviderEnv()>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: env

def optionHeaders(-Reason: Data, -Telemetry: Data, -E: Data, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> Maybe<&2, T.ProviderHeaders()>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: headers

def optionRetention(-Reason: Data, -Telemetry: Data, -E: Data, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> Maybe<&2, T.CacheRetention>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, cacheRetention, _, _, _, _, _, _, _}: cacheRetention

def optionSession(-Reason: Data, -Telemetry: Data, -E: Data, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> Maybe<&2, String>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, sessionId, _, _, _, _, _, _}: sessionId

def midConversation(compat: ResolvedCompat) -> Bool:
  match compat:
    case ResolvedCompat{_, enabled, _, _, _, _, _, _, _, _}: enabled

def affinity(compat: ResolvedCompat) -> T.SessionAffinityFormat:
  match compat:
    case ResolvedCompat{_, _, format, _, _, _, _, _, _, _}: format

def preparedWith(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>, agent: String, configuration: ModelSettings, +apiKey: String, +grammar: R.Record<String>) -> IO(Result<&2, &2, PreparationError, Prepared>):
  match configuration:
    case ModelSettings{+provider, +baseUrl, modelHeaders, +compat, +endpoint}:
      do IO<Result<&2, &2, PreparationError, Prepared>>:
        +retention : T.CacheRetention <- resolveCacheRetention(optionRetention(Reason, Telemetry, E, options), optionEnv(Reason, Telemetry, E, options))
        +resolved : Context(G, D) = Transcript.resolveTranscript(V.Value, V.Value, G, D, context, Some{midConversation(compat)})
        merged : T.ProviderHeaders() = clientHeaders(V.Value, V.Value, G, D, agent, provider, modelHeaders, resolved, affinity(compat), cacheSessionId(retention, optionSession(Reason, Telemetry, E, options)), optionHeaders(Reason, Telemetry, E, options))
        payload : Result<&2, &2, BuildError, T.JsonValue> <- buildParams(~Reason, ~Telemetry, ~E, ~G, ~D, model, resolved, options, compat, grammar, retention, endpoint)
        return finishedPreparation(apiKey, baseUrl, merged, compat, grammar, retention, endpoint, promptCacheKey(retention, optionSession(Reason, Telemetry, E, options)), codexAccount(endpoint, apiKey), payload)

def compatOf(configuration: ModelSettings) -> ResolvedCompat:
  match configuration:
    case ModelSettings{_, _, _, compat, _}: compat

def providerOf(configuration: ModelSettings) -> String:
  match configuration:
    case ModelSettings{provider, _, _, _, _}: provider

def withGrammar(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, context: Context(G, D), options: OpenAIResponsesOptions<Reason, Telemetry, E>, agent: String, configuration: ModelSettings, apiKey: String, grammar: Result<&2, &2, PreparationError, R.Record<String>>) -> IO(Result<&2, &2, PreparationError, Prepared>):
  match grammar:
    case Fail{cause}: IO.pure(Result<&2, &2, PreparationError, Prepared>, Fail{cause})
    case Done{properties}: preparedWith(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, agent, configuration, apiKey, properties)

def withCredential(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, +context: Context(G, D), options: OpenAIResponsesOptions<Reason, Telemetry, E>, agent: String, +configuration: ModelSettings, key: Result<&2, &2, PreparationError, String>) -> IO(Result<&2, &2, PreparationError, Prepared>):
  match key:
    case Fail{cause}: IO.pure(Result<&2, &2, PreparationError, Prepared>, Fail{cause})
    case Done{apiKey}: withGrammar(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, agent, configuration, apiKey, grammarProperties(G, D, Transcript.resolveTranscript(V.Value, V.Value, G, D, context, Some{midConversation(compatOf(configuration))}), compatOf(configuration)))

def preparedSettings(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>, agent: String, resolved: Result<&2, &2, PreparationError, ModelSettings>) -> IO(Result<&2, &2, PreparationError, Prepared>):
  match resolved:
    case Fail{cause}: IO.pure(Result<&2, &2, PreparationError, Prepared>, Fail{cause})
    case Done{+configuration}: withCredential(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, agent, configuration, credential(Reason, Telemetry, E, providerOf(configuration), options))

# Credential, compatibility, grammar discovery, headers and the wire payload,
# in the order the upstream `stream` performs them.
def prepare(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, +model: T.Model<T.JsonValue>, context: Context(G, D), options: OpenAIResponsesOptions<Reason, Telemetry, E>, agent: String) -> IO(Result<&2, &2, PreparationError, Prepared>):
  preparedSettings(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, agent, modelSettings(model))

# Service-tier pricing
# --------------------

def getServiceTierCostMultiplier(modelId: String, serviceTier: Maybe<&2, String>) -> Maybe<&2, F64>:
  match serviceTier:
    case Some{"flex"}: Some{F.fromBits(1071644672, 0)}
    case Some{"priority"}: Some{Bool.pick(F64, String.eq(modelId, "gpt-5.5"), F.fromBits(1074003968, 0), F.fromU32(2))}
    case _: None{}

def scaleCosts(+factor: F64, costs: T.UsageCost) -> T.UsageCost:
  match costs:
    case T.UsageCost{input, output, read, write, _}:
      +input = F.multiply(input, factor)
      +output = F.multiply(output, factor)
      +read = F.multiply(read, factor)
      +write = F.multiply(write, factor)
      T.UsageCost{input, output, read, write, F.add(F.add(F.add(input, output), read), write)}

def scaled(multiplier: Maybe<&2, F64>, usage: T.Usage) -> T.Usage:
  match multiplier usage:
    case None{} original: original
    case Some{factor} T.Usage{input, output, read, write, longWrite, reasoning, total, costs}: T.Usage{input, output, read, write, longWrite, reasoning, total, scaleCosts(factor, costs)}

# Immutable replacement for the upstream in-place cost update. A multiplier of
# one leaves the usage untouched, including its cost total.
def applyServiceTierPricing(model: T.Model<T.JsonValue>, serviceTier: Maybe<&2, String>, usage: T.Usage) -> T.Usage:
  match model:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: scaled(getServiceTierCostMultiplier(id, serviceTier), usage)

# Azure passes no service-tier pricing to processResponsesStream.
def tierPricing(model: T.Model<T.JsonValue>, serviceTier: Maybe<&2, String>, usage: T.Usage) -> T.Usage:
  match model:
    case T.Model{_, _, T.AzureOpenAIResponsesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, _}: usage
    case other: applyServiceTierPricing(other, serviceTier, usage)

# Errors
# ------

type Error<-Reason: Data, -E: Data> is Data:
  PreparationFailure{cause: PreparationError}
  HookFailure{cause: E}
  InvalidRetryOptions{cause: Retry.OptionsError}
  RequestRejected{cause: Client.RequestError}
  InitializationFailure{cause: Fetch.InitError}
  EntropyFailure{cause: Seed.SeedError}
  RequestFailure{cause: Retry.RetryFailure<Client.AttemptError<Reason>>}
  ProcessingFailure{cause: Stream.Error<ReaderError(Reason)>}
  ReleaseFailure{cause: Progress.ResponseProgressError<Client.ReadError(Reason)>}
  DisposalFailure{cause: Sse.CloseError<Reason>}
  RequestAborted{}
  MissingStopReason{api: String}
  OutputFailure{message: String}

def describeAssistant(cause: Shared.AssistantError) -> String:
  match cause:
    case Shared.InvalidReasoningSignature{why}: "Invalid reasoning signature JSON: " ++ Sse.json(why)
    case Shared.InvalidGrammarInput{why}: Sampling.errorMessage(why)
    case Shared.InvalidArguments{}: "Tool call arguments cannot be represented as JSON"

def describePayload(cause: BuildError) -> String:
  match cause:
    case MessageConversion{Shared.AssistantConversion{why}}: describeAssistant(why)
    case MessageConversion{Shared.ToolConversion{why}}: Sampling.errorMessage(why)
    case ToolConversion{why}: Sampling.errorMessage(why)

def describePreparation(cause: PreparationError) -> String:
  match cause:
    case UnsupportedApi{api}: "OpenAI Responses provider does not support API: " ++ Api.name(api)
    case MissingApiKey{provider}: "No API key for provider: " ++ provider
    case MissingAccountId{}: "Failed to extract accountId from token"
    case GrammarFailure{why}: Sampling.errorMessage(why)
    case PayloadFailure{why}: describePayload(why)
    case InvalidAzureBaseUrl{text}: "Invalid Azure OpenAI base URL: " ++ text
    case MissingAzureBaseUrl{}: "Azure OpenAI base URL is required. Set AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME, or pass azureBaseUrl, azureResourceName, or model.baseUrl."

def describeSegments(path: List<&2, Decode.Segment>) -> String:
  match path:
    case Nil{}: ""
    case Decode.Field{name} <> rest: "[" ++ StringJSON.quote(name) ++ "]" ++ describeSegments(rest)
    case Decode.Index{index} <> rest: "[" ++ Nat.show(index) ++ "]" ++ describeSegments(rest)

def describeDecode(error: Decode.Error) -> String:
  match error:
    case Decode.MissingField{path}: "$" ++ describeSegments(path) ++ ": missing field"
    case Decode.WrongType{path, expected}: "$" ++ describeSegments(path) ++ ": expected " ++ expected
    case Decode.InvalidValue{path, expected}: "$" ++ describeSegments(path) ++ ": invalid value; expected " ++ expected

def describeReader(-Reason: Data, error: ReaderError(Reason)) -> String:
  match error:
    case Stream.StreamingFailure{cause}: Sse.describeStreaming(Reason, cause)
    case Stream.ProtocolFailure{cause}: "Invalid Responses event: " ++ describeDecode(cause)

def describeProcessing(-Reason: Data, error: Stream.Error<ReaderError(Reason)>) -> String:
  match error:
    case Stream.ReadFailure{cause}: describeReader(Reason, cause)
    case Stream.EmitFailure{cause}: describeReader(Reason, cause)
    case Stream.ContentFailure{cause}: Sampling.errorMessage(cause)
    case Stream.TerminalFailure{cause}: Stream.terminalMessage(cause)

# Each upstream provider names its own stream.
def missingStopReason(api: String) -> String:
  match api:
    case "azure-openai-responses": "Azure OpenAI Responses stream ended without a stop reason"
    case "openai-codex-responses": "Codex stream ended without a stop reason"
    case _: "OpenAI Responses stream ended without a stop reason"

def describeRetryOptions(cause: Retry.OptionsError) -> String:
  match cause:
    case Retry.InvalidRetryCount{_}: "maxRetries must be a non-negative integer within the native natural-number range"
    case Retry.InvalidDelayLimit{_}: "maxRetryDelayMs must be finite and non-negative"

# The assistant message's errorMessage. Hook errors are rendered by the caller;
# every other cause keeps the diagnostic of the stage that produced it.
def describe(~Reason: Data, ~E: Data, ~render: E -> String, provider: String, error: Error<Reason, E>) -> String:
  match error:
    case PreparationFailure{cause}: describePreparation(cause)
    case HookFailure{cause}: render(cause)
    case InvalidRetryOptions{cause}: describeRetryOptions(cause)
    case RequestRejected{cause}: Client.describeRequest(cause)
    case InitializationFailure{cause}: Fetch.format(cause)
    case EntropyFailure{cause}: Client.describeEntropy(cause)
    case RequestFailure{cause}: Client.describeRetry(Reason, cause, Some{Client.prefix(provider)})
    case ProcessingFailure{cause}: describeProcessing(Reason, cause)
    case ReleaseFailure{_}: "Could not close the response body"
    case DisposalFailure{_}: "Could not close the response body"
    case RequestAborted{}: "Request was aborted"
    case MissingStopReason{api}: missingStopReason(api)
    case OutputFailure{message}: message

# Lifecycle
# ---------

type Terminal<-Reason: Data, -G: Data, -E: Data> is Data:
  Successful{reason: T.DoneReason, message: T.AssistantMessage<V.Value, G>}
  Failed{reason: T.ErrorReason, message: T.AssistantMessage<V.Value, G>, cause: Error<Reason, E>}

# A cleanup failure after a settled message never replaces its terminal cause.
type RunResult<-Reason: Data, -G: Data, -E: Data> is Data:
  RunResult{terminal: Terminal<Reason, G, E>, cleanup: Maybe<&2, Error<Reason, E>>}

def initialMessage(-G: Data, model: T.Model<T.JsonValue>, timestamp: F64) -> T.AssistantMessage<V.Value, G>:
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      +zero = F.fromU32(0)
      T.AssistantMessage{Nil{}, Api.name(api), provider, id, None{}, None{}, None{}, None{}, T.Usage{zero, zero, zero, zero, None{}, None{}, zero, T.UsageCost{zero, zero, zero, zero, zero}}, T.Pending{}, None{}, None{}, None{}, None{}, timestamp}

def terminalMessage(-Reason: Data, -G: Data, -E: Data, terminal: Terminal<Reason, G, E>) -> T.AssistantMessage<V.Value, G>:
  match terminal:
    case Successful{_, output}: output
    case Failed{_, output, _}: output

def terminalEvent(-Reason: Data, -G: Data, -E: Data, terminal: Terminal<Reason, G, E>) -> T.AssistantMessageEvent<V.Value, G>:
  match terminal:
    case Successful{reason, output}: T.StreamDone{reason, output}
    case Failed{reason, output, _}: T.StreamError{reason, output}

# All fields other than stopReason and errorMessage are preserved, including
# partial content, usage, provider metadata and the original timestamp.
def withFailure(-G: Data, output: T.AssistantMessage<V.Value, G>, aborted: Bool, detail: String) -> T.AssistantMessage<V.Value, G>:
  match output:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, Bool.pick(T.StopReason, aborted, T.Aborted{}, T.Error{}), deferred, Some{detail}, raw, endTurn, timestamp}

def outputError(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "An unknown error occurred"
    case Some{""}: "An unknown error occurred"
    case Some{text}: text

# The upstream checks after processing: cancellation first, then a missing or
# failed stop reason.
def check(-Reason: Data, -E: Data, aborted: Bool, reason: T.StopReason, api: String, detail: Maybe<&2, String>) -> Result<&2, &2, Error<Reason, E>, T.DoneReason>:
  match aborted reason:
    case True{} _: Fail{RequestAborted{}}
    case False{} T.Pending{}: Fail{MissingStopReason{api}}
    case False{} T.Error{}: Fail{OutputFailure{outputError(detail)}}
    case False{} T.Aborted{}: Fail{OutputFailure{outputError(detail)}}
    case False{} T.Stop{}: Done{T.DoneStop{}}
    case False{} T.Length{}: Done{T.DoneLength{}}
    case False{} T.ToolUse{}: Done{T.DoneToolUse{}}
    case False{} T.Deferred{}: Done{T.DoneDeferred{}}

def validate(-Reason: Data, -G: Data, -E: Data, output: T.AssistantMessage<V.Value, G>, aborted: Bool) -> Result<&2, &2, Error<Reason, E>, T.DoneReason>:
  match output:
    case T.AssistantMessage{_, api, _, _, _, _, _, _, _, reason, _, detail, _, _, _}: check(Reason, E, aborted, reason, api, detail)

def failed(~Reason: Data, ~E: Data, ~render: E -> String, -G: Data, provider: String, output: T.AssistantMessage<V.Value, G>, +aborted: Bool, +cause: Error<Reason, E>) -> Terminal<Reason, G, E>:
  Failed{Bool.pick(T.ErrorReason, aborted, T.ErrorAborted{}, T.ErrorError{}), withFailure(G, output, aborted, describe(~Reason, ~E, ~render, provider, cause)), cause}

def selectedTerminal(~Reason: Data, ~E: Data, ~render: E -> String, -G: Data, provider: String, +output: T.AssistantMessage<V.Value, G>, +aborted: Bool, result: Result<&2, &2, Error<Reason, E>, T.DoneReason>) -> Terminal<Reason, G, E>:
  match result:
    case Done{reason}: Successful{reason, output}
    case Fail{cause}: failed(~Reason, ~E, ~render, G, provider, output, aborted, cause)

# An existing failure keeps its cause even if the signal was also aborted;
# cancellation becomes the cause only after otherwise successful work.
def complete(~Reason: Data, ~E: Data, ~render: E -> String, -G: Data, provider: String, +output: T.AssistantMessage<V.Value, G>, +aborted: Bool, failure: Maybe<&2, Error<Reason, E>>) -> Terminal<Reason, G, E>:
  match failure:
    case Some{cause}: failed(~Reason, ~E, ~render, G, provider, output, aborted, cause)
    case None{}: selectedTerminal(~Reason, ~E, ~render, G, provider, output, aborted, validate(Reason, G, E, output, aborted))

# Configuration
# -------------

# Native runtime settings that upstream obtains from the host platform.
# TLS authorizer callbacks in security are borrowed for the entire run.
type Config is Data:
  Config{url: URL.Context, defaults: Client.Defaults, files: Fetch.Files, transport: HTTP.Options, security: HTTP.Security, diagnosticLimit: Nat, synthesize: Bool}

def userAgent(config: Config) -> String:
  match config:
    case Config{_, Client.Defaults{name, _, _, _}, _, _, _, _, _}: name

# Transport
# ---------

# The caller's fetch is borrowed; a native transport is owned per request and
# retired after the response body has been disposed.
type Transport<-Reason: Data> is Type:
  Native{runtime: Fetch.Runtime, fetch: Fetch.Fetch(Reason)}
  Custom{fetch: Fetch.Fetch(Reason)}

def transportFetch(-Reason: Data, transport: Transport<Reason>) -> Transport<Reason> & Fetch.Fetch(Reason):
  match transport:
    case Native{runtime, +fetch}: (Native{runtime, fetch}, fetch)
    case Custom{+fetch}: (Custom{fetch}, fetch)

def retireTransport(-Reason: Data, transport: Transport<Reason>) -> IO(Unit):
  match transport:
    case Custom{_}: IO.pure(Unit, Unit{})
    case Native{runtime, fetch}:
      do IO<Unit>:
        Fetch.retire(Reason, fetch)
        Fetch.dispose(runtime)

def nativePair(-Reason: Data, pair: Fetch.Runtime & Fetch.Fetch(Reason)) -> Transport<Reason>:
  match pair:
    case (runtime, fetch): Native{runtime, fetch}

def nativeTransport(~Reason: Data, -E: Data, security: HTTP.Security, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Result<&2, &1, Error<Reason, E>, Transport<Reason>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &1, Error<Reason, E>, Transport<Reason>>, Fail{InitializationFailure{cause}})
    case Done{runtime}:
      do IO<Result<&2, &1, Error<Reason, E>, Transport<Reason>>>:
        pair : Fetch.Runtime & Fetch.Fetch(Reason) <- Fetch.callbackWithSecurity(~Reason, runtime, security)
        return Done{nativePair(Reason, pair)}

def openTransport(~Reason: Data, ~E: Data, config: Config, custom: Maybe<&2, Fetch.Fetch(Reason)>) -> IO(Result<&2, &1, Error<Reason, E>, Transport<Reason>>):
  match config custom:
    case _ Some{fetch}: IO.pure(Result<&2, &1, Error<Reason, E>, Transport<Reason>>, Done{Custom{fetch}})
    case Config{_, _, files, transport, security, _, _} None{}:
      do IO<Result<&2, &1, Error<Reason, E>, Transport<Reason>>>:
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(files, transport)
        nativeTransport(~Reason, E, security, runtime)

# Acquisition
# -----------

type AttemptEnvironment<-Reason: Data> is Data:
  AttemptEnvironment{request: Client.Request, parent: Signal(Reason), fetch: Fetch.Fetch(Reason), diagnosticLimit: Nat}

def attemptBody(~Reason: Data, environment: AttemptEnvironment<Reason>, unused: Unit) -> IO(Client.Outcome(Reason)):
  match environment:
    case AttemptEnvironment{request, parent, fetch, limit}: Client.attempt(~Reason, request, parent, fetch, limit)

def Acquired(-Reason: Data, -E: Data) -> Type: Result<&2, &1, Error<Reason, E>, Response.Response<Client.State(Reason)>>

def retried(-Reason: Data, -E: Data, result: Result<&2, &1, Retry.RetryFailure<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>>) -> Acquired(Reason, E):
  match result:
    case Fail{cause}: Fail{RequestFailure{cause}}
    case Done{response}: Done{response}

# retryProviderRequest around one attempt callback. The retry effects, their
# entropy and the date parser live only for this loop.
def attemptWithEffects(~Reason: Data, ~E: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, pair: Retry.Runtime<Reason> & Retry.Effects<Reason>) -> IO(Acquired(Reason, E)):
  match pair:
    case (owner, effects):
      do IO<Acquired(Reason, E)>:
        +request : C.Callback<Unit, Client.Outcome(Reason)> <- C.create(~AttemptEnvironment<Reason>, ~Unit, ~(Client.Outcome(Reason)), ~(attemptBody(~Reason)), environment)
        result : Result<&2, &1, Retry.RetryFailure<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>> <- Retry.retryProviderRequestOwned(Reason, Client.AttemptError<Reason>, Response.Response<Client.State(Reason)>, request, effects, retry)
        C.dispose(Unit, Client.Outcome(Reason), request)
        Retry.dispose(Reason, owner)
        C.dispose(String, F64, date)
        return retried(Reason, E, result)

# retryProviderRequest around one attempt callback. The retry effects, their
# entropy and the date parser live only for this loop.
def attempted(~Reason: Data, ~E: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, seeded: Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>>) -> IO(Acquired(Reason, E)):
  match seeded:
    case Fail{cause}:
      do IO<Acquired(Reason, E)>:
        C.dispose(String, F64, date)
        return Fail{EntropyFailure{cause}}
    case Done{runtime}: attemptWithEffects(~Reason, ~E, environment, retry, date, Retry.borrow(Reason, runtime))

def acquire(~Reason: Data, ~E: Data, config: Config, fetch: Fetch.Fetch(Reason), request: Client.Request, parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>) -> IO(Acquired(Reason, E)):
  match config:
    case Config{_, _, _, _, _, limit, _}:
      do IO<Acquired(Reason, E)>:
        +date : C.Callback<String, F64> <- Retry.dateParser()
        seeded : Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>> <- Retry.new(~Reason, date)
        attempted(~Reason, ~E, AttemptEnvironment{request, parent, fetch, limit}, retry, date, seeded)

# Hooks
# -----

def payloadHook(-E: Data, +original: T.JsonValue, model: T.Model<T.JsonValue>, hook: Maybe<&2, T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, E)>) -> IO(Result<&2, &2, E, T.JsonValue>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, E, T.JsonValue>, Done{original})
    case Some{callback}:
      do IO<Result<&2, &2, E, T.JsonValue>>:
        result : Result<&2, &2, E, Maybe<&2, T.JsonValue>> <- C.call(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, E, Maybe<&2, T.JsonValue>>, callback, T.PayloadInput{original, model})
        return Result.map(&2, &2, E, Maybe<&2, T.JsonValue>, T.JsonValue, replacement => Maybe.default(&2, T.JsonValue, replacement, original), result)

def providerResponse(+metadata: Metadata.Metadata) -> T.ProviderResponse:
  T.ProviderResponse{F.fromU32(Metadata.metadataStatus(metadata)), ProviderHeaders.headersToRecord(Metadata.headers(metadata))}

def responseHook(-Reason: Data, -E: Data, model: T.Model<T.JsonValue>, hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, response: Response.Response<Client.State(Reason)>) -> IO(Response.Response<Client.State(Reason)> & Result<&2, &2, E, Unit>):
  match hook response:
    case None{} value: IO.pure(Response.Response<Client.State(Reason)> & Result<&2, &2, E, Unit>, (value, Done{Unit{}}))
    case Some{callback} Response.Response{+metadata, body}:
      do IO<Response.Response<Client.State(Reason)> & Result<&2, &2, E, Unit>>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<T.Model<T.JsonValue>>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{providerResponse(metadata), model})
        return (Response.Response{metadata, body}, result)

# Session
# -------

# One producer task and one canonical event stream. Borrowed stream handles
# remain valid until disposal after consumers have finished.
type Run<-Reason: Data, -G: Data, -E: Data> is Type:
  Running{events: Events.AssistantMessageEventStream(V.Value, G), task: Chan(RunResult<Reason, G, E>)}
  Finished{events: Events.AssistantMessageEventStream(V.Value, G), result: RunResult<Reason, G, E>}

def borrow(-Reason: Data, -G: Data, -E: Data, owner: Run<Reason, G, E>) -> Run<Reason, G, E> & Events.AssistantMessageEventStream(V.Value, G):
  match owner:
    case Running{+events, task}: (Running{events, task}, events)
    case Finished{+events, result}: (Finished{events, result}, events)

def completed(-Reason: Data, -G: Data, -E: Data, events: Events.AssistantMessageEventStream(V.Value, G), +result: RunResult<Reason, G, E>) -> Run<Reason, G, E> & RunResult<Reason, G, E>:
  (Finished{events, result}, result)

# The stream's final result may settle before the producer has retired its
# resources; wait is the stronger boundary.
def wait(-Reason: Data, -G: Data, -E: Data, owner: Run<Reason, G, E>) -> IO(Run<Reason, G, E> & RunResult<Reason, G, E>):
  match owner:
    case Finished{events, result}: IO.pure(Run<Reason, G, E> & RunResult<Reason, G, E>, completed(Reason, G, E, events, result))
    case Running{events, task}:
      do IO<Run<Reason, G, E> & RunResult<Reason, G, E>>:
        result : RunResult<Reason, G, E> <- IO.join(RunResult<Reason, G, E>, task)
        return completed(Reason, G, E, events, result)

def disposeStream(-Reason: Data, -G: Data, -E: Data, events: Events.AssistantMessageEventStream(V.Value, G), result: RunResult<Reason, G, E>) -> IO(RunResult<Reason, G, E>):
  do IO<RunResult<Reason, G, E>>:
    Events.disposeAssistantMessageEventStream(V.Value, G, events)
    return result

# Call after all consumer iterators have finished. This waits for production;
# cancellation remains the supplied signal's policy.
def dispose(-Reason: Data, -G: Data, -E: Data, owner: Run<Reason, G, E>) -> IO(RunResult<Reason, G, E>):
  match owner:
    case Finished{events, result}: disposeStream(Reason, G, E, events, result)
    case Running{events, task}:
      do IO<RunResult<Reason, G, E>>:
        result : RunResult<Reason, G, E> <- IO.join(RunResult<Reason, G, E>, task)
        disposeStream(Reason, G, E, events, result)

# Producer
# --------

type SignalOwner<-Reason: Data> is Type:
  Supplied{signal: Signal(Reason)}
  Local{controller: Abort.AbortController<Reason>}

def selectSignal(-Reason: Data, value: Maybe<&2, Signal(Reason)>) -> IO(SignalOwner<Reason>):
  match value:
    case Some{signal}: IO.pure(SignalOwner<Reason>, Supplied{signal})
    case None{}:
      do IO<SignalOwner<Reason>>:
        controller : Abort.AbortController<Reason> <- Abort.new(Reason)
        return Local{controller}

def ownedSignal(-Reason: Data, owner: SignalOwner<Reason>) -> SignalOwner<Reason> & Signal(Reason):
  match owner:
    case Supplied{+value}: (Supplied{value}, value)
    case Local{+controller}: (Local{controller}, Abort.signal(Reason, controller))

def retireSignal(-Reason: Data, owner: SignalOwner<Reason>) -> IO(Unit):
  match owner:
    case Supplied{_}: IO.pure(Unit, Unit{})
    case Local{controller}: Abort.dispose(Reason, controller)

# The producer's typed outcome before the assistant message is settled.
type Outcome<-Reason: Data, -G: Data, -E: Data> is Data:
  Outcome{output: T.AssistantMessage<V.Value, G>, failure: Maybe<&2, Error<Reason, E>>, cleanup: Maybe<&2, Error<Reason, E>>}

def processed(-Reason: Data, -G: Data, -E: Data, result: Stream.RunResult<G, ReaderError(Reason)>, disposal: Result<&2, &2, Sse.CloseError<Reason>, Unit>) -> Outcome<Reason, G, E>:
  match result disposal:
    case Stream.RunResult{output, error} Done{_}: Outcome{output, Maybe.map(&2, Stream.Error<ReaderError(Reason)>, Error<Reason, E>, cause => ProcessingFailure{cause}, error), None{}}
    case Stream.RunResult{output, error} Fail{cause}: Outcome{output, Maybe.map(&2, Stream.Error<ReaderError(Reason)>, Error<Reason, E>, why => ProcessingFailure{why}, error), Some{DisposalFailure{cause}}}

# The processor's iterator state: the acquired body, its SSE cursor and the
# canonical event stream the content events are published to.
type Source<-Reason: Data, -G: Data> is Type:
  Source{body: Sse.Body(Reason), cursor: Sse.Cursor<Sse.TransportError(Reason)>, events: Events.AssistantMessageEventStream(V.Value, G)}

def SourceStep(-Reason: Data, -G: Data) -> Type: Source<Reason, G> & Result<&2, &2, ReaderError(Reason), Maybe<&2, Stream.ResponseStreamEvent>>

def advanced(-Reason: Data, -G: Data, body: Sse.Body(Reason), events: Events.AssistantMessageEventStream(V.Value, G), step: Stream.EventStep(Sse.TransportError(Reason))) -> SourceStep(Reason, G):
  match step:
    case (cursor, result): (Source{body, cursor, events}, result)

def sourceNext(~Reason: Data, ~G: Data, source: Source<Reason, G>) -> IO(SourceStep(Reason, G)):
  match source:
    case Source{body, cursor, events}:
      do IO<SourceStep(Reason, G)>:
        step : Stream.EventStep(Sse.TransportError(Reason)) <- Stream.nextEvent(Sse.TransportError(Reason), cursor)
        return advanced(Reason, G, body, events, step)

def closedSource(-Reason: Data, -G: Data, body: Sse.Body(Reason), events: Events.AssistantMessageEventStream(V.Value, G), step: Sse.Cursor<Sse.TransportError(Reason)> & Result<&2, &2, ReaderError(Reason), Unit>) -> Source<Reason, G> & Result<&2, &2, ReaderError(Reason), Unit>:
  match step:
    case (cursor, result): (Source{body, cursor, events}, result)

def sourceClose(~Reason: Data, ~G: Data, source: Source<Reason, G>) -> IO(Source<Reason, G> & Result<&2, &2, ReaderError(Reason), Unit>):
  match source:
    case Source{body, cursor, events}:
      do IO<Source<Reason, G> & Result<&2, &2, ReaderError(Reason), Unit>>:
        step : Sse.Cursor<Sse.TransportError(Reason)> & Result<&2, &2, ReaderError(Reason), Unit> <- Stream.closeEvents(Sse.TransportError(Reason), cursor)
        return closedSource(Reason, G, body, events, step)

# Publishing to the canonical stream cannot fail.
def sourceEmit(~Reason: Data, ~G: Data, source: Source<Reason, G>, event: T.AssistantMessageEvent<V.Value, G>) -> IO(Source<Reason, G> & Result<&2, &2, ReaderError(Reason), Unit>):
  match source:
    case Source{body, cursor, +events}:
      do IO<Source<Reason, G> & Result<&2, &2, ReaderError(Reason), Unit>>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, event)
        return (Source{body, cursor, events}, Done{Unit{}})

def disposedSource(-Reason: Data, -G: Data, -E: Data, pair: Source<Reason, G> & Stream.RunResult<G, ReaderError(Reason)>) -> IO(Outcome<Reason, G, E>):
  match pair:
    case (Source{body, cursor, _}, result):
      do IO<Outcome<Reason, G, E>>:
        disposal : Result<&2, &2, Sse.CloseError<Reason>, Unit> <- Sse.dispose(Reason, body, cursor)
        return processed(Reason, G, E, result, disposal)

def opened(~Reason: Data, ~G: Data, ~E: Data, model: T.Model<T.JsonValue>, options: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), pair: Sse.Body(Reason) & Sse.Cursor<Sse.TransportError(Reason)>) -> IO(Outcome<Reason, G, E>):
  match pair:
    case (body, cursor):
      do IO<Outcome<Reason, G, E>>:
        result : Source<Reason, G> & Stream.RunResult<G, ReaderError(Reason)> <- Stream.processResponsesStream(~Source<Reason, G>, ~(ReaderError(Reason)), ~T.JsonValue, ~G, ~(sourceNext(~Reason, ~G)), ~(sourceClose(~Reason, ~G)), ~(sourceEmit(~Reason, ~G)), ~Stream.resolveServiceTier, ~tierPricing, Source{body, cursor, events}, output, model, options)
        disposedSource(Reason, G, E, result)

# processResponsesStream over the acquired body, then release everything the
# body borrowed. The transport outlives the body.
def process(~Reason: Data, ~G: Data, ~E: Data, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, options: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), response: Response.Response<Client.State(Reason)>) -> IO(Outcome<Reason, G, E>):
  match config response:
    case Config{_, _, _, _, _, _, synthesize} Response.Response{_, body}:
      do IO<Outcome<Reason, G, E>>:
        pair : Sse.Body(Reason) & Sse.Cursor<Sse.TransportError(Reason)> <- Sse.fromBody(~Reason, body, hooks, synthesize)
        opened(~Reason, ~G, ~E, model, options, output, events, pair)

def released(-Reason: Data, -G: Data, -E: Data, output: T.AssistantMessage<V.Value, G>, cause: E, result: Result<&2, &2, Progress.ResponseProgressError<Client.ReadError(Reason)>, Unit>) -> Outcome<Reason, G, E>:
  match result:
    case Done{_}: Outcome{output, Some{HookFailure{cause}}, None{}}
    case Fail{why}: Outcome{output, Some{HookFailure{cause}}, Some{ReleaseFailure{why}}}

# onResponse sees the status and headers before any body is read. Its failure
# releases the body; success publishes `start` and processes the events.
def observed(~Reason: Data, ~G: Data, ~E: Data, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, options: Stream.OpenAIResponsesStreamOptions, +output: T.AssistantMessage<V.Value, G>, +events: Events.AssistantMessageEventStream(V.Value, G), pair: Response.Response<Client.State(Reason)> & Result<&2, &2, E, Unit>) -> IO(Outcome<Reason, G, E>):
  match pair:
    case (response, Fail{cause}):
      do IO<Outcome<Reason, G, E>>:
        result : Result<&2, &2, Progress.ResponseProgressError<Client.ReadError(Reason)>, Unit> <- Client.release(Reason, response)
        return released(Reason, G, E, output, cause, result)
    case (response, Done{_}):
      do IO<Outcome<Reason, G, E>>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, T.Start{output})
        process(~Reason, ~G, ~E, config, hooks, model, options, output, events, response)

def acquired(~Reason: Data, ~G: Data, ~E: Data, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, options: Stream.OpenAIResponsesStreamOptions, hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), result: Acquired(Reason, E)) -> IO(Outcome<Reason, G, E>):
  match result:
    case Fail{cause}: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{cause}, None{}})
    case Done{response}:
      do IO<Outcome<Reason, G, E>>:
        pair : Response.Response<Client.State(Reason)> & Result<&2, &2, E, Unit> <- responseHook(Reason, E, model, hook, response)
        observed(~Reason, ~G, ~E, config, hooks, model, options, output, events, pair)

def attemptThrough(~Reason: Data, ~G: Data, ~E: Data, +config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, options: Stream.OpenAIResponsesStreamOptions, hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), request: Client.Request, parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>, pair: Transport<Reason> & Fetch.Fetch(Reason)) -> IO(Outcome<Reason, G, E>):
  match pair:
    case (owner, fetch):
      do IO<Outcome<Reason, G, E>>:
        response : Acquired(Reason, E) <- acquire(~Reason, ~E, config, fetch, request, parent, retry)
        outcome : Outcome<Reason, G, E> <- acquired(~Reason, ~G, ~E, config, hooks, model, options, hook, output, events, response)
        retireTransport(Reason, owner)
        return outcome

def transported(~Reason: Data, ~G: Data, ~E: Data, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, options: Stream.OpenAIResponsesStreamOptions, hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), request: Client.Request, parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>, opened: Result<&2, &1, Error<Reason, E>, Transport<Reason>>) -> IO(Outcome<Reason, G, E>):
  match opened:
    case Fail{cause}: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{cause}, None{}})
    case Done{transport}: attemptThrough(~Reason, ~G, ~E, config, hooks, model, options, hook, output, events, request, parent, retry, transportFetch(Reason, transport))

# Like the SDK, observe cancellation after building the request and before
# any transport is initialized, so a configuration error never masks an abort.
def requested(~Reason: Data, ~G: Data, ~E: Data, +config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, options: Stream.OpenAIResponsesStreamOptions, custom: Maybe<&2, Fetch.Fetch(Reason)>, hook: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), +parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>, aborted: Bool, request: Result<&2, &2, Client.RequestError, Client.Request>) -> IO(Outcome<Reason, G, E>):
  match aborted request:
    case True{} _: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{RequestFailure{Retry.RequestAborted{}}}, None{}})
    case False{} Fail{cause}: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{RequestRejected{cause}}, None{}})
    case False{} Done{wire}:
      do IO<Outcome<Reason, G, E>>:
        opened : Result<&2, &1, Error<Reason, E>, Transport<Reason>> <- openTransport(~Reason, ~E, config, custom)
        transported(~Reason, ~G, ~E, config, hooks, model, options, hook, output, events, wire, parent, retry, opened)

def envelope(config: Config, request: ProviderRequest, timeout: Maybe<&2, F64>, payload: T.JsonValue) -> Result<&2, &2, Client.RequestError, Client.Request>:
  match config request:
    case Config{url, defaults, _, _, _, _, _} ProviderRequest{apiKey, baseUrl, headers, _, SDKTarget{}, _}: Client.prepareRequest(url, defaults, apiKey, headers, baseUrl, timeout, payload)
    case Config{url, defaults, _, _, _, _, _} ProviderRequest{apiKey, baseUrl, headers, _, CodexTarget{accountId, sessionId}, _}: Client.prepareCodexRequest(url, defaults, apiKey, accountId, headers, sessionId, baseUrl, timeout, payload)
    case Config{url, defaults, _, _, _, _, _} ProviderRequest{apiKey, baseUrl, headers, _, AzureTarget{apiVersion}, _}: Client.prepareAzureRequest(url, defaults, apiKey, apiVersion, headers, baseUrl, timeout, payload)

def processingOptions(request: ProviderRequest) -> Stream.OpenAIResponsesStreamOptions:
  match request:
    case ProviderRequest{_, _, _, _, _, options}: options

def selectedPayload(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, +config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, +options: StreamOptions(Reason, Telemetry, E), output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), +parent: Signal(Reason), +request: ProviderRequest, retry: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>, payload: Result<&2, &2, E, T.JsonValue>) -> IO(Outcome<Reason, G, E>):
  match options retry payload:
    case _ _ Fail{cause}: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{HookFailure{cause}}, None{}})
    case _ Fail{cause} _: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{InvalidRetryOptions{cause}}, None{}})
    case T.StreamOptions{_, _, _, custom, _, _, hook, _, timeout, _, _, _, _, _, _, _, _, _, _} Done{resolvedRetry} Done{chosen}:
      do IO<Outcome<Reason, G, E>>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        requested(~Reason, ~G, ~E, config, hooks, model, processingOptions(request), custom, hook, output, events, parent, resolvedRetry, aborted, envelope(config, request, timeout, chosen))

def retryOptions(-Reason: Data, -Telemetry: Data, -E: Data, +parent: Signal(Reason), options: StreamOptions(Reason, Telemetry, E)) -> Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>:
  match options:
    case T.StreamOptions{_, _, _, _, _, _, _, _, _, retries, limit, _, _, _, _, _, _, _, _}: Retry.resolve(Reason, retries, limit, Some{parent})

def preparedRequest(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, +options: StreamOptions(Reason, Telemetry, E), output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), +parent: Signal(Reason), result: Result<&2, &2, PreparationError, ProviderRequest>) -> IO(Outcome<Reason, G, E>):
  match options result:
    case _ Fail{cause}: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{PreparationFailure{cause}}, None{}})
    case T.StreamOptions{_, _, _, _, _, hook, _, _, _, _, _, _, _, _, _, _, _, _, _} Done{ProviderRequest{apiKey, baseUrl, headers, +payload, target, processing}}:
      do IO<Outcome<Reason, G, E>>:
        chosen : Result<&2, &2, E, T.JsonValue> <- payloadHook(E, payload, model, hook)
        selectedPayload(~Reason, ~Telemetry, ~G, ~E, config, hooks, model, options, output, events, parent, ProviderRequest{apiKey, baseUrl, headers, payload, target, processing}, retryOptions(Reason, Telemetry, E, parent, options), chosen)

def settled(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, +events: Events.AssistantMessageEventStream(V.Value, G), provider: String, owner: SignalOwner<Reason>, finalizer: IO(Unit), aborted: Bool, outcome: Outcome<Reason, G, E>) -> IO(RunResult<Reason, G, E>):
  match outcome:
    case Outcome{output, failure, cleanup}:
      +terminal = complete(~Reason, ~E, ~render, G, provider, output, aborted, failure)
      do IO<RunResult<Reason, G, E>>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, terminalEvent(Reason, G, E, terminal))
        Events.end(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, Some{terminalMessage(Reason, G, E, terminal)})
        retireSignal(Reason, owner)
        finalizer
        return RunResult{terminal, cleanup}

# The provider named by API error prefixes; AzureOpenAI's is fixed.
def errorProvider(model: T.Model<T.JsonValue>) -> String:
  match model:
    case T.Model{_, _, T.AzureOpenAIResponsesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, _}: "Azure OpenAI"
    case T.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: provider

def produceWith(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, ~render: E -> String, +config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, options: StreamOptions(Reason, Telemetry, E), +events: Events.AssistantMessageEventStream(V.Value, G), timestamp: F64, finalizer: IO(Unit), preparation: IO(Result<&2, &2, PreparationError, ProviderRequest>), pair: SignalOwner<Reason> & Signal(Reason)) -> IO(RunResult<Reason, G, E>):
  match pair:
    case (owner, +parent):
      do IO<RunResult<Reason, G, E>>:
        ready : Result<&2, &2, PreparationError, ProviderRequest> <- preparation
        outcome : Outcome<Reason, G, E> <- preparedRequest(~Reason, ~Telemetry, ~G, ~E, config, hooks, model, options, initialMessage(G, model, timestamp), events, parent, ready)
        aborted : Bool <- Abort.aborted(Reason, parent)
        settled(~Reason, ~G, ~E, ~render, events, errorProvider(model), owner, finalizer, aborted, outcome)

# The body of upstream `stream`'s async task: try everything, then settle the
# message, publish `done`/`error` and end the canonical stream.
def produce(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, ~render: E -> String, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, options: StreamOptions(Reason, Telemetry, E), events: Events.AssistantMessageEventStream(V.Value, G), signal: SignalOwner<Reason>, timestamp: F64, finalizer: IO(Unit), preparation: IO(Result<&2, &2, PreparationError, ProviderRequest>)) -> IO(RunResult<Reason, G, E>):
  produceWith(~Reason, ~Telemetry, ~G, ~E, ~render, config, hooks, model, options, events, timestamp, finalizer, preparation, ownedSignal(Reason, signal))

# Shared request lifecycle
# ------------------------

# Start a Responses request from its preparation, which runs in the producer
# task, with an explicit timestamp, SSE hooks and a finalizer that runs after
# the producer has retired everything it owns. Returns the run owner
# immediately; borrow its event stream, then wait or dispose.
def startRequest(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, ~render: E -> String, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, +options: StreamOptions(Reason, Telemetry, E), preparation: IO(Result<&2, &2, PreparationError, ProviderRequest>), timestamp: F64, finalizer: IO(Unit)) -> IO(Run<Reason, G, E>):
  match options:
    case T.StreamOptions{requestedSignal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      do IO<Run<Reason, G, E>>:
        signal : SignalOwner<Reason> <- selectSignal(Reason, requestedSignal)
        +events : Events.AssistantMessageEventStream(V.Value, G) <- Events.createAssistantMessageEventStream(~V.Value, ~G)
        task : Chan(RunResult<Reason, G, E>) <- IO.fork(RunResult<Reason, G, E>, produce(~Reason, ~Telemetry, ~G, ~E, ~render, config, hooks, model, options, events, signal, timestamp, finalizer, preparation))
        return Running{events, task}

# startRequest at the current time with the default SSE hooks.
def start(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, ~render: E -> String, config: Config, model: T.Model<T.JsonValue>, options: StreamOptions(Reason, Telemetry, E), preparation: IO(Result<&2, &2, PreparationError, ProviderRequest>)) -> IO(Run<Reason, G, E>):
  do IO<Run<Reason, G, E>>:
    timestamp : F64 <- Date.now()
    +hooks : Sse.Hooks<Sse.TransportError(Reason)> <- Sse.defaultHooks(~(Sse.TransportError(Reason)))
    startRequest(~Reason, ~Telemetry, ~G, ~E, ~render, config, hooks, model, options, preparation, timestamp, Sse.disposeHooks(Sse.TransportError(Reason), hooks))

# Public entry points
# -------------------

def optionTier(-Reason: Data, -Telemetry: Data, -E: Data, options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> Maybe<&2, T.Nullable<ServiceTier>>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, tier, _}: tier

def requestFrom(tier: Maybe<&2, T.Nullable<ServiceTier>>, result: Result<&2, &2, PreparationError, Prepared>) -> Result<&2, &2, PreparationError, ProviderRequest>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{prepared}: Done{providerRequest(prepared, tier)}

def responsesPreparation(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, config: Config, model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(Result<&2, &2, PreparationError, ProviderRequest>):
  do IO<Result<&2, &2, PreparationError, ProviderRequest>>:
    result : Result<&2, &2, PreparationError, Prepared> <- prepare(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, userAgent(config))
    return requestFrom(optionTier(Reason, Telemetry, E, options), result)

# The OpenAI Responses request with an explicit timestamp, SSE hooks and
# finalizer (see startRequest).
def streamAt(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, +config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>, timestamp: F64, finalizer: IO(Unit)) -> IO(Run<Reason, G, E>):
  startRequest(~Reason, ~Telemetry, ~G, ~E, ~render, config, hooks, model, toStreamOptions(Reason, Telemetry, E, options), responsesPreparation(~Reason, ~Telemetry, ~G, ~D, ~E, config, model, context, options), timestamp, finalizer)

# Generate function for the OpenAI Responses API.
def stream(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, +config: Config, +model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(Run<Reason, G, E>):
  start(~Reason, ~Telemetry, ~G, ~E, ~render, config, model, toStreamOptions(Reason, Telemetry, E, options), responsesPreparation(~Reason, ~Telemetry, ~G, ~D, ~E, config, model, context, options))

def choiceValue(value: Maybe<&2, T.ToolChoice>) -> Maybe<&2, T.JsonValue>:
  match value:
    case None{}: None{}
    case Some{T.AutoTool{}}: Some{T.JsonString{"auto"}}
    case Some{T.NoTool{}}: Some{T.JsonString{"none"}}

def clampedLevel(level: T.ModelThinkingLevel) -> Maybe<&2, T.ThinkingLevel>:
  match level:
    case T.Off{}: None{}
    case T.Thinking{clamped}: Some{clamped}

def clampedEffort(model: T.Model<T.JsonValue>, reasoning: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, T.ThinkingLevel>:
  match reasoning:
    case None{}: None{}
    case Some{level}: clampedLevel(Models.clampThinkingLevel(T.JsonValue, model, T.Thinking{level}))

def simpleSettings(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, options: Maybe<&2, SimpleStreamOptions(Reason, Telemetry, E)>) -> ResponsesSettings:
  match options:
    case None{}: ResponsesSettings{None{}, None{}, None{}, None{}}
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, toolChoice, reasoning, _, _}}: ResponsesSettings{clampedEffort(model, reasoning), None{}, None{}, choiceValue(toolChoice)}

def simpleApiKey(-Reason: Data, -Telemetry: Data, -E: Data, options: Maybe<&2, SimpleStreamOptions(Reason, Telemetry, E)>) -> Maybe<&2, String>:
  match options:
    case None{}: None{}
    case Some{options}: T.apiKeyOption(T.JsonValue, Signal(Reason), Telemetry, Fetch.Fetch(Reason), E, options)

# streamSimple: base options with the model's defaults and context budget,
# tool choice, and the reasoning level clamped to the model's support.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Config, +model: T.Model<T.JsonValue>, +context: Context(G, D), +options: Maybe<&2, SimpleStreamOptions(Reason, Telemetry, E)>) -> IO(Run<Reason, G, E>):
  stream(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, model, context, fromStreamOptions(Reason, Telemetry, E, Simple.buildBaseOptionsWith(~V.Value, ~V.Value, ~G, ~D, ~T.JsonValue, ~(Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, ~Convert.toJson, ~Convert.toJson, model, context, options, simpleApiKey(Reason, Telemetry, E, options)), simpleSettings(Reason, Telemetry, E, model, options)))

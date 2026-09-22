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
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/u64.bend as Word
import ../../../runtime/src/http-message.bend as Header

# The OpenAI Responses provider (pi `openai-responses.ts`). `stream` prepares
# the request, runs it through the native client with pi's retry policy, folds
# the SSE response into the canonical assistant event stream and settles the
# final message. Message/tool conversion and response processing are shared
# with the other Responses providers through the two shared modules.

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
  OpenAIResponsesOptions{signal: Maybe<&2, Signal(Reason)>, telemetryContext: Maybe<&2, Telemetry>, apiKey: Maybe<&2, String>, fetch: Maybe<&2, Fetch.Fetch(Reason)>, env: Maybe<&2, T.ProviderEnv()>, onPayload: Maybe<&2, T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<T.JsonValue>, E)>, headers: Maybe<&2, T.ProviderHeaders()>, timeoutMs: Maybe<&2, F.F64>, maxRetries: Maybe<&2, F.F64>, maxRetryDelayMs: Maybe<&2, F.F64>, temperature: Maybe<&2, F.F64>, samplingParams: Maybe<&2, R.Record<T.JsonValue>>, maxTokens: Maybe<&2, F.F64>, transport: Maybe<&2, T.Transport>, cacheRetention: Maybe<&2, T.CacheRetention>, sessionId: Maybe<&2, String>, websocketConnectTimeoutMs: Maybe<&2, F.F64>, metadata: Maybe<&2, R.Record<T.JsonValue>>, reasoningEffort: Maybe<&2, T.ThinkingLevel>, reasoningSummary: Maybe<&2, T.Nullable<ReasoningSummary>>, serviceTier: Maybe<&2, T.Nullable<ServiceTier>>, toolChoice: Maybe<&2, T.JsonValue>}

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

def nonblankHeader(value: T.Nullable<String>) -> Bool:
  match value:
    case T.NullValue{}: False{}
    case T.PresentValue{text}: Bool.not(Space.blank(text))

def matchingHeader(entries: List<&2, R.Property<T.Nullable<String>>>, +name: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case R.Property{key, value} <> rest: (String.eq(Header.lowercase(key), name) && nonblankHeader(value)) || matchingHeader(rest, name)

def hasHeader(headers: Maybe<&2, T.ProviderHeaders()>, name: String) -> Bool:
  match headers:
    case None{}: False{}
    case Some{R.Record{entries}}: matchingHeader(entries, Header.lowercase(name))

def headerCredential(provider: String, +headers: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, String, String>:
  Bool.pick(Result<&2, &2, String, String>, hasHeader(headers, "authorization") || hasHeader(headers, "cf-aig-authorization"), Done{"unused"}, Fail{provider})

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
def OPENAI_RESPONSES_MIN_OUTPUT_TOKENS() -> F.F64: F.fromU32(16)

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

def optionalNumber(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, F.F64>) -> R.Record<T.JsonValue>:
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
def outputTokens(enabled: Bool, value: Maybe<&2, F.F64>) -> Maybe<&2, F.F64>:
  match enabled value:
    case True{} Some{+scalar}: Bool.pick(Maybe<&2, F.F64>, activeNumber(F.decode(scalar)), Some{Simple.maximum(scalar, OPENAI_RESPONSES_MIN_OUTPUT_TOKENS())}, None{})
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

def offReasoning(fields: R.Record<T.JsonValue>, provider: String, mapping: Maybe<&2, T.Nullable<String>>) -> R.Record<T.JsonValue>:
  match provider mapping:
    case "github-copilot" _: fields
    case _ Some{T.NullValue{}}: fields
    case _ value: R.set(T.JsonValue, fields, "reasoning", T.JsonObject{R.Record{R.Property{"effort", T.JsonString{mappedEffort(value, "none")}} <> Nil{}}})

def configuredReasoning(requested: Bool, fields: R.Record<T.JsonValue>, provider: String, mapping: Maybe<&2, T.ThinkingLevelMap>, effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match requested:
    case False{}: offReasoning(fields, provider, Thinking.mapped(mapping, T.Off{}))
    case True{}: encryptedContent(R.set(T.JsonValue, fields, "reasoning", T.JsonObject{R.Record{R.Property{"effort", T.JsonString{requestedEffort(effort, mapping)}} <> R.Property{"summary", T.JsonString{summaryOrAuto(summary)}} <> Nil{}}}))

def xaiInclude(provider: String, fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  match provider:
    case "xai": encryptedContent(fields)
    case _: fields

def addReasoning(fields: R.Record<T.JsonValue>, model: T.Model<T.JsonValue>, +effort: Maybe<&2, T.ThinkingLevel>, summary: Maybe<&2, T.Nullable<ReasoningSummary>>) -> R.Record<T.JsonValue>:
  match model:
    case T.Model{_, _, _, _, _, False{}, _, _, _, _, _, _, _, _}: fields
    case T.Model{_, _, _, +provider, _, True{}, mapping, _, _, _, _, _, _, _}:
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
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _} OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, sampling, maxTokens, _, _, session, _, _, effort, summary, tier, choice}:
      fields = baseFields(id, input, compat, retention, session)
      budgeted = optionalNumber(fields, "max_output_tokens", outputTokens(maxOutputSupport(compat), maxTokens))
      configured = optionalNullableString(optionalNumber(budgeted, "temperature", temperature), "service_tier", tierValue(tier))
      toolFields = optionalValue(addTools(configured, tools), "tool_choice", choice)
      T.JsonObject{samplingFields(addReasoning(toolFields, model, effort, summary), sampling)}

def toolOptions(compat: ResolvedCompat) -> Shared.ConvertResponsesToolsOptions:
  match compat:
    case ResolvedCompat{_, _, _, _, strict, grammar, _, _, _, _}: Shared.ConvertResponsesToolsOptions{None{}, Some{strict}, Some{grammar}, None{}}

def messageOptions(+compat: ResolvedCompat, grammar: R.Record<String>) -> Shared.ConvertResponsesMessagesOptions:
  match compat:
    case ResolvedCompat{_, midConvo, _, _, strict, grammarSupport, additional, search, _, _}:
      Shared.ConvertResponsesMessagesOptions{None{}, Some{grammar}, Some{midConvo}, Some{additional}, Some{search}, Some{Shared.ConvertResponsesToolsOptions{None{}, Some{strict}, Some{grammarSupport}, None{}}}}

def requestTools(-G: Data, -D: Data, context: Context(G, D), compat: ResolvedCompat) -> Transcript.TranscriptTools<V.Value>:
  match context compat:
    case T.TranscriptContext{messages} ResolvedCompat{_, _, _, _, _, _, additional, search, _, _}: Transcript.resolveTranscriptTools(V.Value, V.Value, G, D, messages, additional || search)

def convertedTools(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, items: List<&2, Shared.ResponseInputItem>, options: OpenAIResponsesOptions<Reason, Telemetry, E>, compat: ResolvedCompat, retention: T.CacheRetention, tools: Result<&2, &2, Sampling.Error, List<&2, Shared.OpenAITool>>) -> Result<&2, &2, BuildError, T.JsonValue>:
  match tools:
    case Fail{error}: Fail{ToolConversion{error}}
    case Done{converted}: Done{assembledParams(Reason, Telemetry, E, model, inputJson(items), toolsJson(converted), options, compat, retention)}

def convertedParams(-Reason: Data, -Telemetry: Data, -E: Data, model: T.Model<T.JsonValue>, input: Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>, tools: Transcript.TranscriptTools<V.Value>, options: OpenAIResponsesOptions<Reason, Telemetry, E>, +compat: ResolvedCompat, retention: T.CacheRetention) -> Result<&2, &2, BuildError, T.JsonValue>:
  match input tools:
    case Fail{error} _: Fail{MessageConversion{error}}
    case Done{items} Transcript.TranscriptTools{values, _}: convertedTools(Reason, Telemetry, E, model, items, options, compat, retention, Shared.convertResponsesTools(values, Some{toolOptions(compat)}))

def buildParams(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, +model: T.Model<T.JsonValue>, +context: Context(G, D), options: OpenAIResponsesOptions<Reason, Telemetry, E>, +compat: ResolvedCompat, grammar: R.Record<String>, retention: T.CacheRetention) -> IO(Result<&2, &2, BuildError, T.JsonValue>):
  do IO<Result<&2, &2, BuildError, T.JsonValue>>:
    input : Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>> <- Shared.convertResponsesMessagesWith(~V.Value, ~V.Value, ~G, ~D, ~T.JsonValue, ~Shared.parameterValue, ~Shared.parameterValue, ~Shared.conversionClock, model, context, OPENAI_TOOL_CALL_PROVIDERS(), Some{messageOptions(compat, grammar)})
    return convertedParams(Reason, Telemetry, E, model, input, requestTools(G, D, context, compat), options, compat, retention)

# Preparation
# -----------

type PreparationError is Data:
  UnsupportedApi{api: T.ModelApi}
  MissingApiKey{provider: String}
  GrammarFailure{cause: Sampling.Error}
  PayloadFailure{cause: BuildError}

# Everything `stream` computes before touching the network. No socket,
# callback or task is acquired by preparation.
type Prepared is Data:
  Prepared{apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), payload: T.JsonValue, compat: ResolvedCompat, grammarToolInputProperties: R.Record<String>, cacheRetention: T.CacheRetention}

type ModelSettings is Data:
  ModelSettings{provider: String, baseUrl: String, headers: Maybe<&2, R.Record<String>>, compat: ResolvedCompat}

# Azure and Codex have their own provider entry points; a dynamically selected
# model must still satisfy this provider's API type.
def compatible(api: T.ModelApi, +provider: String, +baseUrl: String, headers: Maybe<&2, R.Record<String>>, compat: Maybe<&2, T.ModelCompatibility(api)>) -> Result<&2, &2, PreparationError, ModelSettings>:
  match api:
    case T.OpenAIResponsesApi{}: Done{ModelSettings{provider, baseUrl, headers, getCompat(provider, baseUrl, compat)}}
    case other: Fail{UnsupportedApi{other}}

def modelSettings(model: T.Model<T.JsonValue>) -> Result<&2, &2, PreparationError, ModelSettings>:
  match model:
    case T.Model{_, _, api, provider, baseUrl, _, _, _, _, _, _, _, headers, compat}: compatible(api, provider, baseUrl, headers, compat)

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

def finishPreparation(apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), compat: ResolvedCompat, grammar: R.Record<String>, retention: T.CacheRetention, payload: Result<&2, &2, BuildError, T.JsonValue>) -> Result<&2, &2, PreparationError, Prepared>:
  match payload:
    case Fail{cause}: Fail{PayloadFailure{cause}}
    case Done{value}: Done{Prepared{apiKey, baseUrl, headers, value, compat, grammar, retention}}

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

def preparedWith(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>, agent: String, configuration: ModelSettings, apiKey: String, +grammar: R.Record<String>) -> IO(Result<&2, &2, PreparationError, Prepared>):
  match configuration:
    case ModelSettings{+provider, +baseUrl, modelHeaders, +compat}:
      do IO<Result<&2, &2, PreparationError, Prepared>>:
        +retention : T.CacheRetention <- resolveCacheRetention(optionRetention(Reason, Telemetry, E, options), optionEnv(Reason, Telemetry, E, options))
        +resolved : Context(G, D) = Transcript.resolveTranscript(V.Value, V.Value, G, D, context, Some{midConversation(compat)})
        merged : T.ProviderHeaders() = clientHeaders(V.Value, V.Value, G, D, agent, provider, modelHeaders, resolved, affinity(compat), cacheSessionId(retention, optionSession(Reason, Telemetry, E, options)), optionHeaders(Reason, Telemetry, E, options))
        payload : Result<&2, &2, BuildError, T.JsonValue> <- buildParams(~Reason, ~Telemetry, ~E, ~G, ~D, model, resolved, options, compat, grammar, retention)
        return finishPreparation(apiKey, baseUrl, merged, compat, grammar, retention, payload)

def compatOf(configuration: ModelSettings) -> ResolvedCompat:
  match configuration:
    case ModelSettings{_, _, _, compat}: compat

def providerOf(configuration: ModelSettings) -> String:
  match configuration:
    case ModelSettings{provider, _, _, _}: provider

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

def getServiceTierCostMultiplier(modelId: String, serviceTier: Maybe<&2, String>) -> Maybe<&2, F.F64>:
  match serviceTier:
    case Some{"flex"}: Some{F.fromBits(1071644672, 0)}
    case Some{"priority"}: Some{Bool.pick(F.F64, String.eq(modelId, "gpt-5.5"), F.fromBits(1074003968, 0), F.fromU32(2))}
    case _: None{}

def scaleCosts(+factor: F.F64, costs: T.UsageCost) -> T.UsageCost:
  match costs:
    case T.UsageCost{input, output, read, write, _}:
      +input = F.multiply(input, factor)
      +output = F.multiply(output, factor)
      +read = F.multiply(read, factor)
      +write = F.multiply(write, factor)
      T.UsageCost{input, output, read, write, F.add(F.add(F.add(input, output), read), write)}

def scaled(multiplier: Maybe<&2, F.F64>, usage: T.Usage) -> T.Usage:
  match multiplier usage:
    case None{} original: original
    case Some{factor} T.Usage{input, output, read, write, longWrite, reasoning, total, costs}: T.Usage{input, output, read, write, longWrite, reasoning, total, scaleCosts(factor, costs)}

# Immutable replacement for the upstream in-place cost update. A multiplier of
# one leaves the usage untouched, including its cost total.
def applyServiceTierPricing(model: T.Model<T.JsonValue>, serviceTier: Maybe<&2, String>, usage: T.Usage) -> T.Usage:
  match model:
    case T.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _}: scaled(getServiceTierCostMultiplier(id, serviceTier), usage)

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
  MissingStopReason{}
  OutputFailure{message: String}

def json(cause: JsonParse.ParseError) -> String:
  match cause:
    case JsonParse.ParseInvalidValue{}: "invalid value"
    case JsonParse.InvalidEscape{}: "invalid escape"
    case JsonParse.UnescapedControl{}: "unescaped control character"
    case JsonParse.UnterminatedString{}: "unterminated string"
    case JsonParse.UnexpectedToken{}: "unexpected token"
    case JsonParse.UnexpectedEnd{}: "unexpected end"
    case JsonParse.TrailingInput{}: "trailing input"
    case JsonParse.InputLimit{}: "input limit exceeded"

def describeAssistant(cause: Shared.AssistantError) -> String:
  match cause:
    case Shared.InvalidReasoningSignature{why}: "Invalid reasoning signature JSON: " ++ json(why)
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
    case GrammarFailure{why}: Sampling.errorMessage(why)
    case PayloadFailure{why}: describePayload(why)

def describeHeaderField(error: Header.HeaderSyntaxError) -> String:
  match error:
    case Header.InvalidName{}: "Invalid HTTP header name"
    case Header.InvalidValue{}: "Invalid HTTP header value"
    case Header.NonByteValue{}: "HTTP header value contains a non-byte character"

def describeHeader(error: Client.HeaderError) -> String:
  match error:
    case Client.TimeoutNotInteger{_}: "timeout must be an integer"
    case Client.TimeoutNegative{_}: "timeout must be a positive integer"
    case Client.TimeoutEncodingFailure{_}: "Could not encode request timeout"
    case Client.HeaderFailure{cause}: describeHeaderField(cause)
    case Client.MissingAuthentication{}: "Could not resolve authentication method. Expected either apiKey or adminAPIKey to be set. Or for one of the \"Authorization\" or \"api-key\" headers to be explicitly omitted"

def describeRequest(error: Client.RequestError) -> String:
  match error:
    case Client.URLFailure{Client.InvalidURL{_}}: "Invalid URL"
    case Client.URLFailure{Client.InvalidQuery{_}}: "Invalid URL query"
    case Client.HeaderRejected{cause}: describeHeader(cause)
    case Client.NonFinitePayload{}: "Request payload contains a non-finite number"
    case Client.PayloadEncodingFailure{}: "Could not encode request payload as JSON"

def describeEntropy(error: Seed.SeedError) -> String:
  match error:
    case Seed.SeedSourceFailure{code, message}: "Could not obtain retry entropy (code " ++ Nat.show(U32.to_nat(code)) ++ "): " ++ message
    case Seed.ShortSeed{bytes}: "Retry entropy source returned " ++ Nat.show(bytes) ++ " bytes; expected 8"

# formatProviderError(normalizeProviderError(error), prefix); a diagnostic
# whose status cannot be formatted keeps the SDK message.
def apiMessage(error: Client.APIError) -> String:
  match error:
    case Client.APIError{_, _, message}: message

def formattedAPIError(error: Client.APIError, formatted: Result<&2, &2, Body.NormalizationError, String>) -> String:
  match formatted:
    case Done{text}: text
    case Fail{_}: apiMessage(error)

def describeAPIError(+error: Client.APIError, provider: String) -> String:
  formattedAPIError(error, Client.format(error, provider))

def describeFetch(-Reason: Data, error: Fetch.Error<Reason>) -> String:
  match error:
    case Fetch.InvalidRequest{_}: "Invalid request"
    case Fetch.Rejected{_}: "Unsupported request URL"
    case Fetch.Unresolved{_}: "Could not resolve the request host"
    case Fetch.ExchangeFailure{_, _, _}: "Connection error."
    case Fetch.HeaderFailure{_, _, _}: "Connection error."

def describeCategory(-Reason: Data, cause: Fetch.Error<Reason>, category: Fetch.Category) -> String:
  match category:
    case Fetch.Connection{}: "Connection error."
    case Fetch.Timeout{}: "Request timed out."
    case Fetch.NonRetryable{}: describeFetch(Reason, cause)

def describeAbort(-Reason: Data, reason: Abort.AbortReason<Deadline.Cause<Reason>>) -> String:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: "Request timed out."
    case _: "Request was aborted."

def describeTransport(-Reason: Data, error: Client.FetchError<Reason>) -> String:
  match error:
    case Client.InvalidTimeout{_}: "Invalid request timeout"
    case Client.FetchFailure{Scope.Aborted{why}}: describeAbort(Reason, why)
    case Client.FetchFailure{Scope.DispatchFailure{cause, Some{why}}}: describeAbort(Reason, why)
    case Client.FetchFailure{Scope.DispatchFailure{+cause, None{}}}: describeCategory(Reason, cause, Fetch.classify(Reason, cause))

def describeAttempt(-Reason: Data, error: Client.AttemptError<Reason>, provider: String) -> String:
  match error:
    case Client.TransportFailure{cause}: describeTransport(Reason, cause)
    case Client.HTTPFailure{cause}: describeAPIError(cause, provider)
    case Client.DiagnosticFailure{Client.DiagnosticReadFailure{_, _}}: "Could not read the error response diagnostic."
    case Client.DiagnosticFailure{Client.DiagnosticEncodingFailure{_, _}}: "Could not encode the error response diagnostic."

def describeDelay(result: Result<&2, &2, Retry.FormattingError, Retry.RenderedError>) -> String:
  match result:
    case Done{Retry.RenderedError{_, message}}: message
    case Fail{_}: "Server requested a retry delay above the configured maximum"

def describeRetry(-Reason: Data, error: Retry.RetryFailure<Client.AttemptError<Reason>>, provider: String) -> String:
  match error:
    case Retry.RequestFailed{Retry.Other{cause}}: describeAttempt(Reason, cause, provider)
    case Retry.RequestFailed{Retry.Provider{Retry.ProviderError{cause, _, _, _, _, _}}}: describeAttempt(Reason, cause, provider)
    case Retry.RequestAborted{}: "Request aborted"
    case Retry.SleepRejected{_}: "Retry delay is outside the native timer range"
    case Retry.DelayRejected{cause, message}: describeDelay(Retry.delayError(cause, message))

def describeDispatch(error: Sse.DispatchError) -> String:
  match error:
    case Sse.InvalidJson{cause, _, _, _}: "Invalid SSE JSON: " ++ json(cause)
    case Sse.ApiErrorPayload{value}: Maybe.default(&2, String, Client.detail(Client.JSONDiagnostic{Convert.toJson(value)}), "(no status code or body)")

def describeStreaming(-Reason: Data, error: Sse.Error<Sse.TransportError(Reason)>) -> String:
  match error:
    case Sse.TransportFailure{_}: "Connection error."
    case Sse.DiagnosticFailure{_}: "Connection error."
    case Sse.DispatchFailure{cause}: describeDispatch(cause)

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
    case Stream.StreamingFailure{cause}: describeStreaming(Reason, cause)
    case Stream.ProtocolFailure{cause}: "Invalid Responses event: " ++ describeDecode(cause)

def describeProcessing(-Reason: Data, error: Stream.Error<ReaderError(Reason)>) -> String:
  match error:
    case Stream.ReadFailure{cause}: describeReader(Reason, cause)
    case Stream.EmitFailure{cause}: describeReader(Reason, cause)
    case Stream.ContentFailure{cause}: Sampling.errorMessage(cause)
    case Stream.TerminalFailure{cause}: Stream.terminalMessage(cause)

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
    case RequestRejected{cause}: describeRequest(cause)
    case InitializationFailure{cause}: Fetch.format(cause)
    case EntropyFailure{cause}: describeEntropy(cause)
    case RequestFailure{cause}: describeRetry(Reason, cause, provider)
    case ProcessingFailure{cause}: describeProcessing(Reason, cause)
    case ReleaseFailure{_}: "Could not close the response body"
    case DisposalFailure{_}: "Could not close the response body"
    case RequestAborted{}: "Request was aborted"
    case MissingStopReason{}: "OpenAI Responses events ended without a stop reason"
    case OutputFailure{message}: message

# Lifecycle
# ---------

type Terminal<-Reason: Data, -G: Data, -E: Data> is Data:
  Successful{reason: T.DoneReason, message: T.AssistantMessage<V.Value, G>}
  Failed{reason: T.ErrorReason, message: T.AssistantMessage<V.Value, G>, cause: Error<Reason, E>}

# A cleanup failure after a settled message never replaces its terminal cause.
type RunResult<-Reason: Data, -G: Data, -E: Data> is Data:
  RunResult{terminal: Terminal<Reason, G, E>, cleanup: Maybe<&2, Error<Reason, E>>}

def initialMessage(-G: Data, model: T.Model<T.JsonValue>, timestamp: F.F64) -> T.AssistantMessage<V.Value, G>:
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _}:
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
def check(-Reason: Data, -E: Data, aborted: Bool, reason: T.StopReason, detail: Maybe<&2, String>) -> Result<&2, &2, Error<Reason, E>, T.DoneReason>:
  match aborted reason:
    case True{} _: Fail{RequestAborted{}}
    case False{} T.Pending{}: Fail{MissingStopReason{}}
    case False{} T.Error{}: Fail{OutputFailure{outputError(detail)}}
    case False{} T.Aborted{}: Fail{OutputFailure{outputError(detail)}}
    case False{} T.Stop{}: Done{T.DoneStop{}}
    case False{} T.Length{}: Done{T.DoneLength{}}
    case False{} T.ToolUse{}: Done{T.DoneToolUse{}}
    case False{} T.Deferred{}: Done{T.DoneDeferred{}}

def validate(-Reason: Data, -G: Data, -E: Data, output: T.AssistantMessage<V.Value, G>, aborted: Bool) -> Result<&2, &2, Error<Reason, E>, T.DoneReason>:
  match output:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, reason, _, detail, _, _, _}: check(Reason, E, aborted, reason, detail)

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
def attemptWithEffects(~Reason: Data, ~E: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F.F64>, pair: Retry.Runtime<Reason> & Retry.Effects<Reason>) -> IO(Acquired(Reason, E)):
  match pair:
    case (owner, effects):
      do IO<Acquired(Reason, E)>:
        +request : C.Callback<Unit, Client.Outcome(Reason)> <- C.create(~AttemptEnvironment<Reason>, ~Unit, ~(Client.Outcome(Reason)), ~(attemptBody(~Reason)), environment)
        result : Result<&2, &1, Retry.RetryFailure<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>> <- Retry.retryProviderRequestOwned(Reason, Client.AttemptError<Reason>, Response.Response<Client.State(Reason)>, request, effects, retry)
        C.dispose(Unit, Client.Outcome(Reason), request)
        Retry.dispose(Reason, owner)
        C.dispose(String, F.F64, date)
        return retried(Reason, E, result)

# retryProviderRequest around one attempt callback. The retry effects, their
# entropy and the date parser live only for this loop.
def attempted(~Reason: Data, ~E: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F.F64>, seeded: Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>>) -> IO(Acquired(Reason, E)):
  match seeded:
    case Fail{cause}:
      do IO<Acquired(Reason, E)>:
        C.dispose(String, F.F64, date)
        return Fail{EntropyFailure{cause}}
    case Done{runtime}: attemptWithEffects(~Reason, ~E, environment, retry, date, Retry.borrow(Reason, runtime))

def acquire(~Reason: Data, ~E: Data, config: Config, fetch: Fetch.Fetch(Reason), request: Client.Request, parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>) -> IO(Acquired(Reason, E)):
  match config:
    case Config{_, _, _, _, _, limit, _}:
      do IO<Acquired(Reason, E)>:
        +date : C.Callback<String, F.F64> <- Retry.dateParser()
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
  T.ProviderResponse{F.fromU32(Metadata.statusResponseMetadata(metadata)), ProviderHeaders.headersToRecord(Metadata.headers(metadata))}

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
        result : Source<Reason, G> & Stream.RunResult<G, ReaderError(Reason)> <- Stream.processResponsesStream(~Source<Reason, G>, ~(ReaderError(Reason)), ~T.JsonValue, ~G, ~(sourceNext(~Reason, ~G)), ~(sourceClose(~Reason, ~G)), ~(sourceEmit(~Reason, ~G)), ~Stream.resolveServiceTier, ~applyServiceTierPricing, Source{body, cursor, events}, output, model, options)
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

def streamOptions(prepared: Prepared, tier: Maybe<&2, T.Nullable<ServiceTier>>) -> Stream.OpenAIResponsesStreamOptions:
  match prepared tier:
    case Prepared{_, _, _, _, _, grammar, _} Some{T.PresentValue{selected}}: Stream.OpenAIResponsesStreamOptions{Some{tierName(selected)}, grammar}
    case Prepared{_, _, _, _, _, grammar, _} _: Stream.OpenAIResponsesStreamOptions{None{}, grammar}

def envelope(config: Config, prepared: Prepared, timeout: Maybe<&2, F.F64>, payload: T.JsonValue) -> Result<&2, &2, Client.RequestError, Client.Request>:
  match config prepared:
    case Config{url, defaults, _, _, _, _, _} Prepared{apiKey, baseUrl, headers, _, _, _, _}: Client.prepareRequest(url, defaults, apiKey, headers, baseUrl, timeout, payload)

def selectedPayload(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, +config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, +options: OpenAIResponsesOptions<Reason, Telemetry, E>, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), +parent: Signal(Reason), +prepared: Prepared, retry: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>, payload: Result<&2, &2, E, T.JsonValue>) -> IO(Outcome<Reason, G, E>):
  match options retry payload:
    case _ _ Fail{cause}: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{HookFailure{cause}}, None{}})
    case _ Fail{cause} _: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{InvalidRetryOptions{cause}}, None{}})
    case OpenAIResponsesOptions{_, _, _, custom, _, _, hook, _, timeout, _, _, _, _, _, _, _, _, _, _, _, _, tier, _} Done{resolvedRetry} Done{chosen}:
      do IO<Outcome<Reason, G, E>>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        requested(~Reason, ~G, ~E, config, hooks, model, streamOptions(prepared, tier), custom, hook, output, events, parent, resolvedRetry, aborted, envelope(config, prepared, timeout, chosen))

def retryOptions(-Reason: Data, -Telemetry: Data, -E: Data, +parent: Signal(Reason), options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>:
  match options:
    case OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, retries, limit, _, _, _, _, _, _, _, _, _, _, _, _}: Retry.resolve(Reason, retries, limit, Some{parent})

def preparedRequest(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, +options: OpenAIResponsesOptions<Reason, Telemetry, E>, output: T.AssistantMessage<V.Value, G>, events: Events.AssistantMessageEventStream(V.Value, G), +parent: Signal(Reason), result: Result<&2, &2, PreparationError, Prepared>) -> IO(Outcome<Reason, G, E>):
  match options result:
    case _ Fail{cause}: IO.pure(Outcome<Reason, G, E>, Outcome{output, Some{PreparationFailure{cause}}, None{}})
    case OpenAIResponsesOptions{_, _, _, _, _, hook, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} Done{Prepared{apiKey, baseUrl, headers, +payload, compat, grammar, retention}}:
      do IO<Outcome<Reason, G, E>>:
        chosen : Result<&2, &2, E, T.JsonValue> <- payloadHook(E, payload, model, hook)
        selectedPayload(~Reason, ~Telemetry, ~G, ~E, config, hooks, model, options, output, events, parent, Prepared{apiKey, baseUrl, headers, payload, compat, grammar, retention}, retryOptions(Reason, Telemetry, E, parent, options), chosen)

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

def modelProvider(model: T.Model<T.JsonValue>) -> String:
  match model:
    case T.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _}: provider

def produceWith(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, +config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, +model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>, +events: Events.AssistantMessageEventStream(V.Value, G), timestamp: F.F64, finalizer: IO(Unit), pair: SignalOwner<Reason> & Signal(Reason)) -> IO(RunResult<Reason, G, E>):
  match pair:
    case (owner, +parent):
      do IO<RunResult<Reason, G, E>>:
        preparation : Result<&2, &2, PreparationError, Prepared> <- prepare(~Reason, ~Telemetry, ~E, ~G, ~D, model, context, options, userAgent(config))
        outcome : Outcome<Reason, G, E> <- preparedRequest(~Reason, ~Telemetry, ~G, ~E, config, hooks, model, options, initialMessage(G, model, timestamp), events, parent, preparation)
        aborted : Bool <- Abort.aborted(Reason, parent)
        settled(~Reason, ~G, ~E, ~render, events, modelProvider(model), owner, finalizer, aborted, outcome)

# The body of upstream `stream`'s async task: try everything, then settle the
# message, publish `done`/`error` and end the canonical stream.
def produce(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, context: Context(G, D), options: OpenAIResponsesOptions<Reason, Telemetry, E>, events: Events.AssistantMessageEventStream(V.Value, G), signal: SignalOwner<Reason>, timestamp: F.F64, finalizer: IO(Unit)) -> IO(RunResult<Reason, G, E>):
  produceWith(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, hooks, model, context, options, events, timestamp, finalizer, ownedSignal(Reason, signal))

# Public entry points
# -------------------

# Start the request with an explicit timestamp, SSE hooks and a finalizer that
# runs after the producer has retired everything it owns. Returns the run
# owner immediately; borrow its event stream, then wait or dispose.
def streamAt(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Config, hooks: Sse.Hooks<Sse.TransportError(Reason)>, model: T.Model<T.JsonValue>, context: Context(G, D), +options: OpenAIResponsesOptions<Reason, Telemetry, E>, timestamp: F.F64, finalizer: IO(Unit)) -> IO(Run<Reason, G, E>):
  match options:
    case OpenAIResponsesOptions{requestedSignal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      do IO<Run<Reason, G, E>>:
        signal : SignalOwner<Reason> <- selectSignal(Reason, requestedSignal)
        +events : Events.AssistantMessageEventStream(V.Value, G) <- Events.createAssistantMessageEventStream(~V.Value, ~G)
        task : Chan(RunResult<Reason, G, E>) <- IO.fork(RunResult<Reason, G, E>, produce(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, hooks, model, context, options, events, signal, timestamp, finalizer))
        return Running{events, task}

# Generate function for the OpenAI Responses API.
def stream(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Config, model: T.Model<T.JsonValue>, context: Context(G, D), options: OpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(Run<Reason, G, E>):
  do IO<Run<Reason, G, E>>:
    timestamp : F.F64 <- Date.now()
    +hooks : Sse.Hooks<Sse.TransportError(Reason)> <- Sse.defaultHooks(~(Sse.TransportError(Reason)))
    streamAt(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, hooks, model, context, options, timestamp, Sse.disposeHooks(Sse.TransportError(Reason), hooks))

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
    case Some{T.SimpleStreamOptions{_, _, apiKey, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: apiKey

# streamSimple: base options with the model's defaults and context budget,
# tool choice, and the reasoning level clamped to the model's support.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Config, +model: T.Model<T.JsonValue>, +context: Context(G, D), +options: Maybe<&2, SimpleStreamOptions(Reason, Telemetry, E)>) -> IO(Run<Reason, G, E>):
  stream(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, model, context, fromStreamOptions(Reason, Telemetry, E, Simple.buildBaseOptionsWith(~V.Value, ~V.Value, ~G, ~D, ~T.JsonValue, ~(Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, ~Convert.toJson, ~Convert.toJson, model, context, options, simpleApiKey(Reason, Telemetry, E, options)), simpleSettings(Reason, Telemetry, E, model, options)))

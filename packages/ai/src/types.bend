import Base
import ../../runtime/src/f64.bend as Number
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/record.bend as Record
import ./utils/diagnostics.bend as Diagnostics

# Source: pi-mono packages/ai/src/types.ts, revision 46c9de402.
# This module remains partial: schema constraints, provider options and
# provider contracts remain open; model data records are declared below. Opaque record payloads use explicit generics.
# JavaScript number fields use binary64; optional fields use Maybe.

# Upstream permits arbitrary extension identifiers as well as known literals.
def Api() -> Data: String
def ProviderId() -> Data: String
def ImagesApi() -> Data: String
def ImagesProviderId() -> Data: String

type TextContent is Data:
  TextContent{text: String, textSignature: Maybe<&2, String>}

type ThinkingContent is Data:
  ThinkingContent{thinking: String, thinkingSignature: Maybe<&2, String>, redacted: Maybe<&2, Bool>}

type ImageContent is Data:
  ImageContent{data: String, mimeType: String}

# The content constructors supply the upstream literal "type" discriminator.
# UsageCost names the anonymous record declared as Usage.cost upstream.
type UsageCost is Data:
  UsageCost{input: F64, output: F64, cacheRead: F64, cacheWrite: F64, total: F64}

type Usage is Data:
  Usage{input: F64, output: F64, cacheRead: F64, cacheWrite: F64, cacheWrite1h: Maybe<&2, F64>, reasoning: Maybe<&2, F64>, totalTokens: F64, cost: UsageCost}

type StopReason is Data:
  Pending{}
  Stop{}
  Length{}
  ToolUse{}
  Error{}
  Aborted{}
  Deferred{}

type ModelCostRates is Data:
  ModelCostRates{input: F64, output: F64, cacheRead: F64, cacheWrite: F64}

# TypeScript interface extension is flattened without changing field names.
type ModelCostTier is Data:
  ModelCostTier{input: F64, output: F64, cacheRead: F64, cacheWrite: F64, inputTokensAbove: F64}

type ModelCost is Data:
  ModelCost{input: F64, output: F64, cacheRead: F64, cacheWrite: F64, tiers: Maybe<&2, List<&2, ModelCostTier>>}

# Only explicitly JSON-valued upstream fields use this recursive value type.
# Own string property ordering is provided by the runtime Record type.
type JsonValue is Data:
  JsonNull{}
  JsonBoolean{value: Bool}
  JsonNumber{value: F64}
  JsonString{value: String}
  JsonArray{values: List<&2, JsonValue>}
  JsonObject{fields: Record.Record<JsonValue>}

type DeferredHandle is Data:
  DeferredHandle{provider: String, modelId: String, api: String, id: String, expiresAt: Maybe<&2, F64>, pollAfterMs: Maybe<&2, F64>, data: Maybe<&2, JsonValue>}

type TextSignaturePhase is Data:
  Commentary{}
  FinalAnswer{}

# The constructor supplies the literal v=1 discriminator.
type TextSignatureV1 is Data:
  TextSignatureV1{id: String, phase: Maybe<&2, TextSignaturePhase>}

# Arguments carries the caller's record type, rather than erasing it into JSON.
# A provider may instantiate this with its dynamic object representation.
type ToolCall<-Arguments: Data> is Data:
  ToolCall{id: String, name: String, arguments: Arguments, thoughtSignature: Maybe<&2, String>, namespace: Maybe<&2, String>}

type TextImageContent is Data:
  TextImageText{value: TextContent}
  TextImageImage{value: ImageContent}

type UserContent is Data:
  UserText{value: String}
  UserBlocks{values: List<&2, TextImageContent>}

# Message constructors supply their corresponding literal role discriminator.
type UserMessage is Data:
  UserMessage{content: UserContent, timestamp: F64}

type ToolResultMessage<-Details: Data> is Data:
  ToolResultMessage{toolCallId: String, toolName: String, content: List<&2, TextImageContent>, details: Maybe<&2, Details>, usage: Maybe<&2, Usage>, isError: Bool, timestamp: F64}

# Events carry immutable content values; subsequent updates create new values.
type AssistantContent<-Arguments: Data> is Data:
  AssistantText{value: TextContent}
  AssistantThinking{value: ThinkingContent}
  AssistantToolCall{value: ToolCall<Arguments>}

type AssistantMessage<-Arguments: Data, -DiagnosticDetails: Data> is Data:
  AssistantMessage{content: List<&2, AssistantContent<Arguments>>, api: Api(), provider: ProviderId(), model: String, responseModel: Maybe<&2, String>, responseId: Maybe<&2, String>, providerThinkingLevel: Maybe<&2, String>, diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<DiagnosticDetails>>>, usage: Usage, stopReason: StopReason, deferred: Maybe<&2, DeferredHandle>, errorMessage: Maybe<&2, String>, rawStopReason: Maybe<&2, String>, endTurn: Maybe<&2, Bool>, timestamp: F64}

def assistantContent(-A: Data, -D: Data, message: AssistantMessage<A, D>) -> List<&2, AssistantContent<A>>:
  match message:
    case AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: content

def assistantProvider(-A: Data, -D: Data, message: AssistantMessage<A, D>) -> ProviderId():
  match message:
    case AssistantMessage{_, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: provider

def assistantModel(-A: Data, -D: Data, message: AssistantMessage<A, D>) -> String:
  match message:
    case AssistantMessage{_, _, _, model, _, _, _, _, _, _, _, _, _, _, _}: model

def assistantUsage(-A: Data, -D: Data, message: AssistantMessage<A, D>) -> Usage:
  match message:
    case AssistantMessage{_, _, _, _, _, _, _, _, usage, _, _, _, _, _, _}: usage

def assistantStopReason(-A: Data, -D: Data, message: AssistantMessage<A, D>) -> StopReason:
  match message:
    case AssistantMessage{_, _, _, _, _, _, _, _, _, stopReason, _, _, _, _, _}: stopReason

def assistantErrorMessage(-A: Data, -D: Data, message: AssistantMessage<A, D>) -> Maybe<&2, String>:
  match message:
    case AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, errorMessage, _, _, _}: errorMessage

def assistantTimestamp(-A: Data, -D: Data, message: AssistantMessage<A, D>) -> F64:
  match message:
    case AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, _, _, timestamp}: timestamp

# Restricted terminal reasons preserve upstream Extract<StopReason, ...>.
type DoneReason is Data:
  DoneStop{}
  DoneLength{}
  DoneToolUse{}
  DoneDeferred{}

type ErrorReason is Data:
  ErrorAborted{}
  ErrorError{}

type AssistantMessageEvent<-Arguments: Data, -DiagnosticDetails: Data> is Data:
  Start{partial: AssistantMessage<Arguments, DiagnosticDetails>}
  TextStart{contentIndex: F64, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  TextDelta{contentIndex: F64, delta: String, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  TextEnd{contentIndex: F64, content: String, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  ThinkingStart{contentIndex: F64, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  ThinkingDelta{contentIndex: F64, delta: String, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  ThinkingEnd{contentIndex: F64, content: String, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  ToolcallStart{contentIndex: F64, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  ToolcallDelta{contentIndex: F64, delta: String, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  ToolcallEnd{contentIndex: F64, toolCall: ToolCall<Arguments>, partial: AssistantMessage<Arguments, DiagnosticDetails>}
  StreamDone{reason: DoneReason, message: AssistantMessage<Arguments, DiagnosticDetails>}
  StreamError{reason: ErrorReason, error: AssistantMessage<Arguments, DiagnosticDetails>}

type ImagesStopReason is Data:
  ImagesStop{}
  ImagesError{}
  ImagesAborted{}

def ImagesInputContent() -> Data: TextImageContent
def ImagesOutputContent() -> Data: TextImageContent

type ImagesContext is Data:
  ImagesContext{input: List<&2, ImagesInputContent()>}

type AssistantImages is Data:
  AssistantImages{api: ImagesApi(), provider: ImagesProviderId(), model: String, output: List<&2, ImagesOutputContent()>, responseId: Maybe<&2, String>, usage: Maybe<&2, Usage>, stopReason: ImagesStopReason, errorMessage: Maybe<&2, String>, timestamp: F64}


# Tool schema values retain their concrete type. The TypeBox-equivalent schema
# kind/validation relationship is still pending; this is not an untyped JSON tool.
type GrammarFormat is Data:
  OpenAILark{}
  OpenAIRegex{}

# Each supported grammar has an explicit optional value.
type GrammarVariants is Data:
  GrammarVariants{openaiLark: Maybe<&2, String>, openaiRegex: Maybe<&2, String>}

type SamplingStrictness is Data:
  Prefer{}
  Require{}

type ConstrainedSamplingConfig is Data:
  JsonSchemaSampling{strict: SamplingStrictness}
  GrammarSampling{variants: GrammarVariants}

# Absent, explicitly false, and a supplied configuration are distinct.
type ToolConstrainedSampling is Data:
  SamplingDisabled{}
  SamplingConfigured{config: ConstrainedSamplingConfig}

type Tool<-Parameters: Data> is Data:
  Tool{name: String, description: String, parameters: Parameters, constrainedSampling: Maybe<&2, ToolConstrainedSampling>}

type ToolReference is Data:
  ToolReference{name: String}

type SystemContent is Data:
  SystemText{value: String}
  SystemBlocks{values: List<&2, TextContent>}

type SystemMessage<-Parameters: Data> is Data:
  SystemMessage{content: SystemContent, sections: Maybe<&2, Record.Record<Maybe<&2, String>>>, toolsAdded: Maybe<&2, List<&2, Tool<Parameters>>>, toolsRemoved: Maybe<&2, List<&2, ToolReference>>, timestamp: F64}

type Message<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data> is Data:
  System{value: SystemMessage<Parameters>}
  User{value: UserMessage}
  Assistant{value: AssistantMessage<Arguments, DiagnosticDetails>}
  ToolResult{value: ToolResultMessage<ToolDetails>}

type Context<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data> is Data:
  Context{systemPrompt: Maybe<&2, String>, messages: List<&2, Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>, tools: Maybe<&2, List<&2, Tool<Parameters>>>}

# Nominally distinct from raw Context: provider APIs can require normalization.
# As with an upstream type assertion, explicitly constructing this wrapper is
# possible, but an unnormalized Context cannot be passed implicitly.
type TranscriptContext<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data> is Data:
  TranscriptContext{messages: List<&2, Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>}

# Model metadata and API-dependent compatibility from types.ts. Nullable values
# stay distinct from omitted optional fields, including explicit off mappings.
type Nullable<-Value: Data> is Data:
  NullValue{}
  PresentValue{value: Value}

type ThinkingLevel is Data:
  Minimal{}
  Low{}
  Medium{}
  High{}
  XHigh{}
  Max{}

type ModelThinkingLevel is Data:
  Off{}
  Thinking{level: ThinkingLevel}

type ThinkingLevelMapping is Data:
  ThinkingLevelMapping{level: ModelThinkingLevel, value: Maybe<&2, Nullable<String>>}

type ThinkingLevelMap is Data:
  ThinkingLevelMap{properties: List<&2, ThinkingLevelMapping>}

type ThinkingVariable is Data:
  ThinkingEnabled{}
  ThinkingEffort{}
  ThinkingBudget{}

type ChatTemplateKwargValue is Data:
  TemplateString{value: String}
  TemplateNumber{value: F64}
  TemplateBoolean{value: Bool}
  TemplateNull{}
  TemplateVariable{variable: ThinkingVariable, omitWhenOff: Maybe<&2, Bool>}

type ThinkingTokenBudgetField is Data:
  ThinkingTokenBudget{}
  ThinkingBudgetField{}
  ThinkingBudgetTokens{}

type ThinkingBudgets is Data:
  ThinkingBudgets{minimal: Maybe<&2, F64>, low: Maybe<&2, F64>, medium: Maybe<&2, F64>, high: Maybe<&2, F64>}

type SessionAffinityFormat is Data:
  OpenAISession{}
  OpenAINoSession{}
  OpenRouterSession{}

type DataCollection is Data:
  DenyCollection{}
  AllowCollection{}

type RoutingSort is Data:
  SortByName{value: String}
  SortByOptions{by: Maybe<&2, String>, partition: Maybe<&2, Nullable<String>>}

type PriceValue is Data:
  NumericPrice{value: F64}
  StringPrice{value: String}

type RoutingMaxPrice is Data:
  RoutingMaxPrice{prompt: Maybe<&2, PriceValue>, completion: Maybe<&2, PriceValue>, image: Maybe<&2, PriceValue>, audio: Maybe<&2, PriceValue>, request: Maybe<&2, PriceValue>}

type RoutingPercentiles is Data:
  RoutingPercentiles{p50: Maybe<&2, F64>, p75: Maybe<&2, F64>, p90: Maybe<&2, F64>, p99: Maybe<&2, F64>}

type RoutingPreference is Data:
  OverallPreference{value: F64}
  PercentilePreference{values: RoutingPercentiles}

type OpenRouterRouting is Data:
  OpenRouterRouting{allow_fallbacks: Maybe<&2, Bool>, require_parameters: Maybe<&2, Bool>, data_collection: Maybe<&2, DataCollection>, zdr: Maybe<&2, Bool>, enforce_distillable_text: Maybe<&2, Bool>, order: Maybe<&2, List<&2, String>>, only: Maybe<&2, List<&2, String>>, ignore: Maybe<&2, List<&2, String>>, quantizations: Maybe<&2, List<&2, String>>, sort: Maybe<&2, RoutingSort>, max_price: Maybe<&2, RoutingMaxPrice>, preferred_min_throughput: Maybe<&2, RoutingPreference>, preferred_max_latency: Maybe<&2, RoutingPreference>}

type VercelGatewayRouting is Data:
  VercelGatewayRouting{only: Maybe<&2, List<&2, String>>, order: Maybe<&2, List<&2, String>>}

type MaxTokensField is Data:
  MaxCompletionTokens{}
  MaxTokens{}

type ThinkingFormat is Data:
  OpenAIThinking{}
  OpenRouterThinking{}
  DeepSeekThinking{}
  TogetherThinking{}
  BasetenThinking{}
  ZaiThinking{}
  QwenThinking{}
  ChatTemplateThinking{}
  QwenChatTemplateThinking{}
  StringThinking{}
  AntLingThinking{}

type CacheControlFormat is Data:
  AnthropicCacheControl{}

type OpenAICompletionsCompat is Data:
  OpenAICompletionsCompat{supportsStore: Maybe<&2, Bool>, supportsDeveloperRole: Maybe<&2, Bool>, supportsReasoningEffort: Maybe<&2, Bool>, supportsUsageInStreaming: Maybe<&2, Bool>, supportsFinishReason: Maybe<&2, Bool>, maxTokensField: Maybe<&2, MaxTokensField>, requiresToolResultName: Maybe<&2, Bool>, requiresAssistantAfterToolResult: Maybe<&2, Bool>, requiresThinkingAsText: Maybe<&2, Bool>, requiresReasoningContentOnAssistantMessages: Maybe<&2, Bool>, thinkingFormat: Maybe<&2, ThinkingFormat>, chatTemplateKwargs: Maybe<&2, Record.Record<ChatTemplateKwargValue>>, chatTemplateArgs: Maybe<&2, Record.Record<ChatTemplateKwargValue>>, openRouterRouting: Maybe<&2, OpenRouterRouting>, vercelGatewayRouting: Maybe<&2, VercelGatewayRouting>, zaiToolStream: Maybe<&2, Bool>, thinkingTokenBudgetField: Maybe<&2, ThinkingTokenBudgetField>, supportsThinkingTokenBudget: Maybe<&2, Bool>, supportsOpenAIGrammarTools: Maybe<&2, Bool>, supportsMidConvoSystemMessages: Maybe<&2, Bool>, supportsMidConvoToolAdditions: Maybe<&2, Bool>, supportsStrictMode: Maybe<&2, Bool>, cacheControlFormat: Maybe<&2, CacheControlFormat>, sendSessionAffinityHeaders: Maybe<&2, Bool>, sessionAffinityFormat: Maybe<&2, SessionAffinityFormat>, supportsLongCacheRetention: Maybe<&2, Bool>, vllmPriority: Maybe<&2, F64>}

type OpenAIResponsesCompat is Data:
  OpenAIResponsesCompat{supportsDeveloperRole: Maybe<&2, Bool>, supportsMidConvoSystemMessages: Maybe<&2, Bool>, sessionAffinityFormat: Maybe<&2, SessionAffinityFormat>, supportsLongCacheRetention: Maybe<&2, Bool>, supportsStrictMode: Maybe<&2, Bool>, supportsOpenAIGrammarTools: Maybe<&2, Bool>, supportsAdditionalTools: Maybe<&2, Bool>, supportsToolSearch: Maybe<&2, Bool>, supportsExplicitPromptCacheMode: Maybe<&2, Bool>, supportsMaxOutputTokens: Maybe<&2, Bool>}

type AnthropicSessionAffinityFormat is Data:
  AnthropicOpenRouterSession{}

type AnthropicAllowedFallbackModel is Data:
  AnthropicAllowedFallbackModel{provider: ProviderId(), model: String, cost: ModelCost}

type AnthropicMessagesCompat is Data:
  AnthropicMessagesCompat{supportsEagerToolInputStreaming: Maybe<&2, Bool>, supportsLongCacheRetention: Maybe<&2, Bool>, sendSessionAffinityHeaders: Maybe<&2, Bool>, sessionAffinityFormat: Maybe<&2, AnthropicSessionAffinityFormat>, supportsCacheControlOnTools: Maybe<&2, Bool>, supportsTemperature: Maybe<&2, Bool>, forceAdaptiveThinking: Maybe<&2, Bool>, allowEmptySignature: Maybe<&2, Bool>, supportsStrictTools: Maybe<&2, Bool>, supportsMidConvoEffort: Maybe<&2, Bool>, supportsMidConvoSystemMessages: Maybe<&2, Bool>, supportsMidConvoToolChanges: Maybe<&2, Bool>, allowedFallbackModels: Maybe<&2, List<&2, AnthropicAllowedFallbackModel>>}

type BedrockCompat is Data:
  BedrockCompat{supportsStrictMode: Maybe<&2, Bool>}

type MistralConversationsCompat is Data:
  MistralConversationsCompat{supportsMidConvoSystemMessages: Maybe<&2, Bool>}

# The model API carries the compatibility discriminator. Assistant event API
# identifiers remain strings; model-api.bend maps between this type and strings.
type ModelApi is Data:
  OpenAICompletionsApi{}
  OpenAIResponsesApi{}
  AzureOpenAIResponsesApi{}
  OpenAICodexResponsesApi{}
  AnthropicMessagesApi{}
  BedrockConverseStreamApi{}
  MistralConversationsApi{}
  GoogleGenerativeAiApi{}
  GoogleVertexApi{}
  PiMessagesApi{}
  CustomModelApi{identifier: String}

def ModelCompatibility(api: ModelApi) -> Data:
  match api:
    case OpenAICompletionsApi{}: OpenAICompletionsCompat
    case OpenAIResponsesApi{}: OpenAIResponsesCompat
    case AzureOpenAIResponsesApi{}: OpenAIResponsesCompat
    case OpenAICodexResponsesApi{}: OpenAIResponsesCompat
    case AnthropicMessagesApi{}: AnthropicMessagesCompat
    case BedrockConverseStreamApi{}: BedrockCompat
    case MistralConversationsApi{}: MistralConversationsCompat
    case _: Empty

type ModelInput is Data:
  InputText{}
  InputImage{}

# Compatibility depends on the actual API field, preserving the conditional
# upstream contract. Sampling values remain caller-typed opaque data; this does
# not replace provider payloads or validated argument types with untyped JSON.
type ModelImageResizeOptions is Data:
  ModelImageResizeOptions{maxWidth: Maybe<&2, F64>, maxHeight: Maybe<&2, F64>, maxBytes: Maybe<&2, F64>, jpegQuality: Maybe<&2, F64>}

type ModelImageInputLimits is Data:
  ModelImageInputLimits{resize: Maybe<&2, ModelImageResizeOptions>, maxPerMessage: Maybe<&2, F64>, maxPerRequest: Maybe<&2, F64>}

type ModelInputLimits is Data:
  ModelInputLimits{maxRequestBytes: Maybe<&2, F64>, images: Maybe<&2, ModelImageInputLimits>}

# Prompt cache lifetimes per retention tier ("none" has no lifetime).
type ModelPromptCache is Data:
  ModelPromptCache{short: Maybe<&2, F64>, long: Maybe<&2, F64>}

type Model<-SamplingValue: Data> is Data:
  Model{id: String, name: String, api: ModelApi, provider: ProviderId(), baseUrl: String, reasoning: Bool, thinkingLevelMap: Maybe<&2, ThinkingLevelMap>, input: List<&2, ModelInput>, inputLimits: Maybe<&2, ModelInputLimits>, cost: ModelCost, promptCache: Maybe<&2, ModelPromptCache>, contextWindow: F64, maxTokens: F64, samplingParams: Maybe<&2, Record.Record<SamplingValue>>, headers: Maybe<&2, Record.Record<String>>, compat: Maybe<&2, ModelCompatibility(api)>}

def modelId(model: Model<JsonValue>) -> String:
  match model:
    case Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def modelProvider(model: Model<JsonValue>) -> String:
  match model:
    case Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: provider

def modelReasoning(model: Model<JsonValue>) -> Bool:
  match model:
    case Model{_, _, _, _, _, reasoning, _, _, _, _, _, _, _, _, _, _}: reasoning

def modelContextWindow(model: Model<JsonValue>) -> F64:
  match model:
    case Model{_, _, _, _, _, _, _, _, _, _, _, contextWindow, _, _, _, _}: contextWindow

def modelMaxTokens(model: Model<JsonValue>) -> F64:
  match model:
    case Model{_, _, _, _, _, _, _, _, _, _, _, _, maxTokens, _, _, _}: maxTokens

type ImagesModel<-SamplingValue: Data> is Data:
  ImagesModel{id: String, name: String, api: ImagesApi(), provider: ImagesProviderId(), baseUrl: String, thinkingLevelMap: Maybe<&2, ThinkingLevelMap>, input: List<&2, ModelInput>, inputLimits: Maybe<&2, ModelInputLimits>, cost: ModelCost, promptCache: Maybe<&2, ModelPromptCache>, samplingParams: Maybe<&2, Record.Record<SamplingValue>>, headers: Maybe<&2, Record.Record<String>>, output: List<&2, ModelInput>}

# Shared request options from types.ts. Fetch, Signal and Telemetry remain
# explicit caller types until their complete runtime interfaces are integrated.
type CacheRetention is Data:
  CacheNone{}
  CacheShort{}
  CacheLong{}

type Transport is Data:
  Sse{}
  WebSocket{}
  WebSocketCached{}
  AutoTransport{}

type ToolChoice is Data:
  AutoTool{}
  NoTool{}

type DeferredWindow is Data:
  FifteenMinutes{}
  OneHour{}
  TwentyFourHours{}

type DeferredRequest is Data:
  DeferredBoolean{value: Bool}
  DeferredConfig{window: Maybe<&2, DeferredWindow>}

def ProviderEnv() -> Data: Record.Record<String>
def ProviderHeaders() -> Data: Record.Record<Nullable<String>>

type ProviderResponse is Data:
  ProviderResponse{status: F64, headers: Record.Record<String>}

type PayloadInput<-Payload: Data, -RequestModel: Data> is Data:
  PayloadInput{payload: Payload, model: RequestModel}

type ResponseInput<-RequestModel: Data> is Data:
  ResponseInput{response: ProviderResponse, model: RequestModel}

def PayloadCallback(-Payload: Data, -RequestModel: Data, -Error: Data) -> Data:
  Callback.Callback<PayloadInput<Payload, RequestModel>, Result<&2, &2, Error, Maybe<&2, Payload>>>

def ResponseCallback(-RequestModel: Data, -Error: Data) -> Data:
  Callback.Callback<ResponseInput<RequestModel>, Result<&2, &2, Error, Unit>>

type ProviderRequestOptions<-RequestModel: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Payload: Data, -Error: Data> is Data:
  ProviderRequestOptions{signal: Maybe<&2, Signal>, telemetryContext: Maybe<&2, Telemetry>, apiKey: Maybe<&2, String>, fetch: Maybe<&2, Fetch>, env: Maybe<&2, ProviderEnv()>, onPayload: Maybe<&2, PayloadCallback(Payload, RequestModel, Error)>, onResponse: Maybe<&2, ResponseCallback(RequestModel, Error)>, headers: Maybe<&2, ProviderHeaders()>, timeoutMs: Maybe<&2, F64>, maxRetries: Maybe<&2, F64>, maxRetryDelayMs: Maybe<&2, F64>}

type StreamOptions<-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  StreamOptions{signal: Maybe<&2, Signal>, telemetryContext: Maybe<&2, Telemetry>, apiKey: Maybe<&2, String>, fetch: Maybe<&2, Fetch>, env: Maybe<&2, ProviderEnv()>, onPayload: Maybe<&2, PayloadCallback(Value, Model<Value>, Error)>, onResponse: Maybe<&2, ResponseCallback(Model<Value>, Error)>, headers: Maybe<&2, ProviderHeaders()>, timeoutMs: Maybe<&2, F64>, maxRetries: Maybe<&2, F64>, maxRetryDelayMs: Maybe<&2, F64>, temperature: Maybe<&2, F64>, samplingParams: Maybe<&2, Record.Record<Value>>, maxTokens: Maybe<&2, F64>, transport: Maybe<&2, Transport>, cacheRetention: Maybe<&2, CacheRetention>, sessionId: Maybe<&2, String>, websocketConnectTimeoutMs: Maybe<&2, F64>, metadata: Maybe<&2, Record.Record<Value>>}

type SimpleStreamOptions<-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  SimpleStreamOptions{signal: Maybe<&2, Signal>, telemetryContext: Maybe<&2, Telemetry>, apiKey: Maybe<&2, String>, fetch: Maybe<&2, Fetch>, env: Maybe<&2, ProviderEnv()>, onPayload: Maybe<&2, PayloadCallback(Value, Model<Value>, Error)>, onResponse: Maybe<&2, ResponseCallback(Model<Value>, Error)>, headers: Maybe<&2, ProviderHeaders()>, timeoutMs: Maybe<&2, F64>, maxRetries: Maybe<&2, F64>, maxRetryDelayMs: Maybe<&2, F64>, temperature: Maybe<&2, F64>, samplingParams: Maybe<&2, Record.Record<Value>>, maxTokens: Maybe<&2, F64>, transport: Maybe<&2, Transport>, cacheRetention: Maybe<&2, CacheRetention>, sessionId: Maybe<&2, String>, websocketConnectTimeoutMs: Maybe<&2, F64>, metadata: Maybe<&2, Record.Record<Value>>, toolChoice: Maybe<&2, ToolChoice>, reasoning: Maybe<&2, ThinkingLevel>, deferred: Maybe<&2, DeferredRequest>, thinkingBudgets: Maybe<&2, ThinkingBudgets>}

# Every option unset; callers override individual fields from here.
def emptySimpleStreamOptions(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data) -> SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  SimpleStreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

# Field access and single-field replacement; Bend has no record update syntax.
def apiKeyOption(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> Maybe<&2, String>:
  match options:
    case SimpleStreamOptions{_, _, apiKey, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: apiKey

def onPayloadOption(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> Maybe<&2, PayloadCallback(Value, Model<Value>, Error)>:
  match options:
    case SimpleStreamOptions{_, _, _, _, _, onPayload, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: onPayload

def onResponseOption(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> Maybe<&2, ResponseCallback(Model<Value>, Error)>:
  match options:
    case SimpleStreamOptions{_, _, _, _, _, _, onResponse, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: onResponse

def reasoningOption(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> Maybe<&2, ThinkingLevel>:
  match options:
    case SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, reasoning, _, _}: reasoning

def withSignal(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>, signal: Maybe<&2, Signal>) -> SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case SimpleStreamOptions{_, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}: SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}

def withApiKey(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>, apiKey: Maybe<&2, String>) -> SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case SimpleStreamOptions{signal, telemetryContext, _, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}: SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}

def withOnPayload(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>, onPayload: Maybe<&2, PayloadCallback(Value, Model<Value>, Error)>) -> SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, _, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}: SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}

def withOnResponse(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>, onResponse: Maybe<&2, ResponseCallback(Model<Value>, Error)>) -> SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, _, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}: SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}

def withReasoning(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>, reasoning: Maybe<&2, ThinkingLevel>) -> SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, _, deferred, thinkingBudgets}: SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}

# Explicit structural projections preserve every inherited field and shared
# callback/map handle. They neither apply defaults nor invoke user callbacks.
def toStreamOptions(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> StreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, _, _, _, _}: StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata}

def toProviderRequestOptions(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: StreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> ProviderRequestOptions<Model<Value>, Signal, Telemetry, Fetch, Value, Error>:
  match options:
    case StreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, _, _, _, _, _, _, _, _}: ProviderRequestOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs}

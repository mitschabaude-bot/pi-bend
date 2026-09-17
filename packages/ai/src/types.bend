import Base
import ../../runtime/src/f64.bend as Number
import ../../runtime/src/ref.bend as Ref
import ./utils/diagnostics.bend as Diagnostics

# Source: pi-mono packages/ai/src/types.ts, revision 46c9de402.
# This module remains partial: Model, system/transcript/schema contracts and
# provider options remain open. Opaque record payloads use explicit generics.
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
  UsageCost{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, total: Number.F64}

type Usage is Data:
  Usage{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, cacheWrite1h: Maybe<&2, Number.F64>, reasoning: Maybe<&2, Number.F64>, totalTokens: Number.F64, cost: UsageCost}

type StopReason is Data:
  Pending{}
  Stop{}
  Length{}
  ToolUse{}
  Error{}
  Aborted{}
  Deferred{}

type ModelCostRates is Data:
  ModelCostRates{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64}

# TypeScript interface extension is flattened without changing field names.
type ModelCostTier is Data:
  ModelCostTier{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, inputTokensAbove: Number.F64}

type ModelCost is Data:
  ModelCost{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, tiers: Maybe<&2, List<&2, ModelCostTier>>}

# Only explicitly JSON-valued upstream fields use this recursive value type.
# Objects retain their field order; codecs must enforce object-key semantics.
type JsonProperty<-Value: Data> is Data:
  JsonProperty{key: String, value: Value}

type JsonValue is Data:
  JsonNull{}
  JsonBoolean{value: Bool}
  JsonNumber{value: Number.F64}
  JsonString{value: String}
  JsonArray{values: List<&2, JsonValue>}
  JsonObject{fields: List<&2, JsonProperty<JsonValue>>}

type DeferredHandle is Data:
  DeferredHandle{provider: String, modelId: String, api: String, id: String, expiresAt: Maybe<&2, Number.F64>, pollAfterMs: Maybe<&2, Number.F64>, data: Maybe<&2, JsonValue>}

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
  UserMessage{content: UserContent, timestamp: Number.F64}

type ToolResultMessage<-Details: Data> is Data:
  ToolResultMessage{toolCallId: String, toolName: String, content: List<&2, TextImageContent>, details: Maybe<&2, Details>, usage: Maybe<&2, Usage>, isError: Bool, timestamp: Number.F64}

# Content objects can be retained independently by event consumers. Their
# handles preserve identity while the provider updates the message in place.
type AssistantContent<-Arguments: Data> is Data:
  AssistantText{value: Ref.Ref<TextContent>}
  AssistantThinking{value: Ref.Ref<ThinkingContent>}
  AssistantToolCall{value: Ref.Ref<ToolCall<Arguments>>}

type AssistantMessage<-Arguments: Data, -DiagnosticDetails: Data> is Data:
  AssistantMessage{content: List<&2, AssistantContent<Arguments>>, api: Api(), provider: ProviderId(), model: String, responseModel: Maybe<&2, String>, responseId: Maybe<&2, String>, providerThinkingLevel: Maybe<&2, String>, diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<DiagnosticDetails>>>, usage: Usage, stopReason: StopReason, deferred: Maybe<&2, DeferredHandle>, errorMessage: Maybe<&2, String>, rawStopReason: Maybe<&2, String>, endTurn: Maybe<&2, Bool>, timestamp: Number.F64}

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
  Start{partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  TextStart{contentIndex: Number.F64, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  TextDelta{contentIndex: Number.F64, delta: String, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  TextEnd{contentIndex: Number.F64, content: String, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  ThinkingStart{contentIndex: Number.F64, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  ThinkingDelta{contentIndex: Number.F64, delta: String, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  ThinkingEnd{contentIndex: Number.F64, content: String, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  ToolcallStart{contentIndex: Number.F64, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  ToolcallDelta{contentIndex: Number.F64, delta: String, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  ToolcallEnd{contentIndex: Number.F64, toolCall: Ref.Ref<ToolCall<Arguments>>, partial: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  StreamDone{reason: DoneReason, message: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}
  StreamError{reason: ErrorReason, error: Ref.Ref<AssistantMessage<Arguments, DiagnosticDetails>>}

type ImagesStopReason is Data:
  ImagesStop{}
  ImagesError{}
  ImagesAborted{}

def ImagesInputContent() -> Data: TextImageContent
def ImagesOutputContent() -> Data: TextImageContent

type ImagesContext is Data:
  ImagesContext{input: List<&2, ImagesInputContent()>}

type AssistantImages is Data:
  AssistantImages{api: ImagesApi(), provider: ImagesProviderId(), model: String, output: List<&2, ImagesOutputContent()>, responseId: Maybe<&2, String>, usage: Maybe<&2, Usage>, stopReason: ImagesStopReason, errorMessage: Maybe<&2, String>, timestamp: Number.F64}

import Base
import ../../runtime/src/string.bend as Set
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/f64.bend as Number
import ../../runtime/src/record.bend as Record
import ../../ai/src/utils/event-stream.bend as Stream

# Source: pi-mono packages/agent/src/types.ts at 46c9de402. This initial portion
# covers tool definitions/results, messages, events, state and hook records.
# Agent orchestration is separate from the immutable state and loop types.
# Raw arguments, abort signals and thrown errors retain explicit
# caller types until their runtime interfaces are integrated.
type ToolExecutionMode is Data:
  Sequential{}
  Parallel{}

type ToolReplayPolicy is Data:
  Never{}
  Safe{}

type AgentToolResult<-Details: Data> is Data:
  AgentToolResult{content: List<&2, Ai.TextImageContent>, details: Details, usage: Maybe<&2, Ai.Usage>, terminate: Maybe<&2, Bool>}

# The execution layer must enforce invocation-scoped update lifetime; the type
# alone does not implement ignoring updates after the tool promise settles.
def AgentToolUpdateCallback(-Details: Data) -> Data:
  Callback.Callback<AgentToolResult<Details>, Unit>

# Bend callbacks take one typed argument; this record preserves all four
# upstream execute arguments, including independent optional signal/onUpdate.
type ToolExecutionInput<-Arguments: Data, -Signal: Data, -Details: Data> is Data:
  ToolExecutionInput{toolCallId: String, params: Arguments, signal: Maybe<&2, Signal>, onUpdate: Maybe<&2, AgentToolUpdateCallback(Details)>}

# Parameters/Arguments are deliberately distinct type parameters for now. The
# TypeBox Static<Parameters> relationship still needs a typed schema adapter;
# these declarations do not establish schema validation or inference parity.
# Recoverable callback failures use Result instead of host-language exceptions.
type AgentTool<-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data> is Data:
  AgentTool{name: String, description: String, parameters: Parameters, constrainedSampling: Maybe<&2, Ai.ToolConstrainedSampling>, label: String, prepareArguments: Maybe<&2, Callback.Callback<RawArguments, Result<&2, &2, ExecutionError, Arguments>>>, execute: Callback.Callback<ToolExecutionInput<Arguments, Signal, Details>, Result<&2, &2, ExecutionError, AgentToolResult<Details>>>, replay: Maybe<&2, ToolReplayPolicy>, executionMode: Maybe<&2, ToolExecutionMode>}

# Explicit structural upcast: executable/display fields are not part of Tool.
# This view preserves schema and sampling values without cloning or execution;
# Immutable schema values require no additional copying.
def toTool(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data, tool: AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>) -> Ai.Tool<Parameters>:
  match tool:
    case AgentTool{name, description, parameters, sampling, _, _, _, _, _}: Ai.Tool{name, description, parameters, sampling}

# The agent adds "off" to pi-ai's six reasoning levels. Reuse the canonical
# model-level union rather than introducing incompatible copies of those values.
def ThinkingLevel() -> Data: Ai.ModelThinkingLevel

type QueueMode is Data:
  All{}
  OneAtATime{}

# Declaration merging becomes an explicit application-defined message union.
# Standard and custom messages are values retained by immutable events.
type AgentMessage<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data> is Data:
  LlmMessage{value: Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>}
  CustomMessage{value: Custom}

# Extract<AssistantMessage["content"][number], {type: "toolCall"}> preserves
# the existing tool-call object, including its raw argument payload.
def AgentToolCall(-Arguments: Data) -> Data: Ai.ToolCall<Arguments>

type BeforeToolCallResult is Data:
  BeforeToolCallResult{block: Maybe<&2, Bool>, reason: Maybe<&2, String>, terminate: Maybe<&2, Bool>}

# Native hook updates return arguments/context explicitly. This preserves the
# ability to alter execution inputs without hidden mutation or revalidation.
type BeforeToolCallUpdate<-Arguments: Data, -Context: Data> is Data:
  BeforeToolCallUpdate{args: Arguments, context: Context, result: Maybe<&2, BeforeToolCallResult>}

type AfterToolCallResult<-Details: Data> is Data:
  AfterToolCallResult{content: Maybe<&2, List<&2, Ai.TextImageContent>>, details: Maybe<&2, Details>, isError: Maybe<&2, Bool>, usage: Maybe<&2, Ai.Usage>, terminate: Maybe<&2, Bool>}

# Literal type discriminators are represented by named variants. Event fields
# retain their upstream names. PartialResult/ExecutionResult preserve the two
# source `any` payloads independently; neither is silently narrowed to a tool
# result record. Event emission/order and subscription settlement live in the
# agent implementation, not these declarations.
type AgentEvent<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AgentStart{}
  AgentEnd{messages: List<&2, AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>}
  TurnStart{}
  TurnEnd{message: AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, toolResults: List<&2, Ai.ToolResultMessage<ToolDetails>>}
  MessageStart{message: AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>}
  MessageUpdate{message: AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, assistantMessageEvent: Ai.AssistantMessageEvent<Arguments, DiagnosticDetails>}
  MessageEnd{message: AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>}
  ToolExecutionStart{toolCallId: String, toolName: String, args: Arguments}
  ToolExecutionUpdate{toolCallId: String, toolName: String, args: Arguments, partialResult: PartialResult}
  ToolExecutionEnd{toolCallId: String, toolName: String, result: ExecutionResult, isError: Bool}

def eventType(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, event: AgentEvent<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> String:
  match event:
    case AgentStart{}: "agent_start"
    case AgentEnd{_}: "agent_end"
    case TurnStart{}: "turn_start"
    case TurnEnd{_, _}: "turn_end"
    case MessageStart{_}: "message_start"
    case MessageUpdate{_, _}: "message_update"
    case MessageEnd{_}: "message_end"
    case ToolExecutionStart{_, _, _}: "tool_execution_start"
    case ToolExecutionUpdate{_, _, _, _}: "tool_execution_update"
    case ToolExecutionEnd{_, _, _, _}: "tool_execution_end"

# Contexts contain persistent lists; transformations return updated values.
def AgentMessageArray(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data) -> Data:
  List<&2, AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>>

def AgentToolArray(-Parameters: Data, -Arguments: Data, -Details: Data, -RawArguments: Data, -Signal: Data, -ExecutionError: Data) -> Data:
  List<&2, AgentTool<Parameters, Arguments, Details, RawArguments, Signal, ExecutionError>>

# Arguments is the raw provider payload; ValidatedArguments is the schema's
# execution payload. Tools and their callbacks retain both types independently.
type AgentContext<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data> is Data:
  AgentContext{messages: AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), tools: Maybe<&2, AgentToolArray(Parameters, ValidatedArguments, ToolDetails, Arguments, Signal, ExecutionError)>}

type BeforeToolCallContext<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data> is Data:
  BeforeToolCallContext{assistantMessage: Ai.AssistantMessage<Arguments, DiagnosticDetails>, toolCall: AgentToolCall(Arguments), args: ValidatedArguments, context: AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>}

type AfterToolCallContext<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data> is Data:
  AfterToolCallContext{assistantMessage: Ai.AssistantMessage<Arguments, DiagnosticDetails>, toolCall: AgentToolCall(Arguments), args: ValidatedArguments, result: AgentToolResult<ToolDetails>, isError: Bool, context: AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>}

type ShouldStopAfterTurnContext<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data> is Data:
  ShouldStopAfterTurnContext{message: Ai.AssistantMessage<Arguments, DiagnosticDetails>, toolResults: List<&2, Ai.ToolResultMessage<ToolDetails>>, context: AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, newMessages: AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)}

def PrepareNextTurnContext(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data) -> Data:
  ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>

type AgentLoopTurnUpdate<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -SamplingValue: Data> is Data:
  AgentLoopTurnUpdate{context: Maybe<&2, AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>, messages: Maybe<&2, AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>, model: Maybe<&2, Ai.Model<SamplingValue>>, thinkingLevel: Maybe<&2, ThinkingLevel()>}

# Callback argument records preserve source positional arguments. Exceptions
# become recoverable results; the loop must retain each callback's documented
# fallback/error policy rather than silently treating failure as an empty value.
type TransformContextInput<-Messages: Data, -Signal: Data> is Data:
  TransformContextInput{messages: Messages, signal: Maybe<&2, Signal>}

type ToolHookInput<-Context: Data, -Signal: Data> is Data:
  ToolHookInput{context: Context, signal: Maybe<&2, Signal>}

type AgentLoopConfig<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  AgentLoopConfig{signal: Maybe<&2, Signal>, telemetryContext: Maybe<&2, Telemetry>, apiKey: Maybe<&2, String>, fetch: Maybe<&2, Fetch>, env: Maybe<&2, Ai.ProviderEnv()>, onPayload: Maybe<&2, Ai.PayloadCallback(Value, Ai.Model<Value>, ExecutionError)>, onResponse: Maybe<&2, Ai.ResponseCallback(Ai.Model<Value>, ExecutionError)>, headers: Maybe<&2, Ai.ProviderHeaders()>, timeoutMs: Maybe<&2, Number.F64>, maxRetries: Maybe<&2, Number.F64>, maxRetryDelayMs: Maybe<&2, Number.F64>, temperature: Maybe<&2, Number.F64>, samplingParams: Maybe<&2, Record.Record<Value>>, maxTokens: Maybe<&2, Number.F64>, transport: Maybe<&2, Ai.Transport>, cacheRetention: Maybe<&2, Ai.CacheRetention>, sessionId: Maybe<&2, String>, websocketConnectTimeoutMs: Maybe<&2, Number.F64>, metadata: Maybe<&2, Record.Record<Value>>, toolChoice: Maybe<&2, Ai.ToolChoice>, reasoning: Maybe<&2, Ai.ThinkingLevel>, deferred: Maybe<&2, Ai.DeferredRequest>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, model: Ai.Model<Value>, convertToLlm: Callback.Callback<AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>>>>, transformContext: Maybe<&2, Callback.Callback<TransformContextInput<AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom), Signal>, Result<&2, &2, ExecutionError, AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>, getApiKey: Maybe<&2, Callback.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>, shouldStopAfterTurn: Maybe<&2, Callback.Callback<ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Result<&2, &2, ExecutionError, Bool>>>, prepareNextTurn: Maybe<&2, Callback.Callback<PrepareNextTurnContext(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, AgentLoopTurnUpdate<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value>>>>>, getSteeringMessages: Maybe<&2, Callback.Callback<Unit, Result<&2, &2, ExecutionError, AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>, getFollowUpMessages: Maybe<&2, Callback.Callback<Unit, Result<&2, &2, ExecutionError, AgentMessageArray(Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom)>>>, toolExecution: Maybe<&2, ToolExecutionMode>, beforeToolCall: Maybe<&2, Callback.Callback<ToolHookInput<BeforeToolCallContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Signal>, Result<&2, &2, ExecutionError, BeforeToolCallUpdate<ValidatedArguments, AgentContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>>>>>, afterToolCall: Maybe<&2, Callback.Callback<ToolHookInput<AfterToolCallContext<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError>, Signal>, Result<&2, &2, ExecutionError, Maybe<&2, AfterToolCallResult<ToolDetails>>>>>}

# Structural projection only: preserve provider options and callback identity.
def toSimpleStreamOptions(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ValidatedArguments: Data, -Signal: Data, -ExecutionError: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom, ValidatedArguments, Signal, ExecutionError, Value, Telemetry, Fetch>) -> Ai.SimpleStreamOptions<Value, Signal, Telemetry, Fetch, ExecutionError>:
  match config:
    case AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, _, _, _, _, _, _, _, _, _, _, _}: Ai.SimpleStreamOptions{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}

# Options is explicit because Bend lacks TypeScript structural subtyping.
# Standalone providers instantiate SimpleStreamOptions; the agent uses its full
# configuration snapshot, preserving extra fields visible to injected streams.
# Opening failures are explicit; failures after opening remain stream events.
type StreamInput<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data> is Data:
  StreamInput{model: Ai.Model<Value>, context: Ai.TranscriptContext<Parameters, Arguments, DiagnosticDetails, ToolDetails>, options: Maybe<&2, Options>}

def StreamFn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Value: Data, -Options: Data, -Error: Data) -> Data:
  Callback.Callback<StreamInput<Parameters, Arguments, DiagnosticDetails, ToolDetails, Value, Options>, Result<&2, &2, Error, Stream.AssistantMessageEventStream(Arguments, DiagnosticDetails)>>

# systemPrompt is derived from messages by agent-state.systemPrompt.
# Runtime ownership and borrowed callbacks remain outside this value snapshot.
type AgentState<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data> is Data:
  AgentState{model: Ai.Model<Value>, thinkingLevel: ThinkingLevel(), tools: List<&2, AgentTool<Parameters, Validated, Details, Arguments, Signal, Error>>, messages: List<&2, AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, isStreaming: Bool, streamingMessage: Maybe<&2, AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, pendingToolCalls: Set.StringSet, errorMessage: Maybe<&2, String>}

import Base
import ../../runtime/src/string.bend as Set
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/f64.bend as Number
import ../../runtime/src/record.bend as Record
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/abort.bend as Abort

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
type ToolExecutionInput<-Details: Data> is Data:
  ToolExecutionInput{toolCallId: String, params: Schema.Value, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onUpdate: Maybe<&2, AgentToolUpdateCallback(Details)>}

# Parameters/Arguments are deliberately distinct type parameters for now. The
# TypeBox Static<Parameters> relationship still needs a typed schema adapter;
# these declarations do not establish schema validation or inference parity.
# Recoverable callback failures use Result instead of host-language exceptions.
type AgentTool<-Details: Data, -ExecutionError: Data> is Data:
  AgentTool{name: String, description: String, parameters: Schema.Value, constrainedSampling: Maybe<&2, Ai.ToolConstrainedSampling>, label: String, prepareArguments: Maybe<&2, Callback.Callback<Schema.Value, Result<&2, &2, ExecutionError, Schema.Value>>>, execute: Callback.Callback<ToolExecutionInput<Details>, Result<&2, &2, ExecutionError, AgentToolResult<Details>>>, replay: Maybe<&2, ToolReplayPolicy>, executionMode: Maybe<&2, ToolExecutionMode>}

# Explicit structural upcast: executable/display fields are not part of Tool.
# This view preserves schema and sampling values without cloning or execution;
# Immutable schema values require no additional copying.
def toTool(-Details: Data, -ExecutionError: Data, tool: AgentTool<Details, ExecutionError>) -> Ai.Tool<Schema.Value>:
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
type AgentMessage<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data> is Data:
  LlmMessage{value: Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>}
  CustomMessage{value: Custom}

# Extract<AssistantMessage["content"][number], {type: "toolCall"}> preserves
# the existing tool-call object, including its raw argument payload.
def AgentToolCall() -> Data: Ai.ToolCall<Schema.Value>

type BeforeToolCallResult is Data:
  BeforeToolCallResult{block: Maybe<&2, Bool>, reason: Maybe<&2, String>, terminate: Maybe<&2, Bool>}

# Native hook updates return arguments/context explicitly. This preserves the
# ability to alter execution inputs without hidden mutation or revalidation.
type BeforeToolCallUpdate<-Context: Data> is Data:
  BeforeToolCallUpdate{args: Schema.Value, context: Context, result: Maybe<&2, BeforeToolCallResult>}

type AfterToolCallResult<-Details: Data> is Data:
  AfterToolCallResult{content: Maybe<&2, List<&2, Ai.TextImageContent>>, details: Maybe<&2, Details>, isError: Maybe<&2, Bool>, usage: Maybe<&2, Ai.Usage>, terminate: Maybe<&2, Bool>}

# Literal type discriminators are represented by named variants. Event fields
# retain their upstream names. PartialResult/ExecutionResult preserve the two
# source `any` payloads independently; neither is silently narrowed to a tool
# result record. Event emission/order and subscription settlement live in the
# agent implementation, not these declarations.
type AgentEvent<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data> is Data:
  AgentStart{}
  AgentEnd{messages: List<&2, AgentMessage<DiagnosticDetails, ToolDetails, Custom>>}
  TurnStart{}
  TurnEnd{message: AgentMessage<DiagnosticDetails, ToolDetails, Custom>, toolResults: List<&2, Ai.ToolResultMessage<ToolDetails>>}
  MessageStart{message: AgentMessage<DiagnosticDetails, ToolDetails, Custom>}
  MessageUpdate{message: AgentMessage<DiagnosticDetails, ToolDetails, Custom>, assistantMessageEvent: Ai.AssistantMessageEvent<Schema.Value, DiagnosticDetails>}
  MessageEnd{message: AgentMessage<DiagnosticDetails, ToolDetails, Custom>}
  ToolExecutionStart{toolCallId: String, toolName: String, args: Schema.Value}
  ToolExecutionUpdate{toolCallId: String, toolName: String, args: Schema.Value, partialResult: PartialResult}
  ToolExecutionEnd{toolCallId: String, toolName: String, result: ExecutionResult, isError: Bool}

def eventType(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -PartialResult: Data, -ExecutionResult: Data, event: AgentEvent<DiagnosticDetails, ToolDetails, Custom, PartialResult, ExecutionResult>) -> String:
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
def AgentMessageArray(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data) -> Data:
  List<&2, AgentMessage<DiagnosticDetails, ToolDetails, Custom>>

def AgentToolArray(-Details: Data, -ExecutionError: Data) -> Data:
  List<&2, AgentTool<Details, ExecutionError>>

# Arguments is the raw provider payload; ValidatedArguments is the schema's
# execution payload. Tools and their callbacks retain both types independently.
type AgentContext<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data> is Data:
  AgentContext{messages: AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), tools: Maybe<&2, AgentToolArray(ToolDetails, ExecutionError)>}

type BeforeToolCallContext<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data> is Data:
  BeforeToolCallContext{assistantMessage: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, toolCall: AgentToolCall, args: Schema.Value, context: AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>}

type AfterToolCallContext<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data> is Data:
  AfterToolCallContext{assistantMessage: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, toolCall: AgentToolCall, args: Schema.Value, result: AgentToolResult<ToolDetails>, isError: Bool, context: AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>}

type ShouldStopAfterTurnContext<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data> is Data:
  ShouldStopAfterTurnContext{message: Ai.AssistantMessage<Schema.Value, DiagnosticDetails>, toolResults: List<&2, Ai.ToolResultMessage<ToolDetails>>, context: AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, newMessages: AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)}

def PrepareNextTurnContext(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data) -> Data:
  ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>

type AgentLoopTurnUpdate<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data> is Data:
  AgentLoopTurnUpdate{context: Maybe<&2, AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, messages: Maybe<&2, AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, model: Maybe<&2, Ai.Model<Ai.JsonValue>>, thinkingLevel: Maybe<&2, ThinkingLevel()>}

# Callback argument records preserve source positional arguments. Exceptions
# become recoverable results; the loop must retain each callback's documented
# fallback/error policy rather than silently treating failure as an empty value.
type TransformContextInput<-Messages: Data> is Data:
  TransformContextInput{messages: Messages, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

type ToolHookInput<-Context: Data> is Data:
  ToolHookInput{context: Context, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

type AgentLoopConfig<-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data> is Data:
  AgentLoopConfig{options: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), ExecutionError>, model: Ai.Model<Ai.JsonValue>, convertToLlm: Callback.Callback<AgentMessageArray(DiagnosticDetails, ToolDetails, Custom), Result<&2, &2, ExecutionError, List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>>>>, transformContext: Maybe<&2, Callback.Callback<TransformContextInput<AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>, Result<&2, &2, ExecutionError, AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>, getApiKey: Maybe<&2, Callback.Callback<String, Result<&2, &2, ExecutionError, Maybe<&2, String>>>>, shouldStopAfterTurn: Maybe<&2, Callback.Callback<ShouldStopAfterTurnContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>, Result<&2, &2, ExecutionError, Bool>>>, prepareNextTurn: Maybe<&2, Callback.Callback<PrepareNextTurnContext(DiagnosticDetails, ToolDetails, Custom, ExecutionError), Result<&2, &2, ExecutionError, Maybe<&2, AgentLoopTurnUpdate<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>>>>, getSteeringMessages: Maybe<&2, Callback.Callback<Unit, Result<&2, &2, ExecutionError, AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>, getFollowUpMessages: Maybe<&2, Callback.Callback<Unit, Result<&2, &2, ExecutionError, AgentMessageArray(DiagnosticDetails, ToolDetails, Custom)>>>, toolExecution: Maybe<&2, ToolExecutionMode>, beforeToolCall: Maybe<&2, Callback.Callback<ToolHookInput<BeforeToolCallContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, Result<&2, &2, ExecutionError, BeforeToolCallUpdate<AgentContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>>>>, afterToolCall: Maybe<&2, Callback.Callback<ToolHookInput<AfterToolCallContext<DiagnosticDetails, ToolDetails, Custom, ExecutionError>>, Result<&2, &2, ExecutionError, Maybe<&2, AfterToolCallResult<ToolDetails>>>>>}

# Structural projection only: preserve provider options and callback identity.
def toSimpleStreamOptions(-DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data, -ExecutionError: Data, -Telemetry: Data, config: AgentLoopConfig<DiagnosticDetails, ToolDetails, Custom, ExecutionError, Telemetry>) -> Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), ExecutionError>:
  match config:
    case AgentLoopConfig{options, _, _, _, _, _, _, _, _, _, _, _}: options

# Options is explicit because Bend lacks TypeScript structural subtyping.
# Standalone providers instantiate SimpleStreamOptions; the agent uses its full
# configuration snapshot, preserving extra fields visible to injected streams.
# Opening failures are explicit; failures after opening remain stream events.
type StreamInput<-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data> is Data:
  StreamInput{model: Ai.Model<Ai.JsonValue>, context: Ai.TranscriptContext<Schema.Value, Schema.Value, DiagnosticDetails, ToolDetails>, options: Maybe<&2, Options>}

# A provider lends the loop its event stream together with the action that
# ends the borrow. Upstream leaves the stream to garbage collection; Bend has
# no managed shared handles, so the loop runs `release` once, after its last
# read, and a release failure is reported through the loop's error type.
type StreamLease<-DiagnosticDetails: Data, -Error: Data> is Type:
  StreamLease{events: Stream.AssistantMessageEventStream(Schema.Value, DiagnosticDetails), release: IO(Result<&2, &2, Error, Unit>)}

# A stream whose owner outlives the loop's use of it has nothing to release.
def borrowedStream(-DiagnosticDetails: Data, -Error: Data, events: Stream.AssistantMessageEventStream(Schema.Value, DiagnosticDetails)) -> StreamLease<DiagnosticDetails, Error>:
  StreamLease{events, IO.pure(Result<&2, &2, Error, Unit>, Done{Unit{}})}

def StreamFn(-DiagnosticDetails: Data, -ToolDetails: Data, -Options: Data, -Error: Data) -> Data:
  Callback.Callback<StreamInput<DiagnosticDetails, ToolDetails, Options>, Result<&2, &1, Error, StreamLease<DiagnosticDetails, Error>>>

# systemPrompt is derived from messages by agent-state.systemPrompt.
# Runtime ownership and borrowed callbacks remain outside this value snapshot.
type AgentState<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  AgentState{model: Ai.Model<Ai.JsonValue>, thinkingLevel: ThinkingLevel(), tools: List<&2, AgentTool<Details, Error>>, messages: List<&2, AgentMessage<DiagnosticDetails, Details, Custom>>, isStreaming: Bool, streamingMessage: Maybe<&2, AgentMessage<DiagnosticDetails, Details, Custom>>, pendingToolCalls: Set.StringSet, errorMessage: Maybe<&2, String>}

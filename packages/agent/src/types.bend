import Base
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/ref.bend as Ref

# Source: pi-mono packages/agent/src/types.ts at 46c9de402. This initial portion
# covers tool definitions/results, messages, events and hook result records.
# Agent state accessors, context and loop configuration remain pending. Raw arguments, abort signals and thrown errors retain explicit
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
# transcript.toToolDeclaration owns the subsequent schema snapshot operation.
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
# Standard messages keep the original shared object handles; custom messages
# are also shared so retained events observe application mutations.
type AgentMessage<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -ToolDetails: Data, -Custom: Data> is Data:
  LlmMessage{value: Ai.Message<Parameters, Arguments, DiagnosticDetails, ToolDetails>}
  CustomMessage{value: Ref.Ref<Custom>}

# Extract<AssistantMessage["content"][number], {type: "toolCall"}> preserves
# the existing tool-call object, including its raw argument payload.
def AgentToolCall(-Arguments: Data) -> Data: Ref.Ref<Ai.ToolCall<Arguments>>

type BeforeToolCallResult is Data:
  BeforeToolCallResult{block: Maybe<&2, Bool>, reason: Maybe<&2, String>, terminate: Maybe<&2, Bool>}

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
  TurnEnd{message: AgentMessage<Parameters, Arguments, DiagnosticDetails, ToolDetails, Custom>, toolResults: List<&2, Ref.Ref<Ai.ToolResultMessage<ToolDetails>>>}
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

import Base
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as Callback

# Source: pi-mono packages/agent/src/types.ts at 46c9de402. This initial portion
# covers tool definitions/results. Agent state, context, events and loop config
# remain pending. Raw arguments, abort signals and thrown errors retain explicit
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

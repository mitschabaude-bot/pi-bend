import Base
import ./types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/transcript.bend as Transcript
import ../../runtime/src/f64.bend as F
import ../../runtime/src/string-set.bend as Set

# Pure state transitions from agent.ts. The Agent owner provides synchronization
# and waits for listeners before applying finishRun; agent_end alone is not idle.
type AgentInitialState<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data> is Data:
  AgentInitialState{systemPrompt: Maybe<&2, String>, model: Maybe<&2, Ai.Model<Value>>, thinkingLevel: Maybe<&2, T.ThinkingLevel()>, tools: Maybe<&2, List<&2, T.AgentTool<Parameters, Validated, Details, Arguments, Signal, Error>>>, messages: Maybe<&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>}

def defaultModel(-Value: Data) -> Ai.Model<Value>:
  +zero = F.fromU32(0)
  Ai.Model{"unknown", "unknown", Ai.CustomModelApi{"unknown"}, "unknown", "", False{}, None{}, Nil{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, zero, zero, None{}, None{}, None{}}

def defaultConvertToLlm(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, messages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, Details>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{value} <> rest: value <> defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, rest)
    case T.CustomMessage{_} <> rest: defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, rest)

def declarations(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, tools: List<&2, T.AgentTool<Parameters, Validated, Details, Arguments, Signal, Error>>) -> List<&2, Ai.Tool<Parameters>>:
  match tools:
    case Nil{}: Nil{}
    case tool <> rest: T.toTool(Parameters, Validated, Details, Arguments, Signal, Error, tool) <> declarations(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, rest)

def prependInitial(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, initial: Maybe<&2, Ai.SystemMessage<Parameters>>, messages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match initial:
    case None{}: messages
    case Some{value}: T.LlmMessage{Ai.System{value}} <> messages

def initialMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, prompt: Maybe<&2, String>, tools: List<&2, Ai.Tool<Parameters>>, messages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match messages:
    case T.LlmMessage{Ai.System{value}} <> rest: T.LlmMessage{Ai.System{value}} <> rest
    case other: prependInitial(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Transcript.createInitialSystemMessage(Parameters, prompt, Some{tools}), other)

def create(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, initial: AgentInitialState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match initial:
    case AgentInitialState{prompt, model, thinking, tools, messages}:
      +selectedTools = Maybe.default(&2, List<&2, T.AgentTool<Parameters, Validated, Details, Arguments, Signal, Error>>, tools, Nil{})
      T.AgentState{Maybe.default(&2, Ai.Model<Value>, model, defaultModel(Value)), Maybe.default(&2, T.ThinkingLevel(), thinking, Ai.Off{}), selectedTools, initialMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, prompt, declarations(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, selectedTools), Maybe.default(&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, messages, Nil{})), False{}, None{}, Set.empty(), None{}}

def systemPrompt(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, state: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> String:
  match state:
    case T.AgentState{_, _, _, messages, _, _, _, _}: Transcript.getCurrentSystemPrompt(Parameters, Arguments, DiagnosticDetails, Details, defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, messages))

def beginRun(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, state: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match state:
    case T.AgentState{model, thinking, tools, messages, _, _, pending, _}: T.AgentState{model, thinking, tools, messages, True{}, None{}, pending, None{}}

def finishRun(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, state: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match state:
    case T.AgentState{model, thinking, tools, messages, _, _, _, error}: T.AgentState{model, thinking, tools, messages, False{}, None{}, Set.empty(), error}

def nonemptyError(previous: Maybe<&2, String>, incoming: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case None{}: previous
    case Some{+text}: Bool.pick(Maybe<&2, String>, String.is_empty(text), previous, Some{text})

def turnError(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, previous: Maybe<&2, String>, message: T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>) -> Maybe<&2, String>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, error, _, _, _}}}: nonemptyError(previous, error)
    case _: previous

def processEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -PartialResult: Data, -ExecutionResult: Data, state: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>, event: T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match state event:
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageStart{message}: T.AgentState{model, thinking, tools, messages, streaming, Some{message}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageUpdate{message, _}: T.AgentState{model, thinking, tools, messages, streaming, Some{message}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageEnd{message}: T.AgentState{model, thinking, tools, List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, messages, message <> Nil{}), streaming, None{}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.ToolExecutionStart{id, _, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, Set.insert(pending, id), error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.ToolExecutionEnd{id, _, _, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, Set.remove(pending, id), error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.TurnEnd{message, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, pending, turnError(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, error, message)}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.AgentEnd{_}: T.AgentState{model, thinking, tools, messages, streaming, None{}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} _: T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error}

# Replays the transcript baseline, retaining model/thinking and executable tools.
# The synchronized owner rejects reset during a run and clears both queues.
def reset(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, state: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match state:
    case T.AgentState{model, thinking, tools, messages, _, _, _, _}:
      baseline = Transcript.getCurrentSystemMessage(Parameters, Arguments, DiagnosticDetails, Details, defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, messages))
      T.AgentState{model, thinking, tools, prependInitial(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, baseline, Nil{}), False{}, None{}, Set.empty(), None{}}

import Base
import ../packages/agent/src/agent-state.bend as State
import ../packages/agent/src/types.bend as T
import ../packages/ai/src/types.bend as Ai

type Messages<-P: Data, -A: Data, -G: Data, -D: Data, -C: Data> is Data:
  Messages{history: List<&2, T.AgentMessage<P, A, G, D, C>>, partial: Maybe<&2, T.AgentMessage<P, A, G, D, C>>}

def messages(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>) -> Messages<P, A, G, D, C>:
  match state:
    case T.AgentState{_, _, _, history, _, partial, _, _}: Messages{history, partial}

def partial(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, before: Messages<P, A, G, D, C>, message: T.AgentMessage<P, A, G, D, C>) -> Messages<P, A, G, D, C>:
  match before:
    case Messages{history, _}: Messages{history, Some{message}}

def completed(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, before: Messages<P, A, G, D, C>, message: T.AgentMessage<P, A, G, D, C>) -> Messages<P, A, G, D, C>:
  match before:
    case Messages{history, _}: Messages{List.append(&2, T.AgentMessage<P, A, G, D, C>, history, message <> Nil{}), None{}}

law message_start:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for +message: T.AgentMessage<P, A, G, D, C>
  {messages(P, A, G, D, C, V, S, E, J, State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, T.MessageStart{message})) == partial(P, A, G, D, C, messages(P, A, G, D, C, V, S, E, J, state), message) : Messages<P, A, G, D, C>}

law message_update:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for +message: T.AgentMessage<P, A, G, D, C>
  for detail: Ai.AssistantMessageEvent<A, G>
  {messages(P, A, G, D, C, V, S, E, J, State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, T.MessageUpdate{message, detail})) == partial(P, A, G, D, C, messages(P, A, G, D, C, V, S, E, J, state), message) : Messages<P, A, G, D, C>}

law message_end:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for +message: T.AgentMessage<P, A, G, D, C>
  {messages(P, A, G, D, C, V, S, E, J, State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, T.MessageEnd{message})) == completed(P, A, G, D, C, messages(P, A, G, D, C, V, S, E, J, state), message) : Messages<P, A, G, D, C>}

# Loop events cannot edit configuration or declare the run idle. The owner
# settles listeners and calls finishRun separately.
type Configuration<-P: Data, -A: Data, -D: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  Configuration{model: Ai.Model<J>, thinking: T.ThinkingLevel(), tools: List<&2, T.AgentTool<P, V, D, A, S, E>>, streaming: Bool}

def configuration(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>) -> Configuration<P, A, D, V, S, E, J>:
  match state:
    case T.AgentState{model, thinking, tools, _, streaming, _, _, _}: Configuration{model, thinking, tools, streaming}

law events_preserve_configuration:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for event: T.AgentEvent<P, A, G, D, C, Partial, Execution>
  {configuration(P, A, G, D, C, V, S, E, J, State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, event)) == configuration(P, A, G, D, C, V, S, E, J, state) : Configuration<P, A, D, V, S, E, J>}

def ended(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, before: Messages<P, A, G, D, C>) -> Messages<P, A, G, D, C>:
  match before:
    case Messages{history, _}: Messages{history, None{}}

law agent_end:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for reported: List<&2, T.AgentMessage<P, A, G, D, C>>
  {messages(P, A, G, D, C, V, S, E, J, State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, T.AgentEnd{reported})) == ended(P, A, G, D, C, messages(P, A, G, D, C, V, S, E, J, state)) : Messages<P, A, G, D, C>}

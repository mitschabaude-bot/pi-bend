import Base
import ../packages/agent/src/agent.bend as State
import ../packages/runtime/src/string.bend as Set
import ../packages/agent/src/agent.bend as Runtime
import ../packages/agent/src/agent.bend as Q
import ../packages/agent/src/types.bend as T
import ../packages/agent/src/agent.bend as Queues
import ../packages/agent/src/agent.bend as Queue
import ../packages/ai/src/types.bend as Ai

# Agent owner

# Observe the complete agent state returned by an owner transition.
def resultingState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Result: Type, result: Runtime.OwnedState<P, A, G, D, C, V, S, E, J> & Result) -> T.AgentState<P, A, G, D, C, V, S, E, J>:
  match result:
    case Tuple{owned, _}: Runtime.stateValue(P, A, G, D, C, V, S, E, J, owned)

law enqueue_preserves_state:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +owned: Runtime.OwnedState<P, A, G, D, C, V, S, E, J>
  for kind: Q.QueueKind
  for message: T.AgentMessage<P, A, G, D, C>
  {resultingState(P, A, G, D, C, V, S, E, J, Unit, Runtime.enqueueState(P, A, G, D, C, V, S, E, J, owned, kind, message)) == Runtime.stateValue(P, A, G, D, C, V, S, E, J, owned) : T.AgentState<P, A, G, D, C, V, S, E, J>}

law queue_update_preserves_state:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +owned: Runtime.OwnedState<P, A, G, D, C, V, S, E, J>
  for update: Q.Queues<T.AgentMessage<P, A, G, D, C>> -> Q.Queues<T.AgentMessage<P, A, G, D, C>>
  {resultingState(P, A, G, D, C, V, S, E, J, Unit, Runtime.updatedQueues(P, A, G, D, C, V, S, E, J, owned, update)) == Runtime.stateValue(P, A, G, D, C, V, S, E, J, owned) : T.AgentState<P, A, G, D, C, V, S, E, J>}

law drain_preserves_state:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +owned: Runtime.OwnedState<P, A, G, D, C, V, S, E, J>
  for kind: Q.QueueKind
  {resultingState(P, A, G, D, C, V, S, E, J, List<&2, T.AgentMessage<P, A, G, D, C>>, Runtime.drainState(P, A, G, D, C, V, S, E, J, owned, kind)) == Runtime.stateValue(P, A, G, D, C, V, S, E, J, owned) : T.AgentState<P, A, G, D, C, V, S, E, J>}

type RunState<-P: Data, -A: Data, -G: Data, -D: Data, -C: Data> is Data:
  RunState{streaming: Bool, current: Maybe<&2, T.AgentMessage<P, A, G, D, C>>, pending: Set.StringSet, error: Maybe<&2, String>}

def runState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>) -> RunState<P, A, G, D, C>:
  match state:
    case T.AgentState{_, _, _, _, streaming, current, pending, error}: RunState{streaming, current, pending, error}

law changes_preserve_run_state:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for change: State.StateChange<P, A, G, D, C, V, S, E, J>
  {runState(P, A, G, D, C, V, S, E, J, State.applyChange(P, A, G, D, C, V, S, E, J, state, change)) == runState(P, A, G, D, C, V, S, E, J, state) : RunState<P, A, G, D, C>}

law replace_messages:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for +messages: List<&2, T.AgentMessage<P, A, G, D, C>>
  {Runtime.history(P, A, G, D, C, V, S, E, J, State.applyChange(P, A, G, D, C, V, S, E, J, state, State.ReplaceMessages{messages})) == messages : List<&2, T.AgentMessage<P, A, G, D, C>>}

law append_message:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for +message: T.AgentMessage<P, A, G, D, C>
  {Runtime.history(P, A, G, D, C, V, S, E, J, State.applyChange(P, A, G, D, C, V, S, E, J, state, State.AppendMessage{message})) == List.append(&2, T.AgentMessage<P, A, G, D, C>, Runtime.history(P, A, G, D, C, V, S, E, J, state), message <> Nil{}) : List<&2, T.AgentMessage<P, A, G, D, C>>}


# Agent queues

def selected(-A: Data, queues: Queues.Queues<A>, kind: Queues.QueueKind) -> Queue.PendingMessageQueue<A>:
  match queues kind:
    case Queues.Queues{steering, _} Queues.QueuesSteering{}: steering
    case Queues.Queues{_, followUp} Queues.FollowUp{}: followUp

def other(-A: Data, queues: Queues.Queues<A>, kind: Queues.QueueKind) -> Queue.PendingMessageQueue<A>:
  match queues kind:
    case Queues.Queues{_, followUp} Queues.QueuesSteering{}: followUp
    case Queues.Queues{steering, _} Queues.FollowUp{}: steering

def remainingQueues(-A: Data, result: Queues.Queues<A> & List<&2, A>) -> Queues.Queues<A>:
  match result:
    case Tuple{queues, _}: queues

law enqueue_selected:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  for +value: A
  {selected(A, Queues.enqueueQueues(A, queues, kind, value), kind) == Queue.enqueuePending(A, selected(A, queues, kind), value) : Queue.PendingMessageQueue<A>}

law enqueue_isolated:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  for value: A
  {other(A, Queues.enqueueQueues(A, queues, kind, value), kind) == other(A, queues, kind) : Queue.PendingMessageQueue<A>}

law clear_selected:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  {selected(A, Queues.clearQueues(A, queues, kind), kind) == Queue.clearPending(A, selected(A, queues, kind)) : Queue.PendingMessageQueue<A>}

law clear_isolated:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  {other(A, Queues.clearQueues(A, queues, kind), kind) == other(A, queues, kind) : Queue.PendingMessageQueue<A>}

law mode_selected:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  for mode: T.QueueMode
  {selected(A, Queues.setModeQueues(A, queues, kind, mode), kind) == Queue.setModePending(A, selected(A, queues, kind), mode) : Queue.PendingMessageQueue<A>}

law mode_isolated:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  for mode: T.QueueMode
  {other(A, Queues.setModeQueues(A, queues, kind, mode), kind) == other(A, queues, kind) : Queue.PendingMessageQueue<A>}

law drain_isolated:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  {other(A, remainingQueues(A, Queues.drainQueues(A, queues, kind)), kind) == other(A, queues, kind) : Queue.PendingMessageQueue<A>}

type SelectedDelivery<-A: Data> is Data:
  SelectedDelivery{remaining: Queue.PendingMessageQueue<A>, emitted: List<&2, A>}

def selectedDelivery(-A: Data, kind: Queues.QueueKind, result: Queues.Queues<A> & List<&2, A>) -> SelectedDelivery<A>:
  match result:
    case Tuple{queues, emitted}: SelectedDelivery{selected(A, queues, kind), emitted}

def singleDelivery(-A: Data, result: Queue.PendingMessageQueue<A> & List<&2, A>) -> SelectedDelivery<A>:
  match result:
    case Tuple{queue, emitted}: SelectedDelivery{queue, emitted}

law drain_selected:
  for -A: Data
  for +queues: Queues.Queues<A>
  for +kind: Queues.QueueKind
  {selectedDelivery(A, kind, Queues.drainQueues(A, queues, kind)) == singleDelivery(A, Queue.drainPending(A, selected(A, queues, kind))) : SelectedDelivery<A>}


# Pending queue

type Snapshot<-A: Data> is Data:
  Snapshot{mode: T.QueueMode, values: List<&2, A>}

def snapshot(-A: Data, +queue: Queue.PendingMessageQueue<A>) -> Snapshot<A>:
  Snapshot{Queue.getModePending(A, queue), Queue.values(A, queue)}

def appended(-A: Data, state: Snapshot<A>, value: A) -> Snapshot<A>:
  match state:
    case Snapshot{mode, values}: Snapshot{mode, List.append(&2, A, values, value <> Nil{})}

def withMode(-A: Data, state: Snapshot<A>, mode: T.QueueMode) -> Snapshot<A>:
  match state:
    case Snapshot{_, values}: Snapshot{mode, values}

def cleared(-A: Data, state: Snapshot<A>) -> Snapshot<A>:
  match state:
    case Snapshot{mode, _}: Snapshot{mode, Nil{}}

type Delivery<-A: Data> is Data:
  Delivery{remaining: Snapshot<A>, emitted: List<&2, A>}

def observe(-A: Data, result: Queue.PendingMessageQueue<A> & List<&2, A>) -> Delivery<A>:
  match result:
    case Tuple{remaining, emitted}: Delivery{snapshot(A, remaining), emitted}

# List-level delivery policy, independent of FIFO representation and helpers.
def delivered(-A: Data, state: Snapshot<A>) -> Delivery<A>:
  match state:
    case Snapshot{T.All{}, values}: Delivery{Snapshot{T.All{}, Nil{}}, values}
    case Snapshot{T.OneAtATime{}, Nil{}}: Delivery{Snapshot{T.OneAtATime{}, Nil{}}, Nil{}}
    case Snapshot{T.OneAtATime{}, head <> tail}: Delivery{Snapshot{T.OneAtATime{}, tail}, head <> Nil{}}

law empty:
  for -A: Data
  for mode: T.QueueMode
  {snapshot(A, Queue.newPending(A, mode)) == Snapshot{mode, Nil{}} : Snapshot<A>}

law enqueue:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  for +value: A
  {snapshot(A, Queue.enqueuePending(A, queue, value)) == appended(A, snapshot(A, queue), value) : Snapshot<A>}

law set_mode:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  for mode: T.QueueMode
  {snapshot(A, Queue.setModePending(A, queue, mode)) == withMode(A, snapshot(A, queue), mode) : Snapshot<A>}

law clear:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  {snapshot(A, Queue.clearPending(A, queue)) == cleared(A, snapshot(A, queue)) : Snapshot<A>}

law drain:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  {observe(A, Queue.drainPending(A, queue)) == delivered(A, snapshot(A, queue)) : Delivery<A>}

law has_items:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  {Queue.hasItems(A, queue) == Bool.not(List.is_empty(&2, A, Queue.values(A, queue))) : Bool}


# Agent events

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

def pending(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>) -> Set.StringSet:
  match state:
    case T.AgentState{_, _, _, _, _, _, tools, _}: tools

def error(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>) -> Maybe<&2, String>:
  match state:
    case T.AgentState{_, _, _, _, _, _, _, value}: value

law tool_start_membership:
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
  for state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for +id: String
  for name: String
  for arguments: A
  {Set.contains(pending(P, A, G, D, C, V, S, E, J, State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, T.ToolExecutionStart{id, name, arguments})), id) == True{} : Bool}

law tool_end_membership:
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
  for state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for +id: String
  for name: String
  for result: Execution
  for failed: Bool
  {Set.contains(pending(P, A, G, D, C, V, S, E, J, State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, T.ToolExecutionEnd{id, name, result, failed})), id) == False{} : Bool}

law finish_idle:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  {runState(P, A, G, D, C, V, S, E, J, State.finishRunState(P, A, G, D, C, V, S, E, J, state)) == RunState{False{}, None{}, Set.empty(), error(P, A, G, D, C, V, S, E, J, state)} : RunState<P, A, G, D, C>}

law finish_messages:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  {messages(P, A, G, D, C, V, S, E, J, State.finishRunState(P, A, G, D, C, V, S, E, J, state)) == ended(P, A, G, D, C, messages(P, A, G, D, C, V, S, E, J, state)) : Messages<P, A, G, D, C>}

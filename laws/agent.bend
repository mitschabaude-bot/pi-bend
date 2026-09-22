import Base
import ../packages/agent/src/agent.bend as State
import ../packages/runtime/src/string.bend as Set
import ../packages/agent/src/agent.bend as Runtime
import ../packages/agent/src/agent.bend as Q
import ../packages/agent/src/types.bend as T
import ../packages/agent/src/agent.bend as Queues
import ../packages/agent/src/agent.bend as Queue
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/schema-value.bend as Schema
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/fetch.bend as Fetch

# Agent owner

# Observe the complete agent state returned by an owner transition.
def resultingState(-G: Data, -D: Data, -C: Data, -E: Data, -Result: Type, result: Runtime.OwnedState<G, D, C, E> & Result) -> T.AgentState<G, D, C, E>:
  match result:
    case Tuple{owned, _}: Runtime.stateValue(G, D, C, E, owned)

law enqueue_preserves_state:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for +owned: Runtime.OwnedState<G, D, C, E>
  for kind: Q.QueueKind
  for message: T.AgentMessage<G, D, C>
  {resultingState(G, D, C, E, Unit, Runtime.enqueueState(G, D, C, E, owned, kind, message)) == Runtime.stateValue(G, D, C, E, owned) : T.AgentState<G, D, C, E>}

law queue_update_preserves_state:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for +owned: Runtime.OwnedState<G, D, C, E>
  for update: Q.Queues<T.AgentMessage<G, D, C>> -> Q.Queues<T.AgentMessage<G, D, C>>
  {resultingState(G, D, C, E, Unit, Runtime.updatedQueues(G, D, C, E, owned, update)) == Runtime.stateValue(G, D, C, E, owned) : T.AgentState<G, D, C, E>}

law drain_preserves_state:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for +owned: Runtime.OwnedState<G, D, C, E>
  for kind: Q.QueueKind
  {resultingState(G, D, C, E, List<&2, T.AgentMessage<G, D, C>>, Runtime.drainState(G, D, C, E, owned, kind)) == Runtime.stateValue(G, D, C, E, owned) : T.AgentState<G, D, C, E>}

type RunState<-G: Data, -D: Data, -C: Data> is Data:
  RunState{streaming: Bool, current: Maybe<&2, T.AgentMessage<G, D, C>>, pending: Set.StringSet, error: Maybe<&2, String>}

def runState(-G: Data, -D: Data, -C: Data, -E: Data, state: T.AgentState<G, D, C, E>) -> RunState<G, D, C>:
  match state:
    case T.AgentState{_, _, _, _, streaming, current, pending, error}: RunState{streaming, current, pending, error}

law changes_preserve_run_state:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for +state: T.AgentState<G, D, C, E>
  for change: State.StateChange<G, D, C, E>
  {runState(G, D, C, E, State.applyChange(G, D, C, E, state, change)) == runState(G, D, C, E, state) : RunState<G, D, C>}

law replace_messages:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for state: T.AgentState<G, D, C, E>
  for +messages: List<&2, T.AgentMessage<G, D, C>>
  {Runtime.history(G, D, C, E, State.applyChange(G, D, C, E, state, State.ReplaceMessages{messages})) == messages : List<&2, T.AgentMessage<G, D, C>>}

law append_message:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for +state: T.AgentState<G, D, C, E>
  for +message: T.AgentMessage<G, D, C>
  {Runtime.history(G, D, C, E, State.applyChange(G, D, C, E, state, State.AppendMessage{message})) == List.append(&2, T.AgentMessage<G, D, C>, Runtime.history(G, D, C, E, state), message <> Nil{}) : List<&2, T.AgentMessage<G, D, C>>}


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

type Messages<-G: Data, -D: Data, -C: Data> is Data:
  Messages{history: List<&2, T.AgentMessage<G, D, C>>, partial: Maybe<&2, T.AgentMessage<G, D, C>>}

def messages(-G: Data, -D: Data, -C: Data, -E: Data, state: T.AgentState<G, D, C, E>) -> Messages<G, D, C>:
  match state:
    case T.AgentState{_, _, _, history, _, partial, _, _}: Messages{history, partial}

def partial(-G: Data, -D: Data, -C: Data, before: Messages<G, D, C>, message: T.AgentMessage<G, D, C>) -> Messages<G, D, C>:
  match before:
    case Messages{history, _}: Messages{history, Some{message}}

def completed(-G: Data, -D: Data, -C: Data, before: Messages<G, D, C>, message: T.AgentMessage<G, D, C>) -> Messages<G, D, C>:
  match before:
    case Messages{history, _}: Messages{List.append(&2, T.AgentMessage<G, D, C>, history, message <> Nil{}), None{}}

law message_start:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<G, D, C, E>
  for +message: T.AgentMessage<G, D, C>
  {messages(G, D, C, E, State.processEvent(G, D, C, E, Partial, Execution, state, T.MessageStart{message})) == partial(G, D, C, messages(G, D, C, E, state), message) : Messages<G, D, C>}

law message_update:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<G, D, C, E>
  for +message: T.AgentMessage<G, D, C>
  for detail: Ai.AssistantMessageEvent<Schema.Value, G>
  {messages(G, D, C, E, State.processEvent(G, D, C, E, Partial, Execution, state, T.MessageUpdate{message, detail})) == partial(G, D, C, messages(G, D, C, E, state), message) : Messages<G, D, C>}

law message_end:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<G, D, C, E>
  for +message: T.AgentMessage<G, D, C>
  {messages(G, D, C, E, State.processEvent(G, D, C, E, Partial, Execution, state, T.MessageEnd{message})) == completed(G, D, C, messages(G, D, C, E, state), message) : Messages<G, D, C>}

# Loop events cannot edit configuration or declare the run idle. The owner
# settles listeners and calls finishRun separately.
type Configuration<-D: Data, -E: Data> is Data:
  Configuration{model: Ai.Model<Ai.JsonValue>, thinking: T.ThinkingLevel(), tools: List<&2, T.AgentTool<D, E>>, streaming: Bool}

def configuration(-G: Data, -D: Data, -C: Data, -E: Data, state: T.AgentState<G, D, C, E>) -> Configuration<D, E>:
  match state:
    case T.AgentState{model, thinking, tools, _, streaming, _, _, _}: Configuration{model, thinking, tools, streaming}

law events_preserve_configuration:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<G, D, C, E>
  for event: T.AgentEvent<G, D, C, Partial, Execution>
  {configuration(G, D, C, E, State.processEvent(G, D, C, E, Partial, Execution, state, event)) == configuration(G, D, C, E, state) : Configuration<D, E>}

def ended(-G: Data, -D: Data, -C: Data, before: Messages<G, D, C>) -> Messages<G, D, C>:
  match before:
    case Messages{history, _}: Messages{history, None{}}

law agent_end:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for -Partial: Data
  for -Execution: Data
  for +state: T.AgentState<G, D, C, E>
  for reported: List<&2, T.AgentMessage<G, D, C>>
  {messages(G, D, C, E, State.processEvent(G, D, C, E, Partial, Execution, state, T.AgentEnd{reported})) == ended(G, D, C, messages(G, D, C, E, state)) : Messages<G, D, C>}

def pending(-G: Data, -D: Data, -C: Data, -E: Data, state: T.AgentState<G, D, C, E>) -> Set.StringSet:
  match state:
    case T.AgentState{_, _, _, _, _, _, tools, _}: tools

def error(-G: Data, -D: Data, -C: Data, -E: Data, state: T.AgentState<G, D, C, E>) -> Maybe<&2, String>:
  match state:
    case T.AgentState{_, _, _, _, _, _, _, value}: value

law tool_start_membership:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for -Partial: Data
  for -Execution: Data
  for state: T.AgentState<G, D, C, E>
  for +id: String
  for name: String
  for arguments: Schema.Value
  {Set.contains(pending(G, D, C, E, State.processEvent(G, D, C, E, Partial, Execution, state, T.ToolExecutionStart{id, name, arguments})), id) == True{} : Bool}

law tool_end_membership:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for -Partial: Data
  for -Execution: Data
  for state: T.AgentState<G, D, C, E>
  for +id: String
  for name: String
  for result: Execution
  for failed: Bool
  {Set.contains(pending(G, D, C, E, State.processEvent(G, D, C, E, Partial, Execution, state, T.ToolExecutionEnd{id, name, result, failed})), id) == False{} : Bool}

law finish_idle:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for +state: T.AgentState<G, D, C, E>
  {runState(G, D, C, E, State.finishRunState(G, D, C, E, state)) == RunState{False{}, None{}, Set.empty(), error(G, D, C, E, state)} : RunState<G, D, C>}

law finish_messages:
  for -G: Data
  for -D: Data
  for -C: Data
  for -E: Data
  for +state: T.AgentState<G, D, C, E>
  {messages(G, D, C, E, State.finishRunState(G, D, C, E, state)) == ended(G, D, C, messages(G, D, C, E, state)) : Messages<G, D, C>}


# Continue planning: pi's continue() as a pure decision over the transcript
# tail and the two pending queues.

def Agent(-G: Data, -D: Data, -C: Data) -> Data: T.AgentMessage<G, D, C>

def systemsOf(-G: Data, -D: Data, -C: Data, systems: List<&2, Ai.SystemMessage<Schema.Value>>) -> List<&2, T.AgentMessage<G, D, C>>:
  match systems:
    case Nil{}: Nil{}
    case system <> rest: T.LlmMessage{Ai.System{system}} <> systemsOf(G, D, C, rest)

law busy_agents_cannot_continue:
  for -G: Data
  for -D: Data
  for -C: Data
  for messages: List<&2, Agent(G, D, C)>
  for queues: Runtime.Queues<Agent(G, D, C)>
  {Runtime.continuationPlan(G, D, C, True{}, messages, queues) == (queues, Fail{Runtime.ContinueBusy{}}) : Runtime.Queues<Agent(G, D, C)> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<Agent(G, D, C)>>}

law system_only_transcripts_cannot_continue:
  for -G: Data
  for -D: Data
  for -C: Data
  for systems: List<&2, Ai.SystemMessage<Schema.Value>>
  for queues: Runtime.Queues<Agent(G, D, C)>
  {Runtime.continuationPlan(G, D, C, False{}, systemsOf(G, D, C, systems), queues) == (queues, Fail{Runtime.NoMessages{}}) : Runtime.Queues<Agent(G, D, C)> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<Agent(G, D, C)>>}

law continue_after_a_user_message_resumes_the_run:
  for -G: Data
  for -D: Data
  for -C: Data
  for messages: List<&2, Agent(G, D, C)>
  for user: Ai.UserMessage
  for queues: Runtime.Queues<Agent(G, D, C)>
  {Runtime.continuationPlan(G, D, C, False{}, List.append(&2, Agent(G, D, C), messages, T.LlmMessage{Ai.User{user}} <> Nil{}), queues) == (queues, Done{Runtime.Continue{}}) : Runtime.Queues<Agent(G, D, C)> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<Agent(G, D, C)>>}

law continue_after_assistant_prefers_steering:
  for -M: Data
  for mode: T.QueueMode
  for followUp: Runtime.PendingMessageQueue<M>
  for message: M
  {Runtime.planTail(M, Runtime.enqueueQueues(M, Runtime.Queues{Runtime.newPending(M, mode), followUp}, Runtime.QueuesSteering{}, message), Runtime.Assistant{}) == (Runtime.Queues{Runtime.newPending(M, mode), followUp}, Done{Runtime.Prompt{message <> Nil{}, True{}}}) : Runtime.Queues<M> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<M>>}

law continue_after_assistant_falls_back_to_follow_ups:
  for -M: Data
  for steeringMode: T.QueueMode
  for followUpMode: T.QueueMode
  for message: M
  {Runtime.planTail(M, Runtime.Queues{Runtime.newPending(M, steeringMode), Runtime.enqueuePending(M, Runtime.newPending(M, followUpMode), message)}, Runtime.Assistant{}) == (Runtime.Queues{Runtime.newPending(M, steeringMode), Runtime.newPending(M, followUpMode)}, Done{Runtime.Prompt{message <> Nil{}, False{}}}) : Runtime.Queues<M> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<M>>}

law continue_after_assistant_with_empty_queues_fails:
  for -M: Data
  for steeringMode: T.QueueMode
  for followUpMode: T.QueueMode
  {Runtime.planTail(M, Runtime.Queues{Runtime.newPending(M, steeringMode), Runtime.newPending(M, followUpMode)}, Runtime.Assistant{}) == (Runtime.Queues{Runtime.newPending(M, steeringMode), Runtime.newPending(M, followUpMode)}, Fail{Runtime.AssistantTail{}}) : Runtime.Queues<M> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<M>>}

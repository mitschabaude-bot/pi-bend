import Base
import ../packages/agent/src/agent.bend as State
import ../laws/agent.bend as Laws
import ../packages/agent/src/agent.bend as Runtime
import ../packages/agent/src/agent.bend as Q
import ../packages/agent/src/types.bend as T
import ../packages/agent/src/agent.bend as Queues
import ../packages/agent/src/agent.bend as Queue
import ./fifo.bend as FifoProof
import ../laws/fifo.bend as FifoLaws
import ../packages/runtime/src/fifo.bend as Fifo
import ./string.bend as SetProof
import ../laws/string.bend as SetLaws
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/schema-value.bend as Schema
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/fetch.bend as Fetch

# Agent owner

def Laws.enqueue_preserves_state(G, D, C, E, owned, kind, message):
  match owned:
    case Runtime.OwnedState{_, _}: {==}

def Laws.queue_update_preserves_state(G, D, C, E, owned, update):
  match owned:
    case Runtime.OwnedState{_, _}: {==}

law drained_preserves_state:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for -C: Data
  for -V: Data
  for -S: Data
  for -E: Data
  for -J: Data
  for +state: T.AgentState<G, D, C, E>
  for result: Q.Queues<T.AgentMessage<G, D, C>> & List<&2, T.AgentMessage<G, D, C>>
  {Laws.resultingState(G, D, C, E, List<&2, T.AgentMessage<G, D, C>>, Runtime.drainedRuntime(G, D, C, E, state, result)) == state : T.AgentState<G, D, C, E>}

def drained_preserves_state(P, A, G, D, C, V, S, E, J, state, result):
  match result:
    case Tuple{_, _}: {==}

def Laws.drain_preserves_state(G, D, C, E, owned, kind):
  match owned:
    case Runtime.OwnedState{state, queues}: drained_preserves_state(Schema.Value, Schema.Value, G, D, C, Schema.Value, Abort.AbortSignal<Unit>, E, Ai.JsonValue, state, Q.drainQueues(T.AgentMessage<G, D, C>, queues, kind))

def Laws.changes_preserve_run_state(G, D, C, E, state, change):
  match state change:
    case T.AgentState{_, _, _, _, _, _, _, _} State.SetModel{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.SetThinkingLevel{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.SetTools{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.ReplaceMessages{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.AppendMessage{_}: {==}

def Laws.replace_messages(G, D, C, E, state, messages):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.append_message(G, D, C, E, state, message):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}


# Agent queues

def Laws.enqueue_selected(A, queues, kind, value):
  match queues kind:
    case Queues.Queues{_, _} Queues.QueuesSteering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.enqueue_isolated(A, queues, kind, value):
  match queues kind:
    case Queues.Queues{_, _} Queues.QueuesSteering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.clear_selected(A, queues, kind):
  match queues kind:
    case Queues.Queues{_, _} Queues.QueuesSteering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.clear_isolated(A, queues, kind):
  match queues kind:
    case Queues.Queues{_, _} Queues.QueuesSteering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.mode_selected(A, queues, kind, mode):
  match queues kind:
    case Queues.Queues{_, _} Queues.QueuesSteering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.mode_isolated(A, queues, kind, mode):
  match queues kind:
    case Queues.Queues{_, _} Queues.QueuesSteering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

law delivered_isolated:
  for -A: Data
  for +kind: Queues.QueueKind
  for +untouched: Queue.PendingMessageQueue<A>
  for result: Queue.PendingMessageQueue<A> & List<&2, A>
  {Laws.other(A, Laws.remainingQueues(A, Queues.drainedQueues(A, kind, untouched, result)), kind) == untouched : Queue.PendingMessageQueue<A>}

def delivered_isolated(A, kind, untouched, result):
  match kind result:
    case Queues.QueuesSteering{} Tuple{_, _}: {==}
    case Queues.FollowUp{} Tuple{_, _}: {==}

def Laws.drain_isolated(A, queues, kind):
  match queues kind:
    case Queues.Queues{steering, followUp} Queues.QueuesSteering{}: delivered_isolated(A, Queues.QueuesSteering{}, followUp, Queue.drainPending(A, steering))
    case Queues.Queues{steering, followUp} Queues.FollowUp{}: delivered_isolated(A, Queues.FollowUp{}, steering, Queue.drainPending(A, followUp))

law delivered_selected:
  for -A: Data
  for +kind: Queues.QueueKind
  for untouched: Queue.PendingMessageQueue<A>
  for result: Queue.PendingMessageQueue<A> & List<&2, A>
  {Laws.selectedDelivery(A, kind, Queues.drainedQueues(A, kind, untouched, result)) == Laws.singleDelivery(A, result) : Laws.SelectedDelivery<A>}

def delivered_selected(A, kind, untouched, result):
  match kind result:
    case Queues.QueuesSteering{} Tuple{_, _}: {==}
    case Queues.FollowUp{} Tuple{_, _}: {==}

def Laws.drain_selected(A, queues, kind):
  match queues kind:
    case Queues.Queues{steering, followUp} Queues.QueuesSteering{}: delivered_selected(A, Queues.QueuesSteering{}, followUp, Queue.drainPending(A, steering))
    case Queues.Queues{steering, followUp} Queues.FollowUp{}: delivered_selected(A, Queues.FollowUp{}, steering, Queue.drainPending(A, followUp))


# Pending queue

def Laws.empty(A, mode): {==}

def Laws.enqueue(A, queue, value):
  match queue:
    case Queue.PendingMessageQueue{mode, messages}:
      %FifoLaws.fifo_enqueue(A, messages, value) : {Laws.Snapshot{mode, Fifo.drain(A, Fifo.enqueue(A, messages, value))} == Laws.Snapshot{mode, _} : Laws.Snapshot<A>}
      {==}

def Laws.set_mode(A, queue, mode):
  match queue:
    case Queue.PendingMessageQueue{_, _}: {==}

def Laws.clear(A, queue):
  match queue:
    case Queue.PendingMessageQueue{_, _}: {==}

def one(-A: Data, removal: FifoLaws.Removal<A>) -> Laws.Delivery<A>:
  match removal:
    case FifoLaws.Removal{remaining, None{}}: Laws.Delivery{Laws.Snapshot{T.OneAtATime{}, remaining}, Nil{}}
    case FifoLaws.Removal{remaining, Some{value}}: Laws.Delivery{Laws.Snapshot{T.OneAtATime{}, remaining}, value <> Nil{}}

law one_observation:
  for -A: Data
  for pair: Fifo.Queue<A> & Maybe<&2, A>
  {Laws.observe(A, Queue.drainedOne(A, pair)) == one(A, FifoLaws.observe(A, pair)) : Laws.Delivery<A>}

def one_observation(A, pair):
  match pair:
    case Tuple{_, None{}}: {==}
    case Tuple{_, Some{_}}: {==}

law one_sequence:
  for -A: Data
  for values: List<&2, A>
  {one(A, FifoLaws.uncons(A, values)) == Laws.delivered(A, Laws.Snapshot{T.OneAtATime{}, values}) : Laws.Delivery<A>}

def one_sequence(A, values):
  match values:
    case Nil{}: {==}
    case _ <> _: {==}

def Laws.drain(A, queue):
  match queue:
    case Queue.PendingMessageQueue{T.All{}, _}: {==}
    case Queue.PendingMessageQueue{T.OneAtATime{}, messages}:
      %one_sequence(A, Fifo.drain(A, messages)) : {Laws.observe(A, Queue.drainedOne(A, Fifo.dequeue(A, messages))) == _ : Laws.Delivery<A>}
      %FifoLaws.fifo_dequeue(A, messages) : {Laws.observe(A, Queue.drainedOne(A, Fifo.dequeue(A, messages))) == one(A, _) : Laws.Delivery<A>}
      one_observation(A, Fifo.dequeue(A, messages))

law reverse_nonempty:
  for -A: Data
  for values: List<&2, A>
  for head: A
  for tail: List<&2, A>
  {False{} == List.is_empty(&2, A, List.reverse.go(&2, A, values, head <> tail)) : Bool}

def reverse_nonempty(A, values, head, tail):
  match values:
    case Nil{}: {==}
    case next <> rest: reverse_nonempty(A, rest, next, head <> tail)

def Laws.has_items(A, queue):
  match queue:
    case Queue.PendingMessageQueue{_, Fifo.Queue{Nil{}, Nil{}}}: {==}
    case Queue.PendingMessageQueue{_, Fifo.Queue{head <> tail, Nil{}}}:
      %reverse_nonempty(A, tail, head, Nil{}) : {True{} == Bool.not(_) : Bool}
      {==}
    case Queue.PendingMessageQueue{_, Fifo.Queue{Nil{}, _ <> _}}: {==}
    case Queue.PendingMessageQueue{_, Fifo.Queue{_ <> _, _ <> _}}: {==}


# Agent events

def Laws.message_start(G, D, C, E, Partial, Execution, state, message):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.message_update(G, D, C, E, Partial, Execution, state, message, detail):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.message_end(G, D, C, E, Partial, Execution, state, message):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.events_preserve_configuration(G, D, C, E, Partial, Execution, state, event):
  match state event:
    case T.AgentState{_, _, _, _, _, _, _, _} T.AgentStart{}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.AgentEnd{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.TurnStart{}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.TurnEnd{_, _}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.MessageStart{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.MessageUpdate{_, _}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.MessageEnd{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.ToolExecutionStart{_, _, _}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.ToolExecutionUpdate{_, _, _, _}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} T.ToolExecutionEnd{_, _, _, _}: {==}

def Laws.agent_end(G, D, C, E, Partial, Execution, state, reported):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.tool_start_membership(G, D, C, E, Partial, Execution, state, id, name, arguments):
  match state:
    case T.AgentState{_, _, _, _, _, _, pending, _}: SetLaws.insert_membership(pending, id)

def Laws.tool_end_membership(G, D, C, E, Partial, Execution, state, id, name, result, failed):
  match state:
    case T.AgentState{_, _, _, _, _, _, pending, _}: SetLaws.remove_membership(pending, id)

def Laws.finish_idle(G, D, C, E, state):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.finish_messages(G, D, C, E, state):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}


# Continue planning

def Laws.busy_agents_cannot_continue(G, D, C, messages, queues): {==}

def system_tail(-G: Data, -D: Data, -C: Data, systems: List<&2, Ai.SystemMessage<Schema.Value>>) -> {Runtime.tail(G, D, C, Laws.systemsOf(G, D, C, systems), False{}) == Runtime.Empty{} : Runtime.Tail}:
  match systems:
    case Nil{}: {==}
    case system <> rest:
      match rest:
        case Nil{}: {==}
        case next <> more: system_tail(G, D, C, next <> more)

def Laws.system_only_transcripts_cannot_continue(G, D, C, systems, queues):
  %Equal.sym(Runtime.Tail, Runtime.tail(G, D, C, Laws.systemsOf(G, D, C, systems), False{}), Runtime.Empty{}, system_tail(G, D, C, systems)) : {Runtime.planTail(Laws.Agent(G, D, C), queues, _) == (queues, Fail{Runtime.NoMessages{}}) : Runtime.Queues<Laws.Agent(G, D, C)> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<Laws.Agent(G, D, C)>>}
  {==}

def or_true_is_other(seen: Bool) -> {Bool.pick(Runtime.Tail, Bool.or(seen, True{}), Runtime.Other{}, Runtime.Empty{}) == Runtime.Other{} : Runtime.Tail}:
  match seen:
    case True{}: {==}
    case False{}: {==}

def user_tail(-G: Data, -D: Data, -C: Data, messages: List<&2, Laws.Agent(G, D, C)>, user: Ai.UserMessage, seen: Bool) -> {Runtime.tail(G, D, C, List.append(&2, Laws.Agent(G, D, C), messages, T.LlmMessage{Ai.User{user}} <> Nil{}), seen) == Runtime.Other{} : Runtime.Tail}:
  match messages:
    case Nil{}: or_true_is_other(seen)
    case message <> rest:
      match rest:
        case Nil{}: or_true_is_other(Bool.or(seen, Bool.not(Runtime.isSystem(G, D, C, message))))
        case next <> more: user_tail(G, D, C, next <> more, user, Bool.or(seen, Bool.not(Runtime.isSystem(G, D, C, message))))

def Laws.continue_after_a_user_message_resumes_the_run(G, D, C, messages, user, queues):
  %Equal.sym(Runtime.Tail, Runtime.tail(G, D, C, List.append(&2, Laws.Agent(G, D, C), messages, T.LlmMessage{Ai.User{user}} <> Nil{}), False{}), Runtime.Other{}, user_tail(G, D, C, messages, user, False{})) : {Runtime.planTail(Laws.Agent(G, D, C), queues, _) == (queues, Done{Runtime.Continue{}}) : Runtime.Queues<Laws.Agent(G, D, C)> & Result<&2, &2, Runtime.ContinueError, Runtime.Plan<Laws.Agent(G, D, C)>>}
  {==}

def Laws.continue_after_assistant_prefers_steering(M, mode, followUp, message):
  match mode:
    case T.All{}: {==}
    case T.OneAtATime{}: {==}

def Laws.continue_after_assistant_falls_back_to_follow_ups(M, steeringMode, followUpMode, message):
  match steeringMode:
    case T.All{}:
      match followUpMode:
        case T.All{}: {==}
        case T.OneAtATime{}: {==}
    case T.OneAtATime{}:
      match followUpMode:
        case T.All{}: {==}
        case T.OneAtATime{}: {==}

def Laws.continue_after_assistant_with_empty_queues_fails(M, steeringMode, followUpMode):
  match steeringMode:
    case T.All{}:
      match followUpMode:
        case T.All{}: {==}
        case T.OneAtATime{}: {==}
    case T.OneAtATime{}:
      match followUpMode:
        case T.All{}: {==}
        case T.OneAtATime{}: {==}

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

# Agent owner

def Laws.enqueue_preserves_state(P, A, G, D, C, V, S, E, J, owned, kind, message):
  match owned:
    case Runtime.OwnedState{_, _}: {==}

def Laws.queue_update_preserves_state(P, A, G, D, C, V, S, E, J, owned, update):
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
  for +state: T.AgentState<P, A, G, D, C, V, S, E, J>
  for result: Q.Queues<T.AgentMessage<P, A, G, D, C>> & List<&2, T.AgentMessage<P, A, G, D, C>>
  {Laws.resultingState(P, A, G, D, C, V, S, E, J, List<&2, T.AgentMessage<P, A, G, D, C>>, Runtime.drainedRuntime(P, A, G, D, C, V, S, E, J, state, result)) == state : T.AgentState<P, A, G, D, C, V, S, E, J>}

def drained_preserves_state(P, A, G, D, C, V, S, E, J, state, result):
  match result:
    case Tuple{_, _}: {==}

def Laws.drain_preserves_state(P, A, G, D, C, V, S, E, J, owned, kind):
  match owned:
    case Runtime.OwnedState{state, queues}: drained_preserves_state(P, A, G, D, C, V, S, E, J, state, Q.drainQueues(T.AgentMessage<P, A, G, D, C>, queues, kind))

def Laws.changes_preserve_run_state(P, A, G, D, C, V, S, E, J, state, change):
  match state change:
    case T.AgentState{_, _, _, _, _, _, _, _} State.SetModel{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.SetThinkingLevel{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.SetTools{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.ReplaceMessages{_}: {==}
    case T.AgentState{_, _, _, _, _, _, _, _} State.AppendMessage{_}: {==}

def Laws.replace_messages(P, A, G, D, C, V, S, E, J, state, messages):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.append_message(P, A, G, D, C, V, S, E, J, state, message):
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

def Laws.message_start(P, A, G, D, C, V, S, E, J, Partial, Execution, state, message):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.message_update(P, A, G, D, C, V, S, E, J, Partial, Execution, state, message, detail):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.message_end(P, A, G, D, C, V, S, E, J, Partial, Execution, state, message):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.events_preserve_configuration(P, A, G, D, C, V, S, E, J, Partial, Execution, state, event):
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

def Laws.agent_end(P, A, G, D, C, V, S, E, J, Partial, Execution, state, reported):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.tool_start_membership(P, A, G, D, C, V, S, E, J, Partial, Execution, state, id, name, arguments):
  match state:
    case T.AgentState{_, _, _, _, _, _, pending, _}: SetLaws.insert_membership(pending, id)

def Laws.tool_end_membership(P, A, G, D, C, V, S, E, J, Partial, Execution, state, id, name, result, failed):
  match state:
    case T.AgentState{_, _, _, _, _, _, pending, _}: SetLaws.remove_membership(pending, id)

def Laws.finish_idle(P, A, G, D, C, V, S, E, J, state):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

def Laws.finish_messages(P, A, G, D, C, V, S, E, J, state):
  match state:
    case T.AgentState{_, _, _, _, _, _, _, _}: {==}

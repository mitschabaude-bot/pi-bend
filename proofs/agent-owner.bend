import Base
import ../packages/agent/src/agent-state.bend as State
import ../laws/agent-owner.bend as Laws
import ../packages/agent/src/agent-runtime.bend as Runtime
import ../packages/agent/src/agent-queues.bend as Q
import ../packages/agent/src/types.bend as T

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
  {Laws.resultingState(P, A, G, D, C, V, S, E, J, List<&2, T.AgentMessage<P, A, G, D, C>>, Runtime.drained(P, A, G, D, C, V, S, E, J, state, result)) == state : T.AgentState<P, A, G, D, C, V, S, E, J>}

def drained_preserves_state(P, A, G, D, C, V, S, E, J, state, result):
  match result:
    case Tuple{_, _}: {==}

def Laws.drain_preserves_state(P, A, G, D, C, V, S, E, J, owned, kind):
  match owned:
    case Runtime.OwnedState{state, queues}: drained_preserves_state(P, A, G, D, C, V, S, E, J, state, Q.drain(T.AgentMessage<P, A, G, D, C>, queues, kind))

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

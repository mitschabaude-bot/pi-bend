import Base
import ../packages/agent/src/agent.bend as State
import ../packages/runtime/src/string.bend as Set
import ../packages/agent/src/agent.bend as Runtime
import ../packages/agent/src/agent.bend as Q
import ../packages/agent/src/types.bend as T

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

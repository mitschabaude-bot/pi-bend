import Base
import ./string-set.bend as SetProof
import ../laws/string-set.bend as SetLaws
import ../laws/agent-events.bend as Laws
import ../packages/agent/src/types.bend as T

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

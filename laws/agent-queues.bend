import Base
import ../packages/agent/src/agent.bend as Queues
import ../packages/agent/src/agent.bend as Queue
import ../packages/agent/src/types.bend as T

def selected(-A: Data, queues: Queues.Queues<A>, kind: Queues.QueueKind) -> Queue.PendingMessageQueue<A>:
  match queues kind:
    case Queues.Queues{steering, _} Queues.QueuesSteering{}: steering
    case Queues.Queues{_, followUp} Queues.FollowUp{}: followUp

def other(-A: Data, queues: Queues.Queues<A>, kind: Queues.QueueKind) -> Queue.PendingMessageQueue<A>:
  match queues kind:
    case Queues.Queues{_, followUp} Queues.QueuesSteering{}: followUp
    case Queues.Queues{steering, _} Queues.FollowUp{}: steering

def remaining(-A: Data, result: Queues.Queues<A> & List<&2, A>) -> Queues.Queues<A>:
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
  {other(A, remaining(A, Queues.drainQueues(A, queues, kind)), kind) == other(A, queues, kind) : Queue.PendingMessageQueue<A>}

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

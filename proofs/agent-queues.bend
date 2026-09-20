import Base
import ../laws/agent-queues.bend as Laws
import ../packages/agent/src/agent-queues.bend as Queues
import ../packages/agent/src/pending-message-queue.bend as Queue

def Laws.enqueue_selected(A, queues, kind, value):
  match queues kind:
    case Queues.Queues{_, _} Queues.Steering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.enqueue_isolated(A, queues, kind, value):
  match queues kind:
    case Queues.Queues{_, _} Queues.Steering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.clear_selected(A, queues, kind):
  match queues kind:
    case Queues.Queues{_, _} Queues.Steering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.clear_isolated(A, queues, kind):
  match queues kind:
    case Queues.Queues{_, _} Queues.Steering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.mode_selected(A, queues, kind, mode):
  match queues kind:
    case Queues.Queues{_, _} Queues.Steering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

def Laws.mode_isolated(A, queues, kind, mode):
  match queues kind:
    case Queues.Queues{_, _} Queues.Steering{}: {==}
    case Queues.Queues{_, _} Queues.FollowUp{}: {==}

law delivered_isolated:
  for -A: Data
  for +kind: Queues.QueueKind
  for +untouched: Queue.PendingMessageQueue<A>
  for result: Queue.PendingMessageQueue<A> & List<&2, A>
  {Laws.other(A, Laws.remaining(A, Queues.drained(A, kind, untouched, result)), kind) == untouched : Queue.PendingMessageQueue<A>}

def delivered_isolated(A, kind, untouched, result):
  match kind result:
    case Queues.Steering{} Tuple{_, _}: {==}
    case Queues.FollowUp{} Tuple{_, _}: {==}

def Laws.drain_isolated(A, queues, kind):
  match queues kind:
    case Queues.Queues{steering, followUp} Queues.Steering{}: delivered_isolated(A, Queues.Steering{}, followUp, Queue.drain(A, steering))
    case Queues.Queues{steering, followUp} Queues.FollowUp{}: delivered_isolated(A, Queues.FollowUp{}, steering, Queue.drain(A, followUp))

law delivered_selected:
  for -A: Data
  for +kind: Queues.QueueKind
  for untouched: Queue.PendingMessageQueue<A>
  for result: Queue.PendingMessageQueue<A> & List<&2, A>
  {Laws.selectedDelivery(A, kind, Queues.drained(A, kind, untouched, result)) == Laws.singleDelivery(A, result) : Laws.SelectedDelivery<A>}

def delivered_selected(A, kind, untouched, result):
  match kind result:
    case Queues.Steering{} Tuple{_, _}: {==}
    case Queues.FollowUp{} Tuple{_, _}: {==}

def Laws.drain_selected(A, queues, kind):
  match queues kind:
    case Queues.Queues{steering, followUp} Queues.Steering{}: delivered_selected(A, Queues.Steering{}, followUp, Queue.drain(A, steering))
    case Queues.Queues{steering, followUp} Queues.FollowUp{}: delivered_selected(A, Queues.FollowUp{}, steering, Queue.drain(A, followUp))

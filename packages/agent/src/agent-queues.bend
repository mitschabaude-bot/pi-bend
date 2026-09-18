import Base
import ./types.bend as T
import ./pending-message-queue.bend as Q

type Queues<-M: Data> is Data:
  Queues{steering: Q.PendingMessageQueue<M>, followUp: Q.PendingMessageQueue<M>}
type QueueKind is Data:
  Steering{}
  FollowUp{}

def new(-M: Data, steering: T.QueueMode, followUp: T.QueueMode) -> Queues<M>:
  Queues{Q.new(M, steering), Q.new(M, followUp)}
def defaults(-M: Data) -> Queues<M>: new(M, T.OneAtATime{}, T.OneAtATime{})
def enqueue(-M: Data, queues: Queues<M>, kind: QueueKind, message: M) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUp} Steering{}: Queues{Q.enqueue(M, steering, message), followUp}
    case Queues{steering, followUp} FollowUp{}: Queues{steering, Q.enqueue(M, followUp, message)}
def setMode(-M: Data, queues: Queues<M>, kind: QueueKind, mode: T.QueueMode) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUp} Steering{}: Queues{Q.setMode(M, steering, mode), followUp}
    case Queues{steering, followUp} FollowUp{}: Queues{steering, Q.setMode(M, followUp, mode)}
def clear(-M: Data, queues: Queues<M>, kind: QueueKind) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUp} Steering{}: Queues{Q.clear(M, steering), followUp}
    case Queues{steering, followUp} FollowUp{}: Queues{steering, Q.clear(M, followUp)}
def clearAll(-M: Data, queues: Queues<M>) -> Queues<M>:
  match queues:
    case Queues{steering, followUp}: Queues{Q.clear(M, steering), Q.clear(M, followUp)}
def hasQueuedMessages(-M: Data, queues: Queues<M>) -> Bool:
  match queues:
    case Queues{steering, followUp}: Q.hasItems(M, steering) || Q.hasItems(M, followUp)
def drained(-M: Data, kind: QueueKind, other: Q.PendingMessageQueue<M>, result: Q.PendingMessageQueue<M> & List<&2, M>) -> Queues<M> & List<&2, M>:
  match kind result:
    case Steering{} Tuple{remaining, messages}: (Queues{remaining, other}, messages)
    case FollowUp{} Tuple{remaining, messages}: (Queues{other, remaining}, messages)
def drain(-M: Data, queues: Queues<M>, kind: QueueKind) -> Queues<M> & List<&2, M>:
  match queues kind:
    case Queues{steering, followUp} Steering{}: drained(M, Steering{}, followUp, Q.drain(M, steering))
    case Queues{steering, followUp} FollowUp{}: drained(M, FollowUp{}, steering, Q.drain(M, followUp))

def getMode(-M: Data, queues: Queues<M>, kind: QueueKind) -> T.QueueMode:
  match queues kind:
    case Queues{steering, _} Steering{}: Q.getMode(M, steering)
    case Queues{_, followUp} FollowUp{}: Q.getMode(M, followUp)

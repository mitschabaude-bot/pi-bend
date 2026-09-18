import Base
import ./types.bend as T
import ../../runtime/src/fifo.bend as F

# Immutable counterpart of agent.ts PendingMessageQueue. The Agent owner
# commits these transitions atomically with its other runtime state.
type PendingMessageQueue<-Message: Data> is Data:
  PendingMessageQueue{mode: T.QueueMode, messages: F.Queue<Message>}

def new(-M: Data, mode: T.QueueMode) -> PendingMessageQueue<M>:
  PendingMessageQueue{mode, F.new(M)}
def getMode(-M: Data, queue: PendingMessageQueue<M>) -> T.QueueMode:
  match queue:
    case PendingMessageQueue{value, _}: value
def setMode(-M: Data, queue: PendingMessageQueue<M>, mode: T.QueueMode) -> PendingMessageQueue<M>:
  match queue:
    case PendingMessageQueue{_, messages}: PendingMessageQueue{mode, messages}
def enqueue(-M: Data, queue: PendingMessageQueue<M>, message: M) -> PendingMessageQueue<M>:
  match queue:
    case PendingMessageQueue{mode, messages}: PendingMessageQueue{mode, F.enqueue(M, messages, message)}
def hasItems(-M: Data, queue: PendingMessageQueue<M>) -> Bool:
  match queue:
    case PendingMessageQueue{_, F.Queue{Nil{}, Nil{}}}: False{}
    case _: True{}
def values(-M: Data, queue: PendingMessageQueue<M>) -> List<&2, M>:
  match queue:
    case PendingMessageQueue{_, messages}: F.drain(M, messages)
def clear(-M: Data, queue: PendingMessageQueue<M>) -> PendingMessageQueue<M>:
  match queue:
    case PendingMessageQueue{mode, _}: new(M, mode)
def drainedOne(-M: Data, popped: F.Queue<M> & Maybe<&2, M>) -> PendingMessageQueue<M> & List<&2, M>:
  match popped:
    case Tuple{remaining, None{}}: (PendingMessageQueue{T.OneAtATime{}, remaining}, Nil{})
    case Tuple{remaining, Some{value}}: (PendingMessageQueue{T.OneAtATime{}, remaining}, value <> Nil{})
def drain(-M: Data, queue: PendingMessageQueue<M>) -> PendingMessageQueue<M> & List<&2, M>:
  match queue:
    case PendingMessageQueue{T.All{}, messages}: (new(M, T.All{}), F.drain(M, messages))
    case PendingMessageQueue{T.OneAtATime{}, messages}: drainedOne(M, F.dequeue(M, messages))

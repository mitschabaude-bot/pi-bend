import Base
import ../packages/agent/src/pending-message-queue.bend as Queue
import ../packages/agent/src/types.bend as T

type Snapshot<-A: Data> is Data:
  Snapshot{mode: T.QueueMode, values: List<&2, A>}

def snapshot(-A: Data, +queue: Queue.PendingMessageQueue<A>) -> Snapshot<A>:
  Snapshot{Queue.getMode(A, queue), Queue.values(A, queue)}

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
  {snapshot(A, Queue.new(A, mode)) == Snapshot{mode, Nil{}} : Snapshot<A>}

law enqueue:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  for +value: A
  {snapshot(A, Queue.enqueue(A, queue, value)) == appended(A, snapshot(A, queue), value) : Snapshot<A>}

law set_mode:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  for mode: T.QueueMode
  {snapshot(A, Queue.setMode(A, queue, mode)) == withMode(A, snapshot(A, queue), mode) : Snapshot<A>}

law clear:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  {snapshot(A, Queue.clear(A, queue)) == cleared(A, snapshot(A, queue)) : Snapshot<A>}

law drain:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  {observe(A, Queue.drain(A, queue)) == delivered(A, snapshot(A, queue)) : Delivery<A>}

law has_items:
  for -A: Data
  for +queue: Queue.PendingMessageQueue<A>
  {Queue.hasItems(A, queue) == Bool.not(List.is_empty(&2, A, Queue.values(A, queue))) : Bool}

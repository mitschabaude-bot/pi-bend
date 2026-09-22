import Base
import ./fifo.bend as FifoProof
import ../laws/fifo.bend as FifoLaws
import ../laws/pending-queue.bend as Laws
import ../packages/runtime/src/fifo.bend as Fifo
import ../packages/agent/src/agent.bend as Queue
import ../packages/agent/src/types.bend as T

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

import Base
import ./laws/agent-queues.bend as AgentQueues
import ./laws/pending-queue.bend as Pending
import ./packages/runtime/src/fifo.bend as Fifo

# Observable list semantics, independent of the queue's two-list layout.
type Removal<-A: Data> is Data:
  Removal{remaining: List<&2, A>, value: Maybe<&2, A>}

def uncons(-A: Data, values: List<&2, A>) -> Removal<A>:
  match values:
    case Nil{}: Removal{Nil{}, None{}}
    case head <> tail: Removal{tail, Some{head}}

def observe(-A: Data, result: Fifo.Queue<A> & Maybe<&2, A>) -> Removal<A>:
  match result:
    case Tuple{remaining, value}: Removal{Fifo.drain(A, remaining), value}

law fifo_empty:
  for -A: Data
  {Fifo.drain(A, Fifo.new(A)) == Nil{} : List<&2, A>}

law fifo_enqueue:
  for -A: Data
  for +queue: Fifo.Queue<A>
  for +value: A
  {Fifo.drain(A, Fifo.enqueue(A, queue, value)) == List.append(&2, A, Fifo.drain(A, queue), value <> Nil{}) : List<&2, A>}

law fifo_dequeue:
  for -A: Data
  for +queue: Fifo.Queue<A>
  {observe(A, Fifo.dequeue(A, queue)) == uncons(A, Fifo.drain(A, queue)) : Removal<A>}

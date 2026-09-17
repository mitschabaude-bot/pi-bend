import Base

# Persistent FIFO with amortized O(1) enqueue/dequeue. The reversed incoming
# list is transferred only when the outgoing list has been drained.
type Queue<-A: Data> is Data:
  Queue{incoming: List<&2, A>, outgoing: List<&2, A>}

def new(-A: Data) -> Queue<A>: Queue{Nil{}, Nil{}}

def enqueue(-A: Data, queue: Queue<A>, value: A) -> Queue<A>:
  match queue:
    case Queue{incoming, outgoing}: Queue{value <> incoming, outgoing}

def takeFront(-A: Data, incoming: List<&2, A>, outgoing: List<&2, A>) -> Queue<A> & Maybe<&2, A>:
  match outgoing:
    case Nil{}: (Queue{incoming, Nil{}}, None{})
    case head <> tail: (Queue{incoming, tail}, Some{head})

def dequeue(-A: Data, queue: Queue<A>) -> Queue<A> & Maybe<&2, A>:
  match queue:
    case Queue{incoming, Nil{}}: takeFront(A, Nil{}, List.reverse(&2, A, incoming))
    case Queue{incoming, head <> tail}: (Queue{incoming, tail}, Some{head})

def drain(-A: Data, queue: Queue<A>) -> List<&2, A>:
  match queue:
    case Queue{incoming, outgoing}: List.append(&2, A, outgoing, List.reverse(&2, A, incoming))

import Base
import ../laws/fifo.bend as Laws
import ../packages/runtime/src/fifo.bend as Fifo

# Algebraic lemmas for the existing Base operations; no runtime replacement.
law append_associative:
  for -A: Data
  for xs: List<&2, A>
  for ys: List<&2, A>
  for zs: List<&2, A>
  {List.append(&2, A, xs, List.append(&2, A, ys, zs)) == List.append(&2, A, List.append(&2, A, xs, ys), zs) : List<&2, A>}

def append_associative(A, xs, ys, zs):
  match xs:
    case Nil{}: {==}
    case head <> tail:
      %append_associative(A, tail, ys, zs) : {head <> List.append(&2, A, tail, List.append(&2, A, ys, zs)) == head <> _ : List<&2, A>}
      {==}

law reverse_accumulator:
  for -A: Data
  for xs: List<&2, A>
  for ys: List<&2, A>
  for zs: List<&2, A>
  {List.reverse.go(&2, A, xs, List.append(&2, A, ys, zs)) == List.append(&2, A, List.reverse.go(&2, A, xs, ys), zs) : List<&2, A>}

def reverse_accumulator(A, xs, ys, zs):
  match xs:
    case Nil{}: {==}
    case head <> tail: reverse_accumulator(A, tail, head <> ys, zs)

def Laws.fifo_empty(A): {==}

def Laws.fifo_enqueue(A, queue, value):
  match queue:
    case Fifo.Queue{incoming, outgoing}:
      %append_associative(A, outgoing, List.reverse(&2, A, incoming), value <> Nil{}) : {List.append(&2, A, outgoing, List.reverse.go(&2, A, incoming, value <> Nil{})) == _ : List<&2, A>}
      %reverse_accumulator(A, incoming, Nil{}, value <> Nil{}) : {List.append(&2, A, outgoing, List.reverse.go(&2, A, incoming, value <> Nil{})) == List.append(&2, A, outgoing, _) : List<&2, A>}
      {==}

law append_empty:
  for -A: Data
  for xs: List<&2, A>
  {List.append(&2, A, xs, Nil{}) == xs : List<&2, A>}

def append_empty(A, xs):
  match xs:
    case Nil{}: {==}
    case head <> tail:
      %append_empty(A, tail) : {head <> List.append(&2, A, tail, Nil{}) == head <> _ : List<&2, A>}
      {==}

law take_front_sequence:
  for -A: Data
  for values: List<&2, A>
  {Laws.observe(A, Fifo.takeFront(A, Nil{}, values)) == Laws.uncons(A, values) : Laws.Removal<A>}

def take_front_sequence(A, values):
  match values:
    case Nil{}: {==}
    case head <> tail:
      %append_empty(A, tail) : {Laws.Removal{List.append(&2, A, tail, Nil{}), Some{head}} == Laws.Removal{_, Some{head}} : Laws.Removal<A>}
      {==}

def Laws.fifo_dequeue(A, queue):
  match queue:
    case Fifo.Queue{incoming, Nil{}}: take_front_sequence(A, List.reverse(&2, A, incoming))
    case Fifo.Queue{incoming, head <> tail}: {==}

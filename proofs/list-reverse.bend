import Base
import ./fifo.bend as Fifo

law reverse_go_append:
  for -A: Data
  for +xs: List<&2, A>
  for +ys: List<&2, A>
  for +acc: List<&2, A>
  {List.reverse.go(&2, A, List.append(&2, A, xs, ys), acc) == List.reverse.go(&2, A, ys, List.reverse.go(&2, A, xs, acc)) : List<&2, A>}

def reverse_go_append(A, xs, ys, acc):
  match xs:
    case Nil{}: {==}
    case head <> tail: reverse_go_append(A, tail, ys, head <> acc)

law reverse_suffix:
  for -A: Data
  for +xs: List<&2, A>
  for +head: A
  {List.reverse(&2, A, List.append(&2, A, xs, head <> Nil{})) == head <> List.reverse(&2, A, xs) : List<&2, A>}

def reverse_suffix(A, xs, head):
  reverse_go_append(A, xs, head <> Nil{}, Nil{})

law involution:
  for -A: Data
  for +xs: List<&2, A>
  {List.reverse(&2, A, List.reverse(&2, A, xs)) == xs : List<&2, A>}

def involution(A, xs):
  match xs:
    case Nil{}: {==}
    case head <> tail:
      %Equal.sym(List<&2, A>, List.reverse.go(&2, A, tail, head <> Nil{}), List.append(&2, A, List.reverse(&2, A, tail), head <> Nil{}), Fifo.reverse_accumulator(A, tail, Nil{}, head <> Nil{})) : {List.reverse(&2, A, _) == head <> tail : List<&2, A>}
      %Equal.sym(List<&2, A>, List.reverse(&2, A, List.append(&2, A, List.reverse(&2, A, tail), head <> Nil{})), head <> List.reverse(&2, A, List.reverse(&2, A, tail)), reverse_suffix(A, List.reverse(&2, A, tail), head)) : {_ == head <> tail : List<&2, A>}
      Equal.cong(List<&2, A>, List<&2, A>, values => head <> values, List.reverse(&2, A, List.reverse(&2, A, tail)), tail, involution(A, tail))

law reverse_append:
  for -A: Data
  for +xs: List<&2, A>
  for +ys: List<&2, A>
  {List.reverse(&2, A, List.append(&2, A, xs, ys)) == List.append(&2, A, List.reverse(&2, A, ys), List.reverse(&2, A, xs)) : List<&2, A>}

def reverse_append(A, xs, ys):
  Equal.trans(List<&2, A>, List.reverse(&2, A, List.append(&2, A, xs, ys)), List.reverse.go(&2, A, ys, List.reverse(&2, A, xs)), List.append(&2, A, List.reverse(&2, A, ys), List.reverse(&2, A, xs)), reverse_go_append(A, xs, ys, Nil{}), Fifo.reverse_accumulator(A, ys, Nil{}, List.reverse(&2, A, xs)))

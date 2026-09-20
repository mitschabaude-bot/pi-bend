import Base
import ../packages/runtime/src/list-interleave.bend as Weave

law left_empty:
  for -A: Data
  for +values: List<&2, A>
  {Weave.interleave(A, Nil{}, values) == values : List<&2, A>}

law right_empty:
  for -A: Data
  for +values: List<&2, A>
  {Weave.interleave(A, values, Nil{}) == values : List<&2, A>}

law leading_pair:
  for -A: Data
  for +first: A
  for +second: A
  for +left: List<&2, A>
  for +right: List<&2, A>
  {Weave.interleave(A, first <> left, second <> right) == first <> second <> Weave.interleave(A, left, right) : List<&2, A>}

law combined_count:
  for -A: Data
  for +left: List<&2, A>
  for +right: List<&2, A>
  {List.length(&2, A, Weave.interleave(A, left, right)) == Nat.add(List.length(&2, A, left), List.length(&2, A, right)) : Nat}

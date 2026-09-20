import Base

# Alternate complete occurrences, taking the left head first. Once either
# sequence is exhausted, preserve the other sequence's remaining order.
def interleave(-A: Data, left: List<&2, A>, right: List<&2, A>) -> List<&2, A>:
  match left right:
    case Nil{} other: other
    case other Nil{}: other
    case a <> xs b <> ys: a <> b <> interleave(A, xs, ys)

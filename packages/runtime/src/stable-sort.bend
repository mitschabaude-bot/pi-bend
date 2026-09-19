import Base

# Bottom-up stable merge sort with tail-recursive run construction and passes.
# Base's merge uses a reversed accumulator; reuse that checked comparison path.
def length(-A: Data, values: List<&2, A>, count: Nat) -> Nat:
  match values:
    case Nil{}: count
    case _ <> rest: length(A, rest, Succ{count})

def runs(-A: Data, values: List<&2, A>, reversed: List<&2, List<&2, A>>) -> List<&2, List<&2, A>>:
  match values:
    case Nil{}: List.reverse(&2, List<&2, A>, reversed)
    case head <> rest: runs(A, rest, (head <> Nil{}) <> reversed)

def pass(~A: Data, ~le: A -> A -> Bool, values: List<&2, List<&2, A>>, +count: Nat, reversed: List<&2, List<&2, A>>) -> List<&2, List<&2, A>>:
  match values:
    case Nil{}: List.reverse(&2, List<&2, A>, reversed)
    case last <> Nil{}: List.reverse(&2, List<&2, A>, last <> reversed)
    case left <> right <> rest: pass(~A, ~le, rest, count, List.merge.go(~A, ~le, count, (Nil{}, left, right)) <> reversed)

def rounds(~A: Data, ~le: A -> A -> Bool, fuel: Nat, +count: Nat, values: List<&2, List<&2, A>>) -> List<&2, A>:
  match fuel values:
    case _ Nil{}: Nil{}
    case _ value <> Nil{}: value
    case Succ{rest} values: rounds(~A, ~le, rest, count, pass(~A, ~le, values, count, Nil{}))
    case Zero{} _: Nil{}

# Each pass at least halves the run count, so length bounds the pass count.
def sort(~A: Data, ~le: A -> A -> Bool, +values: List<&2, A>) -> List<&2, A>:
  +count = length(A, values, Zero{})
  rounds(~A, ~le, count, count, runs(A, values, Nil{}))

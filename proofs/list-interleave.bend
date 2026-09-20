import Base
import ../laws/list-interleave.bend as Laws
import ../packages/runtime/src/list-interleave.bend as Weave

law add_zero:
  for +n: Nat
  {Nat.add(n, Zero{}) == n : Nat}

def add_zero(n):
  match n:
    case Zero{}: {==}
    case Succ{p}:
      %add_zero(p) : {Succ{Nat.add(p, Zero{})} == Succ{_} : Nat}
      {==}

law add_successor:
  for +n: Nat
  for +m: Nat
  {Nat.add(n, Succ{m}) == Succ{Nat.add(n, m)} : Nat}

def add_successor(n, m):
  match n:
    case Zero{}: {==}
    case Succ{p}:
      %add_successor(p, m) : {Succ{Nat.add(p, Succ{m})} == Succ{_} : Nat}
      {==}

def Laws.left_empty(A, values):
  match values:
    case Nil{}: {==}
    case first <> rest: {==}
def Laws.right_empty(A, values):
  match values:
    case Nil{}: {==}
    case first <> rest: {==}
def Laws.leading_pair(A, first, second, left, right): {==}

def Laws.combined_count(A, left, right):
  match left right:
    case Nil{} Nil{}: {==}
    case Nil{} first <> rest: {==}
    case first <> rest Nil{}: Equal.sym(Nat, Nat.add(Succ{List.length(&2, A, rest)}, Zero{}), Succ{List.length(&2, A, rest)}, add_zero(Succ{List.length(&2, A, rest)}))
    case first <> xs second <> ys:
      %Equal.sym(Nat, List.length(&2, A, Weave.interleave(A, xs, ys)), Nat.add(List.length(&2, A, xs), List.length(&2, A, ys)), Laws.combined_count(A, xs, ys)) : {Succ{Succ{_}} == Succ{Nat.add(List.length(&2, A, xs), Succ{List.length(&2, A, ys)})} : Nat}
      Equal.cong(Nat, Nat, n => Succ{n}, Succ{Nat.add(List.length(&2, A, xs), List.length(&2, A, ys))}, Nat.add(List.length(&2, A, xs), Succ{List.length(&2, A, ys)}), Equal.sym(Nat, Nat.add(List.length(&2, A, xs), Succ{List.length(&2, A, ys)}), Succ{Nat.add(List.length(&2, A, xs), List.length(&2, A, ys))}, add_successor(List.length(&2, A, xs), List.length(&2, A, ys))))

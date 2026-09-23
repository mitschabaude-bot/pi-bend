import Base
import ../laws/glob.bend as Laws
import ../packages/runtime/src/glob.bend as Glob
import ./list-interleave.bend as Arithmetic

law length_successor:
  for +text: String
  for +count: Nat
  {Glob.textLengthGo(text, 1n + count) == 1n + Glob.textLengthGo(text, count) : Nat}

def length_successor(text, count):
  match text:
    case SNil{}: {==}
    case SCon{_, rest}: length_successor(rest, 1n + count)

# Once the star is installed, each character takes two transitions: retry
# the empty suffix, then advance its saved text. Two more steps finish.
law star_suffix:
  for +text: String
  for +spare: Nat
  {Glob.matchRun(Nat.add(Glob.textLength(text), Nat.add(Glob.textLength(text), 2n + spare)), Glob.Running{Nil{}, text, Glob.StarState{Nil{}, text}}) == True{} : Bool}

def star_suffix(text, spare):
  match text:
    case SNil{}: {==}
    case SCon{char, rest}:
      %Equal.sym(Nat, Glob.textLengthGo(rest, 1n), 1n + Glob.textLength(rest), length_successor(rest, 0n)) : {Glob.matchRun(Nat.add(_, Nat.add(Glob.textLength(SCon{char, rest}), 2n + spare)), Glob.Running{Nil{}, SCon{char, rest}, Glob.StarState{Nil{}, SCon{char, rest}}}) == True{} : Bool}
      %Equal.sym(Nat, Glob.textLengthGo(rest, 1n), 1n + Glob.textLength(rest), length_successor(rest, 0n)) : {Glob.matchRun(Nat.add(1n + Glob.textLength(rest), Nat.add(_, 2n + spare)), Glob.Running{Nil{}, SCon{char, rest}, Glob.StarState{Nil{}, SCon{char, rest}}}) == True{} : Bool}
      %Equal.sym(Nat, Nat.add(Glob.textLength(rest), 1n + Nat.add(Glob.textLength(rest), 2n + spare)), 1n + Nat.add(Glob.textLength(rest), Nat.add(Glob.textLength(rest), 2n + spare)), Arithmetic.add_successor(Glob.textLength(rest), Nat.add(Glob.textLength(rest), 2n + spare))) : {Glob.matchRun(1n + _, Glob.Running{Nil{}, SCon{char, rest}, Glob.StarState{Nil{}, SCon{char, rest}}}) == True{} : Bool}
      star_suffix(rest, spare)

law add_two:
  for +n: Nat
  {Nat.add(n, 2n) == 2n + n : Nat}

def add_two(n):
  match n:
    case 0n: {==}
    case 1n+rest:
      %Equal.sym(Nat, Nat.add(rest, 2n), 2n + rest, add_two(rest)) : {1n + _ == 3n + rest : Nat}
      {==}

def Laws.star_matches_every_string(text):
  %Equal.sym(Nat, Nat.add(Glob.textLength(text), 2n), 2n + Glob.textLength(text), add_two(Glob.textLength(text))) : {Glob.matchRun(Nat.mul(3n, _), Glob.Running{Glob.Star{} <> Nil{}, text, Glob.NoStar{}}) == True{} : Bool}
  %Equal.sym(Nat, Nat.add(Glob.textLength(text), 0n), Glob.textLength(text), Arithmetic.add_zero(Glob.textLength(text))) : {Glob.matchRun(1n + Nat.add(Glob.textLength(text), 2n + Nat.add(Glob.textLength(text), 2n + _)), Glob.Running{Nil{}, text, Glob.StarState{Nil{}, text}}) == True{} : Bool}
  %Arithmetic.add_successor(Glob.textLength(text), 2n + Nat.add(Glob.textLength(text), 2n + Glob.textLength(text))) : {Glob.matchRun(_, Glob.Running{Nil{}, text, Glob.StarState{Nil{}, text}}) == True{} : Bool}
  %Arithmetic.add_successor(Glob.textLength(text), 2n + Glob.textLength(text)) : {Glob.matchRun(Nat.add(Glob.textLength(text), 2n + _), Glob.Running{Nil{}, text, Glob.StarState{Nil{}, text}}) == True{} : Bool}
  %Arithmetic.add_successor(Glob.textLength(text), 3n + Glob.textLength(text)) : {Glob.matchRun(Nat.add(Glob.textLength(text), 1n + _), Glob.Running{Nil{}, text, Glob.StarState{Nil{}, text}}) == True{} : Bool}
  %Arithmetic.add_successor(Glob.textLength(text), 4n + Glob.textLength(text)) : {Glob.matchRun(Nat.add(Glob.textLength(text), _), Glob.Running{Nil{}, text, Glob.StarState{Nil{}, text}}) == True{} : Bool}
  star_suffix(text, 3n + Glob.textLength(text))

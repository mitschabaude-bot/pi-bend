import Base

# A contradictory Bool hypothesis is eliminated through a type-valued motive:
# the rewrite carries Unit{} from the true side of the equation to the
# impossible side, where the motive is Empty.

def IfTrue(flag: Bool) -> Type:
  match flag:
    case False{}: Unit
    case True{}: Empty

def IfFalse(flag: Bool) -> Type:
  match flag:
    case False{}: Empty
    case True{}: Unit

def false_is_not_true(e: {False{} == True{} : Bool}) -> Empty:
  %e : IfTrue(_); Unit{}

def true_is_not_false(e: {True{} == False{} : Bool}) -> Empty:
  %e : IfFalse(_); Unit{}

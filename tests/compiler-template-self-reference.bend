import Base

def apply(~f: Nat -> Nat, value: Nat) -> Nat:
  f(value)

@unsafe def walk(value: Nat) -> Nat:
  match value:
    case Zero{}: Zero{}
    case Succ{rest}: apply(~walk, rest)

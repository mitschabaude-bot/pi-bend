import Base

# Retain at most the caller's byte budget. Overflow is sticky across chunks.
type State is Data:
  State{remaining: Nat, reversed: List<&2, U32>, overflow: Bool}

def consumed(bytes: List<&2, U32>, state: State) -> State:
  match bytes state:
    case Nil{} previous: previous
    case _ State{_, reversed, True{}}: State{0n, reversed, True{}}
    case _ <> _ State{0n, reversed, False{}}: State{0n, reversed, True{}}
    case byte <> rest State{1n+remaining, reversed, False{}}: consumed(rest, State{remaining, byte <> reversed, False{}})


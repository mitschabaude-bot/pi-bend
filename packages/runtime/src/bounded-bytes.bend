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

type Error is Data:
  LimitExceeded{}

def create(limit: Nat) -> State:
  State{limit, Nil{}, False{}}

# An exceeded budget is an error, never a successful truncated body.
def finish(state: State) -> Result<&2, &2, Error, List<&2, U32>>:
  match state:
    case State{_, _, True{}}: Fail{LimitExceeded{}}
    case State{_, reversed, False{}}: Done{List.reverse(&2, U32, reversed)}

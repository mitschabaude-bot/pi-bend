import Base

# BEND-019 recurrence: a closure in one tail self-call's arguments is missed
# when the JS explicit-stack pass rewrites another self-call in the same def.
type State is Data: State{remaining: Nat}
type Decoded is Data: Decoded{state: State, event: Maybe<&2, Bool>}

def step(state: State, unused: Bool) -> Result<&2, &2, String, State>:
  match state:
    case State{remaining}: Done{State{remaining - 1n}}

@unsafe
def loop(result: Result<&2, &2, String, Decoded>, bytes: List<&2, Bool>) -> Result<&2, &2, String, Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Decoded{state, Some{event}}}: Done{Decoded{state, Some{event}}}
    case Done{Decoded{State{0n}, None{}}}: loop(Done{Decoded{State{0n}, Some{True{}}}}, bytes)
    case Done{Decoded{state, None{}}}:
      match bytes:
        case Nil{}: Done{Decoded{state, None{}}}
        case byte <> rest: loop(Result.map(&2, &2, String, State, Decoded, next => Decoded{next, None{}}, step(state, byte)), rest)

def bytes(remaining: Nat, result: List<&2, Bool>) -> List<&2, Bool>:
  match remaining:
    case 0n: result
    case 1n+left: bytes(left, True{} <> result)

def main() -> IO(Unit):
  +result = loop(Done{Decoded{State{70000n}, None{}}}, bytes(70000n, Nil{}))
  IO.print(Result.default(&2, &2, String, String, Result.map(&2, &2, String, Decoded, String, _ => "done", result), "failed"))

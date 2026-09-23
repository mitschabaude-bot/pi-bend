import Base

type Spacer is Data: Spacer{lines: Nat}

def new(lines: Maybe<&2,Nat>) -> Spacer:
  Spacer{Maybe.default(&2,Nat,lines,1n)}
def setLines(state: Spacer,lines: Nat) -> Spacer:
  Spacer{lines}
def blankLines(count: Nat) -> List<&2,String>:
  match count:
    case Zero{}: Nil{}
    case Succ{rest}: "" <> blankLines(rest)
def render(state: Spacer,width: Nat) -> List<&2,String>:
  match state:
    case Spacer{lines}: blankLines(lines)

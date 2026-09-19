import Base

# Equivalent explicit-state control for compiler-dot-patterns.bend.
type DotState is Data:
  Dots{count: U32}
  PercentDot{count: U32}
  HexDot{count: U32}
  NotDots{}

def dotStart(room: Bool, dot: Bool, percent: Bool, count: U32) -> DotState:
  match room dot percent:
    case False{} _ _: NotDots{}
    case True{} True{} _: Dots{(count + 1 : U32)}
    case True{} False{} True{}: PercentDot{count}
    case _ _ _: NotDots{}

def dotHex(valid: Bool, count: U32) -> DotState:
  match valid:
    case True{}: HexDot{count}
    case False{}: NotDots{}

def dotEnd(valid: Bool, count: U32) -> DotState:
  match valid:
    case True{}: Dots{(count + 1 : U32)}
    case False{}: NotDots{}

def dotStep(state: DotState, +char: Char) -> DotState:
  match state:
    case Dots{+count}: dotStart(U32.is_lt(count, 2), Char.is_eq(char, '.'), Char.is_eq(char, '%'), count)
    case PercentDot{count}: dotHex(Char.is_eq(char, '2'), count)
    case HexDot{count}: dotEnd(Char.is_eq(char, 'e') || Char.is_eq(char, 'E'), count)
    case NotDots{}: NotDots{}

def dotCount(text: String, state: DotState) -> Maybe<&2, U32>:
  match text state:
    case _ NotDots{}: None{}
    case SNil{} Dots{count}: Some{count}
    case SNil{} _: None{}
    case SCon{char, rest} previous: dotCount(rest, dotStep(previous, char))


def show(value: Maybe<&2, U32>) -> String:
  match value:
    case None{}: "ordinary"
    case Some{count}: U32.show(count)

def main() -> IO(Unit): IO.print(show(dotCount("%2E.", Dots{0})))

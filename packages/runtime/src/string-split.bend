import Base

# Character-delimited splitting with explicit accumulators. Tail recursion
# bounds machine-stack use independently of text length on every backend.
type State is Data:
  State{field: String, parts: List<&2, String>}

def advance(separator: Bool, char: Char, state: State) -> State:
  match separator state:
    case True{} State{field, parts}: State{"", String.reverse(field) <> parts}
    case False{} State{field, parts}: State{SCon{char, field}, parts}

def scan(text: String, +separator: Char, state: State) -> List<&2, String>:
  match text state:
    case SNil{} State{field, parts}: List.reverse(&2, String, String.reverse(field) <> parts)
    case SCon{+char, rest} previous: scan(rest, separator, advance(Char.is_eq(char, separator), char, previous))

def split(text: String, separator: Char) -> List<&2, String>:
  scan(text, separator, State{"", Nil{}})

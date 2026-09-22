import Base



# Whitespace accepted by Pi's text and numeric normalization. Keep the
# classification shared so replay filtering and numeric parsing agree.
def whitespace(+code: U32) -> Bool:
  (U32.is_ge(code, 9) && U32.is_le(code, 13)) || U32.is_eq(code, 32) || U32.is_eq(code, 160) || U32.is_eq(code, 5760) || (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288) || U32.is_eq(code, 65279)

def blank(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code}, rest}: whitespace(code) && blank(rest)


# UTF-16 code-unit budgets over native characters. No surrogate characters are
# manufactured; an indivisible character either fits completely or is omitted.
type State is Data:
  Taking{remaining: Nat, reversed: String}
  Stopped{prefix: String, omitted: Nat}

type Cut is Data:
  Cut{prefix: String, omitted: Nat}

def width(char: Char) -> Nat:
  match char:
    case Chr{code}: Bool.pick(Nat, U32.is_gt(code, 65535), 2n, 1n)

def room(fits: Bool, remaining: Nat, size: Nat, char: Char, reversed: String) -> State:
  match fits:
    case True{}: Taking{remaining - size, SCon{char, reversed}}
    case False{}: Stopped{String.reverse(reversed), size}

def feed(+char: Char, state: State) -> State:
  match state:
    case Taking{+remaining, reversed}:
      +size = width(char)
      room(Nat.is_ge(remaining, size), remaining, size, char, reversed)
    case Stopped{prefix, omitted}: Stopped{prefix, omitted + width(char)}

def collect(chars: String, state: State) -> State:
  match chars:
    case SNil{}: state
    case SCon{char, rest}: collect(rest, feed(char, state))

def finish(state: State) -> Cut:
  match state:
    case Taking{_, reversed}: Cut{String.reverse(reversed), 0n}
    case Stopped{prefix, omitted}: Cut{prefix, omitted}

def take(text: String, budget: Nat) -> Cut:
  finish(collect(text, Taking{budget, ""}))

def budgetPrefix(state: State) -> String:
  match state:
    case Taking{_, reversed}: String.reverse(reversed)
    case Stopped{text, _}: text

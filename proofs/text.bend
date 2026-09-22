import Base
import ../laws/text.bend as Laws
import ../packages/runtime/src/text.bend as Budget

def Laws.chunk_composition(first, second, state):
  match first:
    case SNil{}: {==}
    case SCon{char, rest}: Laws.chunk_composition(rest, second, Budget.feed(char, state))

def Laws.stopped_prefix_is_stable(chars, prefix, omitted):
  match chars:
    case SNil{}: {==}
    case SCon{char, rest}: Laws.stopped_prefix_is_stable(rest, prefix, omitted + Budget.width(char))

def Laws.fitting_character_is_preserved(remaining, char, reversed, fits):
  Equal.cong(Bool, Budget.State, accepted => Budget.room(accepted, remaining, Budget.width(char), char, reversed), Nat.is_ge(remaining, Budget.width(char)), True{}, fits)
def Laws.nonfitting_character_is_not_split(remaining, char, reversed, fits):
  Equal.cong(Bool, Budget.State, accepted => Budget.room(accepted, remaining, Budget.width(char), char, reversed), Nat.is_ge(remaining, Budget.width(char)), False{}, fits)
def Laws.empty_input_is_unchanged(budget): {==}

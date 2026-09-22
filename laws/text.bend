import Base
import ../packages/runtime/src/text.bend as Budget

law chunk_composition:
  for first: String
  for second: String
  for state: Budget.State
  {Budget.collect(first ++ second, state) == Budget.collect(second, Budget.collect(first, state)) : Budget.State}

law stopped_prefix_is_stable:
  for chars: String
  for prefix: String
  for omitted: Nat
  {Budget.budgetPrefix(Budget.collect(chars, Budget.Stopped{prefix, omitted})) == prefix : String}

law fitting_character_is_preserved:
  for remaining: Nat
  for char: Char
  for reversed: String
  for fits: {Nat.is_ge(remaining, Budget.width(char)) == True{} : Bool}
  {Budget.feed(char, Budget.Taking{remaining, reversed}) == Budget.Taking{remaining - Budget.width(char), SCon{char, reversed}} : Budget.State}

law nonfitting_character_is_not_split:
  for remaining: Nat
  for char: Char
  for reversed: String
  for fits: {Nat.is_ge(remaining, Budget.width(char)) == False{} : Bool}
  {Budget.feed(char, Budget.Taking{remaining, reversed}) == Budget.Stopped{String.reverse(reversed), Budget.width(char)} : Budget.State}

law empty_input_is_unchanged:
  for budget: Nat
  {Budget.take("", budget) == Budget.Cut{"", 0n} : Budget.Cut}

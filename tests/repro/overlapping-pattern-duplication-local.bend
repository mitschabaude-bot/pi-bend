import Base
type Parser is Data: Top{} InSet{}
def parse(text: String, state: Parser) -> Bool:
  match text state:
    case SCon{first, SCon{'-', SCon{Chr{92}, SCon{last, rest}}}} InSet{}:
      +first = {first: Char}
      Char.is_eq(first,first)
    case SCon{first, SCon{'-', SCon{last, rest}}} InSet{}:
      +first = {first: Char}
      Char.is_eq(first,first)
    case _ _: False{}

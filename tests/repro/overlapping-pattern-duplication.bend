import Base
type Parser is Data: Top{} InSet{}
def parse(text: String, state: Parser) -> Bool:
  match text state:
    case SCon{+first, SCon{'-', SCon{Chr{92}, SCon{+last, rest}}}} InSet{}: True{}
    case SCon{+first, SCon{'-', SCon{+last, rest}}} InSet{}: True{}
    case _ _: False{}

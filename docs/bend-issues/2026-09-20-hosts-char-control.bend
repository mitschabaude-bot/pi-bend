import Base

def point(char: Char) -> U32:
  match char:
    case Chr{+code}: (code + code : U32)

def read(text: String) -> U32:
  match text:
    case SNil{}: 0
    case SCon{'#', _}: 1
    case SCon{char, _}: point(char)

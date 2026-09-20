import Base

def read(text: String) -> U32:
  match text:
    case SNil{}: 0
    case SCon{'#', _}: 1
    case SCon{Chr{+code}, _}: (code + code : U32)

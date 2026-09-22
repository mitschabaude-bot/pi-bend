import Base

# Image payloads must remain intact when overlays cover their terminal rows.
def isImageLine(line: String) -> Bool:
  match line:
    case SNil{}: False{}
    case SCon{Chr{27},+rest}:
      Bool.pick(Unit -> Bool,String.starts_with(rest,"_G") || String.starts_with(rest,"]1337;File="),_ => True{},_ => isImageLine(rest))(Unit{})
    case SCon{_,rest}: isImageLine(rest)

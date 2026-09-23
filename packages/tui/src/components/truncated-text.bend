import Base
import ../utils.bend as U

type TruncatedText is Data:
  TruncatedText{text: String,paddingX: Nat,paddingY: Nat}

def new(text: String,paddingX: Maybe<&2,Nat>,paddingY: Maybe<&2,Nat>) -> TruncatedText:
  TruncatedText{text,Maybe.default(&2,Nat,paddingX,0n),Maybe.default(&2,Nat,paddingY,0n)}
def invalidate(state: TruncatedText) -> TruncatedText: state

def firstLine(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\n',_}: String.reverse(reversed)
    case SCon{char,rest}: firstLine(rest,SCon{char,reversed})
def padding(count: Nat,+line: String,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: reversed
    case Succ{count}: padding(count,line,line <> reversed)
def render(state: TruncatedText,+width: Nat) -> List<&2,String>:
  match state:
    case TruncatedText{text,+x,y}:
      +empty = padding(y,U.spaces(width,""),Nil{})
      +margin = U.spaces(x,"")
      +line = margin ++ U.truncateToWidth(firstLine(text,""),Nat.max(1n,width - x * 2n),"...",False{}) ++ margin
      List.append(&2,String,empty,U.padResult(line,U.visibleWidth(line),width,True{}) <> empty)

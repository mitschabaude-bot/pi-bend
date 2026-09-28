import Base
import ./utils.bend as U
import ./terminal-image.bend as Image

# Text selection is a value owned by the fullscreen renderer. Coordinates are
# terminal cells, so character boundaries come from the shared TUI width code.
type Point is Data: Point{row: Nat,col: Nat}
type Selection is Data: Empty{} Pressed{anchor: Point,focus: Point} Complete{anchor: Point,focus: Point}
type Step is Data: Step{selection: Selection,changed: Bool,released: Bool}
type Range is Data: Range{start: Point,end: Point}

def initial() -> Selection: Empty{}
def point(x: Nat,y: Nat,width: Nat,height: Nat) -> Point:
  Point{Nat.min(height - 1n,y),Nat.min(width - 1n,x)}
def same(a: Point,b: Point) -> Bool:
  match a b:
    case Point{ar,ac} Point{br,bc}: Nat.is_eq(ar,br) && Nat.is_eq(ac,bc)
def before(a: Point,b: Point) -> Bool:
  match a b:
    case Point{+ar,ac} Point{+br,bc}: Nat.is_lt(ar,br) || (Nat.is_eq(ar,br) && Nat.is_lt(ac,bc))
def bounds(selection: Selection) -> Maybe<&2,Range>:
  match selection:
    case Empty{}: None{}
    case Pressed{+anchor,+focus}:
      Bool.pick(Maybe<&2,Range>,same(anchor,focus),None{},Some{Bool.pick(Range,before(anchor,focus),Range{anchor,focus},Range{focus,anchor})})
    case Complete{+anchor,+focus}:
      Bool.pick(Maybe<&2,Range>,same(anchor,focus),None{},Some{Bool.pick(Range,before(anchor,focus),Range{anchor,focus},Range{focus,anchor})})
def stepPressed(+anchor: Point,focus: Point,+here: Point,+code: Nat,+isMotion: Bool,+isRelease: Bool) -> Step:
  +left = Nat.is_eq(code,0n)
  +finished = isRelease && (left || Nat.is_eq(code,3n))
  +dragging = Bool.not(isRelease) && isMotion && left
  +starting = Bool.not(isRelease) && Bool.not(isMotion) && left
  Bool.pick(Step,finished,Step{Complete{anchor,here},True{},True{}},
    Bool.pick(Step,dragging,Step{Pressed{anchor,here},True{},False{}},
      Bool.pick(Step,starting,Step{Pressed{here,here},True{},False{}},Step{Pressed{anchor,focus},False{},False{}})))
def stepOther(current: Selection,+here: Point,code: Nat,isMotion: Bool,isRelease: Bool) -> Step:
  +starting = Bool.not(isRelease) && Bool.not(isMotion) && Nat.is_eq(code,0n)
  Bool.pick(Step,starting,Step{Pressed{here,here},True{},False{}},Step{current,False{},False{}})
def advanced(selectionValue: Selection,here: Point,code: Nat,isMotion: Bool,isRelease: Bool) -> Step:
  match selectionValue:
    case Pressed{anchor,focus}: stepPressed(anchor,focus,here,code,isMotion,isRelease)
    case Empty{}: stepOther(Empty{},here,code,isMotion,isRelease)
    case Complete{anchor,focus}: stepOther(Complete{anchor,focus},here,code,isMotion,isRelease)
def advance(selection: Selection,x: Nat,y: Nat,width: Nat,height: Nat,code: Nat,isMotion: Bool,isRelease: Bool) -> Step:
  +here = point(x,y,width,height)
  advanced(selection,here,code,isMotion,isRelease)
def lineAt(lines: List<&2,String>,row: Nat) -> String:
  match lines row:
    case line <> _ Zero{}: line
    case _ <> rest Succ{left}: lineAt(rest,left)
    case _ _: ""
def rangeStart(found: Maybe<&2,U.GraphemeCellRange>,fallback: Nat) -> Nat:
  match found:
    case Some{U.GraphemeCellRange{start,_}}: start
    case None{}: fallback
def rangeEnd(found: Maybe<&2,U.GraphemeCellRange>,fallback: Nat) -> Nat:
  match found:
    case Some{U.GraphemeCellRange{_,end}}: end
    case None{}: fallback
def cellStart(+line: String,+col: Nat) -> Nat: rangeStart(U.getGraphemeCellRange(line,col),Nat.min(col,U.visibleWidth(line)))
def cellEnd(+line: String,+col: Nat) -> Nat: rangeEnd(U.getGraphemeCellRange(line,col),Nat.min(col + 1n,U.visibleWidth(line)))
def columns(range: Range,+row: Nat,+line: String) -> Nat & Nat:
  match range:
    case Range{Point{first,from},Point{last,to}}:
      +start = Bool.pick(Nat,Nat.is_eq(row,first),cellStart(line,from),0n)
      +end = Bool.pick(Nat,Nat.is_eq(row,last),cellEnd(line,to),U.visibleWidth(line))
      (start,end)
def sliced(line: String,selected: Nat & Nat) -> String:
  match selected:
    case (+start,end): U.trimEnd(U.stripTerminalSequences(U.sliceByColumn(line,start,end - start,True{})))
def selectedLine(+line: String,row: Nat,range: Range) -> String: sliced(line,columns(range,row,line))
def prepend(text: String,rest: List<&2,String>) -> List<&2,String>: text <> rest
def selectedRows(fuel: Nat,+lines: List<&2,String>,+row: Nat,+range: Range,reversed: List<&2,String>) -> List<&2,String>:
  match fuel:
    case Zero{}: List.reverse(&2,String,prepend(selectedLine(lineAt(lines,row),row,range),reversed))
    case Succ{left}: selectedRows(left,lines,row + 1n,range,prepend(selectedLine(lineAt(lines,row),row,range),reversed))
def selectedRange(+range: Range,lines: List<&2,String>) -> Maybe<&2,String>:
  match range:
    case Range{Point{+first,_},Point{last,_}}:
      +value = String.join(selectedRows(last - first,lines,first,range,Nil{}),"\n")
      Bool.pick(Maybe<&2,String>,String.is_empty(value),None{},Some{value})
def selectedText(found: Maybe<&2,Range>,lines: List<&2,String>) -> Maybe<&2,String>:
  match found:
    case None{}: None{}
    case Some{range}: selectedRange(range,lines)
def text(selection: Selection,lines: List<&2,String>) -> Maybe<&2,String>: selectedText(bounds(selection),lines)
def invertedToken(token: U.Token) -> String:
  match token:
    case U.Token{text,False{}}: text
    case U.Token{+text,True{}}: text ++ Bool.pick(String,String.ends_with(text,"m"),"\u{1b}[7m","")
def invertedTokens(tokens: List<&2,U.Token>) -> List<&2,String>:
  match tokens:
    case Nil{}: Nil{}
    case token <> rest: invertedToken(token) <> invertedTokens(rest)
def inverted(text: String) -> String:
  "\u{1b}[7m" ++ String.join(invertedTokens(U.tokens(text)),"") ++ "\u{1b}[27m"
def paintedSpan(+line: String,+start: Nat,+end: Nat,width: Nat) -> String:
  U.sliceByColumn(line,0n,start,True{}) ++ inverted(U.sliceByColumn(line,start,end - start,True{})) ++ U.sliceByColumn(line,end,width - end,True{})
def paintedLine(+line: String,selected: Nat & Nat) -> String:
  match selected:
    case (+start,+end):
      +width = U.visibleWidth(line)
      Bool.pick(Unit -> String,Nat.is_le(end,start) || Image.isImageLine(line),_ => line,_ => paintedSpan(line,start,end,width))(Unit{})
def paintLine(+line: String,row: Nat,range: Range) -> String: paintedLine(line,columns(range,row,line))
def within(range: Range,+row: Nat) -> Bool:
  match range:
    case Range{Point{first,_},Point{last,_}}: Nat.is_ge(row,first) && Nat.is_le(row,last)
def paintRows(lines: List<&2,String>,+row: Nat,+range: Range) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case +line <> rest:
      +painted = Bool.pick(Unit -> String,within(range,row),_ => paintLine(line,row,range),_ => line)(Unit{})
      painted <> paintRows(rest,row + 1n,range)
def painted(found: Maybe<&2,Range>,lines: List<&2,String>) -> List<&2,String>:
  match found:
    case None{}: lines
    case Some{range}: paintRows(lines,0n,range)
def paint(selection: Selection,lines: List<&2,String>) -> List<&2,String>: painted(bounds(selection),lines)

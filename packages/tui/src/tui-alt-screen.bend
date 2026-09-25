import Base
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/ref.bend as Ref
import ./keybindings.bend as Bindings
import ../../runtime/src/string.bend as Strings
import ./tui-main-screen.bend as Screen
import ./terminal-image.bend as Image
import ./utils.bend as Layout
import ./tui.bend as Tui
import ./alt-screen-search.bend as Search
import ./tui-base.bend as BaseTui
import ./layout.bend as Geometry

# The alternate screen owns a fixed-size image of the terminal. Rendering is a
# pure diff; the process commits the new image only after its write succeeds.
type State is Data: State{lines: List<&2,String>,width: Maybe<&2,Nat>,height: Maybe<&2,Nat>,indicator: Callback.Callback<Unit,String>,bindings: Ref.Ref<Bindings.KeybindingsManager>,search: Maybe<&2,Search.Session>,styles: Callback.Callback<Unit,Search.Styles>}
type Plan is Data: Plan{state: State,output: Screen.Stream}

def initial(indicator: Callback.Callback<Unit,String>,bindings: Ref.Ref<Bindings.KeybindingsManager>,styles: Callback.Callback<Unit,Search.Styles>) -> State: State{Nil{},None{},None{},indicator,bindings,None{},styles}
def indicator(state: State) -> Callback.Callback<Unit,String>:
  match state: case State{_,_,_,label,_,_,_}: label
def bindings(state: State) -> Ref.Ref<Bindings.KeybindingsManager>:
  match state: case State{_,_,_,_,keys,_,_}: keys
def search(state: State) -> Maybe<&2,Search.Session>:
  match state: case State{_,_,_,_,_,value,_}: value
def styles(state: State) -> Callback.Callback<Unit,Search.Styles>:
  match state: case State{_,_,_,_,_,_,value}: value
def withSearch(state: State,value: Maybe<&2,Search.Session>) -> State:
  match state:
    case State{lines,width,height,label,keys,_,palette}: State{lines,width,height,label,keys,value,palette}
def enter() -> String: "\u{1b}[?1049h\u{1b}[?7l\u{1b}[?1000h\u{1b}[?1002h\u{1b}[?1006h\u{1b}[2J\u{1b}[H\u{1b}[?25l"
def leave() -> String: "\u{1b}[?2026h\u{1b}[?1000l\u{1b}[?1002l\u{1b}[?1003l\u{1b}[?1006l\u{1b}[?7h\u{1b}[?1049l\u{1b}[?25h\u{1b}[?2026l"
def documentLinePrepared(reset: List<&2,String>,+width: Nat) -> String:
  match reset:
    case Nil{}: ""
    case +value <> _:
      Bool.pick(Unit -> String,Image.isImageLine(value) || Nat.is_le(Layout.visibleWidth(value),width),_ => value,_ => Layout.sliceByColumn(value,0n,width,True{}))(Unit{})
def documentLine(line: String,width: Nat) -> String:
  documentLinePrepared(Tui.applyLineResets(Strings.replaceAll(line,Tui.CURSOR_MARKER(),"") <> Nil{}),width)
def documentRows(lines: List<&2,String>,+width: Nat,first: Bool,reversed: List<&2,Screen.Operation>) -> List<&2,Screen.Operation>:
  match lines:
    case Nil{}: List.reverse(&2,Screen.Operation,reversed)
    case +line <> rest:
      +prefix = Bool.pick(String,first,"","\r\n")
      documentRows(rest,width,False{},Screen.Text{prefix ++ "\r\u{1b}[2K" ++ documentLine(line,width)} <> reversed)
def leaveWithDocument(lines: List<&2,String>,width: Nat) -> Screen.Stream:
  Screen.stream(Screen.Text{"\u{1b}[?2026h\u{1b}[?1006l\u{1b}[?1004l\u{1b}[?1003l\u{1b}[?1002l\u{1b}[?1000l\u{1b}[?7h\u{1b}[?1049l\u{1b}[?7l"} <>
    List.append(&2,Screen.Operation,documentRows(lines,width,True{},Nil{}),Screen.Text{"\u{1b}[0m\u{1b}[?7h\r\n\r\n\u{1b}[?25h\u{1b}[?2026l"} <> Nil{}))
def reset(state: State) -> State:
  match state:
    case State{_,_,_,label,keys,_,palette}: initial(label,keys,palette)
def rowText(row: Nat,line: String) -> String:
  "\u{1b}[" ++ Nat.show(row + 1n) ++ ";1H\u{1b}[2K\u{1b}[0m" ++ line
def addRow(operation: Maybe<&2,Screen.Operation>,reversed: List<&2,Screen.Operation>) -> List<&2,Screen.Operation>:
  match operation:
    case None{}: reversed
    case Some{value}: value <> reversed
def fit(lines: List<&2,String>,height: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match lines height:
    case _ Zero{}: List.reverse(&2,String,reversed)
    case Nil{} Succ{left}: fit(Nil{},left,"" <> reversed)
    case line <> rest Succ{left}: fit(rest,left,line <> reversed)
def rows(old: List<&2,String>,next: List<&2,String>,+row: Nat,+full: Bool,reversed: List<&2,Screen.Operation>) -> List<&2,Screen.Operation>:
  match old next:
    case _ Nil{}: List.reverse(&2,Screen.Operation,reversed)
    case Nil{} line <> more:
      rows(Nil{},more,row + 1n,full,Screen.Text{rowText(row,line)} <> reversed)
    case previous <> rest +line <> more:
      +operation = Bool.pick(Maybe<&2,Screen.Operation>,full || Bool.not(Strings.equal(previous,line)),Some{Screen.Text{rowText(row,line)}},None{})
      rows(rest,more,row + 1n,full,addRow(operation,reversed))
def cursorText(cursor: Maybe<&2,Tui.CursorPosition>,width: Nat) -> String:
  match cursor:
    case None{}: "\u{1b}[?25l"
    case Some{Tui.CursorPosition{row,col}}:
      "\u{1b}[" ++ Nat.show(row + 1n) ++ ";" ++ Nat.show(Nat.min(width,col) + 1n) ++ "H\u{1b}[?25h"
def sameDimension(previous: Maybe<&2,Nat>,current: Nat) -> Bool:
  match previous:
    case None{}: False{}
    case Some{value}: Nat.is_eq(value,current)
def plan(state: State,+lines: List<&2,String>,cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat) -> Plan:
  match state:
    case State{old,previousWidth,previousHeight,label,keys,active,palette}:
      +full = Bool.not(sameDimension(previousWidth,width) && sameDimension(previousHeight,height))
      +fitted = fit(lines,height,Nil{})
      +body = rows(old,fitted,0n,full,Nil{})
      +clear = Bool.pick(List<&2,Screen.Operation>,full,Screen.Text{"\u{1b}[2J"} <> body,body)
      +output = Screen.stream(Screen.Text{"\u{1b}[?2026h"} <> List.append(&2,Screen.Operation,clear,Screen.Text{cursorText(cursor,width) ++ "\u{1b}[?2026l"} <> Nil{}))
      Plan{State{fitted,Some{width},Some{height},label,keys,active,palette},output}

def indicatorLine(line: String,+label: String,+width: Nat) -> String:
  +size = Layout.visibleWidth(label)
  Tui.compositeTuiLine(line,label,(width - size) / 2n,size,width)
def indicatorLines(lines: List<&2,String>,row: Nat,+label: String,width: Nat) -> List<&2,String>:
  match lines row:
    case Nil{} _: Nil{}
    case line <> rest Zero{}: indicatorLine(line,label,width) <> rest
    case line <> rest Succ{above}: line <> indicatorLines(rest,above,label,width)
def boxLine(box: List<&2,String>,row: Nat) -> Maybe<&2,String>:
  match box row:
    case line <> _ Zero{}: Some{line}
    case _ <> rest Succ{left}: boxLine(rest,left)
    case _ _: None{}
def paintedSearchRow(line: String,overlay: Maybe<&2,String>,col: Nat,boxWidth: Nat,width: Nat) -> String:
  match overlay:
    case None{}: line
    case Some{value}: Tui.compositeTuiLine(line,value,col,boxWidth,width)
def paintSearch(lines: List<&2,String>,+box: List<&2,String>,+col: Nat,+boxWidth: Nat,+width: Nat,+row: Nat) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest:
      +visible = Bool.pick(Maybe<&2,String>,Nat.is_gt(row,0n),boxLine(box,row - 1n),None{})
      paintedSearchRow(line,visible,col,boxWidth,width) <> paintSearch(rest,box,col,boxWidth,width,row + 1n)
def searchDecorated(active: Maybe<&2,Search.Session>,lines: List<&2,String>,+width: Nat) -> List<&2,String>:
  match active:
    case None{}: lines
    case Some{Search.Session{query,_,matches,selected,_,_}}:
      +boxWidth = Nat.min(width - 2n,Nat.max(32n,width * 40n / 100n))
      +col = width - boxWidth - 1n
      paintSearch(lines,Search.searchLines(query,selected,List.length(&2,Search.Match,matches),boxWidth,"Shift+Enter","Enter"),col,boxWidth,width,0n)
type SearchRange is Data: SearchRange{start: Nat,end: Nat,current: Bool}
def rangeSegment(segment: Search.Segment,contentRow: Nat,+rectX: Nat,minCol: Nat,maxCol: Nat,current: Bool,+ranges: List<&2,SearchRange>) -> List<&2,SearchRange>:
  match segment:
    case Search.Segment{row,left,right}:
      +start = Nat.max(minCol,rectX + left)
      +end = Nat.min(maxCol,rectX + right)
      Bool.pick(List<&2,SearchRange>,Nat.is_eq(row,contentRow) && Nat.is_gt(end,start),SearchRange{start,end,current} <> ranges,ranges)
def matchRanges(segments: List<&2,Search.Segment>,+contentRow: Nat,+rectX: Nat,+minCol: Nat,+maxCol: Nat,+current: Bool,ranges: List<&2,SearchRange>) -> List<&2,SearchRange>:
  match segments:
    case Nil{}: ranges
    case part <> rest: matchRanges(rest,contentRow,rectX,minCol,maxCol,current,rangeSegment(part,contentRow,rectX,minCol,maxCol,current,ranges))
def selectedAt(selected: Maybe<&2,Nat>,position: Nat) -> Bool:
  match selected:
    case None{}: False{}
    case Some{value}: Nat.is_eq(value,position)
def rangesAt(matches: List<&2,Search.Match>,+selected: Maybe<&2,Nat>,+contentRow: Nat,+rectX: Nat,+minCol: Nat,+maxCol: Nat,+position: Nat,ranges: List<&2,SearchRange>) -> List<&2,SearchRange>:
  match matches:
    case Nil{}: ranges
    case Search.Match{parts} <> rest:
      rangesAt(rest,selected,contentRow,rectX,minCol,maxCol,position + 1n,matchRanges(parts,contentRow,rectX,minCol,maxCol,selectedAt(selected,position),ranges))
def styledMatch(+text: String,current: Bool,styles: Search.Styles) -> String:
  match styles:
    case Search.Styles{+foreground,+background}:
      Bool.pick(String,current,"\u{1b}[1;7m" ++ foreground ++ background ++ text ++ "\u{1b}[0m","\u{1b}[4m" ++ foreground ++ background ++ text ++ "\u{1b}[0m")
def paintRange(+line: String,range: SearchRange,styles: Search.Styles) -> String:
  match range:
    case SearchRange{+start,+end,current}:
      +width = Layout.visibleWidth(line)
      Layout.sliceByColumn(line,0n,start,True{}) ++ styledMatch(Layout.sliceByColumn(line,start,end - start,True{}),current,styles) ++ Layout.sliceByColumn(line,end,width - end,True{})
def paintRanges(ranges: List<&2,SearchRange>,line: String,+styles: Search.Styles) -> String:
  match ranges:
    case Nil{}: line
    case range <> rest: paintRanges(rest,paintRange(line,range,styles),styles)
def highlightRow(+line: String,+row: Nat,matches: List<&2,Search.Match>,selected: Maybe<&2,Nat>,+top: Nat,+startIndex: Nat,rect: Geometry.LayoutRect,clip: Geometry.LayoutRect,styles: Search.Styles) -> String:
  match rect clip:
    case Geometry.LayoutRect{+x,+y,width,height} Geometry.LayoutRect{+cx,+cy,cw,ch}:
      Bool.pick(Unit -> String,Nat.is_ge(row,Nat.max(y,cy)) && Nat.is_lt(row,Nat.min(y + height,cy + ch)),
        _ => paintRanges(rangesAt(matches,selected,top + row - y,x,Nat.max(x,cx),Nat.min(x + width,cx + cw),startIndex,Nil{}),line,styles),
        _ => line)(Unit{})
def highlightRows(lines: List<&2,String>,+row: Nat,+matches: List<&2,Search.Match>,+selected: Maybe<&2,Nat>,+top: Nat,+startIndex: Nat,+rect: Geometry.LayoutRect,+clip: Geometry.LayoutRect,+styles: Search.Styles) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: highlightRow(line,row,matches,selected,top,startIndex,rect,clip,styles) <> highlightRows(rest,row + 1n,matches,selected,top,startIndex,rect,clip,styles)
def lastSegmentRow(value: Maybe<&2,Search.Segment>) -> Nat:
  match value:
    case None{}: 0n
    case Some{Search.Segment{row,_,_}}: row
def matchLastRow(value: Search.Match) -> Nat:
  match value:
    case Search.Match{segments}: lastSegmentRow(List.last(&2,Search.Segment,segments))
type VisibleMatches is Data: VisibleMatches{matches: List<&2,Search.Match>,startIndex: Nat}
def visibleMatches(matches: List<&2,Search.Match>,+minimum: Nat,+maximum: Nat,+position: Nat,+startIndex: Nat,+reversed: List<&2,Search.Match>) -> VisibleMatches:
  match matches:
    case Nil{}: VisibleMatches{List.reverse(&2,Search.Match,reversed),startIndex}
    case +value <> +rest:
      Bool.pick(Unit -> VisibleMatches,Nat.is_lt(matchLastRow(value),minimum),
        _ => visibleMatches(rest,minimum,maximum,position + 1n,position + 1n,reversed),
        _ => Bool.pick(Unit -> VisibleMatches,Nat.is_gt(Search.firstRow(value),maximum),
          _ => VisibleMatches{List.reverse(&2,Search.Match,reversed),startIndex},
          _ => visibleMatches(rest,minimum,maximum,position + 1n,startIndex,value <> reversed))(Unit{}))(Unit{})
def highlightVisible(visible: VisibleMatches,lines: List<&2,String>,selected: Maybe<&2,Nat>,top: Nat,rect: Geometry.LayoutRect,clip: Geometry.LayoutRect,styles: Search.Styles) -> List<&2,String>:
  match visible:
    case VisibleMatches{matches,startIndex}: highlightRows(lines,0n,matches,selected,top,startIndex,rect,clip,styles)
def highlightWith(active: Maybe<&2,Search.Session>,content: Maybe<&2,BaseTui.PrimaryContent>,lines: List<&2,String>,styles: Search.Styles) -> List<&2,String>:
  match active content:
    case Some{Search.Session{_,_,matches,selected,_,_}} Some{BaseTui.PrimaryContent{_,+top,visibleRows,rect,clip}}:
      highlightVisible(visibleMatches(matches,top,top + visibleRows,0n,0n,Nil{}),lines,selected,top,rect,clip,styles)
    case _ _: lines
def highlightSearch(+state: State,lines: List<&2,String>,content: Maybe<&2,BaseTui.PrimaryContent>,styles: Search.Styles) -> List<&2,String>:
  highlightWith(search(state),content,lines,styles)
def planWithIndicator(+state: State,lines: List<&2,String>,cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,height: Nat,row: Maybe<&2,Nat>,label: String) -> Plan:
  match row:
    case None{}: plan(state,searchDecorated(search(state),lines,width),cursor,width,height)
    case Some{position}: plan(state,searchDecorated(search(state),indicatorLines(lines,position,label,width),width),cursor,width,height)

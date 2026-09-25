import Base
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/string.bend as Strings
import ./tui-main-screen.bend as Screen
import ./terminal-image.bend as Image
import ./utils.bend as Layout
import ./tui.bend as Tui

# The alternate screen owns a fixed-size image of the terminal. Rendering is a
# pure diff; the process commits the new image only after its write succeeds.
type State is Data: State{lines: List<&2,String>,width: Maybe<&2,Nat>,height: Maybe<&2,Nat>,indicator: Callback.Callback<Unit,String>}
type Plan is Data: Plan{state: State,output: Screen.Stream}

def initial(indicator: Callback.Callback<Unit,String>) -> State: State{Nil{},None{},None{},indicator}
def indicator(state: State) -> Callback.Callback<Unit,String>:
  match state: case State{_,_,_,label}: label
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
    List.append(&2,Screen.Operation,documentRows(lines,width,True{},Nil{}),Screen.Text{"\u{1b}[0m\u{1b}[?7h\r\n\u{1b}[?25h\u{1b}[?2026l"} <> Nil{}))
def reset(state: State) -> State:
  match state:
    case State{_,_,_,label}: initial(label)
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
    case State{old,previousWidth,previousHeight,label}:
      +full = Bool.not(sameDimension(previousWidth,width) && sameDimension(previousHeight,height))
      +fitted = fit(lines,height,Nil{})
      +body = rows(old,fitted,0n,full,Nil{})
      +clear = Bool.pick(List<&2,Screen.Operation>,full,Screen.Text{"\u{1b}[2J"} <> body,body)
      +output = Screen.stream(Screen.Text{"\u{1b}[?2026h"} <> List.append(&2,Screen.Operation,clear,Screen.Text{cursorText(cursor,width) ++ "\u{1b}[?2026l"} <> Nil{}))
      Plan{State{fitted,Some{width},Some{height},label},output}

def indicatorLine(line: String,+label: String,+width: Nat) -> String:
  +size = Layout.visibleWidth(label)
  Tui.compositeTuiLine(line,label,(width - size) / 2n,size,width)
def indicatorLines(lines: List<&2,String>,row: Nat,+label: String,width: Nat) -> List<&2,String>:
  match lines row:
    case Nil{} _: Nil{}
    case line <> rest Zero{}: indicatorLine(line,label,width) <> rest
    case line <> rest Succ{above}: line <> indicatorLines(rest,above,label,width)
def planWithIndicator(state: State,lines: List<&2,String>,cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,height: Nat,row: Maybe<&2,Nat>,label: String) -> Plan:
  match row:
    case None{}: plan(state,lines,cursor,width,height)
    case Some{position}: plan(state,indicatorLines(lines,position,label,width),cursor,width,height)

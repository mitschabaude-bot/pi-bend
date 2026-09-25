import Base
import ../packages/tui/src/alt-screen-search.bend as Search
import ../packages/tui/src/utils.bend as Utils
import ../packages/tui/src/tui-alt-screen.bend as Alt
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/layout.bend as Layout

def segment(value: Search.Segment) -> String:
  match value:
    case Search.Segment{row,startCol,endCol}: Nat.show(row) ++ ":" ++ Nat.show(startCol) ++ "-" ++ Nat.show(endCol)
def segments(values: List<&2,Search.Segment>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: segment(value)
    case value <> rest: segment(value) ++ "," ++ segments(rest)
def found(value: Search.Match) -> String:
  match value: case Search.Match{values}: segments(values)
def matches(values: List<&2,Search.Match>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: found(value)
    case value <> rest: found(value) ++ ";" ++ matches(rest)
def checked(equal: Bool,label: String,actual: String,want: String) -> IO(Unit):
  match equal:
    case True{}: IO.print(label ++ " passed")
    case False{}: IO.die(Unit,1,label ++ ": got " ++ actual ++ ", expected " ++ want)
def check(label: String,+actual: String,+want: String) -> IO(Unit):
  checked(String.eq(actual,want),label,actual,want)
def changed(result: Search.SearchResult) -> String:
  match result:
    case Search.SearchResult{values,isChanged}:
      Bool.pick(String,isChanged,"changed:","cached:") ++ matches(values)
def cacheFourth(pair: Search.Index & Search.SearchResult,prior: String) -> String:
  match pair:
    case (_,result): prior ++ ";" ++ changed(result)
def cacheThird(pair: Search.Index & Search.SearchResult,prior: String) -> String:
  match pair:
    case (index,result): cacheFourth(Search.search(index,["alpha needle","no match"],"omega"),prior ++ ";" ++ changed(result))
def cacheSecond(pair: Search.Index & Search.SearchResult,prior: String) -> String:
  match pair:
    case (index,result): cacheThird(Search.search(index,["alpha needle","omega"],"omega"),prior ++ ";" ++ changed(result))
def cacheFirst(pair: Search.Index & Search.SearchResult) -> String:
  match pair:
    case (index,result): cacheSecond(Search.search(index,["alpha needle","omega"],"needle"),changed(result))
def cacheSequence() -> String:
  cacheFirst(Search.search(Search.index(),["alpha needle","omega"],"needle"))
def plainLines(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: Utils.stripTerminalSequences(line)
    case line <> rest: Utils.stripTerminalSequences(line) ++ "\n" ++ plainLines(rest)
def highlightResult(result: Search.Refreshed) -> String:
  match result:
    case Search.Refreshed{active,_}:
      +lines = Alt.highlightWith(Some{active},Some{Tui.PrimaryContent{["needle one","middle","needle two"],0n,3n,Layout.LayoutRect{0n,0n,20n,3n},Layout.LayoutRect{0n,0n,20n,3n}}},["needle one","middle","needle two"],Search.Styles{"\u{1b}[38;5;188m","\u{1b}[48;5;59m"})
      String.join(lines,"|")
def highlightCase() -> String:
  highlightResult(Search.refreshed(Search.withQuery(Search.open(0n),"needle",0n),["needle one","middle","needle two"],0n,3n))
def main() -> IO(Unit):
  do IO<Unit>:
    check("cross-row",matches(Search.findMatches(["alpha QUICK","brown fox"],"quick brown")),"0:6-11,1:0-5")
    check("Unicode columns",matches(Search.findMatches(["\u{1b}[31mfoo  bar\u{1b}[0m","A界🙂éZ"],"oo   bar\nA界🙂é")),"0:1-3,0:5-8,1:0-6")
    check("index cache",cacheSequence(),"changed:0:6-12;cached:0:6-12;changed:1:0-5;changed:")
    check("search box",plainLines(Search.searchLines("",None{},0n,48n,"Shift+Enter","Enter")),"┌──────────────────────────────────────────────┐\n│ Find in transcript                           │\n└──────────────────── ↑ Shift+Enter · ↓ Enter ─┘")
    check("visible highlight",highlightCase(),"\u{1b}[1;7m\u{1b}[38;5;188m\u{1b}[48;5;59mneedle\u{1b}[0m one|middle|\u{1b}[4m\u{1b}[38;5;188m\u{1b}[48;5;59mneedle\u{1b}[0m two")

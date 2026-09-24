import Base
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../render-utils.bend as Render
import ../index.bend as Tools
import ../edit.bend as Edit
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../tui/src/components/box.bend as Box
import ../../../../../tui/src/components/text.bend as TuiText

def renderCall(args: Value.Value,theme: Theme.Theme) -> IO(String):
  Render.pathCall(theme,"edit",args)
def diffValue(details: Maybe<&2,Tools.ToolDetails>) -> Maybe<&2,String>:
  match details:
    case Some{Tools.EditDetails{Edit.EditToolDetails{diff,_,_}}}: Some{diff}
    case _: None{}
def colorDiffLine(theme: Theme.Theme,line: String) -> IO(String):
  match line:
    case SCon{'-',_}: Messages.foregroundText(theme,"toolDiffRemoved",line)
    case SCon{'+',_}: Messages.foregroundText(theme,"toolDiffAdded",line)
    case _: Messages.foregroundText(theme,"toolDiffContext",line)
def commonLengthFrom(a: String,b: String,+count: Nat) -> Nat:
  match a b:
    case SCon{left,restLeft} SCon{right,restRight}:
      Bool.pick(Unit -> Nat,Char.is_eq(left,right),_ => commonLengthFrom(restLeft,restRight,count + 1n),_ => count)(Unit{})
    case _ _: count
def commonLength(a: String,b: String) -> Nat: commonLengthFrom(a,b,0n)
def wordBoundary(+text: String,+index: Nat) -> Bool:
  Nat.is_eq(index,0n) || Nat.is_eq(index,String.length(text)) || String.ends_with(String.take(text,index)," ") || String.starts_with(String.drop(text,index)," ") || String.ends_with(String.take(text,index),"\t") || String.starts_with(String.drop(text,index),"\t")
def space(+char: Char) -> Bool: Char.is_eq(char,' ') || Char.is_eq(char,'\t')
def lastSpaceEnd(chars: String,+index: Nat,last: Nat) -> Nat:
  match chars:
    case SNil{}: last
    case SCon{char,rest}: lastSpaceEnd(rest,index + 1n,Bool.pick(Nat,space(char),index + 1n,last))
def firstSpace(chars: String,+index: Nat) -> Maybe<&2,Nat>:
  match chars:
    case SNil{}: None{}
    case SCon{char,rest}: Bool.pick(Unit -> Maybe<&2,Nat>,space(char),_ => Some{index},_ => firstSpace(rest,index + 1n))(Unit{})
def suffixAfterSpace(found: Maybe<&2,Nat>,count: Nat) -> Nat:
  match found:
    case Some{position}: count - position
    case None{}: 0n
def alignedPrefix(+before: String,+after: String,+count: Nat) -> Nat:
  Bool.pick(Nat,wordBoundary(before,count) && wordBoundary(after,count),count,lastSpaceEnd(String.take(before,count),0n,0n))
def alignedSuffix(+before: String,+after: String,+count: Nat) -> Nat:
  Bool.pick(Nat,wordBoundary(before,String.length(before) - count) && wordBoundary(after,String.length(after) - count),count,
    suffixAfterSpace(firstSpace(String.take(String.drop(before,String.length(before) - count),count),0n),count))
def contentStart(line: String,count: Nat) -> Nat:
  match line:
    case SNil{}: count
    case SCon{' ',_}: count + 1n
    case SCon{_,rest}: contentStart(rest,count + 1n)
def highlight(+content: String,+prefix: Nat,+suffix: Nat) -> String:
  +middle = String.take(String.drop(content,prefix),String.length(content) - prefix - suffix)
  Bool.pick(String,String.is_empty(middle),content,
    String.take(content,prefix) ++ "\u{1b}[7m" ++ middle ++ "\u{1b}[27m" ++ String.drop(content,String.length(content) - suffix))
def markedPair(+removed: String,+added: String) -> String & String:
  +removedStart = contentStart(removed,0n)
  +addedStart = contentStart(added,0n)
  +before = String.drop(removed,removedStart)
  +after = String.drop(added,addedStart)
  +prefix = alignedPrefix(before,after,commonLength(before,after))
  +suffix = alignedSuffix(before,after,commonLength(String.reverse(String.drop(before,prefix)),String.reverse(String.drop(after,prefix))))
  (String.take(removed,removedStart) ++ highlight(before,prefix,suffix),String.take(added,addedStart) ++ highlight(after,prefix,suffix))
def colorPair(pair: String & String,+theme: Theme.Theme) -> IO(String & String):
  match pair:
    case (oldMarked,newMarked):
      do IO<String & String>:
        oldLine : String <- Messages.foregroundText(theme,"toolDiffRemoved",oldMarked)
        newLine : String <- Messages.foregroundText(theme,"toolDiffAdded",newMarked)
        return (oldLine,newLine)
def prependPair(pair: String & String,reversed: List<&2,String>) -> List<&2,String>:
  match pair:
    case (oldLine,newLine): newLine <> (oldLine <> reversed)
def colorDiff(lines: List<&2,String>,+theme: Theme.Theme,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case SCon{'-',oldRest} <> (SCon{'+',newRest} <> rest):
      do IO<List<&2,String>>:
        pair : String & String <- colorPair(markedPair("-" ++ oldRest,"+" ++ newRest),theme)
        colorDiff(rest,theme,prependPair(pair,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        colored : String <- colorDiffLine(theme,line)
        colorDiff(rest,theme,colored <> reversed)
def renderDiff(diff: String,theme: Theme.Theme) -> IO(String):
  do IO<String>:
    lines : List<&2,String> <- colorDiff(String.split(String.join(String.split(diff,'\t'),"   "),'\n'),theme,Nil{})
    return String.join(lines,"\n")
def renderSuccess(diff: Maybe<&2,String>,theme: Theme.Theme) -> IO(String):
  match diff:
    case Some{value}: renderDiff(value,theme)
    case None{}: IO.pure(String,"")
def renderResult(output: String,details: Maybe<&2,Tools.ToolDetails>,isError: Bool,theme: Theme.Theme) -> IO(String):
  match isError:
    case True{}: Messages.foregroundText(theme,"error",output)
    case False{}: renderSuccess(diffValue(details),theme)
def resultLines(value: TuiText.Text & List<&2,String>) -> List<&2,String>:
  match value: case (_,lines): lines
def textLines(text: String,x: Nat,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    rendered : TuiText.Text & List<&2,String> <- TuiText.render(TuiText.new(text,Some{x},Some{0n},None{}),width)
    return resultLines(rendered)
def background(result: Bool,error: Bool) -> String:
  Bool.pick(String,error,"toolErrorBg",Bool.pick(String,result,"toolSuccessBg","toolPendingBg"))
def paintBox(content: String,+theme: Theme.Theme,hasResult: Bool,error: Bool,+width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +bg : Callback.Callback<String,String> <- Messages.color(theme,background(hasResult,error),True{})
    lines : List<&2,String> <- textLines(content,0n,Nat.max(1n,width - 2n))
    +body : List<&2,String> <- Box.paintContent(Box.prependMargin(lines," ",Nil{}),width,Some{bg},Nil{})
    +top : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
    +bottom : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
    Callback.dispose(String,String,bg)
    return "" <> List.append(&2,String,top,List.append(&2,String,body,bottom))
def displayError(lines: List<&2,String>,body: String,width: Nat) -> IO(List<&2,String>):
  match body:
    case "": IO.pure(List<&2,String>,lines)
    case text:
      do IO<List<&2,String>>:
        result : List<&2,String> <- textLines(text,1n,width)
        return List.append(&2,String,lines,"" <> result)
def display(call: String,+result: String,hasResult: Bool,error: Bool,theme: Theme.Theme,+width: Nat) -> IO(List<&2,String>):
  match error:
    case True{}:
      do IO<List<&2,String>>:
        header : List<&2,String> <- paintBox(call,theme,False{},True{},width)
        displayError(header,result,width)
    case False{}:
      paintBox(call ++ Bool.pick(String,String.is_empty(result),"","\n\n" ++ result),theme,hasResult,False{},width)
def render(args: Value.Value,output: String,details: Maybe<&2,Tools.ToolDetails>,hasResult: Bool,+error: Bool,+theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    call : String <- renderCall(args,theme)
    result : String <- renderResult(output,details,error,theme)
    display(call,result,hasResult,error,theme,width)

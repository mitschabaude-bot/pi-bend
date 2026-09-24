import Base
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../runtime/src/record.bend as Record
import ../index.bend as Tools
import ../read.bend as Read
import ../truncate.bend as Truncate

# Read presentation uses the typed tool result; the collapsed success view is
# intentionally just its path and optional line range.
def field(args: Value.Value,key: String) -> Maybe<&2,Value.Value>:
  match args:
    case Value.ObjectValue{record}: Record.get(Value.Value,record,key)
    case _: None{}
def pathValue(value: Maybe<&2,Value.Value>) -> Maybe<&2,String>:
  match value:
    case None{}: Some{""}
    case Some{Value.Null{}}: Some{""}
    case Some{Value.Text{text}}: Some{text}
    case _: None{}
def pathChoice(file: Maybe<&2,Value.Value>,pathArg: Maybe<&2,Value.Value>) -> Maybe<&2,String>:
  match file:
    case Some{Value.Text{text}}: Some{text}
    case _: pathValue(pathArg)
def path(+args: Value.Value) -> Maybe<&2,String>:
  pathChoice(field(args,"file_path"),field(args,"path"))
def shownPath(theme: Theme.Theme,value: Maybe<&2,String>) -> IO(String):
  match value:
    case None{}: Messages.foregroundText(theme,"error","[invalid arg]")
    case Some{""}: Messages.foregroundText(theme,"toolOutput","...")
    case Some{text}: Messages.foregroundText(theme,"accent",text)
def natural(value: Maybe<&2,Value.Value>) -> Maybe<&2,Nat>:
  match value:
    case Some{Value.Number{number}}: Some{U32.to_nat(F64.to_u32(number))}
    case _: None{}
def range(theme: Theme.Theme,offset: Maybe<&2,Nat>,limit: Maybe<&2,Nat>) -> IO(String):
  match offset limit:
    case None{} None{}: IO.pure(String,"")
    case Some{start} None{}: Messages.foregroundText(theme,"warning",":" ++ Nat.show(start))
    case None{} Some{+count}: Messages.foregroundText(theme,"warning",":" ++ "1" ++ Bool.pick(String,Nat.is_eq(count,0n),"","-" ++ Nat.show(count)))
    case Some{+start} Some{+count}: Messages.foregroundText(theme,"warning",":" ++ Nat.show(start) ++ Bool.pick(String,Nat.is_eq(count,0n),"","-" ++ Nat.show(start + count - 1n)))
def renderCall(+args: Value.Value,+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    title : String <- Messages.foregroundText(theme,"toolTitle","\u{1b}[1mread\u{1b}[22m")
    target : String <- shownPath(theme,path(args))
    lines : String <- range(theme,natural(field(args,"offset")),natural(field(args,"limit")))
    return title ++ " " ++ target ++ lines

def trimmedReverse(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case "" <> rest: trimmedReverse(rest)
    case _: List.reverse(&2,String,lines)
def contentLines(text: String) -> List<&2,String>:
  trimmedReverse(List.reverse(&2,String,String.split(String.join(String.split(text,'\t'),"   "),'\n')))
def colored(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        value : String <- Messages.foregroundText(theme,"toolOutput",line)
        colored(rest,theme,value <> reversed)
def notice(details: Maybe<&2,Tools.ToolDetails>) -> String:
  match details:
    case Some{Tools.ReadDetails{Read.ReadToolDetails{Truncate.TruncationResult{_,True{},_,totalLines,_,outputLines,_,_,True{},_,maxBytes}}}}:
      "[First line exceeds " ++ Truncate.formatSize(maxBytes) ++ " limit]"
    case Some{Tools.ReadDetails{Read.ReadToolDetails{Truncate.TruncationResult{_,True{},Some{Truncate.Lines{}},totalLines,_,outputLines,_,_,False{},maxLines,_}}}}:
      "[Truncated: showing " ++ Nat.show(outputLines) ++ " of " ++ Nat.show(totalLines) ++ " lines (" ++ Nat.show(maxLines) ++ " line limit)]"
    case Some{Tools.ReadDetails{Read.ReadToolDetails{Truncate.TruncationResult{_,True{},_,_,_,outputLines,_,_,False{},_,maxBytes}}}}:
      "[Truncated: " ++ Nat.show(outputLines) ++ " lines shown (" ++ Truncate.formatSize(maxBytes) ++ " limit)]"
    case _: ""
def warning(theme: Theme.Theme,text: String) -> IO(String):
  match text:
    case "": IO.pure(String,"")
    case value:
      do IO<String>:
        colored : String <- Messages.foregroundText(theme,"warning",value)
        return "\n" ++ colored
def renderResult(output: String,details: Maybe<&2,Tools.ToolDetails>,expanded: Bool,isError: Bool,+theme: Theme.Theme) -> IO(String):
  match expanded isError:
    case False{} False{}: IO.pure(String,"")
    case _ _:
      do IO<String>:
        +lines : List<&2,String> <- IO.pure(List<&2,String>,contentLines(output))
        +shown : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,lines,List.take(&2,String,lines,10n)))
        rendered : List<&2,String> <- colored(shown,theme,Nil{})
        truncated : String <- warning(theme,notice(details))
        return "\n\n" ++ String.join(rendered,"\n") ++ truncated

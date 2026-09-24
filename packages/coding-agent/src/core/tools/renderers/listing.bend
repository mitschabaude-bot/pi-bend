import Base
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../runtime/src/record.bend as Record
import ../truncate.bend as Truncate

# Shared presentation for the directory/search tools. The underlying tools
# still return typed details; this view also accepts details restored from JSON.
def field(value: Value.Value,key: String) -> Maybe<&2,Value.Value>:
  match value:
    case Value.ObjectValue{record}: Record.get(Value.Value,record,key)
    case _: None{}
def textValue(value: Maybe<&2,Value.Value>) -> Maybe<&2,String>:
  match value:
    case None{}: Some{""}
    case Some{Value.Null{}}: Some{""}
    case Some{Value.Text{text}}: Some{text}
    case _: None{}
def textField(value: Value.Value,key: String) -> Maybe<&2,String>:
  textValue(field(value,key))
def numberValue(value: Maybe<&2,Value.Value>) -> Maybe<&2,Nat>:
  match value:
    case Some{Value.Number{number}}: Some{U32.to_nat(F64.to_u32(number))}
    case _: None{}
def numberField(value: Value.Value,key: String) -> Maybe<&2,Nat>:
  numberValue(field(value,key))
def title(theme: Theme.Theme,name: String) -> IO(String):
  Messages.foregroundText(theme,"toolTitle","\u{1b}[1m" ++ name ++ "\u{1b}[22m")
def pathValue(theme: Theme.Theme,path: Maybe<&2,String>,accent: Bool) -> IO(String):
  match path:
    case None{}: Messages.foregroundText(theme,"error","[invalid arg]")
    case Some{""}: Messages.foregroundText(theme,Bool.pick(String,accent,"accent","toolOutput"),".")
    case Some{value}: Messages.foregroundText(theme,Bool.pick(String,accent,"accent","toolOutput"),value)
def path(theme: Theme.Theme,args: Value.Value,accent: Bool) -> IO(String):
  pathValue(theme,textField(args,"path"),accent)
def patternValue(theme: Theme.Theme,pattern: Maybe<&2,String>,slash: Bool) -> IO(String):
  match pattern:
    case None{}: Messages.foregroundText(theme,"error","[invalid arg]")
    case Some{+value}: Messages.foregroundText(theme,"accent",Bool.pick(String,slash,"/" ++ value ++ "/",value))
def pattern(theme: Theme.Theme,args: Value.Value,slash: Bool) -> IO(String):
  patternValue(theme,textField(args,"pattern"),slash)
def limitValue(theme: Theme.Theme,value: Maybe<&2,Nat>,bracketed: Bool) -> IO(String):
  match value:
    case None{}: IO.pure(String,"")
    case Some{limit}:
      +count = Nat.show(limit)
      Messages.foregroundText(theme,"toolOutput",Bool.pick(String,bracketed," (limit " ++ count ++ ")"," limit " ++ count))
def limit(theme: Theme.Theme,args: Value.Value,bracketed: Bool) -> IO(String):
  limitValue(theme,numberField(args,"limit"),bracketed)
def coloredLines(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        colored : String <- Messages.foregroundText(theme,"toolOutput",line)
        coloredLines(rest,theme,colored <> reversed)
def expandHint(+theme: Theme.Theme,remaining: Nat) -> IO(String):
  do IO<String>:
    start : String <- Messages.foregroundText(theme,"muted","\n... (" ++ Nat.show(remaining) ++ " more lines,")
    key : String <- Messages.foregroundText(theme,"dim",Messages.expandKeys())
    rest : String <- Messages.foregroundText(theme,"muted"," to expand")
    end : String <- Messages.foregroundText(theme,"muted",")")
    return start ++ " " ++ key ++ rest ++ end
def resultText(text: String,expanded: Bool,+theme: Theme.Theme,maxLines: Nat) -> IO(String):
  match text:
    case "": IO.pure(String,"")
    case content:
      do IO<String>:
        +lines : List<&2,String> <- IO.pure(List<&2,String>,String.split(content,'\n'))
        +display : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,lines,List.take(&2,String,lines,maxLines)))
        +colored : List<&2,String> <- coloredLines(display,theme,Nil{})
        +remaining : Nat <- IO.pure(Nat,List.length(&2,String,lines) - List.length(&2,String,display))
        Bool.pick(Unit -> IO(String),Nat.is_eq(remaining,0n),_ => IO.pure(String,"\n\n" ++ String.join(colored,"\n")),
          _ => do IO<String>:
            hint : String <- expandHint(theme,remaining)
            return "\n\n" ++ String.join(colored,"\n") ++ hint)(Unit{})
def result(output: String,expanded: Bool,theme: Theme.Theme,maxLines: Nat) -> IO(String):
  resultText(String.trim(output),expanded,theme,maxLines)
def warning(theme: Theme.Theme,parts: List<&2,String>) -> IO(String):
  match parts:
    case Nil{}: IO.pure(String,"")
    case values: Messages.foregroundText(theme,"warning","\n[Truncated: " ++ String.join(values,", ") ++ "]")
def withWarning(output: String,expanded: Bool,+theme: Theme.Theme,maxLines: Nat,parts: List<&2,String>) -> IO(String):
  do IO<String>:
    display : String <- result(output,expanded,theme,maxLines)
    notice : String <- warning(theme,parts)
    return display ++ notice
def byteWarning(details: Maybe<&2,Truncate.TruncationResult>) -> List<&2,String>:
  match details:
    case Some{Truncate.TruncationResult{_,True{},_,_,_,_,_,_,_,_,maxBytes}}: (Truncate.formatSize(maxBytes) ++ " limit") <> Nil{}
    case _: Nil{}

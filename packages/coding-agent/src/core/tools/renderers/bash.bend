import Base
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../runtime/src/f64.bend as F
import ../render-utils.bend as Render
import ../index.bend as Tools
import ../bash.bend as Bash
import ../truncate.bend as Truncate

# Bash keeps the latest output visible while streaming, then adds its typed
# truncation notice and elapsed time below the preview.
def command(value: Maybe<&2,String>,theme: Theme.Theme) -> IO(String):
  match value:
    case None{}: Messages.foregroundText(theme,"error","[invalid arg]")
    case Some{""}: Messages.foregroundText(theme,"toolOutput","...")
    case Some{text}: IO.pure(String,text)
def timeout(value: Maybe<&2,Value.Value>,theme: Theme.Theme) -> IO(String):
  match value:
    case Some{Value.Number{+seconds}}:
      Bool.pick(Unit -> IO(String),U32.is_eq(F64.to_u32(seconds),0),_ => IO.pure(String,""),
        _ => Messages.foregroundText(theme,"muted"," (timeout " ++ U32.show(F64.to_u32(seconds)) ++ "s)"))(Unit{})
    case _: IO.pure(String,"")
def renderCall(+args: Value.Value,+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    cmd : String <- command(Render.argument(args,"command"),theme)
    title : String <- Render.title(theme,"$ " ++ cmd)
    limit : String <- timeout(Render.field(args,"timeout"),theme)
    return title ++ limit

def colored(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        value : String <- Messages.foregroundText(theme,"toolOutput",line)
        colored(rest,theme,value <> reversed)
def expandHint(+theme: Theme.Theme,skipped: Nat) -> IO(String):
  do IO<String>:
    start : String <- Messages.foregroundText(theme,"muted","... (" ++ Nat.show(skipped) ++ " earlier lines,")
    key : String <- Messages.foregroundText(theme,"dim",Messages.expandKeys())
    ending : String <- Messages.foregroundText(theme,"muted"," to expand)")
    return "\n\n" ++ start ++ " " ++ key ++ ending
def trimmedOutput(source: String,+expanded: Bool,+theme: Theme.Theme) -> IO(String):
  match source:
    case "": IO.pure(String,"")
    case source:
      do IO<String>:
        +lines : List<&2,String> <- IO.pure(List<&2,String>,String.split(source,'\n'))
        +count : Nat <- IO.pure(Nat,List.length(&2,String,lines))
        +shown : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,lines,List.drop(&2,String,lines,count - 5n)))
        +display : List<&2,String> <- colored(shown,theme,Nil{})
        +skipped : Nat <- IO.pure(Nat,count - List.length(&2,String,shown))
        Bool.pick(Unit -> IO(String),Bool.not(expanded) && Nat.is_gt(skipped,0n),
          _ => do IO<String>:
            hint : String <- expandHint(theme,skipped)
            return hint ++ "\n" ++ String.join(display,"\n"),
          _ => IO.pure(String,"\n\n" ++ String.join(display,"\n")))(Unit{})
def outputText(output: String,expanded: Bool,theme: Theme.Theme) -> IO(String):
  trimmedOutput(String.trim(output),expanded,theme)
def withoutFooter(reversed: List<&2,String>,+output: String,path: String) -> String:
  match reversed:
    case +footer <> ("" <> earlier):
      Bool.pick(String,String.starts_with(footer,"[") && String.ends_with(footer,"]") && String.contains(footer,path),String.join(List.reverse(&2,String,earlier),"\n"),output)
    case _: output
def stripSettled(+output: String,details: Maybe<&2,Tools.ToolDetails>) -> String:
  match details:
    case Some{Tools.BashDetails{Bash.BashToolDetails{Some{Truncate.TruncationResult{_,True{},_,_,_,_,_,_,_,_,_}},Some{path}}}}:
      withoutFooter(List.reverse(&2,String,String.split(String.trim(output),'\n')),output,path)
    case _: output
def stripFooter(output: String,details: Maybe<&2,Tools.ToolDetails>,partial: Bool) -> String:
  match partial:
    case False{}: stripSettled(output,details)
    case True{}: output
def truncationNotice(value: Truncate.TruncationResult) -> String:
  match value:
    case Truncate.TruncationResult{_,False{},_,_,_,_,_,_,_,_,_}: ""
    case Truncate.TruncationResult{_,True{},Some{Truncate.Lines{}},totalLines,_,outputLines,_,_,_,_,_}:
      "Truncated: showing " ++ Nat.show(outputLines) ++ " of " ++ Nat.show(totalLines) ++ " lines"
    case Truncate.TruncationResult{_,True{},_,_,_,outputLines,_,_,_,_,maxBytes}:
      "Truncated: " ++ Nat.show(outputLines) ++ " lines shown (" ++ Truncate.formatSize(maxBytes) ++ " limit)"
def part(value: Maybe<&2,String>) -> List<&2,String>:
  match value:
    case None{}: Nil{}
    case Some{""}: Nil{}
    case Some{text}: text <> Nil{}
def detailsNotice(details: Maybe<&2,Tools.ToolDetails>) -> String:
  match details:
    case Some{Tools.BashDetails{Bash.BashToolDetails{cut,path}}}:
      +full = Maybe.map(&2,String,String,value => "Full output: " ++ value,path)
      +truncated = Maybe.map(&2,Truncate.TruncationResult,String,truncationNotice,cut)
      +parts = List.append(&2,String,part(full),part(truncated))
      Bool.pick(String,List.is_empty(&2,String,parts),"","[" ++ String.join(parts,". ") ++ "]")
    case _: ""
def warning(theme: Theme.Theme,notice: String) -> IO(String):
  match notice:
    case "": IO.pure(String,"")
    case value:
      do IO<String>:
        shown : String <- Messages.foregroundText(theme,"warning",value)
        return "\n" ++ shown
def tenths(result: Result<&2,&2,F.Error,Nat>) -> Nat:
  match result:
    case Done{value}: value
    case Fail{_}: 0n
def longDuration(+seconds: Nat) -> String:
  Bool.pick(String,Nat.is_lt(seconds,3600n),Nat.show(seconds / 60n) ++ "m " ++ Nat.show(seconds % 60n) ++ "s",Nat.show(seconds / 3600n) ++ "h " ++ Nat.show((seconds % 3600n) / 60n) ++ "m " ++ Nat.show(seconds % 60n) ++ "s")
def duration(+tenthsValue: Nat) -> String:
  Bool.pick(String,Nat.is_lt(tenthsValue,600n),Nat.show(tenthsValue / 10n) ++ "." ++ Nat.show(tenthsValue % 10n) ++ "s",longDuration(tenthsValue / 10n))
def timing(elapsed: Maybe<&2,F64>,partial: Bool,theme: Theme.Theme) -> IO(String):
  match elapsed:
    case None{}: IO.pure(String,"")
    case Some{ms}:
      do IO<String>:
        label : String <- Messages.foregroundText(theme,"muted",Bool.pick(String,partial,"Elapsed ","Took ") ++ duration(tenths(F.convert(F.divide(F.add(ms,F.fromU32(50)),F.fromU32(100))))))
        return "\n\n" ++ label
def renderResult(+output: String,+details: Maybe<&2,Tools.ToolDetails>,expanded: Bool,+partial: Bool,elapsed: Maybe<&2,F64>,+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    body : String <- outputText(stripFooter(output,details,partial),expanded,theme)
    notice : String <- warning(theme,detailsNotice(details))
    durationText : String <- timing(elapsed,partial,theme)
    return body ++ notice ++ durationText

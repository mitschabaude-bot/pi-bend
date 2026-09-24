import Base
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../render-utils.bend as Render

# The call previews the content being written; successful results need no
# second body because the call already shows it.
def trimmedReverse(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case "" <> rest: trimmedReverse(rest)
    case _: List.reverse(&2,String,lines)
def contentLines(content: String) -> List<&2,String>:
  trimmedReverse(List.reverse(&2,String,String.split(String.join(String.split(String.join(String.split(content,'\r'),""),'\t'),"   "),'\n')))
def coloredLines(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        colored : String <- Messages.foregroundText(theme,"toolOutput",line)
        coloredLines(rest,theme,colored <> reversed)
def expandHint(+theme: Theme.Theme,remaining: Nat,total: Nat) -> IO(String):
  do IO<String>:
    start : String <- Messages.foregroundText(theme,"muted","\n... (" ++ Nat.show(remaining) ++ " more lines, " ++ Nat.show(total) ++ " total,")
    key : String <- Messages.foregroundText(theme,"dim",Messages.expandKeys())
    rest : String <- Messages.foregroundText(theme,"muted"," to expand)")
    return start ++ " " ++ key ++ rest
def content(+theme: Theme.Theme,header: String,expanded: Bool,contentArg: Maybe<&2,String>) -> IO(String):
  match contentArg:
    case None{}:
      do IO<String>:
        invalid : String <- Messages.foregroundText(theme,"error","[invalid content arg - expected string]")
        return header ++ "\n\n" ++ invalid
    case Some{""}: IO.pure(String,header)
    case Some{body}:
      do IO<String>:
        +all : List<&2,String> <- IO.pure(List<&2,String>,contentLines(body))
        +display : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,all,List.take(&2,String,all,10n)))
        shown : List<&2,String> <- coloredLines(display,theme,Nil{})
        +remaining : Nat <- IO.pure(Nat,List.length(&2,String,all) - List.length(&2,String,display))
        +preview : String <- IO.pure(String,header ++ "\n\n" ++ String.join(shown,"\n"))
        Bool.pick(Unit -> IO(String),Nat.is_eq(remaining,0n),_ => IO.pure(String,preview),
          _ => do IO<String>:
            hint : String <- expandHint(theme,remaining,List.length(&2,String,all))
            return preview ++ hint)(Unit{})
def renderCall(+args: Value.Value,+theme: Theme.Theme,expanded: Bool) -> IO(String):
  do IO<String>:
    header : String <- Render.pathCall(theme,"write",args)
    content(theme,header,expanded,Render.argument(args,"content"))
def renderError(output: String,theme: Theme.Theme) -> IO(String):
  match output:
    case SCon{_,_}:
      do IO<String>:
        colored : String <- Messages.foregroundText(theme,"error",output)
        return "\n" ++ colored
    case _: IO.pure(String,"")
def renderResult(output: String,isError: Bool,theme: Theme.Theme) -> IO(String):
  match isError:
    case True{}: renderError(output,theme)
    case False{}: IO.pure(String,"")

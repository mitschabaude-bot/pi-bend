import Base
import ../../../modes/interactive/components/diff.bend as DiffView
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../runtime/src/json.bend as Decode
import ../../../../../runtime/src/record.bend as Record
import ../render-utils.bend as Render
import ../index.bend as Tools
import ../edit.bend as Edit
import ../edit-diff.bend as Edits
import ../diff.bend as Diff
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../tui/src/components/box.bend as Box
import ../../../../../tui/src/components/text.bend as TuiText

def renderCall(args: Value.Value,theme: Theme.Theme) -> IO(String):
  Render.pathCall(theme,"edit",args)
# Stored presentation data may predate the executable edit result's patch.
def decodeStoredDiff(value: Value.Value) -> Result<&2,&2,Decode.Error,Diff.DiffResult>:
  do Result<&2,&2,Decode.Error,Diff.DiffResult>:
    +fields : Record.Record<Value.Value> <- Decode.object(value)
    diff : String <- Decode.required(String,fields,"diff",Decode.string)
    first : Maybe<&2,Nat> <- Decode.optional(Nat,fields,"firstChangedLine",Tools.natural)
    return Diff.DiffResult{diff,first}
def decodedDiff(result: Result<&2,&2,Decode.Error,Diff.DiffResult>) -> Maybe<&2,Diff.DiffResult>:
  match result: case Done{diff}: Some{diff} case Fail{_}: None{}
def diffDetails(details: Maybe<&2,Tools.ToolDetails>) -> Maybe<&2,Diff.DiffResult>:
  match details:
    case Some{Tools.EditDetails{Edit.EditToolDetails{diff,_,line}}}: Some{Diff.DiffResult{diff,line}}
    case Some{Tools.RawDetails{value}}: decodedDiff(decodeStoredDiff(value))
    case _: None{}
def diffText(value: Diff.DiffResult) -> String:
  match value: case Diff.DiffResult{diff,_}: diff
def diffValue(details: Maybe<&2,Tools.ToolDetails>) -> Maybe<&2,String>:
  Maybe.map(&2,Diff.DiffResult,String,diffText,diffDetails(details))
def renderSuccess(diff: Maybe<&2,String>,theme: Theme.Theme) -> IO(String):
  match diff:
    case Some{value}: DiffView.renderDiff(value,theme)
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
# Once available, the preview stays in the call region. Settling an identical
# result changes its status without moving the diff into a second region.
def settledPreview(details: Maybe<&2,Tools.ToolDetails>,error: Bool,previous: Maybe<&2,Edits.Preview()>) -> Maybe<&2,Edits.Preview()>:
  match error:
    case True{}: previous
    case False{}: Maybe.default(&2,Maybe<&2,Edits.Preview()>,Maybe.map(&2,Diff.DiffResult,Maybe<&2,Edits.Preview()>,diff => Some{Done{diff}},diffDetails(details)),previous)
def previewText(preview: Maybe<&2,Edits.Preview()>,theme: Theme.Theme) -> IO(String):
  match preview:
    case None{}: IO.pure(String,"")
    case Some{Fail{message}}: Messages.foregroundText(theme,"error",message)
    case Some{Done{Diff.DiffResult{diff,_}}}: DiffView.renderDiff(diff,theme)
def previewFailed(preview: Maybe<&2,Edits.Preview()>,fallback: Bool) -> Bool:
  match preview:
    case Some{Fail{_}}: True{}
    case Some{Done{_}}: False{}
    case None{}: fallback
def errorRemainder(preview: Maybe<&2,Edits.Preview()>,+output: String,error: Bool) -> String:
  match preview:
    case Some{Fail{message}}: Bool.pick(String,error && Bool.not(String.eq(message,output)),output,"")
    case _: Bool.pick(String,error,output,"")
def renderRemainder(header: List<&2,String>,text: String,theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  match text:
    case "": IO.pure(List<&2,String>,header)
    case value:
      do IO<List<&2,String>>:
        colored : String <- Messages.foregroundText(theme,"error",value)
        displayError(header,colored,width)
def renderWithPreview(args: Value.Value,output: String,details: Maybe<&2,Tools.ToolDetails>,previous: Maybe<&2,Edits.Preview()>,+error: Bool,+theme: Theme.Theme,+width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    call : String <- renderCall(args,theme)
    +preview : Maybe<&2,Edits.Preview()> = settledPreview(details,error,previous)
    +text : String <- previewText(preview,theme)
    header : List<&2,String> <- paintBox(call ++ Bool.pick(String,String.is_empty(text),"","\n\n" ++ text),theme,Maybe.is_some(&2,Edits.Preview(),preview),previewFailed(preview,error),width)
    renderRemainder(header,errorRemainder(preview,output,error),theme,width)
def render(args: Value.Value,output: String,details: Maybe<&2,Tools.ToolDetails>,hasResult: Bool,error: Bool,theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  renderWithPreview(args,output,details,None{},error,theme,width)

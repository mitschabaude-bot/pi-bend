import Base
import ./messages.bend as Messages
import ../theme/theme.bend as Theme
import ../../../../../tui/src/components/box.bend as Box
import ../../../../../tui/src/components/text.bend as TuiText
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../tui/src/components/image.bend as ImageComponent
import ../../../../../tui/src/terminal-image.bend as TerminalImage
import ../../../../../tui/src/utils.bend as U
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../runtime/src/clock.bend as Clock
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../ai/src/types.bend as Ai
import ../../../../../ai/src/utils/json.bend as Json
import ../../../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../utils/shell.bend as Shell
import ../../../core/tools/renderers/find.bend as FindRenderer
import ../../../core/tools/renderers/grep.bend as GrepRenderer
import ../../../core/tools/renderers/ls.bend as LsRenderer
import ../../../core/tools/renderers/edit.bend as EditRenderer
import ../../../core/tools/edit.bend as Edit
import ../../../core/tools/edit-diff.bend as Edits
import ../../../core/tools/renderers/read.bend as ReadRenderer
import ../../../core/tools/renderers/write.bend as WriteRenderer
import ../../../core/tools/renderers/bash.bend as BashRenderer
import ../../../core/tools/render-utils.bend as Render
import ../../../core/tools/index.bend as Tools
import ../../../../../agent/src/types.bend as Agent
import ../../../core/extensions/tool-render.bend as ToolRender
import ../../../utils/image-convert.bend as ImageConvert

# Context computation is injectable, like a tool's operations. The transcript
# owns the callback; each mounted tool joins its reads before being disposed.
type PreviewRequest is Data: PreviewRequest{cwd: String,input: Edit.EditToolInput}
type ImageConfig is Data: ImageConfig{environment: TerminalImage.Environment,capabilities: TerminalImage.TerminalCapabilities,widthCells: F64,showImages: Bool}
type ToolContext is Data:
  ToolContext{cwd: String,compute: Callback.Callback<PreviewRequest,Edits.Preview()>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,read: Maybe<&2,ReadRenderer.Context>,markdown: Maybe<&2,Markdown.MarkdownTheme>,images: Maybe<&2,ImageConfig>}
type Shell is Data:
  Generic{}
  Boxed{call: Maybe<&2,ToolRender.Renderer()>,result: Maybe<&2,ToolRender.Renderer()>}
  SelfRendered{call: Maybe<&2,ToolRender.Renderer()>,result: Maybe<&2,ToolRender.Renderer()>}
  NativeBash{}
# A returned component belongs to this tool row until the next renderer
# replacement or row retirement. Line renderers remain width-dependent.
type Retained is Type: Retained{version: Nat,owner: Component.Owner}
type Slots is Type: Slots{call: Maybe<&1,Retained>,result: Maybe<&1,Retained>,callHeight: Nat,resultHeight: Nat}
type RenderMount is Data: RenderMount{slots: Ref.Ref<Slots>,version: Nat,invalidate: Callback.Callback<Unit,Unit>}
type ToolExecution is Data:
  ToolExecution{toolName: String,toolCallId: String,args: Value.Value,result: Maybe<&2,ToolRender.ToolResult>,expanded: Bool,showImages: Bool,isPartial: Bool,executionStarted: Bool,argsComplete: Bool,theme: Theme.Theme,shell: Shell,highlightCode: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>}
type Timing is Data:
  Waiting{}
  Running{clock: Clock.Clock}
  Finished{elapsedMs: F64}
def finished(state: ToolExecution) -> Bool:
  match state:
    case ToolExecution{_,_,_,Some{_},_,_,False{},_,_,_,_,_}: True{}
    case _: False{}
def completedTiming(clock: Clock.Clock,done: Bool) -> IO(Timing & Unit):
  match done:
    case False{}: IO.pure(Timing & Unit,(Running{clock},Unit{}))
    case True{}:
      do IO<Timing & Unit>:
        elapsed : F64 <- Clock.now(clock)
        return (Finished{elapsed},Unit{})
def beginTiming(current: Timing) -> IO(Timing & Unit):
  match current:
    case Finished{elapsed}: IO.pure(Timing & Unit,(Finished{elapsed},Unit{}))
    case Running{clock}: IO.pure(Timing & Unit,(Running{clock},Unit{}))
    case Waiting{}:
      do IO<Timing & Unit>:
        clock : Clock.Clock <- Clock.new()
        return (Running{clock},Unit{})
def updateTiming(current: Timing,done: Bool) -> IO(Timing & Unit):
  match current:
    case Finished{elapsed}: IO.pure(Timing & Unit,(Finished{elapsed},Unit{}))
    case Running{clock}: completedTiming(clock,done)
    case Waiting{}: IO.pure(Timing & Unit,(Waiting{},Unit{}))
def measured(current: Timing) -> IO(Timing & Maybe<&2,F64>):
  match current:
    case Finished{+elapsed}: IO.pure(Timing & Maybe<&2,F64>,(Finished{elapsed},Some{elapsed}))
    case Running{+clock}:
      do IO<Timing & Maybe<&2,F64>>:
        elapsed : F64 <- Clock.now(clock)
        return (Running{clock},Some{elapsed})
    case Waiting{}: IO.pure(Timing & Maybe<&2,F64>,(Waiting{},None{}))

def new(toolName: String,toolCallId: String,args: Value.Value,theme: Theme.Theme,shell: Shell) -> ToolExecution:
  ToolExecution{toolName,toolCallId,args,None{},False{},True{},True{},False{},False{},theme,shell,None{}}
def fromAiToolCall(call: Ai.ToolCall<Value.Value>,theme: Theme.Theme,shell: Shell) -> ToolExecution:
  match call: case Ai.ToolCall{id,name,args,_,_}: new(name,id,args,theme,shell)
# The theme's highlightCode for read and write previews.
def withHighlightCode(state: ToolExecution,highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,_}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def updateArgs(state: ToolExecution,args: Value.Value) -> ToolExecution:
  match state: case ToolExecution{name,id,_,result,expanded,images,partial,started,complete,theme,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def markExecutionStarted(state: ToolExecution) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,_,complete,theme,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,True{},complete,theme,shell,highlight}
def setArgsComplete(state: ToolExecution) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,started,_,theme,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,True{},theme,shell,highlight}
def updateResult(state: ToolExecution,result: ToolRender.ToolResult,isPartial: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,_,expanded,images,_,started,complete,theme,shell,highlight}: ToolExecution{name,id,args,Some{result},expanded,images,isPartial,started,complete,theme,shell,highlight}
def updateFromAgent(-D: Data,state: ToolExecution,result: Agent.AgentToolResult<D>,details: Maybe<&2,Tools.ToolDetails>,isError: Bool,isPartial: Bool) -> ToolExecution:
  match result: case Agent.AgentToolResult{content,_,_,_}: updateResult(state,ToolRender.ToolResult{content,isError,details},isPartial)
def updateFromAiResult(-D: Data,state: ToolExecution,message: Ai.ToolResultMessage<D>,details: Maybe<&2,Tools.ToolDetails>) -> ToolExecution:
  match message:
    case Ai.ToolResultMessage{_,_,content,_,_,isError,_}:
      updateResult(markExecutionStarted(setArgsComplete(state)),ToolRender.ToolResult{content,isError,details},False{})
def setExpanded(state: ToolExecution,expanded: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,_,images,partial,started,complete,theme,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def setShowImages(state: ToolExecution,images: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,_,partial,started,complete,theme,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def retheme(state: ToolExecution,theme: Theme.Theme) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,started,complete,_,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def context(state: ToolExecution,width: Nat,tool: Maybe<&2,ToolContext>,last: Maybe<&2,Component.Component>,invalidate: Maybe<&2,Callback.Callback<Unit,Unit>>) -> ToolRender.RenderContext:
  match state tool:
    case ToolExecution{name,id,args,result,expanded,_,partial,started,complete,theme,_,_} Some{ToolContext{_,_,_,_,markdown,_}}: ToolRender.RenderContext{name,id,args,result,expanded,partial,started,complete,width,theme,markdown,last,invalidate}
    case ToolExecution{name,id,args,result,expanded,_,partial,started,complete,theme,_,_} None{}: ToolRender.RenderContext{name,id,args,result,expanded,partial,started,complete,width,theme,None{},last,invalidate}
def title(state: ToolExecution) -> IO(String):
  match state:
    case ToolExecution{name,_,_,_,_,_,_,_,_,theme,_,_}:
      Messages.foregroundText(theme,"toolTitle","\u{1b}[1m" ++ name ++ "\u{1b}[22m")
def backgroundKey(state: ToolExecution) -> String:
  match state:
    case ToolExecution{_,_,_,_,_,_,True{},_,_,_,_,_}: "toolPendingBg"
    case ToolExecution{_,_,_,Some{ToolRender.ToolResult{_,True{},_}},_,_,False{},_,_,_,_,_}: "toolErrorBg"
    case _: "toolSuccessBg"
def resultTexts(content: List<&2,Ai.TextImageContent>,reversed: List<&2,String>) -> List<&2,String>:
  match content:
    case Nil{}: List.reverse(&2,String,reversed)
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest:
      +clean = String.join(String.split(Shell.sanitizeBinaryOutput(U.stripTerminalSequences(text)),'\r'),"")
      resultTexts(rest,clean <> reversed)
    case _ <> rest: resultTexts(rest,reversed)
def imageConfig(context: Maybe<&2,ToolContext>) -> Maybe<&2,ImageConfig>:
  match context:
    case Some{ToolContext{_,_,_,_,_,images}}: images
    case None{}: None{}
def configuredImages(state: ToolExecution,context: Maybe<&2,ToolContext>) -> ToolExecution:
  match context:
    case Some{ToolContext{_,_,_,_,_,Some{ImageConfig{_,_,_,enabled}}}}: setShowImages(state,enabled)
    case _: state
def withImageSetting(context: ToolContext,enabled: Bool) -> ToolContext:
  match context:
    case ToolContext{cwd,compute,redraw,read,markdown,Some{ImageConfig{environment,capabilities,width,_}}}:
      ToolContext{cwd,compute,redraw,read,markdown,Some{ImageConfig{environment,capabilities,width,enabled}}}
    case context: context
def canShowImages(config: Maybe<&2,ImageConfig>,enabled: Bool) -> Bool:
  match config enabled:
    case Some{ImageConfig{_,TerminalImage.TerminalCapabilities{TerminalImage.Kitty{},_,_},_,_}} True{}: True{}
    case Some{ImageConfig{_,TerminalImage.TerminalCapabilities{TerminalImage.ITerm2{},_,_},_,_}} True{}: True{}
    case _ _: False{}
def maybeDimensions(result: Result<&2,&2,TerminalImage.Error,TerminalImage.ImageDimensions>) -> Maybe<&2,TerminalImage.ImageDimensions>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}
def fallbackImage(+data: String,+mime: String,config: Maybe<&2,ImageConfig>) -> String:
  match config:
    case Some{ImageConfig{TerminalImage.Environment{_,_,home},capabilities,_,_}}:
      Result.default(&2,&2,TerminalImage.Error,String,TerminalImage.imageFallback(mime,maybeDimensions(TerminalImage.getImageDimensions(data,mime)),None{},home,capabilities),"")
    case None{}:
      Result.default(&2,&2,TerminalImage.Error,String,TerminalImage.imageFallback(mime,maybeDimensions(TerminalImage.getImageDimensions(data,mime)),None{},"",TerminalImage.TerminalCapabilities{TerminalImage.NoImages{},False{},False{}}),"")
def imageIndicators(content: List<&2,Ai.TextImageContent>,+config: Maybe<&2,ImageConfig>,reversed: List<&2,String>) -> List<&2,String>:
  match content:
    case Nil{}: List.reverse(&2,String,reversed)
    case Ai.TextImageImage{Ai.ImageContent{data,mime}} <> rest: imageIndicators(rest,config,fallbackImage(data,mime,config) <> reversed)
    case _ <> rest: imageIndicators(rest,config,reversed)
def textOutput(result: Maybe<&2,ToolRender.ToolResult>,images: Bool,+config: Maybe<&2,ImageConfig>) -> String:
  match result:
    case None{}: ""
    case Some{ToolRender.ToolResult{+content,_,_}}:
      +texts = resultTexts(content,Nil{})
      Bool.pick(String,canShowImages(config,images),String.join(texts,"\n"),String.join(List.append(&2,String,texts,imageIndicators(content,config,Nil{})),"\n"))
def argsJson(args: Value.Value) -> String:
  Maybe.default(&2,String,Json.stringifyPretty(SchemaJson.toJson(args)),"")
def textResult(value: TuiText.Text & List<&2,String>) -> List<&2,String>:
  match value: case (_,lines): lines
def textLines(text: String,x: Nat,y: Nat,width: Nat,bg: Maybe<&2,Callback.Callback<String,String>>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    rendered : TuiText.Text & List<&2,String> <- TuiText.render(TuiText.new(text,Some{x},Some{y},bg),width)
    return textResult(rendered)
def callFallback(state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    name : String <- title(state)
    textLines(name,0n,0n,width,None{})
def genericText(+state: ToolExecution,config: Maybe<&2,ImageConfig>) -> IO(String):
  match state:
    case ToolExecution{_,_,args,result,_,images,_,_,_,_,_,_}:
      do IO<String>:
        name : String <- title(state)
        +json : String <- IO.pure(String,argsJson(args))
        +output : String <- IO.pure(String,textOutput(result,images,config))
        return name ++ Bool.pick(String,String.is_empty(json),"","\n\n" ++ json) ++ Bool.pick(String,String.is_empty(output),"","\n" ++ output)
def generic(+state: ToolExecution,width: Nat,config: Maybe<&2,ImageConfig>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,_,_,_,_,_,_,theme,_,_}:
      do IO<List<&2,String>>:
        +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
        content : String <- genericText(state,config)
        lines : List<&2,String> <- textLines(content,1n,1n,width,Some{bg})
        Callback.dispose(String,String,bg)
        return "" <> lines

def errorOutput(result: Maybe<&2,ToolRender.ToolResult>) -> Bool:
  match result:
    case Some{ToolRender.ToolResult{_,True{},_}}: True{}
    case _: False{}
def resultDetails(result: Maybe<&2,ToolRender.ToolResult>) -> Maybe<&2,Tools.ToolDetails>:
  match result:
    case Some{ToolRender.ToolResult{_,_,details}}: details
    case None{}: None{}
def bashElapsed(result: Maybe<&2,ToolRender.ToolResult>,elapsed: Maybe<&2,F64>) -> Maybe<&2,F64>:
  match result:
    case None{}: None{}
    case Some{_}: elapsed
def builtResult(+name: String,+args: Value.Value,+highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>,+result: Maybe<&2,ToolRender.ToolResult>,+expanded: Bool,partial: Bool,elapsed: Maybe<&2,F64>,+theme: Theme.Theme,width: Nat,images: Bool,config: Maybe<&2,ImageConfig>) -> IO(String):
  match result name:
    case None{} _: IO.pure(String,"")
    case _ "read": ReadRenderer.renderResult(args,highlight,textOutput(result,images,config),resultDetails(result),expanded,errorOutput(result),theme)
    case _ "write":
      do IO<String>:
        +text : String <- WriteRenderer.renderResult(textOutput(result,images,config),errorOutput(result),theme)
        # Separate call/result Text components contribute a line boundary;
        # the write renderer itself contributes the blank line before errors.
        return Bool.pick(String,String.eq(text,""),"","\n" ++ text)
    case _ "bash": BashRenderer.renderResult(textOutput(result,images,config),resultDetails(result),expanded,partial,bashElapsed(result,elapsed),theme,width)
    case _ "find": FindRenderer.renderResult(textOutput(result,images,config),resultDetails(result),expanded,theme)
    case _ "grep": GrepRenderer.renderResult(textOutput(result,images,config),resultDetails(result),expanded,theme)
    case _ "ls": LsRenderer.renderResult(textOutput(result,images,config),resultDetails(result),expanded,theme)
    case _ _: IO.pure(String,"")
def readCall(args: Value.Value,theme: Theme.Theme,expanded: Bool,context: Maybe<&2,ToolContext>) -> IO(String):
  match context:
    case None{}: ReadRenderer.renderCall(args,theme)
    case Some{ToolContext{cwd,_,_,read,_,_}}: ReadRenderer.renderCallWithContext(args,theme,expanded,read,cwd)
def builtCall(name: String,args: Value.Value,context: Maybe<&2,ToolContext>,highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>,expanded: Bool,theme: Theme.Theme) -> IO(String):
  match name:
    case "read": readCall(args,theme,expanded,context)
    case "bash": BashRenderer.renderCall(args,theme)
    case "write": WriteRenderer.renderCall(args,highlight,write,theme,expanded)
    case "find": FindRenderer.renderCall(args,theme)
    case "grep": GrepRenderer.renderCall(args,theme)
    case "ls": LsRenderer.renderCall(args,theme)
    case _: Render.pathCall(theme,name,args)
def boxedBuiltinAs(+renderName: String,+state: ToolExecution,+width: Nat,elapsed: Maybe<&2,F64>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>,+context: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,+args,result,expanded,images,partial,_,_,+theme,_,+highlight}:
      do IO<List<&2,String>>:
        call : String <- builtCall(renderName,args,context,highlight,write,expanded,theme)
        extra : String <- builtResult(renderName,args,highlight,result,expanded,partial,elapsed,theme,Nat.max(1n,width - 2n),images,imageConfig(context))
        +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
        lines : List<&2,String> <- textLines(call ++ extra,0n,0n,Nat.max(1n,width - 2n),None{})
        +body : List<&2,String> <- Box.paintContent(Box.prependMargin(lines," ",Nil{}),width,Some{bg},Nil{})
        +top : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
        +bottom : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
        Callback.dispose(String,String,bg)
        return "" <> List.append(&2,String,top,List.append(&2,String,body,bottom))
def boxedBuiltin(+state: ToolExecution,+width: Nat,elapsed: Maybe<&2,F64>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>,+context: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  match state: case ToolExecution{name,_,_,_,_,_,_,_,_,_,_,_}: boxedBuiltinAs(name,state,width,elapsed,write,context)
def builtinWithPreview(+state: ToolExecution,width: Nat,elapsed: Maybe<&2,F64>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>,preview: Maybe<&2,Edits.Preview()>,context: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{"edit",_,args,+result,_,images,partial,_,_,theme,_,_}:
      EditRenderer.renderWithPreview(args,textOutput(result,images,imageConfig(context)),resultDetails(result),preview,errorOutput(result),theme,width)
    case _: boxedBuiltin(state,width,elapsed,write,context)
def builtinWithDuration(state: ToolExecution,width: Nat,elapsed: Maybe<&2,F64>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>) -> IO(List<&2,String>):
  builtinWithPreview(state,width,elapsed,write,None{},None{})
def builtin(state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  builtinWithDuration(state,width,None{},None{})

def coloredOutput(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        colored : String <- Messages.foregroundText(theme,"toolOutput",line)
        coloredOutput(rest,theme,colored <> reversed)
def preview(output: String,expanded: Bool) -> List<&2,String>:
  +lines = String.split(output,'\n')
  Bool.pick(List<&2,String>,expanded,lines,List.take(&2,String,lines,10n))
def resultFallback(state: ToolExecution,width: Nat,tool: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,result,expanded,images,_,_,_,+theme,_,_}:
      +output = textOutput(result,images,imageConfig(tool))
      Bool.pick(Unit -> IO(List<&2,String>),String.is_empty(output),_ => IO.pure(List<&2,String>,Nil{}),
        _ => do IO<List<&2,String>>:
          +display : List<&2,String> <- IO.pure(List<&2,String>,preview(output,expanded))
          colored : List<&2,String> <- coloredOutput(display,theme,Nil{})
          +remaining : Nat <- IO.pure(Nat,List.length(&2,String,String.split(output,'\n')) - List.length(&2,String,display))
          +joined : String <- IO.pure(String,String.join(colored,"\n"))
          +text : String <- Bool.pick(Unit -> IO(String),Nat.is_eq(remaining,0n),_ => IO.pure(String,joined),
            _ => do IO<String>:
              start : String <- Messages.foregroundText(theme,"muted","\n... (" ++ Nat.show(remaining) ++ " more lines,")
              key : String <- Messages.foregroundText(theme,"dim",Messages.expandKeys())
              hint : String <- Messages.foregroundText(theme,"muted"," to expand")
              end : String <- Messages.foregroundText(theme,"muted",")")
              return joined ++ start ++ " " ++ key ++ hint ++ end)(Unit{})
          textLines(text,0n,0n,width,None{}))(Unit{})
def componentRows(pair: Component.Owner & Component.Component,width: Nat) -> IO(List<&2,String>):
  match pair:
    case (owner,component):
      do IO<List<&2,String>>:
        lines : List<&2,String> <- Component.render(component,width)
        Component.dispose(owner)
        return lines
def renderedSlot(output: ToolRender.RenderResult(),+state: ToolExecution,+width: Nat,call: Bool,tool: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  match output:
    case Done{ToolRender.RenderLines{lines}}: IO.pure(List<&2,String>,lines)
    case Done{ToolRender.RenderComponent{owner}}: componentRows(Component.borrow(owner),width)
    case _: Bool.pick(Unit -> IO(List<&2,String>),call,_ => callFallback(state,width),_ => resultFallback(state,width,tool))(Unit{})
def disposeRetained(slot: Maybe<&1,Retained>) -> IO(Unit):
  match slot:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Retained{_,owner}}: Component.dispose(owner)
def borrowedRetained(slot: Maybe<&1,Retained>) -> Maybe<&1,Retained> & Maybe<&2,Component.Component>:
  match slot:
    case None{}: (None{},None{})
    case Some{Retained{version,Component.Owner{+component,retire}}}:
      (Some{Retained{version,Component.Owner{component,retire}}},Some{component})
def paintedRetained(slot: Retained,width: Nat) -> IO(Retained & List<&2,String>):
  match slot:
    case Retained{version,Component.Owner{+component,retire}}:
      do IO<Retained & List<&2,String>>:
        lines : List<&2,String> <- Component.render(component,width)
        return (Retained{version,Component.Owner{component,retire}},lines)
def keptRows(pair: Retained & List<&2,String>) -> Maybe<&1,Retained> & List<&2,String>:
  match pair: case (kept,lines): (Some{kept},lines)
def retainedRows(slot: Maybe<&1,Retained>,+version: Nat,+width: Nat,+state: ToolExecution,call: Bool,tool: Maybe<&2,ToolContext>) -> IO(Maybe<&1,Retained> & List<&2,String>):
  match slot:
    case Some{Retained{_,owner}}:
      do IO<Maybe<&1,Retained> & List<&2,String>>:
        pair : Retained & List<&2,String> <- paintedRetained(Retained{version,owner},width)
        return keptRows(pair)
    case None{}:
      do IO<Maybe<&1,Retained> & List<&2,String>>:
        lines : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),call,_ => callFallback(state,width),_ => resultFallback(state,width,tool))(Unit{})
        return (None{},lines)
def installedOutput(previous: Maybe<&1,Retained>,output: ToolRender.RenderResult(),+version: Nat,+width: Nat,+state: ToolExecution,call: Bool,tool: Maybe<&2,ToolContext>) -> IO(Maybe<&1,Retained> & List<&2,String>):
  match output:
    case Done{ToolRender.RenderComponent{owner}}:
      do IO<Maybe<&1,Retained> & List<&2,String>>:
        disposeRetained(previous)
        shared : Component.Owner <- Component.shared(owner)
        retainedRows(Some{Retained{version,shared}},version,width,state,call,tool)
    case Done{ToolRender.ReuseComponent{}}: retainedRows(previous,version,width,state,call,tool)
    case Done{ToolRender.RenderLines{lines}}:
      do IO<Maybe<&1,Retained> & List<&2,String>>:
        disposeRetained(previous)
        return (None{},lines)
    case Fail{_}:
      do IO<Maybe<&1,Retained> & List<&2,String>>:
        disposeRetained(previous)
        lines : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),call,_ => callFallback(state,width),_ => resultFallback(state,width,tool))(Unit{})
        return (None{},lines)
def invokeWithLast(pair: Maybe<&1,Retained> & Maybe<&2,Component.Component>,renderer: ToolRender.Renderer(),+state: ToolExecution,+width: Nat,call: Bool,+tool: Maybe<&2,ToolContext>,version: Nat,invalidate: Callback.Callback<Unit,Unit>) -> IO(Maybe<&1,Retained> & List<&2,String>):
  match pair:
    case (prior,last):
      do IO<Maybe<&1,Retained> & List<&2,String>>:
        output : ToolRender.RenderResult() <- Callback.call(ToolRender.RenderContext,ToolRender.RenderResult(),renderer,context(state,width,tool,last,Some{invalidate}))
        installedOutput(prior,output,version,width,state,call,tool)
def invokeMounted(previous: Maybe<&1,Retained>,renderer: ToolRender.Renderer(),state: ToolExecution,width: Nat,call: Bool,tool: Maybe<&2,ToolContext>,version: Nat,invalidate: Callback.Callback<Unit,Unit>) -> IO(Maybe<&1,Retained> & List<&2,String>):
  invokeWithLast(borrowedRetained(previous),renderer,state,width,call,tool,version,invalidate)
def existingMounted(same: Bool,previous: Maybe<&1,Retained>,renderer: ToolRender.Renderer(),+state: ToolExecution,+width: Nat,call: Bool,+tool: Maybe<&2,ToolContext>,+version: Nat,+invalidate: Callback.Callback<Unit,Unit>) -> IO(Maybe<&1,Retained> & List<&2,String>):
  match same:
    case True{}: retainedRows(previous,version,width,state,call,tool)
    case False{}: invokeMounted(previous,renderer,state,width,call,tool,version,invalidate)
def renderMountedSlot(previous: Maybe<&1,Retained>,renderer: Maybe<&2,ToolRender.Renderer()>,+state: ToolExecution,+width: Nat,call: Bool,+tool: Maybe<&2,ToolContext>,+version: Nat,+invalidate: Callback.Callback<Unit,Unit>) -> IO(Maybe<&1,Retained> & List<&2,String>):
  match previous renderer:
    case Some{Retained{+oldVersion,owner}} Some{callback}:
      existingMounted(Nat.is_eq(oldVersion,version),Some{Retained{oldVersion,owner}},callback,state,width,call,tool,version,invalidate)
    case previous Some{callback}: invokeMounted(previous,callback,state,width,call,tool,version,invalidate)
    case previous None{}:
      do IO<Maybe<&1,Retained> & List<&2,String>>:
        disposeRetained(previous)
        lines : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),call,_ => callFallback(state,width),_ => resultFallback(state,width,tool))(Unit{})
        return (None{},lines)
def callRows(pair: Maybe<&1,Retained> & List<&2,String>,result: Maybe<&1,Retained>,resultHeight: Nat) -> Slots & List<&2,String>:
  match pair: case (next,+lines): (Slots{next,result,List.length(&2,String,lines),resultHeight},lines)
def resultRows(pair: Maybe<&1,Retained> & List<&2,String>,call: Maybe<&1,Retained>,callHeight: Nat) -> Slots & List<&2,String>:
  match pair: case (next,+lines): (Slots{call,next,callHeight,List.length(&2,String,lines)},lines)
def mountedIn(slots: Slots,renderer: Maybe<&2,ToolRender.Renderer()>,state: ToolExecution,width: Nat,call: Bool,tool: Maybe<&2,ToolContext>,version: Nat,invalidate: Callback.Callback<Unit,Unit>) -> IO(Slots & List<&2,String>):
  match slots call:
    case Slots{callSlot,resultSlot,_,resultHeight} True{}:
      do IO<Slots & List<&2,String>>:
        pair : Maybe<&1,Retained> & List<&2,String> <- renderMountedSlot(callSlot,renderer,state,width,True{},tool,version,invalidate)
        return callRows(pair,resultSlot,resultHeight)
    case Slots{callSlot,resultSlot,callHeight,_} False{}:
      do IO<Slots & List<&2,String>>:
        pair : Maybe<&1,Retained> & List<&2,String> <- renderMountedSlot(resultSlot,renderer,state,width,False{},tool,version,invalidate)
        return resultRows(pair,callSlot,callHeight)
def renderMounted(mount: RenderMount,renderer: Maybe<&2,ToolRender.Renderer()>,state: ToolExecution,width: Nat,call: Bool,tool: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  match mount:
    case RenderMount{slots,version,invalidate}:
      Ref.update(Slots,List<&2,String>,slots,current => mountedIn(current,renderer,state,width,call,tool,version,invalidate))
def renderSlot(renderer: Maybe<&2,ToolRender.Renderer()>,+state: ToolExecution,+width: Nat,call: Bool,+tool: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  match renderer:
    case Some{callback}:
      do IO<List<&2,String>>:
        output : ToolRender.RenderResult() <- Callback.call(ToolRender.RenderContext,ToolRender.RenderResult(),callback,context(state,width,tool,None{},None{}))
        renderedSlot(output,state,width,call,tool)
    case None{}: Bool.pick(Unit -> IO(List<&2,String>),call,_ => callFallback(state,width),_ => resultFallback(state,width,tool))(Unit{})
def renderWithMount(renderer: Maybe<&2,ToolRender.Renderer()>,state: ToolExecution,width: Nat,call: Bool,tool: Maybe<&2,ToolContext>,mount: Maybe<&2,RenderMount>) -> IO(List<&2,String>):
  match mount:
    case Some{ready}: renderMounted(ready,renderer,state,width,call,tool)
    case None{}: renderSlot(renderer,state,width,call,tool)
def resultSlot(renderer: Maybe<&2,ToolRender.Renderer()>,state: ToolExecution,width: Nat,tool: Maybe<&2,ToolContext>,mount: Maybe<&2,RenderMount>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,None{},_,_,_,_,_,_,_,_}: renderWithMount(None{},state,width,False{},tool,mount)
    case _: renderWithMount(renderer,state,width,False{},tool,mount)
def boxContent(+state: ToolExecution,call: Maybe<&2,ToolRender.Renderer()>,result: Maybe<&2,ToolRender.Renderer()>,+width: Nat,+tool: Maybe<&2,ToolContext>,+mount: Maybe<&2,RenderMount>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    first : List<&2,String> <- renderWithMount(call,state,Nat.max(1n,width - 2n),True{},tool,mount)
    second : List<&2,String> <- resultSlot(result,state,Nat.max(1n,width - 2n),tool,mount)
    return List.append(&2,String,first,second)
def boxed(+state: ToolExecution,call: Maybe<&2,ToolRender.Renderer()>,result: Maybe<&2,ToolRender.Renderer()>,+width: Nat,tool: Maybe<&2,ToolContext>,mount: Maybe<&2,RenderMount>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,_,_,_,_,_,_,theme,_,_}:
      do IO<List<&2,String>>:
        +content : List<&2,String> <- boxContent(state,call,result,width,tool,mount)
        Bool.pick(Unit -> IO(List<&2,String>),List.is_empty(&2,String,content),
          _ => IO.pure(List<&2,String>,Nil{}),
          _ => do IO<List<&2,String>>:
            +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
            body : List<&2,String> <- Box.paintContent(Box.prependMargin(content," ",Nil{}),width,Some{bg},Nil{})
            top : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
            bottom : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
            Callback.dispose(String,String,bg)
            return "" <> List.append(&2,String,top,List.append(&2,String,body,bottom)))(Unit{})
def selfRendered(+state: ToolExecution,call: Maybe<&2,ToolRender.Renderer()>,result: Maybe<&2,ToolRender.Renderer()>,+width: Nat,+tool: Maybe<&2,ToolContext>,+mount: Maybe<&2,RenderMount>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    first : List<&2,String> <- renderWithMount(call,state,width,True{},tool,mount)
    second : List<&2,String> <- resultSlot(result,state,width,tool,mount)
    +content : List<&2,String> <- IO.pure(List<&2,String>,List.append(&2,String,first,second))
    return Bool.pick(List<&2,String>,List.is_empty(&2,String,content),Nil{},"" <> content)
def hasBuiltin(+name: String) -> Bool:
  String.eq(name,"read") || String.eq(name,"bash") || String.eq(name,"edit") || String.eq(name,"write") || String.eq(name,"find") || String.eq(name,"grep") || String.eq(name,"ls")
def convertedImage(converted: ImageConvert.ConvertedImage) -> Ai.ImageContent:
  match converted: case ImageConvert.ConvertedImage{base64,mime}: Ai.ImageContent{base64,mime}
def imageData(image: Ai.ImageContent,protocol: TerminalImage.ImageProtocol) -> Maybe<&2,Ai.ImageContent>:
  match image protocol:
    case Ai.ImageContent{data,"image/png"} _: Some{Ai.ImageContent{data,"image/png"}}
    case Ai.ImageContent{data,mime} TerminalImage.Kitty{}:
      Maybe.map(&2,ImageConvert.ConvertedImage,Ai.ImageContent,convertedImage,ImageConvert.convertToPng(data,mime))
    case image _: Some{image}
def imageLinesResult(result: Result<&2,&2,ImageComponent.Error,ImageComponent.Rendered>) -> List<&2,String>:
  match result:
    case Done{ImageComponent.Rendered{_,_,lines}}: "" <> lines
    case Fail{_}: Nil{}
def imageCreated(result: Result<&2,&2,ImageComponent.Error,ImageComponent.ImageComponent>,width: Nat,environment: TerminalImage.Environment,capabilities: TerminalImage.TerminalCapabilities) -> IO(List<&2,String>):
  match result:
    case Fail{_}: IO.pure(List<&2,String>,Nil{})
    case Done{component}:
      do IO<List<&2,String>>:
        rendered : Result<&2,&2,ImageComponent.Error,ImageComponent.Rendered> <- ImageComponent.render(component,width,TerminalImage.setCapabilities(TerminalImage.create(),capabilities),environment,False{})
        return imageLinesResult(rendered)
def imageProtocol(capabilities: TerminalImage.TerminalCapabilities) -> TerminalImage.ImageProtocol:
  match capabilities: case TerminalImage.TerminalCapabilities{protocol,_,_}: protocol
def preparedImage(image: Maybe<&2,Ai.ImageContent>,width: Nat,environment: TerminalImage.Environment,capabilities: TerminalImage.TerminalCapabilities,widthCells: F64,foreground: Callback.Callback<String,String>) -> IO(List<&2,String>):
  match image:
    case None{}: IO.pure(List<&2,String>,Nil{})
    case Some{Ai.ImageContent{data,mime}}:
      imageCreated(ImageComponent.new(data,mime,ImageComponent.ImageTheme{foreground},ImageComponent.ImageOptions{Some{widthCells},None{},None{},None{}},None{}),width,environment,capabilities)
def renderImage(image: Ai.ImageContent,width: Nat,theme: Theme.Theme,config: ImageConfig) -> IO(List<&2,String>):
  match config:
    case ImageConfig{environment,+capabilities,widthCells,_}:
      do IO<List<&2,String>>:
        +foreground : Callback.Callback<String,String> <- Messages.color(theme,"toolOutput",False{})
        +prepared : Maybe<&2,Ai.ImageContent> = imageData(image,imageProtocol(capabilities))
        +lines : List<&2,String> <- preparedImage(prepared,width,environment,capabilities,widthCells,foreground)
        Callback.dispose(String,String,foreground)
        return lines
def resultImages(content: List<&2,Ai.TextImageContent>,+width: Nat,+theme: Theme.Theme,+config: ImageConfig,reversed: List<&2,List<&2,String>>) -> IO(List<&2,String>):
  match content:
    case Nil{}: IO.pure(List<&2,String>,List.concat(&2,String,List.reverse(&2,List<&2,String>,reversed)))
    case Ai.TextImageImage{image} <> rest:
      do IO<List<&2,String>>:
        lines : List<&2,String> <- renderImage(image,width,theme,config)
        resultImages(rest,width,theme,config,lines <> reversed)
    case _ <> rest: resultImages(rest,width,theme,config,reversed)
def toolImagesFor(state: ToolExecution,width: Nat,config: Maybe<&2,ImageConfig>) -> IO(List<&2,String>):
  match state config:
    case ToolExecution{_,_,_,Some{ToolRender.ToolResult{content,_,_}},_,enabled,_,_,_,theme,_,_} Some{+config}:
      Bool.pick(Unit -> IO(List<&2,String>),canShowImages(Some{config},enabled),_ => resultImages(content,width,theme,config,Nil{}),_ => IO.pure(List<&2,String>,Nil{}))(Unit{})
    case _ _: IO.pure(List<&2,String>,Nil{})
def toolImages(state: ToolExecution,width: Nat,context: Maybe<&2,ToolContext>) -> IO(List<&2,String>):
  toolImagesFor(state,width,imageConfig(context))
def renderContent(+state: ToolExecution,+width: Nat,elapsed: Maybe<&2,F64>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>,preview: Maybe<&2,Edits.Preview()>,+context: Maybe<&2,ToolContext>,mount: Maybe<&2,RenderMount>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{+name,_,_,_,_,_,_,_,_,_,Generic{},_}:
      Bool.pick(Unit -> IO(List<&2,String>),hasBuiltin(name),_ => builtinWithPreview(state,width,elapsed,write,preview,context),_ => generic(state,width,imageConfig(context)))(Unit{})
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,NativeBash{},_}: boxedBuiltinAs("bash",state,width,elapsed,write,context)
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,Boxed{+call,+result},_}: boxed(state,call,result,width,context,mount)
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,SelfRendered{+call,+result},_}: selfRendered(state,call,result,width,context,mount)
def renderWithPreview(+state: ToolExecution,+width: Nat,elapsed: Maybe<&2,F64>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>,preview: Maybe<&2,Edits.Preview()>,+context: Maybe<&2,ToolContext>,mount: Maybe<&2,RenderMount>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    first : List<&2,String> <- renderContent(state,width,elapsed,write,preview,context,mount)
    images : List<&2,String> <- toolImages(state,width,context)
    return List.append(&2,String,first,images)
def renderWithDuration(state: ToolExecution,width: Nat,elapsed: Maybe<&2,F64>,write: Maybe<&2,WriteRenderer.WriteHighlightCache>) -> IO(List<&2,String>):
  renderWithPreview(state,width,elapsed,write,None{},None{},None{})
def render(state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  renderWithDuration(state,width,None{},None{})

# The viewport keeps this component mounted while the transcript replaces its
# immutable state as tool events arrive. As upstream's components keep their
# rendered text between frames, rendered lines are reused until the state
# (version), the width or the shown elapsed time changes.
type Preflight is Data:
  Preflight{context: Maybe<&2,ToolContext>,tasks: Ref.Ref<List<&2,Chan(Unit)>>,slots: Ref.Ref<Slots>}
type Stamped is Data: Stamped{value: ToolExecution,version: Nat,preview: Maybe<&2,Edits.Preview()>,revision: Nat}
type ImageKey is Data: ImageKey{data: String,mime: String}
type ImageFrame is Data: ImageFrame{width: Nat,keys: List<&2,ImageKey>,lines: List<&2,String>}
type Rendered is Data: Rendered{version: Nat,width: Nat,elapsed: Maybe<&2,F64>,lines: List<&2,String>,images: ImageFrame}
# The write preview's highlight cache (upstream WriteCallRenderComponent.cache).
type Owner is Type:
  Owner{state: Ref.Ref<Stamped>,rendered: Ref.Ref<Maybe<&2,Rendered>>,write: Ref.Ref<Maybe<&2,WriteRenderer.WriteHighlightCache>>,timing: Serial.Owner<Timing>,component: Component.Component,draw: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,children: Callback.Callback<Unit,List<&2,Component.Component>>,preflight: Preflight}
type Handle is Data: Handle{state: Ref.Ref<Stamped>,rendered: Ref.Ref<Maybe<&2,Rendered>>,write: Ref.Ref<Maybe<&2,WriteRenderer.WriteHighlightCache>>,timing: Serial.Handle<Timing>,preflight: Preflight,invalidate: Callback.Callback<Unit,Unit>}
def sameElapsed(left: Maybe<&2,F64>,right: Maybe<&2,F64>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: F64.is_eq(a,b)
    case _ _: False{}
# upstream renderCall runs whenever the display updates, which is when the
# stamped state changes here.
def refreshedWrite(value: ToolExecution,previous: Maybe<&2,WriteRenderer.WriteHighlightCache>) -> IO(Maybe<&2,WriteRenderer.WriteHighlightCache>):
  match value:
    case ToolExecution{"write",_,args,_,_,_,_,_,complete,_,_,highlight}: WriteRenderer.refreshCache(highlight,args,complete,previous)
    case _: IO.pure(Maybe<&2,WriteRenderer.WriteHighlightCache>,None{})
def imageKeys(content: List<&2,Ai.TextImageContent>,reversed: List<&2,ImageKey>) -> List<&2,ImageKey>:
  match content:
    case Nil{}: List.reverse(&2,ImageKey,reversed)
    case Ai.TextImageImage{Ai.ImageContent{data,mime}} <> rest: imageKeys(rest,ImageKey{data,mime} <> reversed)
    case _ <> rest: imageKeys(rest,reversed)
def visibleImageKeys(state: ToolExecution,config: Maybe<&2,ImageConfig>) -> List<&2,ImageKey>:
  match state config:
    case ToolExecution{_,_,_,Some{ToolRender.ToolResult{content,_,_}},_,enabled,_,_,_,_,_,_} config:
      Bool.pick(List<&2,ImageKey>,canShowImages(config,enabled),imageKeys(content,Nil{}),Nil{})
    case _ _: Nil{}
def sameImageKeys(left: List<&2,ImageKey>,right: List<&2,ImageKey>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case ImageKey{leftData,leftMime} <> moreLeft ImageKey{rightData,rightMime} <> moreRight:
      String.eq(leftData,rightData) && String.eq(leftMime,rightMime) && sameImageKeys(moreLeft,moreRight)
    case _ _: False{}
def imageFrameLines(frame: ImageFrame) -> List<&2,String>:
  match frame: case ImageFrame{_,_,lines}: lines
def freshImageFrame(state: ToolExecution,+width: Nat,context: Maybe<&2,ToolContext>,keys: List<&2,ImageKey>) -> IO(ImageFrame):
  match keys:
    case Nil{}: IO.pure(ImageFrame,ImageFrame{width,Nil{},Nil{}})
    case keys:
      do IO<ImageFrame>:
        lines : List<&2,String> <- toolImages(state,width,context)
        return ImageFrame{width,keys,lines}
def changedImageFrame(+state: ToolExecution,+width: Nat,+context: Maybe<&2,ToolContext>,+oldWidth: Nat,+oldKeys: List<&2,ImageKey>,oldLines: List<&2,String>) -> IO(ImageFrame):
  +keys = visibleImageKeys(state,imageConfig(context))
  Bool.pick(Unit -> IO(ImageFrame),Nat.is_eq(oldWidth,width) && sameImageKeys(oldKeys,keys),
    _ => IO.pure(ImageFrame,ImageFrame{oldWidth,oldKeys,oldLines}),
    _ => freshImageFrame(state,width,context,keys))(Unit{})
def cachedImageFrame(+state: ToolExecution,+width: Nat,+context: Maybe<&2,ToolContext>,version: Nat,previous: Maybe<&2,Rendered>) -> IO(ImageFrame):
  match previous:
    case Some{Rendered{oldVersion,_,_,_,ImageFrame{+oldWidth,+oldKeys,+oldLines}}}:
      Bool.pick(Unit -> IO(ImageFrame),Nat.is_eq(oldWidth,width) && Nat.is_eq(oldVersion,version),
        _ => IO.pure(ImageFrame,ImageFrame{oldWidth,oldKeys,oldLines}),
        _ => changedImageFrame(state,width,context,oldWidth,oldKeys,oldLines))(Unit{})
    case None{}: freshImageFrame(state,width,context,visibleImageKeys(state,imageConfig(context)))
def renderStamped(+context: Maybe<&2,ToolContext>,current: Stamped,+width: Nat,+elapsed: Maybe<&2,F64>,+rendered: Ref.Ref<Maybe<&2,Rendered>>,+write: Ref.Ref<Maybe<&2,WriteRenderer.WriteHighlightCache>>,slots: Ref.Ref<Slots>,invalidate: Callback.Callback<Unit,Unit>) -> IO(List<&2,String>):
  match current:
    case Stamped{+value,+version,+preview,+revision}:
      do IO<List<&2,String>>:
        previous : Maybe<&2,WriteRenderer.WriteHighlightCache> <- Ref.read(Maybe<&2,WriteRenderer.WriteHighlightCache>,write)
        +cache : Maybe<&2,WriteRenderer.WriteHighlightCache> <- refreshedWrite(value,previous)
        Ref.write(Maybe<&2,WriteRenderer.WriteHighlightCache>,write,cache)
        previousFrame : Maybe<&2,Rendered> <- Ref.read(Maybe<&2,Rendered>,rendered)
        +base : List<&2,String> <- renderContent(value,width,elapsed,cache,preview,context,Some{RenderMount{slots,version,invalidate}})
        +frame : ImageFrame <- cachedImageFrame(value,width,context,version,previousFrame)
        +lines : List<&2,String> = List.append(&2,String,base,imageFrameLines(frame))
        Ref.write(Maybe<&2,Rendered>,rendered,Some{Rendered{version,width,elapsed,lines,frame}})
        return lines
def cachedLines(+context: Maybe<&2,ToolContext>,cached: Maybe<&2,Rendered>,current: Stamped,+width: Nat,+elapsed: Maybe<&2,F64>,rendered: Ref.Ref<Maybe<&2,Rendered>>,write: Ref.Ref<Maybe<&2,WriteRenderer.WriteHighlightCache>>,slots: Ref.Ref<Slots>,invalidate: Callback.Callback<Unit,Unit>) -> IO(List<&2,String>):
  match cached current:
    case Some{Rendered{version,oldWidth,oldElapsed,lines,_}} Stamped{value,+now,+preview,+revision}:
      Bool.pick(Unit -> IO(List<&2,String>),Nat.is_eq(version,now) && Nat.is_eq(oldWidth,width) && sameElapsed(oldElapsed,elapsed),
        _ => IO.pure(List<&2,String>,lines),
        _ => renderStamped(context,Stamped{value,now,preview,revision},width,elapsed,rendered,write,slots,invalidate))(Unit{})
    case None{} current: renderStamped(context,current,width,elapsed,rendered,write,slots,invalidate)
def renderPrepared(preflight: Preflight,cached: Maybe<&2,Rendered>,current: Stamped,width: Nat,elapsed: Maybe<&2,F64>,rendered: Ref.Ref<Maybe<&2,Rendered>>,write: Ref.Ref<Maybe<&2,WriteRenderer.WriteHighlightCache>>,invalidate: Callback.Callback<Unit,Unit>) -> IO(List<&2,String>):
  match preflight:
    case Preflight{context,_,slots}: cachedLines(context,cached,current,width,elapsed,rendered,write,slots,invalidate)
def displayedElapsed(current: Stamped,elapsed: Maybe<&2,F64>) -> Maybe<&2,F64>:
  match current:
    case Stamped{ToolExecution{"bash",_,_,_,_,_,_,_,_,_,_,_},_,_,_}: elapsed
    case Stamped{ToolExecution{_,_,_,_,_,_,_,_,_,_,NativeBash{},_},_,_,_}: elapsed
    case _: None{}
def renderLive(handle: Handle,width: Nat) -> IO(List<&2,String>):
  match handle:
    case Handle{state,+rendered,write,timing,+preflight,invalidate}:
      do IO<List<&2,String>>:
        +current : Stamped <- Ref.read(Stamped,state)
        elapsed : Maybe<&2,F64> <- Serial.run(Timing,Maybe<&2,F64>,timing,measured)
        cached : Maybe<&2,Rendered> <- Ref.read(Maybe<&2,Rendered>,rendered)
        renderPrepared(preflight,cached,current,width,displayedElapsed(current,elapsed),rendered,write,invalidate)
def arguments(value: ToolExecution) -> Value.Value:
  match value: case ToolExecution{_,_,args,_,_,_,_,_,_,_,_,_}: args
def argsComplete(value: ToolExecution) -> Bool:
  match value: case ToolExecution{_,_,_,_,_,_,_,_,complete,_,_,_}: complete
def samePreviewInput(+left: ToolExecution,+right: ToolExecution) -> Bool:
  Value.equal(arguments(left),arguments(right)) && Bool.pick(Bool,argsComplete(left),argsComplete(right),Bool.not(argsComplete(right)))
def prepared(current: Stamped,+value: ToolExecution) -> Stamped & Maybe<&2,Nat>:
  match current:
    case Stamped{+old,version,preview,+revision}:
      +changed = Bool.not(samePreviewInput(old,value))
      +next = Bool.pick(Nat,changed,revision + 1n,revision)
      (Stamped{value,version + 1n,Bool.pick(Maybe<&2,Edits.Preview()>,changed,None{},preview),next},Bool.pick(Maybe<&2,Nat>,argsComplete(value) && changed,Some{next},None{}))
def notifyPreview(callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{ready}: Callback.call(Unit,Unit,ready,Unit{})
def parsedPreview(result: Edit.ResultOf(Edit.EditToolInput)) -> Maybe<&2,Edit.EditToolInput>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}
def previewInput(value: ToolExecution) -> Maybe<&2,Edit.EditToolInput>:
  match value:
    case ToolExecution{"edit",_,args,None{},_,_,_,_,True{},_,Generic{},_}: parsedPreview(Edit.parseInput(args))
    case _: None{}
def requestedPreview(context: ToolContext) -> IO(Unit):
  match context:
    case ToolContext{_,_,redraw,_,_,_}:
      do IO<Unit>:
        callback : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
        notifyPreview(callback)
type Invalidation is Data: Invalidation{rendered: Ref.Ref<Maybe<&2,Rendered>>,state: Ref.Ref<Stamped>,context: Maybe<&2,ToolContext>}
def requestInvalidated(context: Maybe<&2,ToolContext>) -> IO(Unit):
  match context:
    case Some{ready}: requestedPreview(ready)
    case None{}: IO.pure(Unit,Unit{})
def invalidatedStamp(current: Stamped) -> Stamped & Unit:
  match current:
    case Stamped{value,version,preview,revision}: (Stamped{value,version + 1n,preview,revision},Unit{})
def invalidateLive(env: Invalidation,unit: Unit) -> IO(Unit):
  match env:
    case Invalidation{rendered,state,context}:
      do IO<Unit>:
        cleared : Maybe<&1,Unit> <- Ref.tryModify(Maybe<&2,Rendered>,Unit,rendered,_ => (None{},Unit{}))
        advanced : Maybe<&1,Unit> <- Ref.tryModify(Stamped,Unit,state,current => invalidatedStamp(current))
        requestInvalidated(context)
def previewArrived(current: Stamped,expected: Value.Value,requestRevision: Nat,+result: Edits.Preview()) -> Stamped & Bool:
  match current:
    case Stamped{+value,+version,+preview,+revision}:
      +accept = Nat.is_eq(revision,requestRevision) && Value.equal(arguments(value),expected) && Maybe.is_some(&2,Edit.EditToolInput,previewInput(value))
      (Stamped{value,Bool.pick(Nat,accept,version + 1n,version),Bool.pick(Maybe<&2,Edits.Preview()>,accept,Some{result},preview),revision},accept)
def computePreview(+state: Ref.Ref<Stamped>,+context: ToolContext,expected: Value.Value,revision: Nat,input: Edit.EditToolInput) -> IO(Unit):
  match context:
    case ToolContext{+cwd,+compute,+redraw,+read,+markdown,+images}:
      do IO<Unit>:
        result : Edits.Preview() <- Callback.call(PreviewRequest,Edits.Preview(),compute,PreviewRequest{cwd,input})
        accepted : Bool <- Ref.modify(Stamped,Bool,state,current => previewArrived(current,expected,revision,result))
        Bool.pick(Unit -> IO(Unit),accepted,_ => requestedPreview(ToolContext{cwd,compute,redraw,read,markdown,images}),_ => IO.pure(Unit,Unit{}))(Unit{})
def previewStarted(state: Ref.Ref<Stamped>,preflight: Preflight,expected: Value.Value,revision: Nat,input: Maybe<&2,Edit.EditToolInput>) -> IO(Unit):
  match preflight input:
    case Preflight{Some{context},tasks,_} Some{ready}:
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit,computePreview(state,context,expected,revision,ready))
        Ref.modify(List<&2,Chan(Unit)>,Unit,tasks,current => (task <> current,Unit{}))
    case _ _: IO.pure(Unit,Unit{})
def launchPreview(state: Ref.Ref<Stamped>,preflight: Preflight,+value: ToolExecution,revision: Nat) -> IO(Unit):
  previewStarted(state,preflight,arguments(value),revision,previewInput(value))
def launchChanged(state: Ref.Ref<Stamped>,preflight: Preflight,value: ToolExecution,revision: Maybe<&2,Nat>) -> IO(Unit):
  match revision:
    case None{}: IO.pure(Unit,Unit{})
    case Some{number}: launchPreview(state,preflight,value,number)
def joinPreviews(tasks: List<&2,Chan(Unit)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit,Unit{})
    case task <> rest:
      do IO<Unit>:
        IO.join(Unit,task)
        joinPreviews(rest)
def disposeSlots(slots: Slots) -> IO(Unit):
  match slots:
    case Slots{call,result,_,_}:
      do IO<Unit>:
        disposeRetained(call)
        disposeRetained(result)
def childList(call: Maybe<&2,Component.Component>,result: Maybe<&2,Component.Component>) -> List<&2,Component.Component>:
  match call result:
    case Some{first} Some{second}: [first,second]
    case Some{first} None{}: [first]
    case None{} Some{second}: [second]
    case None{} None{}: Nil{}
def borrowedChildren(call: Maybe<&1,Retained> & Maybe<&2,Component.Component>,result: Maybe<&1,Retained> & Maybe<&2,Component.Component>,callHeight: Nat,resultHeight: Nat) -> Slots & List<&2,Component.Component>:
  match call result:
    case Tuple{ownedCall,callComponent} Tuple{ownedResult,resultComponent}:
      (Slots{ownedCall,ownedResult,callHeight,resultHeight},childList(callComponent,resultComponent))
def currentChildren(slots: Slots) -> Slots & List<&2,Component.Component>:
  match slots:
    case Slots{call,result,callHeight,resultHeight}:
      borrowedChildren(borrowedRetained(call),borrowedRetained(result),callHeight,resultHeight)
def children(slots: Ref.Ref<Slots>,_: Unit) -> IO(List<&2,Component.Component>):
  Ref.modify(Slots,List<&2,Component.Component>,slots,currentChildren)
def insideX(x: Tui.Offset,+start: Nat,width: Nat) -> Bool:
  match x:
    case Tui.Forward{+column}: Nat.is_le(start,column) && Nat.is_lt(column - start,width)
    case _: False{}
def childEvent(event: Tui.TuiMouseEvent,start: Nat,left: Nat,width: Nat,height: Nat) -> Tui.TuiMouseEvent:
  match event:
    case Tui.TuiMouseEvent{kind,button,x,y,screenX,screenY,_,_,shift,alt,ctrl,wheel,clicks}:
      Tui.TuiMouseEvent{kind,button,Component.subtract(x,Tui.Forward{left}),Component.subtract(y,Tui.Forward{start}),screenX,screenY,width,height,shift,alt,ctrl,wheel,clicks}
def routedRetained(slot: Maybe<&1,Retained>,+event: Tui.TuiMouseEvent,+start: Nat,+left: Nat,+width: Nat,+height: Nat) -> IO(Maybe<&1,Retained> & Maybe<&2,Component.TuiMouseDispatchResult()>):
  match slot event:
    case Some{Retained{version,Component.Owner{+component,retire}}} Tui.TuiMouseEvent{_,_,x,+y,_,_,_,_,_,_,_,_,_}:
      do IO<Maybe<&1,Retained> & Maybe<&2,Component.TuiMouseDispatchResult()>>:
        response : Maybe<&2,Component.TuiMouseDispatchResult()> <- Bool.pick(Unit -> IO(Maybe<&2,Component.TuiMouseDispatchResult()>),insideX(x,left,width) && Component.within(y,start,height),
          _ => Component.dispatchMouseEvent(component,childEvent(event,start,left,width,height)),
          _ => IO.pure(Maybe<&2,Component.TuiMouseDispatchResult()>,None{}))(Unit{})
        return (Some{Retained{version,Component.Owner{component,retire}}},response)
    case slot _: IO.pure(Maybe<&1,Retained> & Maybe<&2,Component.TuiMouseDispatchResult()>,(slot,None{}))
def calledChild(pair: Maybe<&1,Retained> & Maybe<&2,Component.TuiMouseDispatchResult()>,result: Maybe<&1,Retained>,callHeight: Nat,resultHeight: Nat) -> Slots & Maybe<&2,Component.TuiMouseDispatchResult()>:
  match pair: case (call,response): (Slots{call,result,callHeight,resultHeight},response)
def resultedChild(pair: Maybe<&1,Retained> & Maybe<&2,Component.TuiMouseDispatchResult()>,call: Maybe<&1,Retained>,callHeight: Nat,resultHeight: Nat) -> Slots & Maybe<&2,Component.TuiMouseDispatchResult()>:
  match pair: case (result,response): (Slots{call,result,callHeight,resultHeight},response)
def routeResult(hit: Bool,call: Maybe<&1,Retained>,result: Maybe<&1,Retained>,+callHeight: Nat,+resultHeight: Nat,event: Tui.TuiMouseEvent,+start: Nat,left: Nat,width: Nat) -> IO(Slots & Maybe<&2,Component.TuiMouseDispatchResult()>):
  match hit:
    case True{}:
      do IO<Slots & Maybe<&2,Component.TuiMouseDispatchResult()>>:
        pair : Maybe<&1,Retained> & Maybe<&2,Component.TuiMouseDispatchResult()> <- routedRetained(result,event,start + callHeight,left,width,resultHeight)
        return resultedChild(pair,call,callHeight,resultHeight)
    case False{}: IO.pure(Slots & Maybe<&2,Component.TuiMouseDispatchResult()>,(Slots{call,result,callHeight,resultHeight},None{}))
def routeCall(hit: Bool,call: Maybe<&1,Retained>,result: Maybe<&1,Retained>,+callHeight: Nat,+resultHeight: Nat,+event: Tui.TuiMouseEvent,+start: Nat,left: Nat,width: Nat) -> IO(Slots & Maybe<&2,Component.TuiMouseDispatchResult()>):
  match hit event:
    case True{} event:
      do IO<Slots & Maybe<&2,Component.TuiMouseDispatchResult()>>:
        pair : Maybe<&1,Retained> & Maybe<&2,Component.TuiMouseDispatchResult()> <- routedRetained(call,event,start,left,width,callHeight)
        return calledChild(pair,result,callHeight,resultHeight)
    case False{} Tui.TuiMouseEvent{_,_,_,y,_,_,_,_,_,_,_,_,_}:
      routeResult(Component.within(y,start + callHeight,resultHeight),call,result,callHeight,resultHeight,event,start,left,width)
def routeSlots(slots: Slots,+event: Tui.TuiMouseEvent,+start: Nat,left: Nat,width: Nat) -> IO(Slots & Maybe<&2,Component.TuiMouseDispatchResult()>):
  match slots event:
    case Slots{call,result,+callHeight,resultHeight} Tui.TuiMouseEvent{_,_,_,y,_,_,_,_,_,_,_,_,_}:
      routeCall(Component.within(y,start,callHeight),call,result,callHeight,resultHeight,event,start,left,width)
def routeMounted(preflight: Preflight,state: ToolExecution,+event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.TuiMouseDispatchResult()>):
  match preflight state event:
    case Preflight{_,_,slots} ToolExecution{_,_,_,_,_,_,_,_,_,_,SelfRendered{_,_},_} Tui.TuiMouseEvent{_,_,_,_,_,_,+width,_,_,_,_,_,_}:
      Ref.update(Slots,Maybe<&2,Component.TuiMouseDispatchResult()>,slots,current => routeSlots(current,event,1n,0n,width))
    case Preflight{_,_,slots} ToolExecution{_,_,_,_,_,_,_,_,_,_,Boxed{_,_},_} Tui.TuiMouseEvent{_,_,_,_,_,_,+width,_,_,_,_,_,_}:
      Ref.update(Slots,Maybe<&2,Component.TuiMouseDispatchResult()>,slots,current => routeSlots(current,event,2n,1n,Nat.max(1n,width - 2n)))
    case _ _ _: IO.pure(Maybe<&2,Component.TuiMouseDispatchResult()>,None{})
def retirePreflight(preflight: Preflight) -> IO(Unit):
  match preflight:
    case Preflight{_,tasks,slots}:
      do IO<Unit>:
        pending : List<&2,Chan(Unit)> <- Ref.dispose(List<&2,Chan(Unit)>,tasks)
        joinPreviews(pending)
        old : Slots <- Ref.dispose(Slots,slots)
        disposeSlots(old)
        return Unit{}
def expandedOf(state: ToolExecution) -> Bool:
  match state: case ToolExecution{_,_,_,_,expanded,_,_,_,_,_,_,_}: expanded
def hasResult(state: ToolExecution) -> Bool:
  match state: case ToolExecution{_,_,_,result,_,_,_,_,_,_,_,_}: Maybe.is_some(&2,ToolRender.ToolResult,result)
def clickedStamp(current: Stamped) -> Stamped & Bool:
  match current:
    case Stamped{+value,+version,preview,revision}:
      +accept = hasResult(value)
      (Stamped{Bool.pick(ToolExecution,accept,setExpanded(value,Bool.not(expandedOf(value))),value),Bool.pick(Nat,accept,version + 1n,version),preview,revision},accept)
def clickArea(state: ToolExecution,+rows: Nat,y: Tui.Offset) -> Bool:
  match state y:
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,SelfRendered{_,_},_} Tui.Forward{+row}: Nat.is_le(1n,row) && Nat.is_lt(row,rows)
    case ToolExecution{+name,_,_,_,_,_,_,_,_,_,Generic{},_} Tui.Forward{+row}:
      Bool.pick(Bool,hasBuiltin(name),Nat.is_le(2n,row) && Nat.is_lt(row + 1n,rows),Nat.is_le(1n,row) && Nat.is_lt(row,rows))
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,Boxed{_,_},_} Tui.Forward{+row}: Nat.is_le(2n,row) && Nat.is_lt(row + 1n,rows)
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,NativeBash{},_} Tui.Forward{+row}: Nat.is_le(2n,row) && Nat.is_lt(row + 1n,rows)
    case _ _: False{}
def displayedRows(cached: Maybe<&2,Rendered>) -> Nat:
  match cached:
    case Some{Rendered{_,_,_,lines,_}}: List.length(&2,String,lines)
    case None{}: 0n
def valueOf(current: Stamped) -> ToolExecution:
  match current: case Stamped{value,_,+preview,+revision}: value
def clickFallback(child: Maybe<&2,Component.TuiMouseDispatchResult()>,handle: Handle,event: Tui.TuiMouseEvent,view: ToolExecution,rows: Nat) -> IO(Maybe<&2,Component.MouseResponse()>):
  match child event handle:
    case Some{result} _ _: IO.pure(Maybe<&2,Component.MouseResponse()>,Some{Component.DispatchedResult{result}})
    case None{} Tui.TuiMouseEvent{Tui.MouseClick{},Tui.MouseLeft{},_,y,_,_,_,_,_,_,_,_,_} Handle{state,_,_,_,_,_}:
      Bool.pick(Unit -> IO(Maybe<&2,Component.MouseResponse()>),clickArea(view,rows,y),
        _ => do IO<Maybe<&2,Component.MouseResponse()>>:
          changed : Bool <- Ref.modify(Stamped,Bool,state,clickedStamp)
          return Bool.pick(Maybe<&2,Component.MouseResponse()>,changed,Some{Component.LocalResult{Tui.TuiMouseEventResult{True{},False{},False{},Some{True{}}}}},None{}),
        _ => IO.pure(Maybe<&2,Component.MouseResponse()>,None{}))(Unit{})
    case _ _ _: IO.pure(Maybe<&2,Component.MouseResponse()>,None{})
def mouseShared(handle: Handle,+event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match handle:
    case Handle{+state,+rendered,write,timing,+preflight,invalidate}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        current : Stamped <- Ref.read(Stamped,state)
        cached : Maybe<&2,Rendered> <- Ref.read(Maybe<&2,Rendered>,rendered)
        +view : ToolExecution = valueOf(current)
        child : Maybe<&2,Component.TuiMouseDispatchResult()> <- routeMounted(preflight,view,event)
        clickFallback(child,Handle{state,rendered,write,timing,preflight,invalidate},event,view,displayedRows(cached))
def mouse(handle: Handle,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  mouseShared(handle,event)
def created(id: Component.ComponentId,+state: Ref.Ref<Stamped>,+preflight: Preflight,pair: Serial.Owner<Timing> & Serial.Handle<Timing>) -> IO(Owner):
  match pair preflight:
    case (timing,handle) Preflight{context,_,slots}:
      do IO<Owner>:
        +rendered : Ref.Ref<Maybe<&2,Rendered>> <- Ref.new(Maybe<&2,Rendered>,None{})
        +write : Ref.Ref<Maybe<&2,WriteRenderer.WriteHighlightCache>> <- Ref.new(Maybe<&2,WriteRenderer.WriteHighlightCache>,None{})
        +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Invalidation,~Unit,~Unit,~invalidateLive,Invalidation{rendered,state,context})
        +live : Handle = Handle{state,rendered,write,handle,preflight,invalidate}
        +draw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Handle,~Nat,~List<&2,String>,~renderLive,live)
        +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Handle,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~mouse,live)
        +childrenCallback : Callback.Callback<Unit,List<&2,Component.Component>> <- Callback.create(~Ref.Ref<Slots>,~Unit,~List<&2,Component.Component>,~children,slots)
        return Owner{state,rendered,write,timing,Component.Group{Component.Component{id,draw,None{},Some{mouseCallback},invalidate,None{},False{}},childrenCallback},draw,invalidate,mouseCallback,childrenCallback,preflight}
def createWithContext(id: Component.ComponentId,+value: ToolExecution,context: Maybe<&2,ToolContext>) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<Stamped> <- Ref.new(Stamped,Stamped{value,0n,None{},0n})
    timing : Serial.Owner<Timing> <- Serial.create(Timing,Waiting{})
    +tasks : Ref.Ref<List<&2,Chan(Unit)>> <- Ref.new(List<&2,Chan(Unit)>,Nil{})
    +slots : Ref.Ref<Slots> <- Ref.new(Slots,Slots{None{},None{},0n,0n})
    +preflight : Preflight = Preflight{context,tasks,slots}
    launchPreview(state,preflight,value,0n)
    created(id,state,preflight,Serial.borrow(Timing,timing))
def create(id: Component.ComponentId,value: ToolExecution) -> IO(Owner):
  createWithContext(id,value,None{})
def borrowed(pair: Serial.Owner<Timing> & Serial.Handle<Timing>,+state: Ref.Ref<Stamped>,+rendered: Ref.Ref<Maybe<&2,Rendered>>,+write: Ref.Ref<Maybe<&2,WriteRenderer.WriteHighlightCache>>,+component: Component.Component,draw: Callback.Callback<Nat,List<&2,String>>,+invalidate: Callback.Callback<Unit,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,children: Callback.Callback<Unit,List<&2,Component.Component>>,+preflight: Preflight) -> Owner & Component.Component & Handle:
  match pair:
    case (timing,handle): (Owner{state,rendered,write,timing,component,draw,invalidate,mouse,children,preflight},component,Handle{state,rendered,write,handle,preflight,invalidate})
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{+state,+rendered,+write,timing,+component,draw,invalidate,mouse,children,+preflight}: borrowed(Serial.borrow(Timing,timing),state,rendered,write,component,draw,invalidate,mouse,children,preflight)
def invalidateOwner(owner: Owner) -> IO(Owner):
  match owner:
    case Owner{state,+rendered,write,timing,component,draw,+invalidate,mouse,children,+preflight}:
      do IO<Owner>:
        Callback.call(Unit,Unit,invalidate,Unit{})
        return Owner{state,rendered,write,timing,component,draw,invalidate,mouse,children,preflight}
def rethemed(current: Stamped,theme: Theme.Theme) -> Stamped:
  match current: case Stamped{value,version,+preview,+revision}: Stamped{retheme(value,theme),version + 1n,preview,revision}
def rethemeOwner(owner: Owner,theme: Theme.Theme) -> IO(Owner):
  match owner:
    case Owner{+state,rendered,write,timing,+component,draw,invalidate,mouse,children,+preflight}:
      do IO<Owner>:
        Ref.modify(Stamped,Unit,state,current => (rethemed(current,theme),Unit{}))
        return Owner{state,rendered,write,timing,component,draw,invalidate,mouse,children,preflight}
def expandedStamp(current: Stamped,expanded: Bool) -> Stamped:
  match current: case Stamped{value,version,+preview,+revision}: Stamped{setExpanded(value,expanded),version + 1n,preview,revision}
def expandOwner(owner: Owner,expanded: Bool) -> IO(Owner):
  match owner:
    case Owner{+state,rendered,write,timing,+component,draw,invalidate,mouse,children,+preflight}:
      do IO<Owner>:
        Ref.modify(Stamped,Unit,state,current => (expandedStamp(current,expanded),Unit{}))
        return Owner{state,rendered,write,timing,component,draw,invalidate,mouse,children,preflight}
def imagesStamp(current: Stamped,enabled: Bool) -> Stamped:
  match current: case Stamped{value,version,+preview,+revision}: Stamped{setShowImages(value,enabled),version + 1n,preview,revision}
def showImagesOwner(owner: Owner,enabled: Bool) -> IO(Owner):
  match owner:
    case Owner{+state,rendered,write,timing,+component,draw,invalidate,mouse,children,+preflight}:
      do IO<Owner>:
        Ref.modify(Stamped,Unit,state,current => (imagesStamp(current,enabled),Unit{}))
        return Owner{state,rendered,write,timing,component,draw,invalidate,mouse,children,preflight}
def set(handle: Handle,+value: ToolExecution) -> IO(Unit):
  match handle:
    case Handle{+state,_,_,timing,+preflight,_}:
      do IO<Unit>:
        updated : Unit <- Serial.run(Timing,Unit,timing,current => updateTiming(current,finished(value)))
        start : Maybe<&2,Nat> <- Ref.modify(Stamped,Maybe<&2,Nat>,state,current => prepared(current,value))
        launchChanged(state,preflight,value,start)
def executionBegan(handle: Handle) -> IO(Unit):
  match handle: case Handle{_,_,_,timing,+preflight,_}: Serial.run(Timing,Unit,timing,beginTiming)
def current(handle: Handle) -> IO(ToolExecution):
  match handle:
    case Handle{state,_,_,_,+preflight,_}:
      do IO<ToolExecution>:
        stamped : Stamped <- Ref.read(Stamped,state)
        return valueOf(stamped)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state,rendered,write,timing,_,draw,invalidate,mouse,children,+preflight}:
      do IO<Unit>:
        retirePreflight(preflight)
        old : Stamped <- Ref.dispose(Stamped,state)
        lines : Maybe<&2,Rendered> <- Ref.dispose(Maybe<&2,Rendered>,rendered)
        highlights : Maybe<&2,WriteRenderer.WriteHighlightCache> <- Ref.dispose(Maybe<&2,WriteRenderer.WriteHighlightCache>,write)
        oldTiming : Timing <- Serial.retire(Timing,timing)
        Callback.dispose(Nat,List<&2,String>,draw)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)
        Callback.dispose(Unit,List<&2,Component.Component>,children)

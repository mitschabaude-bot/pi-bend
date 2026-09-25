import Base
import ./messages.bend as Messages
import ../theme/theme.bend as Theme
import ../../../../../tui/src/components/box.bend as Box
import ../../../../../tui/src/components/text.bend as TuiText
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../tui/src/utils.bend as U
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../runtime/src/clock.bend as Clock
import ../../../../../tui/src/component.bend as Component
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../ai/src/types.bend as Ai
import ../../../../../ai/src/utils/json.bend as Json
import ../../../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../utils/shell.bend as Shell
import ../../../core/tools/renderers/find.bend as FindRenderer
import ../../../core/tools/renderers/grep.bend as GrepRenderer
import ../../../core/tools/renderers/ls.bend as LsRenderer
import ../../../core/tools/renderers/edit.bend as EditRenderer
import ../../../core/tools/renderers/read.bend as ReadRenderer
import ../../../core/tools/renderers/write.bend as WriteRenderer
import ../../../core/tools/renderers/bash.bend as BashRenderer
import ../../../core/tools/render-utils.bend as Render
import ../../../core/tools/index.bend as Tools
import ../../../../../agent/src/types.bend as Agent

type ToolResult is Data: ToolResult{content: List<&2,Ai.TextImageContent>,isError: Bool,details: Maybe<&2,Tools.ToolDetails>}
type RenderContext is Data:
  RenderContext{toolName: String,toolCallId: String,args: Value.Value,result: Maybe<&2,ToolResult>,expanded: Bool,isPartial: Bool,executionStarted: Bool,argsComplete: Bool,width: Nat}
def Renderer() -> Data: Callback.Callback<RenderContext,List<&2,String>>
type Shell is Data:
  Generic{}
  Boxed{call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>}
  SelfRendered{call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>}
type ToolExecution is Data:
  ToolExecution{toolName: String,toolCallId: String,args: Value.Value,result: Maybe<&2,ToolResult>,expanded: Bool,showImages: Bool,isPartial: Bool,executionStarted: Bool,argsComplete: Bool,theme: Theme.Theme,shell: Shell,highlightCode: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>}
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
def updateResult(state: ToolExecution,result: ToolResult,isPartial: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,_,expanded,images,_,started,complete,theme,shell,highlight}: ToolExecution{name,id,args,Some{result},expanded,images,isPartial,started,complete,theme,shell,highlight}
def updateFromAgent(-D: Data,state: ToolExecution,result: Agent.AgentToolResult<D>,details: Maybe<&2,Tools.ToolDetails>,isError: Bool,isPartial: Bool) -> ToolExecution:
  match result: case Agent.AgentToolResult{content,_,_,_}: updateResult(state,ToolResult{content,isError,details},isPartial)
def updateFromAiResult(-D: Data,state: ToolExecution,message: Ai.ToolResultMessage<D>,details: Maybe<&2,Tools.ToolDetails>) -> ToolExecution:
  match message:
    case Ai.ToolResultMessage{_,_,content,_,_,isError,_}:
      updateResult(markExecutionStarted(setArgsComplete(state)),ToolResult{content,isError,details},False{})
def setExpanded(state: ToolExecution,expanded: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,_,images,partial,started,complete,theme,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def setShowImages(state: ToolExecution,images: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,_,partial,started,complete,theme,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def retheme(state: ToolExecution,theme: Theme.Theme) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,started,complete,_,shell,highlight}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell,highlight}
def context(state: ToolExecution,width: Nat) -> RenderContext:
  match state: case ToolExecution{name,id,args,result,expanded,_,partial,started,complete,_,_,_}: RenderContext{name,id,args,result,expanded,partial,started,complete,width}
def title(state: ToolExecution) -> IO(String):
  match state:
    case ToolExecution{name,_,_,_,_,_,_,_,_,theme,_,_}:
      Messages.foregroundText(theme,"toolTitle","\u{1b}[1m" ++ name ++ "\u{1b}[22m")
def backgroundKey(state: ToolExecution) -> String:
  match state:
    case ToolExecution{_,_,_,_,_,_,True{},_,_,_,_,_}: "toolPendingBg"
    case ToolExecution{_,_,_,Some{ToolResult{_,True{},_}},_,_,False{},_,_,_,_,_}: "toolErrorBg"
    case _: "toolSuccessBg"
def resultTexts(content: List<&2,Ai.TextImageContent>,reversed: List<&2,String>) -> List<&2,String>:
  match content:
    case Nil{}: List.reverse(&2,String,reversed)
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest:
      +clean = String.join(String.split(Shell.sanitizeBinaryOutput(U.stripTerminalSequences(text)),'\r'),"")
      resultTexts(rest,clean <> reversed)
    case _ <> rest: resultTexts(rest,reversed)
def textOutput(result: Maybe<&2,ToolResult>) -> String:
  match result:
    case None{}: ""
    case Some{ToolResult{content,_,_}}: String.join(resultTexts(content,Nil{}),"\n")
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
def genericText(+state: ToolExecution) -> IO(String):
  match state:
    case ToolExecution{_,_,args,result,_,_,_,_,_,_,_,_}:
      do IO<String>:
        name : String <- title(state)
        +json : String <- IO.pure(String,argsJson(args))
        +output : String <- IO.pure(String,textOutput(result))
        return name ++ Bool.pick(String,String.is_empty(json),"","\n\n" ++ json) ++ Bool.pick(String,String.is_empty(output),"","\n" ++ output)
def generic(+state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,_,_,_,_,_,_,theme,_,_}:
      do IO<List<&2,String>>:
        +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
        content : String <- genericText(state)
        lines : List<&2,String> <- textLines(content,1n,1n,width,Some{bg})
        Callback.dispose(String,String,bg)
        return "" <> lines

def errorOutput(result: Maybe<&2,ToolResult>) -> Bool:
  match result:
    case Some{ToolResult{_,True{},_}}: True{}
    case _: False{}
def resultDetails(result: Maybe<&2,ToolResult>) -> Maybe<&2,Tools.ToolDetails>:
  match result:
    case Some{ToolResult{_,_,details}}: details
    case None{}: None{}
def bashElapsed(result: Maybe<&2,ToolResult>,elapsed: Maybe<&2,F64>) -> Maybe<&2,F64>:
  match result:
    case None{}: None{}
    case Some{_}: elapsed
def builtResult(+name: String,+args: Value.Value,+highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>,+result: Maybe<&2,ToolResult>,+expanded: Bool,partial: Bool,elapsed: Maybe<&2,F64>,+theme: Theme.Theme) -> IO(String):
  match name:
    case "read": ReadRenderer.renderResult(args,highlight,textOutput(result),resultDetails(result),expanded,errorOutput(result),theme)
    case "write": WriteRenderer.renderResult(textOutput(result),errorOutput(result),theme)
    case "bash": BashRenderer.renderResult(textOutput(result),resultDetails(result),expanded,partial,bashElapsed(result,elapsed),theme)
    case "find": FindRenderer.renderResult(textOutput(result),resultDetails(result),expanded,theme)
    case "grep": GrepRenderer.renderResult(textOutput(result),resultDetails(result),expanded,theme)
    case "ls": LsRenderer.renderResult(textOutput(result),resultDetails(result),expanded,theme)
    case _: IO.pure(String,"")
def builtCall(name: String,args: Value.Value,highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>,expanded: Bool,theme: Theme.Theme) -> IO(String):
  match name:
    case "read": ReadRenderer.renderCall(args,theme)
    case "bash": BashRenderer.renderCall(args,theme)
    case "write": WriteRenderer.renderCall(args,highlight,theme,expanded)
    case "find": FindRenderer.renderCall(args,theme)
    case "grep": GrepRenderer.renderCall(args,theme)
    case "ls": LsRenderer.renderCall(args,theme)
    case _: Render.pathCall(theme,name,args)
def boxedBuiltin(+state: ToolExecution,+width: Nat,elapsed: Maybe<&2,F64>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{name,_,+args,result,expanded,_,partial,_,_,+theme,_,+highlight}:
      do IO<List<&2,String>>:
        call : String <- builtCall(name,args,highlight,expanded,theme)
        extra : String <- builtResult(name,args,highlight,result,expanded,partial,elapsed,theme)
        +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
        lines : List<&2,String> <- textLines(call ++ extra,0n,0n,Nat.max(1n,width - 2n),None{})
        +body : List<&2,String> <- Box.paintContent(Box.prependMargin(lines," ",Nil{}),width,Some{bg},Nil{})
        +top : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
        +bottom : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
        Callback.dispose(String,String,bg)
        return "" <> List.append(&2,String,top,List.append(&2,String,body,bottom))
def builtinWithDuration(+state: ToolExecution,width: Nat,elapsed: Maybe<&2,F64>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{"edit",_,args,+result,_,_,partial,_,_,theme,_,_}:
      EditRenderer.render(args,textOutput(result),resultDetails(result),Bool.not(partial) && Maybe.is_some(&2,ToolResult,result),errorOutput(result),theme,width)
    case _: boxedBuiltin(state,width,elapsed)
def builtin(state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  builtinWithDuration(state,width,None{})

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
def resultFallback(state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,result,expanded,_,_,_,_,+theme,_,_}:
      +output = textOutput(result)
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
def renderSlot(renderer: Maybe<&2,Renderer()>,+state: ToolExecution,+width: Nat,call: Bool) -> IO(List<&2,String>):
  match renderer:
    case Some{callback}: Callback.call(RenderContext,List<&2,String>,callback,context(state,width))
    case None{}: Bool.pick(Unit -> IO(List<&2,String>),call,_ => callFallback(state,width),_ => resultFallback(state,width))(Unit{})
def resultSlot(renderer: Maybe<&2,Renderer()>,state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,None{},_,_,_,_,_,_,_,_}: IO.pure(List<&2,String>,Nil{})
    case _: renderSlot(renderer,state,width,False{})
def boxContent(+state: ToolExecution,call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>,+width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    first : List<&2,String> <- renderSlot(call,state,Nat.max(1n,width - 2n),True{})
    second : List<&2,String> <- resultSlot(result,state,Nat.max(1n,width - 2n))
    return List.append(&2,String,first,second)
def boxed(+state: ToolExecution,call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>,+width: Nat) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,_,_,_,_,_,_,theme,_,_}:
      do IO<List<&2,String>>:
        +content : List<&2,String> <- boxContent(state,call,result,width)
        Bool.pick(Unit -> IO(List<&2,String>),List.is_empty(&2,String,content),
          _ => IO.pure(List<&2,String>,Nil{}),
          _ => do IO<List<&2,String>>:
            +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
            body : List<&2,String> <- Box.paintContent(Box.prependMargin(content," ",Nil{}),width,Some{bg},Nil{})
            top : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
            bottom : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
            Callback.dispose(String,String,bg)
            return "" <> List.append(&2,String,top,List.append(&2,String,body,bottom)))(Unit{})
def selfRendered(+state: ToolExecution,call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>,+width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    first : List<&2,String> <- renderSlot(call,state,width,True{})
    second : List<&2,String> <- resultSlot(result,state,width)
    +content : List<&2,String> <- IO.pure(List<&2,String>,List.append(&2,String,first,second))
    return Bool.pick(List<&2,String>,List.is_empty(&2,String,content),Nil{},"" <> content)
def renderWithDuration(+state: ToolExecution,+width: Nat,elapsed: Maybe<&2,F64>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{+name,_,_,_,_,_,_,_,_,_,Generic{},_}:
      Bool.pick(Unit -> IO(List<&2,String>),String.eq(name,"read") || String.eq(name,"bash") || String.eq(name,"edit") || String.eq(name,"write") || String.eq(name,"find") || String.eq(name,"grep") || String.eq(name,"ls"),_ => builtinWithDuration(state,width,elapsed),_ => generic(state,width))(Unit{})
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,Boxed{+call,+result},_}: boxed(state,call,result,width)
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,SelfRendered{+call,+result},_}: selfRendered(state,call,result,width)
def render(state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  renderWithDuration(state,width,None{})

# The viewport keeps this component mounted while the transcript replaces its
# immutable state as tool events arrive.
type Owner is Type:
  Owner{state: Ref.Ref<ToolExecution>,timing: Serial.Owner<Timing>,component: Component.Component,draw: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{state: Ref.Ref<ToolExecution>,timing: Serial.Handle<Timing>}
def renderLive(handle: Handle,width: Nat) -> IO(List<&2,String>):
  match handle:
    case Handle{state,timing}:
      do IO<List<&2,String>>:
        value : ToolExecution <- Ref.read(ToolExecution,state)
        elapsed : Maybe<&2,F64> <- Serial.run(Timing,Maybe<&2,F64>,timing,measured)
        renderWithDuration(value,width,elapsed)
def noInvalidate(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def created(id: Component.ComponentId,+state: Ref.Ref<ToolExecution>,pair: Serial.Owner<Timing> & Serial.Handle<Timing>) -> IO(Owner):
  match pair:
    case (timing,handle):
      do IO<Owner>:
        +draw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Handle,~Nat,~List<&2,String>,~renderLive,Handle{state,handle})
        +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
        return Owner{state,timing,Component.Component{id,draw,None{},None{},invalidate,None{},False{}},draw,invalidate}
def create(id: Component.ComponentId,value: ToolExecution) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<ToolExecution> <- Ref.new(ToolExecution,value)
    timing : Serial.Owner<Timing> <- Serial.create(Timing,Waiting{})
    created(id,state,Serial.borrow(Timing,timing))
def borrowed(pair: Serial.Owner<Timing> & Serial.Handle<Timing>,+state: Ref.Ref<ToolExecution>,+component: Component.Component,draw: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>) -> Owner & Component.Component & Handle:
  match pair:
    case (timing,handle): (Owner{state,timing,component,draw,invalidate},component,Handle{state,handle})
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{+state,timing,+component,draw,invalidate}: borrowed(Serial.borrow(Timing,timing),state,component,draw,invalidate)
def rethemeOwner(owner: Owner,theme: Theme.Theme) -> IO(Owner):
  match owner:
    case Owner{+state,timing,+component,draw,invalidate}:
      do IO<Owner>:
        value : ToolExecution <- Ref.read(ToolExecution,state)
        Ref.write(ToolExecution,state,retheme(value,theme))
        return Owner{state,timing,component,draw,invalidate}
def expandOwner(owner: Owner,expanded: Bool) -> IO(Owner):
  match owner:
    case Owner{+state,timing,+component,draw,invalidate}:
      do IO<Owner>:
        value : ToolExecution <- Ref.read(ToolExecution,state)
        Ref.write(ToolExecution,state,setExpanded(value,expanded))
        return Owner{state,timing,component,draw,invalidate}
def set(handle: Handle,+value: ToolExecution) -> IO(Unit):
  match handle:
    case Handle{state,timing}:
      do IO<Unit>:
        updated : Unit <- Serial.run(Timing,Unit,timing,current => updateTiming(current,finished(value)))
        Ref.write(ToolExecution,state,value)
def executionBegan(handle: Handle) -> IO(Unit):
  match handle: case Handle{_,timing}: Serial.run(Timing,Unit,timing,beginTiming)
def current(handle: Handle) -> IO(ToolExecution):
  match handle: case Handle{state,_}: Ref.read(ToolExecution,state)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state,timing,_,draw,invalidate}:
      do IO<Unit>:
        old : ToolExecution <- Ref.dispose(ToolExecution,state)
        oldTiming : Timing <- Serial.retire(Timing,timing)
        Callback.dispose(Nat,List<&2,String>,draw)
        Callback.dispose(Unit,Unit,invalidate)

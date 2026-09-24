import Base
import ./messages.bend as Messages
import ../theme/theme.bend as Theme
import ../../../../../tui/src/components/box.bend as Box
import ../../../../../tui/src/components/text.bend as TuiText
import ../../../../../tui/src/utils.bend as U
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../runtime/src/clock.bend as Clock
import ../../../../../tui/src/component.bend as Component
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../runtime/src/record.bend as Record
import ../../../../../runtime/src/f64.bend as F
import ../../../../../ai/src/types.bend as Ai
import ../../../../../ai/src/utils/json.bend as Json
import ../../../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../utils/shell.bend as Shell
import ../../../core/tools/renderers/find.bend as FindRenderer
import ../../../core/tools/renderers/grep.bend as GrepRenderer
import ../../../core/tools/renderers/ls.bend as LsRenderer
import ../../../core/tools/renderers/edit.bend as EditRenderer
import ../../../../../agent/src/types.bend as Agent

type ToolResult is Data: ToolResult{content: List<&2,Ai.TextImageContent>,isError: Bool,details: Maybe<&2,Value.Value>}
type RenderContext is Data:
  RenderContext{toolName: String,toolCallId: String,args: Value.Value,result: Maybe<&2,ToolResult>,expanded: Bool,isPartial: Bool,executionStarted: Bool,argsComplete: Bool,width: Nat}
def Renderer() -> Data: Callback.Callback<RenderContext,List<&2,String>>
type Shell is Data:
  Generic{}
  Boxed{call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>}
  SelfRendered{call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>}
type ToolExecution is Data:
  ToolExecution{toolName: String,toolCallId: String,args: Value.Value,result: Maybe<&2,ToolResult>,expanded: Bool,showImages: Bool,isPartial: Bool,executionStarted: Bool,argsComplete: Bool,theme: Theme.Theme,shell: Shell}
type Timing is Data:
  Waiting{}
  Running{clock: Clock.Clock}
  Finished{elapsedMs: F64}
def finished(state: ToolExecution) -> Bool:
  match state:
    case ToolExecution{_,_,_,Some{_},_,_,False{},_,_,_,_}: True{}
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
  ToolExecution{toolName,toolCallId,args,None{},False{},True{},True{},False{},False{},theme,shell}
def fromAiToolCall(call: Ai.ToolCall<Value.Value>,theme: Theme.Theme,shell: Shell) -> ToolExecution:
  match call: case Ai.ToolCall{id,name,args,_,_}: new(name,id,args,theme,shell)
def updateArgs(state: ToolExecution,args: Value.Value) -> ToolExecution:
  match state: case ToolExecution{name,id,_,result,expanded,images,partial,started,complete,theme,shell}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell}
def markExecutionStarted(state: ToolExecution) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,_,complete,theme,shell}: ToolExecution{name,id,args,result,expanded,images,partial,True{},complete,theme,shell}
def setArgsComplete(state: ToolExecution) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,started,_,theme,shell}: ToolExecution{name,id,args,result,expanded,images,partial,started,True{},theme,shell}
def updateResult(state: ToolExecution,result: ToolResult,isPartial: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,_,expanded,images,_,started,complete,theme,shell}: ToolExecution{name,id,args,Some{result},expanded,images,isPartial,started,complete,theme,shell}
def updateFromAgent(-D: Data,state: ToolExecution,result: Agent.AgentToolResult<D>,details: Maybe<&2,Value.Value>,isError: Bool,isPartial: Bool) -> ToolExecution:
  match result: case Agent.AgentToolResult{content,_,_,_}: updateResult(state,ToolResult{content,isError,details},isPartial)
def updateFromAiResult(-D: Data,state: ToolExecution,message: Ai.ToolResultMessage<D>,details: Maybe<&2,Value.Value>) -> ToolExecution:
  match message:
    case Ai.ToolResultMessage{_,_,content,_,_,isError,_}:
      updateResult(markExecutionStarted(setArgsComplete(state)),ToolResult{content,isError,details},False{})
def setExpanded(state: ToolExecution,expanded: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,_,images,partial,started,complete,theme,shell}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell}
def setShowImages(state: ToolExecution,images: Bool) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,_,partial,started,complete,theme,shell}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell}
def retheme(state: ToolExecution,theme: Theme.Theme) -> ToolExecution:
  match state: case ToolExecution{name,id,args,result,expanded,images,partial,started,complete,_,shell}: ToolExecution{name,id,args,result,expanded,images,partial,started,complete,theme,shell}
def context(state: ToolExecution,width: Nat) -> RenderContext:
  match state: case ToolExecution{name,id,args,result,expanded,_,partial,started,complete,_,_}: RenderContext{name,id,args,result,expanded,partial,started,complete,width}
def title(state: ToolExecution) -> IO(String):
  match state:
    case ToolExecution{name,_,_,_,_,_,_,_,_,theme,_}:
      Messages.foregroundText(theme,"toolTitle","\u{1b}[1m" ++ name ++ "\u{1b}[22m")
def backgroundKey(state: ToolExecution) -> String:
  match state:
    case ToolExecution{_,_,_,_,_,_,True{},_,_,_,_}: "toolPendingBg"
    case ToolExecution{_,_,_,Some{ToolResult{_,True{},_}},_,_,False{},_,_,_,_}: "toolErrorBg"
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
    case ToolExecution{_,_,args,result,_,_,_,_,_,_,_}:
      do IO<String>:
        name : String <- title(state)
        +json : String <- IO.pure(String,argsJson(args))
        +output : String <- IO.pure(String,textOutput(result))
        return name ++ Bool.pick(String,String.is_empty(json),"","\n\n" ++ json) ++ Bool.pick(String,String.is_empty(output),"","\n" ++ output)
def generic(+state: ToolExecution,width: Nat) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,_,_,_,_,_,_,theme,_}:
      do IO<List<&2,String>>:
        +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
        content : String <- genericText(state)
        lines : List<&2,String> <- textLines(content,1n,1n,width,Some{bg})
        Callback.dispose(String,String,bg)
        return "" <> lines

def field(args: Value.Value,key: String) -> Maybe<&2,Value.Value>:
  match args:
    case Value.ObjectValue{record}: Record.get(Value.Value,record,key)
    case _: None{}
def stringField(value: Maybe<&2,Value.Value>) -> Maybe<&2,String>:
  match value:
    case None{}: Some{""}
    case Some{Value.Null{}}: Some{""}
    case Some{Value.Text{text}}: Some{text}
    case _: None{}
def argument(args: Value.Value,key: String) -> Maybe<&2,String>:
  stringField(field(args,key))
def numberValue(value: Maybe<&2,Value.Value>) -> Maybe<&2,Nat>:
  match value:
    case Some{Value.Number{number}}: Some{U32.to_nat(F64.to_u32(number))}
    case _: None{}
def numberArgument(args: Value.Value,key: String) -> Maybe<&2,Nat>:
  numberValue(field(args,key))
def pathField(args: Value.Value,file: Maybe<&2,Value.Value>) -> Maybe<&2,String>:
  match file:
    case Some{Value.Text{text}}: Some{text}
    case _: argument(args,"path")
def pathArgument(+args: Value.Value) -> Maybe<&2,String>:
  pathField(args,field(args,"file_path"))
def shownPath(theme: Theme.Theme,path: Maybe<&2,String>) -> IO(String):
  match path:
    case None{}: Messages.foregroundText(theme,"error","[invalid arg]")
    case Some{""}: Messages.foregroundText(theme,"toolOutput","...")
    case Some{value}: Messages.foregroundText(theme,"accent",value)
def shownTitle(theme: Theme.Theme,label: String) -> IO(String):
  Messages.foregroundText(theme,"toolTitle","\u{1b}[1m" ++ label ++ "\u{1b}[22m")
def pathCall(+theme: Theme.Theme,label: String,args: Value.Value) -> IO(String):
  do IO<String>:
    name : String <- shownTitle(theme,label)
    path : String <- shownPath(theme,pathArgument(args))
    return name ++ " " ++ path
def readRange(theme: Theme.Theme,offset: Maybe<&2,Nat>,limit: Maybe<&2,Nat>) -> IO(String):
  match offset limit:
    case None{} None{}: IO.pure(String,"")
    case Some{start} None{}: Messages.foregroundText(theme,"warning",":" ++ Nat.show(start))
    case None{} Some{+count}: Messages.foregroundText(theme,"warning",":" ++ "1" ++ Bool.pick(String,Nat.is_eq(count,0n),"","-" ++ Nat.show(count)))
    case Some{+start} Some{+count}: Messages.foregroundText(theme,"warning",":" ++ Nat.show(start) ++ Bool.pick(String,Nat.is_eq(count,0n),"","-" ++ Nat.show(start + count - 1n)))
def readCall(+theme: Theme.Theme,+args: Value.Value) -> IO(String):
  do IO<String>:
    name : String <- pathCall(theme,"read",args)
    range : String <- readRange(theme,numberArgument(args,"offset"),numberArgument(args,"limit"))
    return name ++ range
def shellCommand(value: Maybe<&2,String>,theme: Theme.Theme) -> IO(String):
  match value:
    case None{}: Messages.foregroundText(theme,"error","[invalid arg]")
    case Some{""}: Messages.foregroundText(theme,"toolOutput","...")
    case Some{command}: IO.pure(String,command)
def bashCall(+theme: Theme.Theme,args: Value.Value) -> IO(String):
  do IO<String>:
    command : String <- shellCommand(argument(args,"command"),theme)
    shownTitle(theme,"$ " ++ command)
def tabs(value: String) -> String: String.join(String.split(value,'\t'),"   ")
def trimmedReverse(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case "" <> rest: trimmedReverse(rest)
    case _: List.reverse(&2,String,lines)
def nonemptyLines(lines: List<&2,String>) -> List<&2,String>:
  trimmedReverse(List.reverse(&2,String,lines))
def contentLines(content: String) -> List<&2,String>:
  nonemptyLines(String.split(tabs(String.join(String.split(content,'\r'),"")),'\n'))
def coloredLines(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        colored : String <- Messages.foregroundText(theme,"toolOutput",line)
        coloredLines(rest,theme,colored <> reversed)
def expandHint(+theme: Theme.Theme,lead: String) -> IO(String):
  do IO<String>:
    start : String <- Messages.foregroundText(theme,"muted",lead)
    key : String <- Messages.foregroundText(theme,"dim",Messages.expandKeys())
    rest : String <- Messages.foregroundText(theme,"muted"," to expand")
    end : String <- Messages.foregroundText(theme,"muted",")")
    return start ++ " " ++ key ++ rest ++ end
def writeContent(+theme: Theme.Theme,header: String,expanded: Bool,contentArg: Maybe<&2,String>) -> IO(String):
  match contentArg:
    case None{}:
      do IO<String>:
        invalid : String <- Messages.foregroundText(theme,"error","[invalid content arg - expected string]")
        return header ++ "\n\n" ++ invalid
    case Some{""}: IO.pure(String,header)
    case Some{content}:
      do IO<String>:
        +all : List<&2,String> <- IO.pure(List<&2,String>,contentLines(content))
        +display : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,all,List.take(&2,String,all,10n)))
        colored : List<&2,String> <- coloredLines(display,theme,Nil{})
        +remaining : Nat <- IO.pure(Nat,List.length(&2,String,all) - List.length(&2,String,display))
        +preview : String <- IO.pure(String,header ++ "\n\n" ++ String.join(colored,"\n"))
        Bool.pick(Unit -> IO(String),Nat.is_eq(remaining,0n),_ => IO.pure(String,preview),
          _ => do IO<String>:
            hint : String <- expandHint(theme,"\n... (" ++ Nat.show(remaining) ++ " more lines, " ++ Nat.show(List.length(&2,String,all)) ++ " total,")
            return preview ++ hint)(Unit{})
def writeCall(+theme: Theme.Theme,+args: Value.Value,expanded: Bool) -> IO(String):
  do IO<String>:
    header : String <- pathCall(theme,"write",args)
    writeContent(theme,header,expanded,argument(args,"content"))
def errorOutput(result: Maybe<&2,ToolResult>) -> Bool:
  match result:
    case Some{ToolResult{_,True{},_}}: True{}
    case _: False{}
def resultDetails(result: Maybe<&2,ToolResult>) -> Maybe<&2,Value.Value>:
  match result:
    case Some{ToolResult{_,_,details}}: details
    case None{}: None{}
def builtFileResult(+name: String,+result: Maybe<&2,ToolResult>,+expanded: Bool,+theme: Theme.Theme) -> IO(String):
  +output = textOutput(result)
  Bool.pick(Unit -> IO(String),String.is_empty(output),_ => IO.pure(String,""),
    _ => Bool.pick(Unit -> IO(String),String.eq(name,"read") && Bool.not(expanded) && Bool.not(errorOutput(result)),
      _ => IO.pure(String,""),
      _ => Bool.pick(Unit -> IO(String),String.eq(name,"edit") && Bool.not(errorOutput(result)),
        _ => IO.pure(String,""),
        _ => Bool.pick(Unit -> IO(String),String.eq(name,"write") && Bool.not(errorOutput(result)),
          _ => IO.pure(String,""),
          _ => do IO<String>:
            +source : String <- IO.pure(String,Bool.pick(String,String.eq(name,"bash"),String.trim(output),output))
            +lines : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,String.eq(name,"read"),nonemptyLines(String.split(source,'\n')),String.split(source,'\n')))
            +count : Nat <- IO.pure(Nat,List.length(&2,String,lines))
            +bash : Bool <- IO.pure(Bool,String.eq(name,"bash"))
            +display : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,lines,Bool.pick(List<&2,String>,bash,List.drop(&2,String,lines,count - 5n),List.take(&2,String,lines,10n))))
            +colored : List<&2,String> <- coloredLines(display,theme,Nil{})
            +skipped : Nat <- IO.pure(Nat,count - List.length(&2,String,display))
            +plain : String <- IO.pure(String,Bool.pick(String,String.eq(name,"read") || bash,"\n\n","\n") ++ String.join(colored,"\n"))
            Bool.pick(Unit -> IO(String),bash && Bool.not(expanded) && Nat.is_gt(skipped,0n),
              _ => do IO<String>:
                hint : String <- expandHint(theme,"... (" ++ Nat.show(skipped) ++ " earlier lines,")
                return "\n\n" ++ hint ++ "\n" ++ String.join(colored,"\n"),
              _ => IO.pure(String,plain))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def builtResult(+name: String,+result: Maybe<&2,ToolResult>,+expanded: Bool,+theme: Theme.Theme) -> IO(String):
  match name:
    case "find": FindRenderer.renderResult(textOutput(result),resultDetails(result),expanded,theme)
    case "grep": GrepRenderer.renderResult(textOutput(result),resultDetails(result),expanded,theme)
    case "ls": LsRenderer.renderResult(textOutput(result),resultDetails(result),expanded,theme)
    case _: builtFileResult(name,result,expanded,theme)
def builtCall(name: String,args: Value.Value,expanded: Bool,theme: Theme.Theme) -> IO(String):
  match name:
    case "read": readCall(theme,args)
    case "bash": bashCall(theme,args)
    case "write": writeCall(theme,args,expanded)
    case "find": FindRenderer.renderCall(args,theme)
    case "grep": GrepRenderer.renderCall(args,theme)
    case "ls": LsRenderer.renderCall(args,theme)
    case _: pathCall(theme,"edit",args)
def durationTenths(result: Result<&2,&2,F.Error,Nat>) -> Nat:
  match result:
    case Done{value}: value
    case Fail{_}: 0n
def durationLong(+seconds: Nat) -> String:
  Bool.pick(String,Nat.is_lt(seconds,3600n),Nat.show(seconds / 60n) ++ "m " ++ Nat.show(seconds % 60n) ++ "s",Nat.show(seconds / 3600n) ++ "h " ++ Nat.show((seconds % 3600n) / 60n) ++ "m " ++ Nat.show(seconds % 60n) ++ "s")
def durationText(+tenths: Nat) -> String:
  Bool.pick(String,Nat.is_lt(tenths,600n),Nat.show(tenths / 10n) ++ "." ++ Nat.show(tenths % 10n) ++ "s",durationLong(tenths / 10n))
def bashTiming(name: String,result: Maybe<&2,ToolResult>,partial: Bool,elapsed: Maybe<&2,F64>,theme: Theme.Theme) -> IO(String):
  match name result elapsed:
    case "bash" Some{_} Some{ms}:
      do IO<String>:
        prefix : String <- IO.pure(String,Bool.pick(String,partial,"Elapsed ","Took "))
        label : String <- Messages.foregroundText(theme,"muted",prefix ++ durationText(durationTenths(F.convert(F.divide(F.add(ms,F.fromU32(50)),F.fromU32(100))))))
        return "\n\n" ++ label
    case _ _ _: IO.pure(String,"")
def boxedBuiltin(+state: ToolExecution,+width: Nat,elapsed: Maybe<&2,F64>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{name,_,args,result,expanded,_,partial,_,_,+theme,_}:
      do IO<List<&2,String>>:
        call : String <- builtCall(name,args,expanded,theme)
        extra : String <- builtResult(name,result,expanded,theme)
        timing : String <- bashTiming(name,result,partial,elapsed,theme)
        +bg : Callback.Callback<String,String> <- Messages.color(theme,backgroundKey(state),True{})
        lines : List<&2,String> <- textLines(call ++ extra ++ timing,0n,0n,Nat.max(1n,width - 2n),None{})
        +body : List<&2,String> <- Box.paintContent(Box.prependMargin(lines," ",Nil{}),width,Some{bg},Nil{})
        +top : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
        +bottom : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
        Callback.dispose(String,String,bg)
        return "" <> List.append(&2,String,top,List.append(&2,String,body,bottom))
def builtinWithDuration(+state: ToolExecution,width: Nat,elapsed: Maybe<&2,F64>) -> IO(List<&2,String>):
  match state:
    case ToolExecution{"edit",_,args,+result,_,_,partial,_,_,theme,_}:
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
    case ToolExecution{_,_,_,result,expanded,_,_,_,_,+theme,_}:
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
    case ToolExecution{_,_,_,None{},_,_,_,_,_,_,_}: IO.pure(List<&2,String>,Nil{})
    case _: renderSlot(renderer,state,width,False{})
def boxContent(+state: ToolExecution,call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>,+width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    first : List<&2,String> <- renderSlot(call,state,Nat.max(1n,width - 2n),True{})
    second : List<&2,String> <- resultSlot(result,state,Nat.max(1n,width - 2n))
    return List.append(&2,String,first,second)
def boxed(+state: ToolExecution,call: Maybe<&2,Renderer()>,result: Maybe<&2,Renderer()>,+width: Nat) -> IO(List<&2,String>):
  match state:
    case ToolExecution{_,_,_,_,_,_,_,_,_,theme,_}:
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
    case ToolExecution{+name,_,_,_,_,_,_,_,_,_,Generic{}}:
      Bool.pick(Unit -> IO(List<&2,String>),String.eq(name,"read") || String.eq(name,"bash") || String.eq(name,"edit") || String.eq(name,"write") || String.eq(name,"find") || String.eq(name,"grep") || String.eq(name,"ls"),_ => builtinWithDuration(state,width,elapsed),_ => generic(state,width))(Unit{})
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,Boxed{+call,+result}}: boxed(state,call,result,width)
    case ToolExecution{_,_,_,_,_,_,_,_,_,_,SelfRendered{+call,+result}}: selfRendered(state,call,result,width)
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

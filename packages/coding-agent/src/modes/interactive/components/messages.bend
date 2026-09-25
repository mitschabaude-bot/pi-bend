import Base
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../tui/src/components/text.bend as TuiText
import ../../../../../tui/src/components/box.bend as Box
import ../../../../../tui/src/components/loader.bend as Loader
import ../../../core/tools/truncate.bend as Truncate
import ../../../../../tui/src/utils.bend as U
import ../theme/theme.bend as Theme
import ./session-info.bend as SessionInfo
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/text.bend as Text
import ../../../../../ai/src/types.bend as Ai
import ../../../../../tui/src/component.bend as Component

type Paint is Data: Paint{theme: Theme.Theme,key: String,background: Bool}
type Content is Data: TextBlock{text: String} ThinkingBlock{text: String} ToolCall{}
type Stop is Data: Stop{} Length{} Aborted{} Error{}
type UserMessage is Data: UserMessage{text: String,outputPad: Nat,theme: Theme.Theme,styles: Markdown.MarkdownTheme}
type AssistantMessage is Data:
  AssistantMessage{content: List<&2,Content>,hideThinkingBlock: Bool,hiddenThinkingLabel: String,outputPad: Nat,streaming: Bool,stop: Stop,errorMessage: Maybe<&2,String>,theme: Theme.Theme,styles: Markdown.MarkdownTheme}

# The Markdown and Box callbacks are borrowed only during a render. Message
# state stays immutable across streaming updates and theme changes.
def colorResult(result: Result<&2,&2,Theme.Error,String>) -> IO(String):
  match result:
    case Done{value}: IO.pure(String,value)
    case Fail{_}: IO.die(String,1,"invalid message theme color")
def painted(style: Paint,text: String) -> IO(String):
  match style:
    case Paint{theme,key,False{}}: colorResult(Theme.foreground(theme,key,text))
    case Paint{theme,key,True{}}: colorResult(Theme.background(theme,key,text))
def color(theme: Theme.Theme,key: String,background: Bool) -> IO(Callback.Callback<String,String>):
  Callback.create(~Paint,~String,~String,~painted,Paint{theme,key,background})
def zoneStart() -> String: "\u{1b}]133;A\u{7}"
def zoneEnd() -> String: "\u{1b}]133;B\u{7}\u{1b}]133;C\u{7}"
def zoneLast(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> Nil{}: (zoneEnd() ++ line) <> Nil{}
    case first <> rest: first <> zoneLast(rest)
def zone(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> Nil{}: (zoneEnd() ++ zoneStart() ++ line) <> Nil{}
    case first <> rest: (zoneStart() ++ first) <> zoneLast(rest)
def markdownResult(value: Markdown.Markdown & List<&2,String>) -> List<&2,String>:
  match value: case (_,lines): lines
def textResult(value: TuiText.Text & List<&2,String>) -> List<&2,String>:
  match value: case (_,lines): lines
def markdownLines(source: String,pad: Nat,width: Nat,styles: Markdown.MarkdownTheme,style: Maybe<&2,Markdown.DefaultTextStyle>,options: Maybe<&2,Markdown.MarkdownOptions>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    rendered : Markdown.Markdown & List<&2,String> <- Markdown.render(Markdown.new(source,pad,0n,styles,style,options),width)
    return markdownResult(rendered)
def textLines(source: String,pad: Nat,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    rendered : TuiText.Text & List<&2,String> <- TuiText.render(TuiText.new(source,Some{pad},Some{0n},None{}),width)
    return textResult(rendered)
def user(text: String,theme: Theme.Theme,styles: Markdown.MarkdownTheme,outputPad: Nat) -> UserMessage:
  UserMessage{text,outputPad,theme,styles}
def setUserOutputPad(state: UserMessage,pad: Nat) -> UserMessage:
  match state: case UserMessage{text,_,theme,styles}: UserMessage{text,pad,theme,styles}
def userPainted(lines: List<&2,String>,+width: Nat,pad: Nat,+bg: Callback.Callback<String,String>) -> IO(List<&2,String>):
  +margin = U.spaces(pad,"")
  +indented = Box.prependMargin(lines,margin,Nil{})
  do IO<List<&2,String>>:
    top : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
    body : List<&2,String> <- Box.paintContent(indented,width,Some{bg},Nil{})
    bottom : List<&2,String> <- Box.paintPadding(1n,width,Some{bg},Nil{})
    return zone(List.append(&2,String,top,List.append(&2,String,body,bottom)))
def renderUser(state: UserMessage,+width: Nat) -> IO(List<&2,String>):
  match state:
    case UserMessage{text,+pad,+theme,styles}:
      do IO<List<&2,String>>:
        +foreground : Callback.Callback<String,String> <- color(theme,"userMessageText",False{})
        +background : Callback.Callback<String,String> <- color(theme,"userMessageBg",True{})
        +body : List<&2,String> <- markdownLines(text,0n,Nat.max(1n,width - pad * 2n),styles,Some{Markdown.DefaultTextStyle{Some{foreground},None{},False{},False{},False{},False{}}},Some{Markdown.MarkdownOptions{True{},True{},None{},True{},False{}}})
        lines : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),List.is_empty(&2,String,body),_ => IO.pure(List<&2,String>,Nil{}),_ => userPainted(body,width,pad,background))(Unit{})
        Callback.dispose(String,String,foreground)
        Callback.dispose(String,String,background)
        return lines

def assistant(content: List<&2,Content>,theme: Theme.Theme,styles: Markdown.MarkdownTheme,outputPad: Nat) -> AssistantMessage:
  AssistantMessage{content,False{},"Thinking...",outputPad,False{},Stop{},None{},theme,styles}
def updateContent(state: AssistantMessage,content: List<&2,Content>,stop: Stop,errorMessage: Maybe<&2,String>,streaming: Bool) -> AssistantMessage:
  match state: case AssistantMessage{_,hide,label,pad,_,_,_,theme,styles}: AssistantMessage{content,hide,label,pad,streaming,stop,errorMessage,theme,styles}
def setHideThinkingBlock(state: AssistantMessage,hide: Bool) -> AssistantMessage:
  match state: case AssistantMessage{content,_,label,pad,streaming,stop,error,theme,styles}: AssistantMessage{content,hide,label,pad,streaming,stop,error,theme,styles}
def setHiddenThinkingLabel(state: AssistantMessage,label: String) -> AssistantMessage:
  match state: case AssistantMessage{content,hide,_,pad,streaming,stop,error,theme,styles}: AssistantMessage{content,hide,label,pad,streaming,stop,error,theme,styles}
def setAssistantOutputPad(state: AssistantMessage,pad: Nat) -> AssistantMessage:
  match state: case AssistantMessage{content,hide,label,_,streaming,stop,error,theme,styles}: AssistantMessage{content,hide,label,pad,streaming,stop,error,theme,styles}
def projectContent(-A: Data,blocks: List<&2,Ai.AssistantContent<A>>) -> List<&2,Content>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.AssistantText{Ai.TextContent{text,_}} <> rest: TextBlock{text} <> projectContent(A,rest)
    case Ai.AssistantThinking{Ai.ThinkingContent{text,_,_}} <> rest: ThinkingBlock{text} <> projectContent(A,rest)
    case Ai.AssistantToolCall{_} <> rest: ToolCall{} <> projectContent(A,rest)
def projectStop(value: Ai.StopReason) -> Stop:
  match value:
    case Ai.Length{}: Length{}
    case Ai.Aborted{}: Aborted{}
    case Ai.Error{}: Error{}
    case _: Stop{}
def updateFromAi(-A: Data,-D: Data,state: AssistantMessage,message: Ai.AssistantMessage<A,D>,streaming: Bool) -> AssistantMessage:
  match message:
    case Ai.AssistantMessage{content,_,_,_,_,_,_,_,_,stop,_,error,_,_,_}:
      updateContent(state,projectContent(A,content),projectStop(stop),error,streaming)
def visible(content: Content) -> Bool:
  match content:
    case TextBlock{text}: Bool.not(String.is_empty(Text.trim(text)))
    case ThinkingBlock{text}: Bool.not(String.is_empty(Text.trim(text)))
    case ToolCall{}: False{}
def anyVisible(content: List<&2,Content>) -> Bool:
  match content:
    case Nil{}: False{}
    case first <> rest: visible(first) || anyVisible(rest)
def hasTool(content: List<&2,Content>) -> Bool:
  match content:
    case Nil{}: False{}
    case ToolCall{} <> _: True{}
    case _ <> rest: hasTool(rest)
def foregroundText(theme: Theme.Theme,key: String,source: String) -> IO(String):
  colorResult(Theme.foreground(theme,key,source))
def thought(text: String,hide: Bool,label: String,pad: Nat,width: Nat,theme: Theme.Theme,styles: Markdown.MarkdownTheme) -> IO(List<&2,String>):
  match hide:
    case True{}:
      do IO<List<&2,String>>:
        colored : String <- foregroundText(theme,"thinkingText",label)
        textLines("\u{1b}[3m" ++ colored ++ "\u{1b}[23m",pad,width)
    case False{}:
      do IO<List<&2,String>>:
        +fg : Callback.Callback<String,String> <- color(theme,"thinkingText",False{})
        lines : List<&2,String> <- markdownLines(text,pad,width,styles,Some{Markdown.DefaultTextStyle{Some{fg},None{},False{},True{},False{},False{}}},None{})
        Callback.dispose(String,String,fg)
        return lines
@unsafe def contentLines(+content: List<&2,Content>,+pending: List<&2,String>,+hide: Bool,+label: String,+pad: Nat,+width: Nat,+theme: Theme.Theme,+styles: Markdown.MarkdownTheme) -> IO(List<&2,String>):
  match content pending:
    case Nil{} Nil{}: IO.pure(List<&2,String>,Nil{})
    case Nil{} _:
      thought(String.join(List.reverse(&2,String,pending),"\n\n"),hide,label,pad,width,theme,styles)
    case ThinkingBlock{text} <> rest _:
      +clean = Text.trim(text)
      contentLines(rest,Bool.pick(List<&2,String>,String.is_empty(clean),pending,clean <> pending),hide,label,pad,width,theme,styles)
    case TextBlock{text} <> rest Nil{}:
      Bool.pick(Unit -> IO(List<&2,String>),String.is_empty(Text.trim(text)),
        _ => contentLines(rest,Nil{},hide,label,pad,width,theme,styles),
        _ => do IO<List<&2,String>>:
          block : List<&2,String> <- markdownLines(Text.trim(text),pad,width,styles,None{},None{})
          next : List<&2,String> <- contentLines(rest,Nil{},hide,label,pad,width,theme,styles)
          return List.append(&2,String,block,next))(Unit{})
    case TextBlock{text} <> rest _:
      Bool.pick(Unit -> IO(List<&2,String>),String.is_empty(Text.trim(text)),
        _ => contentLines(rest,pending,hide,label,pad,width,theme,styles),
        _ => do IO<List<&2,String>>:
          block : List<&2,String> <- thought(String.join(List.reverse(&2,String,pending),"\n\n"),hide,label,pad,width,theme,styles)
          next : List<&2,String> <- contentLines(TextBlock{text} <> rest,Nil{},hide,label,pad,width,theme,styles)
          return List.append(&2,String,block,"" <> next))(Unit{})
    case ToolCall{} <> rest Nil{}: contentLines(rest,Nil{},hide,label,pad,width,theme,styles)
    case ToolCall{} <> +rest _:
      do IO<List<&2,String>>:
        block : List<&2,String> <- thought(String.join(List.reverse(&2,String,pending),"\n\n"),hide,label,pad,width,theme,styles)
        +next : List<&2,String> <- contentLines(rest,Nil{},hide,label,pad,width,theme,styles)
        return List.append(&2,String,block,Bool.pick(List<&2,String>,anyVisible(rest),"" <> next,next))
def errorText(stop: Stop,+error: Maybe<&2,String>,tools: Bool) -> Maybe<&2,String>:
  match stop:
    case Length{}: Some{"Response was truncated before completion."}
    case Aborted{}:
      Bool.pick(Maybe<&2,String>,tools,None{},Some{Bool.pick(String,Bool.not(String.eq(Maybe.default(&2,String,error,"Request was aborted"),"Request was aborted")),Maybe.default(&2,String,error,""),"Operation aborted")})
    case Error{}:
      Bool.pick(Maybe<&2,String>,tools,None{},Some{"Error: " ++ Maybe.default(&2,String,error,"Unknown error")})
    case _: None{}
def withError(lines: List<&2,String>,error: Maybe<&2,String>,pad: Nat,width: Nat,theme: Theme.Theme) -> IO(List<&2,String>):
  match error:
    case None{}: IO.pure(List<&2,String>,lines)
    case Some{source}:
      do IO<List<&2,String>>:
        colored : String <- foregroundText(theme,"error",source)
        text : List<&2,String> <- textLines(colored,pad,width)
        return List.append(&2,String,lines,"" <> text)
def renderAssistant(state: AssistantMessage,+width: Nat) -> IO(List<&2,String>):
  match state:
    case AssistantMessage{+content,hide,label,+pad,_,stop,error,+theme,styles}:
      do IO<List<&2,String>>:
        +body : List<&2,String> <- contentLines(content,Nil{},hide,label,pad,width,theme,styles)
        +started : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,anyVisible(content),"" <> body,body))
        +complete : List<&2,String> <- withError(started,errorText(stop,error,hasTool(content)),pad,width,theme)
        return Bool.pick(List<&2,String>,hasTool(content),complete,zone(complete))

type BashStatus is Data:
  BashRunning{}
  BashComplete{exitCode: Maybe<&2,U32>,cancelled: Bool,truncated: Bool,fullOutputPath: Maybe<&2,String>}
type BashMessage is Data:
  BashMessage{command: String,output: String,status: BashStatus,excluded: Bool,theme: Theme.Theme,expanded: Bool}
def bash(command: String,excluded: Bool,theme: Theme.Theme,expanded: Bool) -> BashMessage:
  BashMessage{command,"",BashRunning{},excluded,theme,expanded}
def normalizedOutput(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'\r',SCon{'\n',rest}}: SCon{'\n',normalizedOutput(rest)}
    case SCon{'\r',rest}: SCon{'\n',normalizedOutput(rest)}
    case SCon{char,rest}: SCon{char,normalizedOutput(rest)}
def appendBash(state: BashMessage,chunk: String) -> BashMessage:
  match state:
    case BashMessage{command,output,status,excluded,theme,expanded}: BashMessage{command,output ++ normalizedOutput(U.stripTerminalSequences(chunk)),status,excluded,theme,expanded}
def completeBash(state: BashMessage,output: String,exitCode: Maybe<&2,U32>,cancelled: Bool,truncated: Bool,path: Maybe<&2,String>) -> BashMessage:
  match state:
    case BashMessage{command,_,_,excluded,theme,expanded}: BashMessage{command,normalizedOutput(U.stripTerminalSequences(output)),BashComplete{exitCode,cancelled,truncated,path},excluded,theme,expanded}
# upstream: a failed execution completes without an exit code; the caller
# shows the error.
def failBash(state: BashMessage) -> BashMessage:
  match state:
    case BashMessage{command,output,_,excluded,theme,expanded}: BashMessage{command,output,BashComplete{None{},False{},False{},None{}},excluded,theme,expanded}
def bashTheme(state: BashMessage,theme: Theme.Theme) -> BashMessage:
  match state: case BashMessage{command,output,status,excluded,_,expanded}: BashMessage{command,output,status,excluded,theme,expanded}
def bashExpanded(state: BashMessage,expanded: Bool) -> BashMessage:
  match state: case BashMessage{command,output,status,excluded,theme,_}: BashMessage{command,output,status,excluded,theme,expanded}
def bashBorder(count: Nat) -> String:
  match count:
    case Zero{}: ""
    case Succ{rest}: SCon{'─',bashBorder(rest)}
def bashColor(excluded: Bool) -> String:
  match excluded: case True{}: "dim" case False{}: "bashMode"
# upstream BashExecutionComponent. Key texts are keyText's defaults for
# tui.select.cancel and app.tools.expand.
def PREVIEW_LINES() -> Nat: 20n
def cancelKeys() -> String: "escape/ctrl+c"
def expandKeys() -> String: "ctrl+o"
def bashRunning(+theme: Theme.Theme,key: String,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    spinner : String <- foregroundText(theme,key,Loader.frameAt(Loader.defaultFrames(),0n))
    message : String <- foregroundText(theme,"muted","Running... (" ++ cancelKeys() ++ " to cancel)")
    lines : List<&2,String> <- textLines(spinner ++ " " ++ message,1n,width)
    return "" <> lines
# The displayed lines follow the context truncation of the bash tool.
def bashAvailable(result: Truncate.TruncationResult) -> List<&2,String>:
  match result:
    case Truncate.TruncationResult{SNil{},_,_,_,_,_,_,_,_,_,_}: Nil{}
    case Truncate.TruncationResult{content,_,_,_,_,_,_,_,_,_,_}: String.split(content,'\n')
def contextTruncated(result: Truncate.TruncationResult) -> Bool:
  match result: case Truncate.TruncationResult{_,truncated,_,_,_,_,_,_,_,_,_}: truncated
def bashPaintedLines(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        painted : String <- foregroundText(theme,"muted",line)
        bashPaintedLines(rest,theme,painted <> reversed)
def lastLines(+lines: List<&2,String>,count: Nat) -> List<&2,String>:
  List.drop(&2,String,lines,List.length(&2,String,lines) - count)
# Collapsed output shows the last PREVIEW_LINES logical lines, cut to as many
# visual lines (upstream truncateToVisualLines).
def bashOutput(lines: List<&2,String>,+theme: Theme.Theme,+expanded: Bool,width: Nat) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case +lines:
      do IO<List<&2,String>>:
        painted : List<&2,String> <- bashPaintedLines(Bool.pick(List<&2,String>,expanded,lines,lastLines(lines,PREVIEW_LINES())),theme,Nil{})
        +visual : List<&2,String> <- textLines("\n" ++ String.join(painted,"\n"),1n,width)
        return Bool.pick(List<&2,String>,expanded,visual,lastLines(visual,PREVIEW_LINES()))
def keyHint(+theme: Theme.Theme,description: String) -> IO(String):
  do IO<String>:
    key : String <- foregroundText(theme,"dim",expandKeys())
    text : String <- foregroundText(theme,"muted"," " ++ description)
    return key ++ text
def hiddenPart(+theme: Theme.Theme,+hidden: Nat,expanded: Bool) -> IO(List<&2,String>):
  match hidden expanded:
    case Zero{} _: IO.pure(List<&2,String>,Nil{})
    case Succ{_} True{}:
      do IO<List<&2,String>>:
        open : String <- foregroundText(theme,"muted","(")
        hint : String <- keyHint(theme,"to collapse")
        close : String <- foregroundText(theme,"muted",")")
        return [open ++ hint ++ close]
    case Succ{_} False{}:
      do IO<List<&2,String>>:
        open : String <- foregroundText(theme,"muted","... " ++ Nat.show(hidden) ++ " more lines (")
        hint : String <- keyHint(theme,"to expand")
        close : String <- foregroundText(theme,"muted",")")
        return [open ++ hint ++ close]
def endingPart(+theme: Theme.Theme,cancelled: Bool,exitCode: Maybe<&2,U32>) -> IO(List<&2,String>):
  match cancelled exitCode:
    case True{} _:
      do IO<List<&2,String>>:
        text : String <- foregroundText(theme,"warning","(cancelled)")
        return [text]
    case False{} Some{+code}:
      Bool.pick(Unit -> IO(List<&2,String>),U32.is_eq(code,0),_ => IO.pure(List<&2,String>,Nil{}),_ => do IO<List<&2,String>>:
        text : String <- foregroundText(theme,"error","(exit " ++ U32.show(code) ++ ")")
        return [text])(Unit{})
    case False{} None{}: IO.pure(List<&2,String>,Nil{})
def truncationPart(+theme: Theme.Theme,truncated: Bool,path: Maybe<&2,String>) -> IO(List<&2,String>):
  match truncated path:
    case True{} Some{path}:
      do IO<List<&2,String>>:
        text : String <- foregroundText(theme,"warning","Output truncated. Full output: " ++ path)
        return [text]
    case _ _: IO.pure(List<&2,String>,Nil{})
def statusLines(parts: List<&2,String>,width: Nat) -> IO(List<&2,String>):
  match parts:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case parts: textLines("\n" ++ String.join(parts,"\n"),1n,width)
def bashStatus(status: BashStatus,+theme: Theme.Theme,key: String,+hidden: Nat,expanded: Bool,contextCut: Bool,+width: Nat) -> IO(List<&2,String>):
  match status:
    case BashRunning{}: bashRunning(theme,key,width)
    case BashComplete{exitCode,cancelled,truncated,path}:
      do IO<List<&2,String>>:
        more : List<&2,String> <- hiddenPart(theme,hidden,expanded)
        ending : List<&2,String> <- endingPart(theme,cancelled,exitCode)
        cut : List<&2,String> <- truncationPart(theme,truncated || contextCut,path)
        statusLines(List.append(&2,String,more,List.append(&2,String,ending,cut)),width)
def renderBash(state: BashMessage,+width: Nat) -> IO(List<&2,String>):
  match state:
    case BashMessage{command,output,status,excluded,+theme,+expanded}:
      +key = bashColor(excluded)
      +truncation = Truncate.truncateTail(output,Truncate.TruncationOptions{None{},None{}})
      +available = bashAvailable(truncation)
      +hidden = List.length(&2,String,available) - PREVIEW_LINES()
      do IO<List<&2,String>>:
        +top : String <- foregroundText(theme,key,bashBorder(width))
        header : String <- foregroundText(theme,key,"\u{1b}[1m$ " ++ command ++ "\u{1b}[22m")
        headerLines : List<&2,String> <- textLines(header,1n,width)
        body : List<&2,String> <- bashOutput(available,theme,expanded,width)
        after : List<&2,String> <- bashStatus(status,theme,key,hidden,expanded,contextTruncated(truncation),width)
        return List.append(&2,String,"" <> top <> headerLines,List.append(&2,String,body,List.append(&2,String,after,top <> Nil{})))

# A mounted message renders the latest immutable snapshot. The transcript owns
# the callback lifetime; stream updates replace only this message's snapshot.
# Changelog blocks (upstream /changelog and the startup "What's New" notice).
type Changelog is Data:
  FullChangelog{markdown: String}
  WhatsNew{markdown: String,spaced: Bool}
  UpdatedTo{version: String,spaced: Bool}
type Body is Data: UserBody{value: UserMessage,preceded: Bool} AssistantBody{value: AssistantMessage} BashBody{value: BashMessage} StatusBody{text: String,theme: Theme.Theme} NewSessionBody{theme: Theme.Theme} ErrorBody{text: String,theme: Theme.Theme} WarningBody{text: String,theme: Theme.Theme,label: Bool} ManagedBody{text: String,theme: Theme.Theme,warning: Bool,first: Bool} ChangelogBody{value: Changelog,theme: Theme.Theme,styles: Markdown.MarkdownTheme} SessionInfoBody{value: SessionInfo.SessionInfo,theme: Theme.Theme}
def expandedBody(body: Body,expanded: Bool) -> Body:
  match body:
    case BashBody{value}: BashBody{bashExpanded(value,expanded)}
    case other: other
def retheme(body: Body,theme: Theme.Theme) -> Body:
  match body:
    case UserBody{UserMessage{text,pad,_,styles},preceded}: UserBody{UserMessage{text,pad,theme,styles},preceded}
    case AssistantBody{AssistantMessage{content,hide,label,pad,streaming,stop,error,_,styles}}:
      AssistantBody{AssistantMessage{content,hide,label,pad,streaming,stop,error,theme,styles}}
    case BashBody{value}: BashBody{bashTheme(value,theme)}
    case StatusBody{text,_}: StatusBody{text,theme}
    case NewSessionBody{_}: NewSessionBody{theme}
    case ErrorBody{text,_}: ErrorBody{text,theme}
    case WarningBody{text,_,label}: WarningBody{text,theme,label}
    case ManagedBody{text,_,warning,first}: ManagedBody{text,theme,warning,first}
    case ChangelogBody{value,_,styles}: ChangelogBody{value,theme,styles}
    case SessionInfoBody{value,_}: SessionInfoBody{value,theme}
type Owner is Type:
  Owner{state: Ref.Ref<Body>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{state: Ref.Ref<Body>}
def managedLines(first: Bool,lines: List<&2,String>) -> List<&2,String>:
  match first:
    case True{}: "" <> lines
    case False{}: lines
def spacedUser(preceded: Bool,lines: List<&2,String>) -> List<&2,String>:
  match preceded:
    case True{}: "" <> lines
    case False{}: lines
def dashes(count: Nat) -> String:
  match count:
    case Zero{}: ""
    case Succ{rest}: SCon{'─',dashes(rest)}
# upstream DynamicBorder: one rule across the width, in the border colour.
def dynamicBorder(theme: Theme.Theme,width: Nat) -> IO(String): foregroundText(theme,"border",dashes(Nat.max(1n,width)))
def whatsNewTitle(theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    accent : String <- foregroundText(theme,"accent","What's New")
    textLines("\u{1b}[1m" ++ accent ++ "\u{1b}[22m",1n,width)
def changelogMarkdown(source: String,paddingY: Nat,width: Nat,styles: Markdown.MarkdownTheme) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    rendered : Markdown.Markdown & List<&2,String> <- Markdown.render(Markdown.new(source,1n,paddingY,styles,None{},None{}),width)
    return markdownResult(rendered)
def spacedLines(spaced: Bool,lines: List<&2,String>) -> List<&2,String>:
  match spaced:
    case True{}: "" <> lines
    case False{}: lines
def renderChangelog(value: Changelog,+theme: Theme.Theme,styles: Markdown.MarkdownTheme,+width: Nat) -> IO(List<&2,String>):
  match value:
    case FullChangelog{markdown}:
      do IO<List<&2,String>>:
        +border : String <- dynamicBorder(theme,width)
        title : List<&2,String> <- whatsNewTitle(theme,width)
        body : List<&2,String> <- changelogMarkdown(markdown,1n,width,styles)
        return "" <> border <> List.append(&2,String,title,"" <> List.append(&2,String,body,[border]))
    case WhatsNew{markdown,spaced}:
      do IO<List<&2,String>>:
        +border : String <- dynamicBorder(theme,width)
        title : List<&2,String> <- whatsNewTitle(theme,width)
        body : List<&2,String> <- changelogMarkdown(markdown,0n,width,styles)
        return spacedLines(spaced,border <> List.append(&2,String,title,"" <> List.append(&2,String,body,["",border])))
    case UpdatedTo{version,spaced}:
      do IO<List<&2,String>>:
        +border : String <- dynamicBorder(theme,width)
        text : List<&2,String> <- textLines("Updated to v" ++ version ++ ". Use \u{1b}[1m/changelog\u{1b}[22m to view full changelog.",1n,width)
        return spacedLines(spaced,border <> List.append(&2,String,text,[border]))
def renderBody(body: Body,width: Nat) -> IO(List<&2,String>):
  match body:
    case UserBody{value,preceded}:
      do IO<List<&2,String>>:
        lines : List<&2,String> <- renderUser(value,width)
        return spacedUser(preceded,lines)
    case AssistantBody{value}: renderAssistant(value,width)
    case BashBody{value}: renderBash(value,width)
    case StatusBody{text,theme}:
      do IO<List<&2,String>>:
        colored : String <- foregroundText(theme,"dim",text)
        lines : List<&2,String> <- textLines(colored,1n,width)
        return "" <> lines
    case NewSessionBody{theme}:
      do IO<List<&2,String>>:
        colored : String <- foregroundText(theme,"accent","✓ New session started")
        lines : List<&2,String> <- textLines(colored,1n,width)
        return "" <> "" <> List.append(&2,String,lines,[""])
    case ErrorBody{text,theme}:
      do IO<List<&2,String>>:
        colored : String <- foregroundText(theme,"error","Error: " ++ text)
        lines : List<&2,String> <- textLines(colored,1n,width)
        return "" <> lines
    case WarningBody{+text,theme,label}:
      do IO<List<&2,String>>:
        colored : String <- foregroundText(theme,"warning",Bool.pick(String,label,"Warning: " ++ text,text))
        lines : List<&2,String> <- textLines(colored,1n,width)
        return "" <> lines
    case ManagedBody{text,theme,warning,first}:
      do IO<List<&2,String>>:
        colored : String <- foregroundText(theme,Bool.pick(String,warning,"warning","dim"),text)
        lines : List<&2,String> <- textLines(colored,1n,width)
        return managedLines(first,lines)
    case ChangelogBody{value,theme,styles}: renderChangelog(value,theme,styles,width)
    case SessionInfoBody{value,theme}: SessionInfo.render(value,theme,width)
def renderLive(handle: Handle,width: Nat) -> IO(List<&2,String>):
  match handle:
    case Handle{state}:
      do IO<List<&2,String>>:
        body : Body <- Ref.read(Body,state)
        renderBody(body,width)
def noInvalidate(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def create(id: Component.ComponentId,body: Body) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<Body> <- Ref.new(Body,body)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Handle,~Nat,~List<&2,String>,~renderLive,Handle{state})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~noInvalidate,Unit{})
    return Owner{state,Component.Component{id,render,None{},None{},invalidate,None{},False{}},render,invalidate}
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{+state,+component,render,invalidate}: (Owner{state,component,render,invalidate},component,Handle{state})
def rethemeOwner(owner: Owner,theme: Theme.Theme) -> IO(Owner):
  match owner:
    case Owner{+state,+component,render,invalidate}:
      do IO<Owner>:
        body : Body <- Ref.read(Body,state)
        Ref.write(Body,state,retheme(body,theme))
        return Owner{state,component,render,invalidate}
def expandOwner(owner: Owner,expanded: Bool) -> IO(Owner):
  match owner:
    case Owner{+state,+component,render,invalidate}:
      do IO<Owner>:
        body : Body <- Ref.read(Body,state)
        Ref.write(Body,state,expandedBody(body,expanded))
        return Owner{state,component,render,invalidate}
def hiddenBody(body: Body,hidden: Bool) -> Body:
  match body:
    case AssistantBody{value}: AssistantBody{setHideThinkingBlock(value,hidden)}
    case other: other
def paddedBody(body: Body,pad: Nat) -> Body:
  match body:
    case UserBody{value,preceded}: UserBody{setUserOutputPad(value,pad),preceded}
    case AssistantBody{value}: AssistantBody{setAssistantOutputPad(value,pad)}
    case other: other
def padOwner(owner: Owner,pad: Nat) -> IO(Owner):
  match owner:
    case Owner{+state,+component,render,invalidate}:
      do IO<Owner>:
        body : Body <- Ref.read(Body,state)
        Ref.write(Body,state,paddedBody(body,pad))
        return Owner{state,component,render,invalidate}
def hideThinkingOwner(owner: Owner,hidden: Bool) -> IO(Owner):
  match owner:
    case Owner{+state,+component,render,invalidate}:
      do IO<Owner>:
        body : Body <- Ref.read(Body,state)
        Ref.write(Body,state,hiddenBody(body,hidden))
        return Owner{state,component,render,invalidate}
def set(handle: Handle,body: Body) -> IO(Unit):
  match handle:
    case Handle{state}: Ref.write(Body,state,body)
def current(handle: Handle) -> IO(Body):
  match handle:
    case Handle{state}: Ref.read(Body,state)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state,_,render,invalidate}:
      do IO<Unit>:
        old : Body <- Ref.dispose(Body,state)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)

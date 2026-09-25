import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/modes/interactive/transcript.bend as Transcript
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/interactive/components/messages.bend as Messages
import ../packages/coding-agent/src/modes/interactive/viewport.bend as View
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as Styles
import ../packages/coding-agent/src/utils/syntax-highlight.bend as SyntaxHighlight
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/serial-resource.bend as Serial
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/tui/src/utils.bend as Utils

def AgentEventT() -> Data: Agent.AgentEvent<Value.Value,Tools.ToolDetails,Unit,Agent.AgentToolResult<Tools.ToolDetails>,Agent.AgentToolResult<Tools.ToolDetails>>
def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def user(text: String) -> AgentEventT():
  Agent.MessageStart{Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},F64{0,0}}}}}
def historical(text: String) -> Agent.AgentMessage<Value.Value,Tools.ToolDetails,Unit>:
  Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},F64{0,0}}}}
def assistant(text: String) -> Ai.AssistantMessage<Value.Value,Value.Value>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text,None{}}} <> Nil{},"openai-responses","openai","gpt-4o-mini",None{},None{},None{},None{},Ai.Usage{F64{0,0},F64{0,0},F64{0,0},F64{0,0},None{},None{},F64{0,0},Ai.UsageCost{F64{0,0},F64{0,0},F64{0,0},F64{0,0},F64{0,0}}},Ai.Stop{},None{},None{},None{},None{},F64{0,0}}
def thinking(text: String) -> Ai.AssistantMessage<Value.Value,Value.Value>:
  Ai.AssistantMessage{Ai.AssistantThinking{Ai.ThinkingContent{text,None{},None{}}} <> Ai.AssistantText{Ai.TextContent{"visible answer",None{}}} <> Nil{},"openai-responses","openai","gpt-4o-mini",None{},None{},None{},None{},Ai.Usage{F64{0,0},F64{0,0},F64{0,0},F64{0,0},None{},None{},F64{0,0},Ai.UsageCost{F64{0,0},F64{0,0},F64{0,0},F64{0,0},F64{0,0}}},Ai.Stop{},None{},None{},None{},None{},F64{0,0}}
def withTools(text: String) -> Ai.AssistantMessage<Value.Value,Value.Value>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text,None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"call-1","sample_tool",Value.Null{},None{},None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"call-2","second_tool",Value.Null{},None{},None{}}} <> Nil{},"openai-responses","openai","gpt-4o-mini",None{},None{},None{},None{},Ai.Usage{F64{0,0},F64{0,0},F64{0,0},F64{0,0},None{},None{},F64{0,0},Ai.UsageCost{F64{0,0},F64{0,0},F64{0,0},F64{0,0},F64{0,0}}},Ai.Stop{},None{},None{},None{},None{},F64{0,0}}
def withBash(text: String) -> Ai.AssistantMessage<Value.Value,Value.Value>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text,None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"thinking-bash","bash",Value.Null{},None{},None{}}} <> Nil{},"openai-responses","openai","gpt-4o-mini",None{},None{},None{},None{},Ai.Usage{F64{0,0},F64{0,0},F64{0,0},F64{0,0},None{},None{},F64{0,0},Ai.UsageCost{F64{0,0},F64{0,0},F64{0,0},F64{0,0},F64{0,0}}},Ai.Stop{},None{},None{},None{},None{},F64{0,0}}
def resumedAssistant() -> Agent.AgentMessage<Value.Value,Tools.ToolDetails,Unit>:
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"resumed turn",None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"resume-1","first_saved",Value.Null{},None{},None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"resume-2","second_saved",Value.Null{},None{},None{}}} <> Nil{},"openai-responses","openai","gpt-4o-mini",None{},None{},None{},None{},Ai.Usage{F64{0,0},F64{0,0},F64{0,0},F64{0,0},None{},None{},F64{0,0},Ai.UsageCost{F64{0,0},F64{0,0},F64{0,0},F64{0,0},F64{0,0}}},Ai.Stop{},None{},None{},None{},None{},F64{0,0}}}}
def savedResult(id: String,name: String,text: String,error: Bool) -> Agent.AgentMessage<Value.Value,Tools.ToolDetails,Unit>:
  Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id,name,Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},None{},None{},error,F64{0,0}}}}
def toolResult(text: String) -> Agent.AgentToolResult<Tools.ToolDetails>:
  Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},Some{Tools.RawDetails{Value.Null{}}},None{},None{}}
def started(value: Ai.AssistantMessage<Value.Value,Value.Value>) -> AgentEventT():
  Agent.MessageStart{Agent.LlmMessage{Ai.Assistant{value}}}
def updated(+value: Ai.AssistantMessage<Value.Value,Value.Value>) -> AgentEventT():
  Agent.MessageUpdate{Agent.LlmMessage{Ai.Assistant{value}},Ai.Start{value}}
def ended(value: Ai.AssistantMessage<Value.Value,Value.Value>) -> AgentEventT():
  Agent.MessageEnd{Agent.LlmMessage{Ai.Assistant{value}}}
def clean(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> rest: Utils.stripTerminalSequences(line) ++ clean(rest)
def contains(text: String,part: String) -> Bool: String.contains(text,part)
def rowContaining(rows: List<&2,String>,+needle: String) -> String:
  match rows:
    case Nil{}: ""
    case +row <> rest: Bool.pick(String,contains(Utils.stripTerminalSequences(row),needle),Utils.stripTerminalSequences(row),rowContaining(rest,needle))
def countDocument(document: View.Document) -> IO(View.Document & Nat):
  match document:
    case View.Document{+children}: IO.pure(View.Document & Nat,(View.Document{children},List.length(&2,Component.Component,children)))
def mountedCount(handle: View.Handle) -> IO(Nat):
  match handle:
    case View.Handle{document,_,_}: Serial.run(View.Document,Nat,document,countDocument)
def lineOf(rows: List<&2,String>,+needle: String,+index: Nat) -> Maybe<&2,Nat>:
  match rows:
    case Nil{}: None{}
    case row <> rest:
      Bool.pick(Maybe<&2,Nat>,contains(Utils.stripTerminalSequences(row),needle),Some{index},lineOf(rest,needle,index + 1n))
def orderedPositions(first: Maybe<&2,Nat>,last: Maybe<&2,Nat>) -> Bool:
  match first last:
    case Some{a} Some{b}: Nat.is_lt(a,b)
    case _ _: False{}
def orderedRows(+rows: List<&2,String>,first: String,last: String) -> Bool:
  orderedPositions(lineOf(rows,first,0n),lineOf(rows,last,0n))
def check(value: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
def repeatedLines(count: Nat) -> String:
  match count:
    case Zero{}: ""
    case Succ{rest}: "later\n" ++ repeatedLines(rest)
def runEvents(pair: Transcript.Owner & Transcript.Handle,view: View.View,+document: Component.Component,+viewHandle: View.Handle,styles: Styles.Styles) -> IO(Unit):
  match pair:
    case (transcript,+handle):
      do IO<Unit>:
        added : Bool <- Transcript.accept(Value.Value,Unit,handle,user("hello"))
        check(added,"user event did not append")
        +partial : Ai.AssistantMessage<Value.Value,Value.Value> <- IO.pure(Ai.AssistantMessage<Value.Value,Value.Value>,assistant("partial"))
        begun : Bool <- Transcript.accept(Value.Value,Unit,handle,started(partial))
        check(begun,"assistant start did not append")
        +interim : List<&2,String> <- Component.render(document,20n)
        check(contains(clean(interim),"hello") && contains(clean(interim),"partial"),"streaming transcript omitted a message")
        replaced : Bool <- Transcript.accept(Value.Value,Unit,handle,updated(assistant("answer")))
        check(replaced,"assistant update did not replace")
        +current : List<&2,String> <- Component.render(document,20n)
        check(contains(clean(current),"answer") && Bool.not(contains(clean(current),"partial")),"assistant update appended stale content")
        completed : Bool <- Transcript.accept(Value.Value,Unit,handle,ended(assistant("final")))
        check(completed,"assistant end did not settle")
        +final : List<&2,String> <- Component.render(document,20n)
        check(contains(clean(final),"final") && Bool.not(contains(clean(final),"answer")),"assistant end retained stale content")
        Transcript.setOutputPad(handle,0n)
        +compact : List<&2,String> <- Component.render(document,20n)
        check(Bool.not(String.eq(rowContaining(final,"hello"),rowContaining(compact,"hello"))) && Bool.not(String.eq(rowContaining(final,"final"),rowContaining(compact,"final"))),"output padding did not update mounted user and assistant messages")
        Transcript.setOutputPad(handle,1n)
        +restored : List<&2,String> <- Component.render(document,20n)
        check(String.eq(rowContaining(final,"hello"),rowContaining(restored,"hello")) && String.eq(rowContaining(final,"final"),rowContaining(restored,"final")),"restoring output padding did not restore mounted messages")
        Transcript.seed(Value.Value,Unit,handle,historical("archived") <> Nil{})
        seeded : List<&2,String> <- Component.render(document,20n)
        check(contains(clean(seeded),"archived"),"stored message was not restored")
        toolBegin : Bool <- Transcript.accept(Value.Value,Unit,handle,started(assistant("invoke")))
        check(toolBegin,"assistant was not mounted")
        callDiscovered : Bool <- Transcript.accept(Value.Value,Unit,handle,updated(withTools("invoke")))
        check(callDiscovered,"assistant tool call was not mounted")
        +pending : List<&2,String> <- Component.render(document,28n)
        check(contains(clean(pending),"invoke") && contains(clean(pending),"sample_tool") && contains(clean(pending),"second_tool") && orderedRows(pending,"invoke","sample_tool") && orderedRows(pending,"sample_tool","second_tool"),"pending tools missing or out of order")
        initialCount : Nat <- mountedCount(viewHandle)
        check(Nat.is_eq(initialCount,6n),"tool calls were not mounted exactly once")
        callStart : Bool <- Transcript.accept(Value.Value,Unit,handle,Agent.ToolExecutionStart{"call-1","sample_tool",Value.Text{"start"}})
        check(callStart,"tool start was not accepted")
        partialResult : Bool <- Transcript.accept(Value.Value,Unit,handle,Agent.ToolExecutionUpdate{"call-1","sample_tool",Value.Text{"running"},toolResult("partial output")})
        check(partialResult,"tool update was not accepted")
        +partialView : List<&2,String> <- Component.render(document,28n)
        check(contains(clean(partialView),"partial output") && contains(clean(partialView),"running"),"partial tool state was not rendered")
        finalResult : Bool <- Transcript.accept(Value.Value,Unit,handle,Agent.ToolExecutionEnd{"call-1","sample_tool",toolResult("final output"),True{}})
        check(finalResult,"tool end was not accepted")
        +finalView : List<&2,String> <- Component.render(document,28n)
        check(contains(clean(finalView),"final output") && Bool.not(contains(clean(finalView),"partial output")),"final tool result retained stale output")
        secondResult : Bool <- Transcript.accept(Value.Value,Unit,handle,Agent.ToolExecutionEnd{"call-2","second_tool",toolResult("other output"),False{}})
        check(secondResult,"second tool end was not accepted")
        +secondView : List<&2,String> <- Component.render(document,28n)
        check(contains(clean(secondView),"final output") && contains(clean(secondView),"other output"),"tool results were not tracked by ID")
        toolMessageEnd : Bool <- Transcript.accept(Value.Value,Unit,handle,ended(withTools("invoke complete")))
        check(toolMessageEnd,"assistant tool message did not settle")
        settledCount : Nat <- mountedCount(viewHandle)
        check(Nat.is_eq(settledCount,6n),"assistant end mounted a duplicate tool")
        toolSeed : Bool <- Transcript.accept(Value.Value,Unit,handle,user("after tool"))
        check(toolSeed,"next user message did not append")
        +ordered : List<&2,String> <- Component.render(document,28n)
        check(contains(clean(ordered),"final output") && contains(clean(ordered),"after tool") && orderedRows(ordered,"final output","after tool"),"tool result lost or reordered across subsequent message")
        # pi f07218c4d interactive-mode.ts renderSessionItems matches stored
        # tool results by ID without adding result rows, even out of result order.
        Transcript.seed(Value.Value,Unit,handle,resumedAssistant() <>
          savedResult("resume-2","second_saved","saved second",False{}) <>
          savedResult("resume-1","first_saved","saved first error",True{}) <>
          savedResult("unknown","missing","unmatched output",False{}) <>
          historical("resumed user") <> Nil{})
        +resumed : List<&2,String> <- Component.render(document,28n)
        check(orderedRows(resumed,"resumed turn","first_saved") && orderedRows(resumed,"first_saved","saved first error") && orderedRows(resumed,"saved first error","second_saved") && orderedRows(resumed,"second_saved","saved second") && orderedRows(resumed,"saved second","resumed user"),"saved tool results did not follow their calls")
        check(Bool.not(contains(clean(resumed),"unmatched output")),"unmatched saved tool result rendered a standalone row")
        resumedCount : Nat <- mountedCount(viewHandle)
        check(Nat.is_eq(resumedCount,11n),"saved tool results added duplicate components")
        bash : Messages.Handle <- Transcript.startBash(handle,"printf first",False{})
        Transcript.finishBash(bash,"FIRST_HIDDEN\n" ++ repeatedLines(25n),Some{0},False{},False{},None{})
        +collapsed : List<&2,String> <- Component.render(document,80n)
        check(Bool.not(contains(clean(collapsed),"FIRST_HIDDEN")),"collapsed Bash output showed hidden lines")
        isExpanded : Bool <- Transcript.toggleExpanded(handle)
        +opened : List<&2,String> <- Component.render(document,80n)
        check(isExpanded && contains(clean(opened),"FIRST_HIDDEN"),"expanding transcript did not reveal Bash output")
        nextBash : Messages.Handle <- Transcript.startBash(handle,"printf next",False{})
        Transcript.finishBash(nextBash,"NEXT_VISIBLE\n" ++ repeatedLines(25n),Some{0},False{},False{},None{})
        +newEntry : List<&2,String> <- Component.render(document,80n)
        check(contains(clean(newEntry),"NEXT_VISIBLE"),"new Bash message did not inherit expansion")
        isCollapsed : Bool <- Transcript.toggleExpanded(handle)
        +closed : List<&2,String> <- Component.render(document,80n)
        check(Bool.not(isCollapsed) && Bool.not(contains(clean(closed),"FIRST_HIDDEN")),"collapsing transcript left Bash output expanded")
        thinkingStart : Bool <- Transcript.accept(Value.Value,Unit,handle,started(thinking("private reasoning")))
        +thoughtVisible : List<&2,String> <- Component.render(document,80n)
        check(thinkingStart && contains(clean(thoughtVisible),"private reasoning"),"thinking block did not initially render")
        Transcript.setHideThinking(handle,True{})
        +thoughtHidden : List<&2,String> <- Component.render(document,80n)
        check(Bool.not(contains(clean(thoughtHidden),"private reasoning")) && contains(clean(thoughtHidden),"visible answer"),"toggle did not hide existing thinking without hiding answer")
        newThinking : Bool <- Transcript.accept(Value.Value,Unit,handle,started(thinking("future reasoning")))
        +futureHidden : List<&2,String> <- Component.render(document,80n)
        check(newThinking && Bool.not(contains(clean(futureHidden),"future reasoning")),"new assistant did not inherit thinking visibility")
        Transcript.setHideThinking(handle,False{})
        +thoughtShown : List<&2,String> <- Component.render(document,80n)
        check(contains(clean(thoughtShown),"private reasoning") && contains(clean(thoughtShown),"future reasoning"),"toggle did not restore mounted thinking")
        bashCall : Bool <- Transcript.accept(Value.Value,Unit,handle,started(withBash("running bash")))
        bashPartial : Bool <- Transcript.accept(Value.Value,Unit,handle,Agent.ToolExecutionUpdate{"thinking-bash","bash",Value.Null{},toolResult("first output")})
        +beforeToggle : List<&2,String> <- Component.render(document,80n)
        check(bashCall && bashPartial && contains(clean(beforeToggle),"first output"),"partial bash output did not render")
        Transcript.setHideThinking(handle,True{})
        +afterToggle : List<&2,String> <- Component.render(document,80n)
        check(contains(clean(afterToggle),"first output"),"thinking toggle lost partial bash output")
        bashEnd : Bool <- Transcript.accept(Value.Value,Unit,handle,Agent.ToolExecutionEnd{"thinking-bash","bash",toolResult("final output"),False{}})
        +afterBash : List<&2,String> <- Component.render(document,80n)
        check(bashEnd && contains(clean(afterBash),"final output") && Bool.not(contains(clean(afterBash),"first output")),"thinking toggle broke live bash completion")
        beforeStatus : Nat <- mountedCount(viewHandle)
        Transcript.status(handle,"Tool output: expanded")
        +firstStatus : List<&2,String> <- Component.render(document,80n)
        check(contains(clean(firstStatus),"Tool output: expanded"),"status was not mounted in the transcript")
        Transcript.status(handle,"Thinking blocks: hidden")
        +replacedStatus : List<&2,String> <- Component.render(document,80n)
        afterStatus : Nat <- mountedCount(viewHandle)
        check(contains(clean(replacedStatus),"Thinking blocks: hidden") && Bool.not(contains(clean(replacedStatus),"Tool output: expanded")) && Nat.is_eq(afterStatus,beforeStatus + 1n),"consecutive status did not replace the previous line")
        Transcript.dispose(transcript)
        View.dispose(view)
        Styles.dispose(styles)
        IO.print("interactive transcript replaces stream snapshots")
def runStyle(pair: Styles.Styles & Markdown.MarkdownTheme,view: View.View,document: Component.Component,+viewHandle: View.Handle,theme: Theme.Theme) -> IO(Unit):
  match pair:
    case (styles,markdown):
      do IO<Unit>:
        transcript : Transcript.Owner <- Transcript.create(viewHandle,theme,markdown)
      runEvents(Transcript.borrow(transcript),view,document,viewHandle,styles)
def runTranscript(view: View.View,document: Component.Component,viewHandle: View.Handle,theme: Theme.Theme,styles: Styles.Styles) -> IO(Unit):
  runStyle(Styles.borrow(styles),view,document,viewHandle,theme)
def runView(pair: View.View & Component.Component & View.Handle,theme: Theme.Theme,styles: Styles.Styles) -> IO(Unit):
  match pair:
    case (view,document,handle): runTranscript(view,document,handle,theme,styles)
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(result)
    highlighter : SyntaxHighlight.Highlighter <- SyntaxHighlight.create("packages/runtime/data/highlight")
    styles : Styles.Styles <- Styles.create(theme,highlighter)
    view : View.View <- View.create(Component.ComponentId{1n})
    runView(View.borrow(view),theme,styles)

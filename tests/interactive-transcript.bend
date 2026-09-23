import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/modes/interactive/transcript.bend as Transcript
import ../packages/coding-agent/src/modes/interactive/viewport.bend as View
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as Styles
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/tui/src/utils.bend as Utils

def AgentEventT() -> Data: Agent.AgentEvent<Value.Value,Value.Value,Unit,Unit,Unit>
def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def user(text: String) -> AgentEventT():
  Agent.MessageStart{Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},F64{0,0}}}}}
def assistant(text: String) -> Ai.AssistantMessage<Value.Value,Value.Value>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text,None{}}} <> Nil{},"openai-responses","openai","gpt-4o-mini",None{},None{},None{},None{},Ai.Usage{F64{0,0},F64{0,0},F64{0,0},F64{0,0},None{},None{},F64{0,0},Ai.UsageCost{F64{0,0},F64{0,0},F64{0,0},F64{0,0},F64{0,0}}},Ai.Stop{},None{},None{},None{},None{},F64{0,0}}
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
def check(value: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
def runEvents(pair: Transcript.Owner & Transcript.Handle,view: View.View,+document: Component.Component,styles: Styles.Styles) -> IO(Unit):
  match pair:
    case (transcript,+handle):
      do IO<Unit>:
        added : Bool <- Transcript.accept(Value.Value,Value.Value,Unit,Unit,Unit,handle,user("hello"))
        check(added,"user event did not append")
        +partial : Ai.AssistantMessage<Value.Value,Value.Value> <- IO.pure(Ai.AssistantMessage<Value.Value,Value.Value>,assistant("partial"))
        begun : Bool <- Transcript.accept(Value.Value,Value.Value,Unit,Unit,Unit,handle,started(partial))
        check(begun,"assistant start did not append")
        +interim : List<&2,String> <- Component.render(document,20n)
        check(contains(clean(interim),"hello") && contains(clean(interim),"partial"),"streaming transcript omitted a message")
        replaced : Bool <- Transcript.accept(Value.Value,Value.Value,Unit,Unit,Unit,handle,updated(assistant("answer")))
        check(replaced,"assistant update did not replace")
        +current : List<&2,String> <- Component.render(document,20n)
        check(contains(clean(current),"answer") && Bool.not(contains(clean(current),"partial")),"assistant update appended stale content")
        completed : Bool <- Transcript.accept(Value.Value,Value.Value,Unit,Unit,Unit,handle,ended(assistant("final")))
        check(completed,"assistant end did not settle")
        +final : List<&2,String> <- Component.render(document,20n)
        check(contains(clean(final),"final") && Bool.not(contains(clean(final),"answer")),"assistant end retained stale content")
        Transcript.dispose(transcript)
        View.dispose(view)
        Styles.dispose(styles)
        IO.print("interactive transcript replaces stream snapshots")
def runStyle(pair: Styles.Styles & Markdown.MarkdownTheme,view: View.View,document: Component.Component,viewHandle: View.Handle,theme: Theme.Theme) -> IO(Unit):
  match pair:
    case (styles,markdown):
      do IO<Unit>:
        transcript : Transcript.Owner <- Transcript.create(viewHandle,theme,markdown)
        runEvents(Transcript.borrow(transcript),view,document,styles)
def runTranscript(view: View.View,document: Component.Component,viewHandle: View.Handle,theme: Theme.Theme,styles: Styles.Styles) -> IO(Unit):
  runStyle(Styles.borrow(styles),view,document,viewHandle,theme)
def runView(pair: View.View & Component.Component & View.Handle,theme: Theme.Theme,styles: Styles.Styles) -> IO(Unit):
  match pair:
    case (view,document,handle): runTranscript(view,document,handle,theme,styles)
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(result)
    styles : Styles.Styles <- Styles.create(theme)
    view : View.View <- View.create(Component.ComponentId{1n})
    runView(View.borrow(view),theme,styles)

import Base
import ../packages/coding-agent/src/modes/interactive/components/messages.bend as M
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as Styles
import ../packages/coding-agent/src/utils/syntax-highlight.bend as SyntaxHighlight
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/schema-value.bend as Value

def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def output(label: String,lines: List<&2,String>) -> IO(Unit):
  IO.print(label ++ "\u{1e}" ++ String.join(lines,"\u{1f}"))
def run(+theme: Theme.Theme,styles: Styles.Styles) -> IO(Unit):
  do IO<Unit>:
    +md : Markdown.MarkdownTheme <- IO.pure(Markdown.MarkdownTheme,Styles.theme(styles))
    +user : M.UserMessage <- IO.pure(M.UserMessage,M.user("hello",theme,md,1n))
    lines : List<&2,String> <- M.renderUser(user,20n)
    output("user",lines)
    unpadded : List<&2,String> <- M.renderUser(M.setUserOutputPad(user,0n),20n)
    output("user-pad0",unpadded)
    +base : M.AssistantMessage <- IO.pure(M.AssistantMessage,M.assistant(Nil{},theme,md))
    first : List<&2,String> <- M.renderAssistant(M.updateContent(base,M.TextBlock{"  hello **world**  "} <> Nil{},M.Stop{},None{},False{}),20n)
    output("text",first)
    +thinking : M.AssistantMessage <- IO.pure(M.AssistantMessage,M.updateContent(base,M.ThinkingBlock{"  first thought  "} <> M.ThinkingBlock{"second thought"} <> M.TextBlock{"answer"} <> Nil{},M.Stop{},None{},False{}))
    expanded : List<&2,String> <- M.renderAssistant(thinking,20n)
    output("thinking",expanded)
    collapsed : List<&2,String> <- M.renderAssistant(M.setHideThinkingBlock(thinking,True{}),20n)
    output("hidden",collapsed)
    streaming : List<&2,String> <- M.renderAssistant(M.updateContent(base,M.TextBlock{"partial"} <> Nil{},M.Stop{},None{},True{}),20n)
    output("stream",streaming)
    complete : List<&2,String> <- M.renderAssistant(M.updateContent(base,M.TextBlock{"partial answer"} <> Nil{},M.Stop{},None{},False{}),20n)
    output("complete",complete)
    +ai : Ai.AssistantMessage<Value.Value,Value.Value> <- IO.pure(Ai.AssistantMessage<Value.Value,Value.Value>,Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"partial answer",None{}}} <> Nil{},"openai-responses","openai","gpt-4o-mini",None{},None{},None{},None{},Ai.Usage{F64{0,0},F64{0,0},F64{0,0},F64{0,0},None{},None{},F64{0,0},Ai.UsageCost{F64{0,0},F64{0,0},F64{0,0},F64{0,0},F64{0,0}}},Ai.Stop{},None{},None{},None{},None{},F64{0,0}})
    adapted : List<&2,String> <- M.renderAssistant(M.updateFromAi(Value.Value,Value.Value,base,ai,False{}),20n)
    output("ai-adapter",adapted)
    length : List<&2,String> <- M.renderAssistant(M.updateContent(base,M.TextBlock{"partial"} <> Nil{},M.Length{},None{},False{}),20n)
    output("length",length)
    aborted : List<&2,String> <- M.renderAssistant(M.updateContent(base,M.TextBlock{"partial"} <> Nil{},M.Aborted{},Some{"Request was aborted"},False{}),20n)
    output("aborted",aborted)
    failed : List<&2,String> <- M.renderAssistant(M.updateContent(base,M.TextBlock{"partial"} <> Nil{},M.Error{},Some{"network failed"},False{}),20n)
    output("error",failed)
    tool : List<&2,String> <- M.renderAssistant(M.updateContent(base,M.TextBlock{"calling tool"} <> M.ToolCall{} <> Nil{},M.Error{},Some{"network failed"},False{}),20n)
    output("tool-error",tool)
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(result)
    highlighter : SyntaxHighlight.Highlighter <- SyntaxHighlight.create("packages/runtime/data/highlight")
    styles : Styles.Styles <- Styles.create(theme,highlighter)
    run(theme,styles)

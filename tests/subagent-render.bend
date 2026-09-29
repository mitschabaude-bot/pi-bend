import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/coding-agent/examples/extensions/subagent/index.bend as Subagent
import ../packages/coding-agent/examples/extensions/subagent/agents.bend as Agents
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/loader.bend as ExtensionLoader
import ../packages/coding-agent/src/core/extensions/tool-render.bend as ToolRender
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/interactive/components/tool-execution.bend as Tool
import ../packages/coding-agent/src/modes/interactive/transcript.bend as Transcript
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as MarkdownTheme
import ../packages/coding-agent/src/utils/syntax-highlight.bend as SyntaxHighlight
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/tui/src/utils.bend as U
import ../packages/tui/src/components/markdown.bend as Markdown

def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match result:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def check(yes: Bool,label: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),yes,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,label))(Unit{})
def clean(rows: List<&2,String>) -> String:
  match rows:
    case Nil{}: ""
    case row <> rest: U.stripTerminalSequences(row) ++ "\n" ++ clean(rest)
def zero() -> F64: U32.to_f64(0)
def assistant(text: String) -> Subagent.Message():
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text,None{}}} <> Nil{},"openai-responses","openai","gpt-6-luna",None{},None{},None{},None{},Ai.Usage{zero(),zero(),zero(),zero(),None{},None{},zero(),Ai.UsageCost{zero(),zero(),zero(),zero(),zero()}},Ai.Stop{},None{},None{},None{},None{},zero()}}}
def result(agent: String,text: String) -> Subagent.SingleResult:
  Subagent.SingleResult{agent,Subagent.KnownSource{Agents.UserSource{}},"Find the issue",Some{0},[assistant(text)],"",Subagent.UsageStats{U32.to_f64(120),U32.to_f64(20),zero(),zero(),zero(),zero(),1n},Some{"openai/gpt-6-luna"},None{},None{},None{}}
def execute(_: Unit,call: Ext.ToolCallInput) -> IO(Tools.Output()): IO.pure(Tools.Output(),Fail{Tools.failure("unused")})
def run(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +executeCallback : Ext.ToolExecute() <- C.create(~Unit,~Ext.ToolCallInput,~Tools.Output(),~execute,Unit{})
    +call : ToolRender.Renderer() <- C.create(~Unit,~ToolRender.RenderContext,~ToolRender.RenderResult(),~Subagent.renderCall,Unit{})
    +resultCallback : ToolRender.Renderer() <- C.create(~Unit,~ToolRender.RenderContext,~ToolRender.RenderResult(),~Subagent.renderResult,Unit{})
    +definition : Ext.ToolDefinition <- IO.pure(Ext.ToolDefinition,Ext.ToolDefinition{"subagent","Subagent","delegate",None{},Nil{},V.ObjectValue{R.Record{Nil{}}},None{},None{},executeCallback,Ext.DefaultShell{},Some{call},Some{resultCallback}})
    +shell : Tool.Shell <- IO.pure(Tool.Shell,Transcript.registeredShell([Ext.RegisteredTool{definition,ExtensionLoader.createSourceInfo("<test:subagent>")}],"subagent"))
    +args : V.Value <- IO.pure(V.Value,Json.object(Json.field("agent",Json.text("worker"),Json.field("task",Json.text("Find the issue"),Nil{}))))
    +pending : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("subagent","call-1",args,theme,shell))
    +callRows : List<&2,String> <- Tool.render(pending,80n)
    check(String.contains(clean(callRows),"subagent worker [user]") && String.contains(clean(callRows),"Find the issue"),"registered subagent call renderer was not mounted")
    +details : Subagent.SubagentDetails <- IO.pure(Subagent.SubagentDetails,Subagent.SubagentDetails{Subagent.SingleMode{},Agents.UserScope{},None{},[result("worker","The fix is ready.")]})
    +finished : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(pending,ToolRender.ToolResult{[Ai.TextImageText{Ai.TextContent{"The fix is ready.",None{}}}],False{},Some{Tools.RawDetails{Subagent.detailsValue(details)}}},False{}))
    +rows : List<&2,String> <- Tool.render(finished,80n)
    check(String.contains(clean(rows),"✓ worker (user)") && String.contains(clean(rows),"The fix is ready.") && String.contains(clean(rows),"1 turn"),"subagent result renderer missed completed agent output")
    +expandedRows : List<&2,String> <- Tool.render(Tool.setExpanded(finished,True{}),80n)
    check(String.contains(clean(expandedRows),"─── Task ───") && String.contains(clean(expandedRows),"─── Output ───") && String.contains(clean(expandedRows),"The fix is ready."),"expanded subagent result lost the task or output")
    +chain : V.Value <- IO.pure(V.Value,Json.object(Json.field("chain",V.ArrayValue{[Json.object(Json.field("agent",Json.text("a"),Json.field("task",Json.text("one"),Nil{}))),Json.object(Json.field("agent",Json.text("b"),Json.field("task",Json.text("{previous} two"),Nil{}))),Json.object(Json.field("agent",Json.text("c"),Json.field("task",Json.text("three"),Nil{}))),Json.object(Json.field("agent",Json.text("d"),Json.field("task",Json.text("four"),Nil{})))]},Nil{})))
    check(String.contains(U.stripTerminalSequences(Subagent.callText(chain,theme)),"chain (4 steps)") && String.contains(U.stripTerminalSequences(Subagent.callText(chain,theme)),"... +1 more"),"subagent chain call preview differs")
    C.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),call)
    C.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),resultCallback)
    C.dispose(Ext.ToolCallInput,Tools.Output(),executeCallback)
def renderedLines(output: ToolRender.RenderResult()) -> IO(List<&2,String>):
  match output:
    case Done{ToolRender.RenderLines{lines}}: IO.pure(List<&2,String>,lines)
    case _: IO.die(List<&2,String>,1,"subagent renderer did not return lines")
def styledMode(mode: Subagent.SubagentMode,markdown: Markdown.MarkdownTheme,theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +agent : Subagent.SingleResult = result("worker","**bold** and `code`")
    +details : Subagent.SubagentDetails = Subagent.SubagentDetails{mode,Agents.UserScope{},None{},[agent]}
    +toolResult : ToolRender.ToolResult = ToolRender.ToolResult{[Ai.TextImageText{Ai.TextContent{"**bold** and `code`",None{}}}],False{},Some{Tools.RawDetails{Subagent.detailsValue(details)}}}
    +context : ToolRender.RenderContext = ToolRender.RenderContext{"subagent","call-1",V.ObjectValue{R.Record{Nil{}}},Some{toolResult},True{},False{},True{},True{},80n,theme,Some{markdown},None{},None{}}
    rendered : ToolRender.RenderResult() <- Subagent.renderResult(Unit{},context)
    +rows : List<&2,String> <- renderedLines(rendered)
    check(String.contains(clean(rows),"bold and code") && Bool.not(String.contains(clean(rows),"**bold**")) && String.contains(String.join(rows,"\n"),"\u{1b}[1m"),"expanded subagent answer was not rendered as Markdown")
def styledBorrowed(pair: MarkdownTheme.Styles & Markdown.MarkdownTheme,+theme: Theme.Theme) -> IO(Unit):
  match pair:
    case (styles,+markdown):
      do IO<Unit>:
        styledMode(Subagent.SingleMode{},markdown,theme)
        styledMode(Subagent.ChainMode{},markdown,theme)
        styledMode(Subagent.ParallelMode{},markdown,theme)
        MarkdownTheme.dispose(styles)
def main() -> IO(Unit):
  do IO<Unit>:
    loadedTheme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(loadedTheme)
    run(theme)
    highlighter : SyntaxHighlight.Highlighter <- SyntaxHighlight.create("packages/runtime/data/highlight")
    styles : MarkdownTheme.Styles <- MarkdownTheme.create(theme,highlighter)
    styledBorrowed(MarkdownTheme.borrow(styles),theme)

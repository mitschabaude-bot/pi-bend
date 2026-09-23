import Base
import ../packages/coding-agent/src/modes/interactive/components/tool-execution.bend as Tool
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/callback.bend as Callback
import ../packages/ai/src/types.bend as Ai
import ../packages/agent/src/types.bend as Agent
import ../packages/tui/src/utils.bend as U

def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value: case Done{theme}: IO.pure(Theme.Theme,theme) case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def output(label: String,lines: List<&2,String>) -> IO(Unit): IO.print(label ++ "\u{1e}" ++ String.join(lines,"\u{1f}"))
def show(label: String,state: Tool.ToolExecution) -> IO(Unit):
  do IO<Unit>:
    lines : List<&2,String> <- Tool.render(state,28n)
    output(label,lines)
def text(value: String) -> Ai.TextImageContent: Ai.TextImageText{Ai.TextContent{value,None{}}}
def result(value: String,error: Bool) -> Tool.ToolResult: Tool.ToolResult{text(value) <> Nil{},error}
def args1() -> Value.Value: Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> Nil{}}}
def args2() -> Value.Value: Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> R.Property{"limit",Value.Number{F64{1073741824,0}}} <> Nil{}}}
@unsafe def lines(+from: Nat,count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{rest}: lines(from + 1n,rest,("line-" ++ Nat.show(from)) <> reversed)
def draw(label: String,context: Tool.RenderContext) -> IO(List<&2,String>):
  match context:
    case Tool.RenderContext{_,_,_,_,_,_,_,_,width}:
      +label = {label: String}
      IO.pure(List<&2,String>,U.padResult(label,U.visibleWidth(label),width,True{}) <> Nil{})
def drawEmpty(label: String,context: Tool.RenderContext) -> IO(List<&2,String>): IO.pure(List<&2,String>,Nil{})
def mainRun(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +generic : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","g1",args1(),theme,Tool.Generic{}))
    show("generic-pending",generic)
    +args : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateArgs(generic,args2()))
    show("generic-args",args)
    +started : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.setArgsComplete(Tool.markExecutionStarted(args)))
    show("generic-started",started)
    +partial : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(started,result("first\nsecond",False{}),True{}))
    show("generic-partial",partial)
    +success : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(partial,result("first\nsecond",False{}),False{}))
    show("generic-success",success)
    show("generic-error",Tool.updateResult(success,result("bad\r\n\u{1b}[31mred\u{1b}[0m",True{}),False{}))
    +fallback : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","f1",Value.ObjectValue{R.Record{R.Property{"foo",Value.Text{"bar"}} <> Nil{}}},theme,Tool.Boxed{None{},None{}}))
    show("fallback-pending",fallback)
    +preview : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(fallback,result(String.join(lines(1n,12n,Nil{}),"\n"),False{}),False{}))
    show("fallback-preview",preview)
    +expanded : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.setExpanded(preview,True{}))
    show("fallback-expanded",expanded)
    show("fallback-error",Tool.updateResult(expanded,result("failed",True{}),False{}))
    +call : Callback.Callback<Tool.RenderContext,List<&2,String>> <- Callback.create(~String,~Tool.RenderContext,~List<&2,String>,~draw,"custom call")
    +resultCall : Callback.Callback<Tool.RenderContext,List<&2,String>> <- Callback.create(~String,~Tool.RenderContext,~List<&2,String>,~draw,"custom result")
    +rendered : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","r1",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.Boxed{Some{call},Some{resultCall}}))
    show("rendered-call",rendered)
    show("rendered-result",Tool.updateResult(rendered,result("done",False{}),False{}))
    +ownCall : Callback.Callback<Tool.RenderContext,List<&2,String>> <- Callback.create(~String,~Tool.RenderContext,~List<&2,String>,~draw,"own call")
    +ownResult : Callback.Callback<Tool.RenderContext,List<&2,String>> <- Callback.create(~String,~Tool.RenderContext,~List<&2,String>,~draw,"own result")
    +self : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","s1",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.SelfRendered{Some{ownCall},Some{ownResult}}))
    show("self-call",self)
    show("self-result",Tool.updateResult(self,result("done",False{}),False{}))
    +empty : Callback.Callback<Tool.RenderContext,List<&2,String>> <- Callback.create(~String,~Tool.RenderContext,~List<&2,String>,~drawEmpty,"")
    +emptyBox : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","e1",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.Boxed{Some{empty},Some{empty}}))
    show("boxed-empty",emptyBox)
    +emptySelf : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","e2",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.SelfRendered{Some{empty},Some{empty}}))
    show("self-empty",emptySelf)
    show("self-empty-result",Tool.updateResult(emptySelf,Tool.ToolResult{Nil{},False{}},False{}))
    +callValue : Ai.ToolCall<Value.Value> <- IO.pure(Ai.ToolCall<Value.Value>,Ai.ToolCall{"a1","custom_tool",Value.ObjectValue{R.Record{Nil{}}},None{},None{}})
    +adapter : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.fromAiToolCall(callValue,theme,Tool.Generic{}))
    +agentResult : Agent.AgentToolResult<Value.Value> <- IO.pure(Agent.AgentToolResult<Value.Value>,Agent.AgentToolResult{text("from agent") <> Nil{},Value.Null{},None{},None{}})
    show("agent-adapter",Tool.updateFromAgent(Value.Value,adapter,agentResult,False{},False{}))
    Callback.dispose(Tool.RenderContext,List<&2,String>,call)
    Callback.dispose(Tool.RenderContext,List<&2,String>,resultCall)
    Callback.dispose(Tool.RenderContext,List<&2,String>,ownCall)
    Callback.dispose(Tool.RenderContext,List<&2,String>,ownResult)
    Callback.dispose(Tool.RenderContext,List<&2,String>,empty)
def main() -> IO(Unit):
  do IO<Unit>:
    loadedTheme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(loadedTheme)
    mainRun(theme)

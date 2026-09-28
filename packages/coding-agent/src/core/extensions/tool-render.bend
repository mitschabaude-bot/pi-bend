import Base
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/schema-value.bend as Value
import ../../modes/interactive/theme/theme.bend as Theme
import ../../../../tui/src/components/markdown.bend as Markdown
import ../../../../tui/src/component.bend as Component
import ../tools/index.bend as Tools

# Shared input to native extension tool renderers.
type ToolResult is Data:
  ToolResult{content: List<&2,Ai.TextImageContent>,isError: Bool,details: Maybe<&2,Tools.ToolDetails>}
type RenderContext is Data:
  RenderContext{toolName: String,toolCallId: String,args: Value.Value,result: Maybe<&2,ToolResult>,expanded: Bool,isPartial: Bool,executionStarted: Bool,argsComplete: Bool,width: Nat,theme: Theme.Theme,markdown: Maybe<&2,Markdown.MarkdownTheme>,lastComponent: Maybe<&2,Component.Component>,invalidate: Maybe<&2,Callback.Callback<Unit,Unit>>}
type RenderOutput is Type:
  RenderLines{lines: List<&2,String>}
  RenderComponent{owner: Component.Owner}
  ReuseComponent{}
def RenderResult() -> Type: Result<&2,&1,String,RenderOutput>
def Renderer() -> Data: Callback.Callback<RenderContext,RenderResult()>

import Base
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/schema-value.bend as Value
import ../../modes/interactive/theme/theme.bend as Theme
import ../tools/index.bend as Tools

# Shared input to native extension tool renderers. A renderer receives the
# current immutable tool snapshot and paints lines for the terminal width.
type ToolResult is Data:
  ToolResult{content: List<&2,Ai.TextImageContent>,isError: Bool,details: Maybe<&2,Tools.ToolDetails>}
type RenderContext is Data:
  RenderContext{toolName: String,toolCallId: String,args: Value.Value,result: Maybe<&2,ToolResult>,expanded: Bool,isPartial: Bool,executionStarted: Bool,argsComplete: Bool,width: Nat,theme: Theme.Theme}
def Renderer() -> Data: Callback.Callback<RenderContext,List<&2,String>>

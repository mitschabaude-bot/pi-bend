import Base
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/coding-agent/src/core/tools/index.bend as Tools

# Each built-in tool's system prompt snippet and guidelines, as the system
# prompt builder reads them (Tools.promptSnippet and Tools.promptGuidelines),
# one JSON object keyed by tool name. tests/tool_prompt_contributions.test.ts
# compares them with upstream's *ToolSystemPromptContribution constants.

def texts(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> texts(rest)

def entries(names: List<&2, Tools.ToolName>) -> List<&2, V.Value>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: Json.object(Json.field("name", Json.text(Tools.toolName(name)), Json.field("snippet", Json.text(Tools.promptSnippet(name)), Json.field("guidelines", V.ArrayValue{texts(Tools.promptGuidelines(name))}, Nil{})))) <> entries(rest)

def main() -> IO(Unit):
  IO.print(Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(V.ArrayValue{entries([Tools.ReadTool{}, Tools.BashTool{}, Tools.EditTool{}, Tools.WriteTool{}, Tools.GrepTool{}, Tools.FindTool{}, Tools.LsTool{}])})), "null"))

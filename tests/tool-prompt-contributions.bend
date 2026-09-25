import Base
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/tools/bash.bend as Bash

# Each built-in tool's system prompt snippet and guidelines as its definition
# has them with default options (Tools.promptSnippet and
# Tools.definitionGuidelines, which the system prompt builder reads), one JSON
# object per tool; then the bash definition's guidelines with
# exposeSessionEnvironment false, named "bash:noSessionEnvironment". tests/tool_prompt_contributions.test.ts
# compares them with upstream's *ToolSystemPromptContribution constants.

def texts(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> texts(rest)

def entry(name: String, snippet: String, guidelines: List<&2, String>) -> V.Value:
  Json.object(Json.field("name", Json.text(name), Json.field("snippet", Json.text(snippet), Json.field("guidelines", V.ArrayValue{texts(guidelines)}, Nil{}))))

def entries(names: List<&2, Tools.ToolName>) -> List<&2, V.Value>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: entry(Tools.toolName(name), Tools.promptSnippet(name), Tools.definitionGuidelines(name, Tools.defaultOptions())) <> entries(rest)

def withoutSessionEnvironment() -> Tools.ToolsOptions:
  Tools.ToolsOptions{None{}, Some{Bash.BashToolOptions{None{}, None{}, None{}, Some{False{}}, None{}}}, None{}, None{}, None{}, None{}, None{}}

def main() -> IO(Unit):
  IO.print(Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(V.ArrayValue{List.append(&2, V.Value, entries([Tools.ReadTool{}, Tools.BashTool{}, Tools.EditTool{}, Tools.WriteTool{}, Tools.GrepTool{}, Tools.FindTool{}, Tools.LsTool{}]), [entry("bash:noSessionEnvironment", Tools.promptSnippet(Tools.BashTool{}), Tools.definitionGuidelines(Tools.BashTool{}, withoutSessionEnvironment()))])})), "null"))
